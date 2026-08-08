import '../database/app_database.dart';
import '../database/dao/message_dao.dart';
import '../database/dao/session_dao.dart';
import '../memory/key_point_memory.dart';

enum LocalSearchMatchType { title, message, memory }

class LocalSearchResult {
  const LocalSearchResult({
    required this.sessionId,
    required this.title,
    required this.subtitle,
    required this.matchType,
    required this.score,
    this.matchCount,
  });

  final String sessionId;
  final String title;
  final String subtitle;
  final LocalSearchMatchType matchType;
  final double score;
  final int? matchCount;
}

class LocalFullTextSearchService {
  const LocalFullTextSearchService({
    required SessionDao sessionDao,
    required MessageDao messageDao,
    List<KeyPointMemoryItem> memoryItems = const [],
    bool enableSemanticMessageSearch = true,
  }) : _sessionDao = sessionDao,
       _messageDao = messageDao,
       _memoryItems = memoryItems,
       _enableSemanticMessageSearch = enableSemanticMessageSearch;

  final SessionDao _sessionDao;
  final MessageDao _messageDao;
  final List<KeyPointMemoryItem> _memoryItems;
  final bool _enableSemanticMessageSearch;

  Future<List<LocalSearchResult>> search(String query, {int limit = 30}) async {
    if (limit <= 0) return const [];
    final resultLimit = limit.clamp(1, 100).toInt();
    final normalizedQuery = normalizeLocalSearchQuery(query);
    final tokens = tokenizeLocalSearchQuery(normalizedQuery);
    if (normalizedQuery.isEmpty || tokens.isEmpty) return const [];

    final accumulators = <String, _LocalSearchAccumulator>{};
    final sessionCache = <String, Session?>{};

    Future<Session?> getSession(String sessionId) async {
      if (sessionCache.containsKey(sessionId)) return sessionCache[sessionId];
      final session = await _sessionDao.getSession(sessionId);
      sessionCache[sessionId] = session;
      return session;
    }

    final titleMatches = <String, Session>{};
    for (final token in tokens) {
      final sessions = await _sessionDao.searchSessions(token, limit: 200);
      for (final session in sessions) {
        titleMatches[session.id] = session;
        sessionCache[session.id] = session;
      }
    }

    for (final session in titleMatches.values) {
      final title = session.title ?? '新会话';
      final score = _scoreTextMatch(title, normalizedQuery, tokens) + 80;
      accumulators
          .putIfAbsent(session.id, () => _LocalSearchAccumulator(session))
          .addTitle(score);
    }

    final messageMatches = <String, _MessageHit>{};
    final ftsHits = await _messageDao.searchOriginalMessagesFullText(tokens);
    for (final hit in ftsHits) {
      final messageHit = messageMatches.putIfAbsent(
        hit.message.id,
        () => _MessageHit(hit.message),
      );
      messageHit.ftsRank = hit.rank;
      for (final token in tokens) {
        if (hit.message.content.toLowerCase().contains(token.toLowerCase())) {
          messageHit.tokens.add(token);
        }
      }
    }

    for (final token in tokens) {
      final messages = await _messageDao.searchAll(token, limit: 200);
      for (final message in messages) {
        if (message.messageType != 'original') continue;
        final hit = messageMatches.putIfAbsent(
          message.id,
          () => _MessageHit(message),
        );
        hit.tokens.add(token);
      }
    }

    final queryVector = _enableSemanticMessageSearch
        ? buildLocalSemanticVector(normalizedQuery)
        : const <String, double>{};
    if (_enableSemanticMessageSearch && queryVector.isNotEmpty) {
      final semanticHits = await _messageDao.searchOriginalMessagesSemantic(
        queryVector,
      );
      for (final semanticHit in semanticHits) {
        final hit = messageMatches.putIfAbsent(
          semanticHit.message.id,
          () => _MessageHit(semanticHit.message),
        );
        if (semanticHit.similarity > hit.semanticScore) {
          hit.semanticScore = semanticHit.similarity;
        }
      }
    }

    for (final hit in messageMatches.values) {
      final session = await getSession(hit.message.sessionId);
      if (session == null) continue;
      final score =
          45 +
          hit.ftsScore +
          hit.semanticScore * 32 +
          _scoreTextMatch(hit.message.content, normalizedQuery, tokens) +
          hit.tokens.length * 12;
      final snippet = buildLocalSearchSnippet(
        hit.message.content,
        normalizedQuery,
        tokens,
        prefix: hit.tokens.isEmpty && hit.semanticScore > 0 ? '语义匹配：' : '',
      );
      accumulators
          .putIfAbsent(session.id, () => _LocalSearchAccumulator(session))
          .addMessage(
            score: score,
            snippet: snippet,
            messageId: hit.message.id,
          );
    }

    final relevantMemory = rankRelevantKeyPoints(
      _memoryItems,
      normalizedQuery,
      limit: 20,
    );
    for (final item in relevantMemory) {
      final session = await getSession(item.sessionId);
      if (session == null) continue;
      final score = 38 + _scoreTextMatch(item.content, normalizedQuery, tokens);
      final snippet = buildLocalSearchSnippet(
        item.content,
        normalizedQuery,
        tokens,
        prefix: '记忆：',
      );
      accumulators
          .putIfAbsent(session.id, () => _LocalSearchAccumulator(session))
          .addMemory(score: score, snippet: snippet);
    }

    final results = accumulators.values.map((item) => item.toResult()).toList()
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;
        return a.title.compareTo(b.title);
      });

    return results.take(resultLimit).toList(growable: false);
  }
}

