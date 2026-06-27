import '../database/app_database.dart';
import '../database/dao/message_dao.dart';
import '../database/dao/session_dao.dart';
import 'key_point_memory.dart';

class DreamingSessionDigest {
  const DreamingSessionDigest({
    required this.sessionId,
    required this.title,
    required this.messageCount,
    required this.userMessageCount,
    required this.assistantMessageCount,
    required this.highlights,
    required this.firstMessageAt,
    required this.lastMessageAt,
  });

  factory DreamingSessionDigest.fromJson(Map<String, dynamic> json) {
    return DreamingSessionDigest(
      sessionId: json['sessionId'] as String? ?? '',
      title: json['title'] as String? ?? '新会话',
      messageCount: json['messageCount'] as int? ?? 0,
      userMessageCount: json['userMessageCount'] as int? ?? 0,
      assistantMessageCount: json['assistantMessageCount'] as int? ?? 0,
      highlights:
          (json['highlights'] as List?)?.whereType<String>().toList() ??
          const [],
      firstMessageAt:
          DateTime.tryParse(json['firstMessageAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastMessageAt:
          DateTime.tryParse(json['lastMessageAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String sessionId;
  final String title;
  final int messageCount;
  final int userMessageCount;
  final int assistantMessageCount;
  final List<String> highlights;
  final DateTime firstMessageAt;
  final DateTime lastMessageAt;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'title': title,
    'messageCount': messageCount,
    'userMessageCount': userMessageCount,
    'assistantMessageCount': assistantMessageCount,
    'highlights': highlights,
    'firstMessageAt': firstMessageAt.toIso8601String(),
    'lastMessageAt': lastMessageAt.toIso8601String(),
  };
}

class DreamingDigest {
  const DreamingDigest({
    required this.day,
    required this.generatedAt,
    required this.sessionCount,
    required this.originalMessageCount,
    required this.userMessageCount,
    required this.assistantMessageCount,
    required this.sessions,
    required this.memoryCandidates,
    required this.keywords,
    required this.elapsedMs,
  });

  factory DreamingDigest.empty({
    required DateTime day,
    required DateTime generatedAt,
    required int elapsedMs,
  }) {
    return DreamingDigest(
      day: _dateOnly(day),
      generatedAt: generatedAt,
      sessionCount: 0,
      originalMessageCount: 0,
      userMessageCount: 0,
      assistantMessageCount: 0,
      sessions: const [],
      memoryCandidates: const [],
      keywords: const [],
      elapsedMs: elapsedMs,
    );
  }

  factory DreamingDigest.fromJson(Map<String, dynamic> json) {
    return DreamingDigest(
      day:
          DateTime.tryParse(json['day'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sessionCount: json['sessionCount'] as int? ?? 0,
      originalMessageCount: json['originalMessageCount'] as int? ?? 0,
      userMessageCount: json['userMessageCount'] as int? ?? 0,
      assistantMessageCount: json['assistantMessageCount'] as int? ?? 0,
      sessions:
          (json['sessions'] as List?)
              ?.whereType<Map>()
              .map((item) => DreamingSessionDigest.fromJson(item.cast()))
              .toList() ??
          const [],
      memoryCandidates:
          (json['memoryCandidates'] as List?)
              ?.whereType<Map>()
              .map((item) => KeyPointMemoryItem.fromJson(item.cast()))
              .where((item) => item.content.isNotEmpty)
              .toList() ??
          const [],
      keywords:
          (json['keywords'] as List?)?.whereType<String>().toList() ?? const [],
      elapsedMs: json['elapsedMs'] as int? ?? 0,
    );
  }

  final DateTime day;
  final DateTime generatedAt;
  final int sessionCount;
  final int originalMessageCount;
  final int userMessageCount;
  final int assistantMessageCount;
  final List<DreamingSessionDigest> sessions;
  final List<KeyPointMemoryItem> memoryCandidates;
  final List<String> keywords;
  final int elapsedMs;

  bool get hasContent => originalMessageCount > 0;

  String get dayKey => formatDreamingDay(day);

  Map<String, dynamic> toJson() => {
    'day': day.toIso8601String(),
    'generatedAt': generatedAt.toIso8601String(),
    'sessionCount': sessionCount,
    'originalMessageCount': originalMessageCount,
    'userMessageCount': userMessageCount,
    'assistantMessageCount': assistantMessageCount,
    'sessions': sessions.map((item) => item.toJson()).toList(),
    'memoryCandidates': memoryCandidates.map((item) => item.toJson()).toList(),
    'keywords': keywords,
    'elapsedMs': elapsedMs,
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Dreaming 日报 $dayKey')
      ..writeln()
      ..writeln('- 生成时间：${generatedAt.toIso8601String()}')
      ..writeln('- 会话数：$sessionCount')
      ..writeln('- 原始消息数：$originalMessageCount')
      ..writeln('- 用户消息：$userMessageCount')
      ..writeln('- 助手消息：$assistantMessageCount')
      ..writeln('- 耗时：$elapsedMs ms')
      ..writeln();

    if (!hasContent) {
      buffer
        ..writeln('## 概览')
        ..writeln()
        ..writeln('今天暂无可整理的本地原始对话。');
      return buffer.toString();
    }

    buffer
      ..writeln('## 关键词')
      ..writeln()
      ..writeln(
        keywords.isEmpty ? '- 暂无' : keywords.map((k) => '- $k').join('\n'),
      )
      ..writeln()
      ..writeln('## 会话摘要')
      ..writeln();

    for (final session in sessions) {
      buffer
        ..writeln('### ${session.title}')
        ..writeln()
        ..writeln('- session_id：${session.sessionId}')
        ..writeln(
          '- 消息：${session.messageCount} 条，用户 ${session.userMessageCount} 条，助手 ${session.assistantMessageCount} 条',
        );
      if (session.highlights.isNotEmpty) {
        buffer.writeln('- 重点：');
        for (final highlight in session.highlights) {
          buffer.writeln('  - $highlight');
        }
      }
      buffer.writeln();
    }

    buffer
      ..writeln('## 记忆候选')
      ..writeln();
    if (memoryCandidates.isEmpty) {
      buffer.writeln('- 暂无新增候选');
    } else {
      for (final item in memoryCandidates) {
        buffer.writeln('- [${item.category}] ${item.content}');
      }
    }
    return buffer.toString();
  }
}

class DreamingService {
  const DreamingService({
    required SessionDao sessionDao,
    required MessageDao messageDao,
    KeyPointExtractor extractor = const KeyPointExtractor(),
    DateTime Function()? now,
  }) : _sessionDao = sessionDao,
       _messageDao = messageDao,
       _extractor = extractor,
       _now = now;

  final SessionDao _sessionDao;
  final MessageDao _messageDao;
  final KeyPointExtractor _extractor;
  final DateTime Function()? _now;

  Future<DreamingDigest> runDailyDigest({
    DateTime? day,
    int maxMessages = 5000,
    int maxMemoryCandidates = 40,
  }) async {
    final stopwatch = Stopwatch()..start();
    final targetDay = _dateOnly(day ?? (_now?.call() ?? DateTime.now()));
    final start = targetDay;
    final end = targetDay.add(const Duration(days: 1));

    final messages = await _messageDao.getOriginalMessagesInTimeRange(
      start: start,
      end: end,
      limit: maxMessages,
    );
    final generatedAt = _now?.call() ?? DateTime.now();
    if (messages.isEmpty) {
      stopwatch.stop();
      return DreamingDigest.empty(
        day: targetDay,
        generatedAt: generatedAt,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }

    final sessions = await _sessionDao.getAllSessions();
    final sessionById = {for (final session in sessions) session.id: session};
    final grouped = <String, List<Message>>{};
    for (final message in messages) {
      grouped.putIfAbsent(message.sessionId, () => []).add(message);
    }

    final sessionDigests = <DreamingSessionDigest>[];
    final memoryCandidates = <String, KeyPointMemoryItem>{};
    final keywordCounts = <String, int>{};
    var userMessageCount = 0;
    var assistantMessageCount = 0;

    for (final entry in grouped.entries) {
      final sessionMessages = entry.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final userMessages = sessionMessages
          .where((message) => message.role == 'user')
          .toList(growable: false);
      final assistantMessages = sessionMessages
          .where((message) => message.role == 'assistant')
          .toList(growable: false);
      userMessageCount += userMessages.length;
      assistantMessageCount += assistantMessages.length;

      for (final message in userMessages) {
        if (_looksSensitive(message.content)) continue;
        for (final keyword in extractMemoryKeywords(message.content)) {
          keywordCounts[keyword] = (keywordCounts[keyword] ?? 0) + 1;
        }
        for (final item in _extractor.extractFromUserMessage(
          sessionId: message.sessionId,
          sourceMessageId: message.id,
          content: message.content,
          now: generatedAt,
        )) {
          memoryCandidates.putIfAbsent(item.id, () => item);
        }
      }

      final session = sessionById[entry.key];
      sessionDigests.add(
        DreamingSessionDigest(
          sessionId: entry.key,
          title: session?.title ?? '新会话',
          messageCount: sessionMessages.length,
          userMessageCount: userMessages.length,
          assistantMessageCount: assistantMessages.length,
          highlights: _buildHighlights(userMessages),
          firstMessageAt: DateTime.fromMillisecondsSinceEpoch(
            sessionMessages.first.createdAt,
          ),
          lastMessageAt: DateTime.fromMillisecondsSinceEpoch(
            sessionMessages.last.createdAt,
          ),
        ),
      );
    }

    sessionDigests.sort((a, b) => b.messageCount.compareTo(a.messageCount));
    stopwatch.stop();
    return DreamingDigest(
      day: targetDay,
      generatedAt: generatedAt,
      sessionCount: grouped.length,
      originalMessageCount: messages.length,
      userMessageCount: userMessageCount,
      assistantMessageCount: assistantMessageCount,
      sessions: List.unmodifiable(sessionDigests),
      memoryCandidates: List.unmodifiable(
        memoryCandidates.values.take(maxMemoryCandidates),
      ),
      keywords: List.unmodifiable(_topKeywords(keywordCounts)),
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }
}

String formatDreamingDay(DateTime day) {
  final date = _dateOnly(day);
  return [
    date.year.toString().padLeft(4, '0'),
    date.month.toString().padLeft(2, '0'),
    date.day.toString().padLeft(2, '0'),
  ].join('-');
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

List<String> _buildHighlights(List<Message> userMessages) {
  final highlights = <String>[];
  final seen = <String>{};
  for (final message in userMessages) {
    final snippet = _safeSnippet(message.content);
    if (snippet.isEmpty || seen.contains(snippet)) continue;
    seen.add(snippet);
    highlights.add(snippet);
    if (highlights.length >= 3) break;
  }
  return highlights;
}

List<String> _topKeywords(Map<String, int> counts) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      if (countCompare != 0) return countCompare;
      return a.key.compareTo(b.key);
    });
  return entries.map((entry) => entry.key).take(12).toList(growable: false);
}

String _safeSnippet(String content) {
  if (_looksSensitive(content)) return '';
  final normalized = normalizeMemoryContent(content)
      .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'), 'Bearer ***')
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{6,}'), 'sk-***')
      .replaceAll(RegExp(r'AIza[0-9A-Za-z_-]{10,}'), 'AIza***')
      .replaceAll(RegExp(r'(/Users/|/var/|/private/)[^\s，。；；]+'), '[本地路径]');
  if (normalized.length <= 100) return normalized;
  return '${normalized.substring(0, 100)}...';
}

bool _looksSensitive(String content) {
  return RegExp(
    r'(api[_ -]?key|authorization|bearer\s+|password|passwd|secret|token|密钥|密码|sk-[A-Za-z0-9_-]{10,}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-)',
    caseSensitive: false,
  ).hasMatch(content);
}