String normalizeLocalSearchQuery(String query) {
  return query.trim().replaceAll(RegExp(r'\s+'), ' ');
}

List<String> tokenizeLocalSearchQuery(String query) {
  final normalized = normalizeLocalSearchQuery(query).toLowerCase();
  if (normalized.isEmpty) return const [];
  final tokens = <String>{};

  if (normalized.length >= 2 && normalized.length <= 40) {
    tokens.add(normalized);
  }

  for (final match in RegExp(r'[a-z0-9_+-]{2,}').allMatches(normalized)) {
    final token = match.group(0);
    if (token != null) tokens.add(token);
  }

  for (final match in RegExp(r'[\u4e00-\u9fa5]{2,16}').allMatches(normalized)) {
    final token = match.group(0);
    if (token == null) continue;
    tokens.add(token);
    if (token.length > 4) {
      for (var i = 0; i <= token.length - 2 && tokens.length < 12; i++) {
        tokens.add(token.substring(i, i + 2));
      }
    }
  }

  return tokens.take(12).toList(growable: false);
}

String buildLocalSearchSnippet(
  String content,
  String query,
  List<String> tokens, {
  String prefix = '',
  int radiusBefore = 30,
  int radiusAfter = 50,
}) {
  final normalizedQuery = normalizeLocalSearchQuery(query).toLowerCase();
  final lower = content.toLowerCase();
  var idx = normalizedQuery.isEmpty ? -1 : lower.indexOf(normalizedQuery);
  var matchedLength = normalizedQuery.length;

  if (idx == -1) {
    for (final token in tokens) {
      idx = lower.indexOf(token.toLowerCase());
      if (idx != -1) {
        matchedLength = token.length;
        break;
      }
    }
  }

  if (idx == -1) {
    final clipped = content.length > 80
        ? '${content.substring(0, 80)}...'
        : content;
    return '$prefix$clipped';
  }

  final start = (idx - radiusBefore).clamp(0, content.length);
  final end = (idx + matchedLength + radiusAfter).clamp(0, content.length);
  final snippet = [
    if (start > 0) '...',
    content.substring(start, end),
    if (end < content.length) '...',
  ].join();
  return '$prefix$snippet';
}

double _scoreTextMatch(String content, String query, List<String> tokens) {
  final lower = content.toLowerCase();
  final normalizedQuery = normalizeLocalSearchQuery(query).toLowerCase();
  var score = 0.0;
  if (normalizedQuery.isNotEmpty && lower.contains(normalizedQuery)) {
    score += 30;
  }
  for (final token in tokens) {
    if (lower.contains(token.toLowerCase())) score += 8;
  }
  return score;
}

class _MessageHit {
  _MessageHit(this.message);

  final Message message;
  final Set<String> tokens = {};
  double? ftsRank;
  double semanticScore = 0;

  double get ftsScore {
    final rank = ftsRank;
    if (rank == null) return 0;
    return 24 / (1 + rank.abs());
  }
}

class _LocalSearchAccumulator {
  _LocalSearchAccumulator(this.session);

  final Session session;
  var score = 0.0;
  LocalSearchMatchType? matchType;
  String? titleSnippet;
  String? messageSnippet;
  String? memorySnippet;
  final messageIds = <String>{};

  void addTitle(double value) {
    score += value;
    matchType = LocalSearchMatchType.title;
    titleSnippet = '会话标题匹配';
  }

  void addMessage({
    required double score,
    required String snippet,
    required String messageId,
  }) {
    this.score += score;
    messageIds.add(messageId);
    messageSnippet ??= snippet;
    if (matchType != LocalSearchMatchType.title) {
      matchType = LocalSearchMatchType.message;
    }
  }

  void addMemory({required double score, required String snippet}) {
    this.score += score;
    memorySnippet ??= snippet;
    if (matchType != LocalSearchMatchType.title &&
        matchType != LocalSearchMatchType.message) {
      matchType = LocalSearchMatchType.memory;
    }
  }

  LocalSearchResult toResult() {
    final subtitle = titleSnippet ?? messageSnippet ?? memorySnippet ?? '匹配';
    final count = messageIds.length > 1 ? messageIds.length : null;
    return LocalSearchResult(
      sessionId: session.id,
      title: session.title ?? '新会话',
      subtitle: subtitle,
      matchType: matchType ?? LocalSearchMatchType.message,
      score: score,
      matchCount: count,
    );
  }
}
