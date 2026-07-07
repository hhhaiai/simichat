import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:crypto/crypto.dart';
import '../../memory/key_point_memory.dart';
import '../app_database.dart';
import '../tables.dart';

part 'message_dao.g.dart';

class MessageSearchHit {
  const MessageSearchHit({required this.message, required this.rank});

  final Message message;
  final double rank;
}

class MessageSemanticSearchHit {
  const MessageSemanticSearchHit({
    required this.message,
    required this.similarity,
  });

  final Message message;
  final double similarity;
}

class MessageFtsIndexHealth {
  const MessageFtsIndexHealth({
    required this.isAvailable,
    required this.isConsistent,
    required this.originalMessageCount,
    required this.indexedRowCount,
    required this.rebuilt,
    required this.elapsedMs,
    this.failureReason,
  });

  factory MessageFtsIndexHealth.unavailable({
    required int elapsedMs,
    String failureReason = '当前 SQLite 环境暂不支持 FTS5 搜索索引',
  }) {
    return MessageFtsIndexHealth(
      isAvailable: false,
      isConsistent: false,
      originalMessageCount: 0,
      indexedRowCount: 0,
      rebuilt: false,
      elapsedMs: elapsedMs,
      failureReason: failureReason,
    );
  }

  final bool isAvailable;
  final bool isConsistent;
  final int originalMessageCount;
  final int indexedRowCount;
  final bool rebuilt;
  final int elapsedMs;
  final String? failureReason;

  bool get isHealthy => isAvailable && isConsistent;

  int get missingIndexCount {
    final missing = originalMessageCount - indexedRowCount;
    return missing > 0 ? missing : 0;
  }
}

class MessageSemanticIndexHealth {
  const MessageSemanticIndexHealth({
    required this.isAvailable,
    required this.isConsistent,
    required this.originalMessageCount,
    required this.indexedRowCount,
    required this.staleIndexCount,
    required this.extraIndexCount,
    required this.rebuilt,
    required this.elapsedMs,
    this.failureReason,
  });

  factory MessageSemanticIndexHealth.unavailable({
    required int elapsedMs,
    String failureReason = '本地语义索引不可用',
  }) {
    return MessageSemanticIndexHealth(
      isAvailable: false,
      isConsistent: false,
      originalMessageCount: 0,
      indexedRowCount: 0,
      staleIndexCount: 0,
      extraIndexCount: 0,
      rebuilt: false,
      elapsedMs: elapsedMs,
      failureReason: failureReason,
    );
  }

  final bool isAvailable;
  final bool isConsistent;
  final int originalMessageCount;
  final int indexedRowCount;
  final int staleIndexCount;
  final int extraIndexCount;
  final bool rebuilt;
  final int elapsedMs;
  final String? failureReason;

  bool get isHealthy => isAvailable && isConsistent;

  int get missingOrStaleIndexCount => staleIndexCount;
}

@DriftAccessor(tables: [Messages])
class MessageDao extends DatabaseAccessor<AppDatabase> with _$MessageDaoMixin {
  MessageDao(super.db);

  bool _messageFtsReady = false;
  bool _messageSemanticIndexReady = false;

  Future<List<Message>> getMessagesBySession(String sessionId) {
    return (select(messages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// 分页获取消息（用于上滑加载历史）
  Future<List<Message>> getMessagesPaginated(
    String sessionId, {
    int limit = 50,
    int offset = 0,
  }) {
    return (select(messages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// 获取会话的消息总数
  Future<int> getMessageCount(String sessionId) {
    return (selectOnly(messages)
          ..addColumns([messages.id.count()])
          ..where(messages.sessionId.equals(sessionId)))
        .map((row) => row.read(messages.id.count()) ?? 0)
        .getSingle();
  }

  Future<List<Message>> getSummaries(String sessionId) {
    return (select(messages)
          ..where(
            (t) =>
                t.sessionId.equals(sessionId) & t.messageType.equals('summary'),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<Message>> getUnsummarizedOriginals(String sessionId) {
    return (select(messages)
          ..where(
            (t) =>
                t.sessionId.equals(sessionId) &
                t.isSummarized.equals(false) &
                t.messageType.equals('original'),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<int> getUnsummarizedTokenCount(String sessionId) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(tokens), 0) as total FROM messages '
      'WHERE session_id = ? AND is_summarized = 0 AND message_type = ?',
      variables: [
        Variable.withString(sessionId),
        Variable.withString('original'),
      ],
    ).getSingle();
    return result.data['total'] as int;
  }

  Future<int> insertMessage({
    required String id,
    required String sessionId,
    required String role,
    required String content,
    String? thinkingContent,
    String messageType = 'original',
    String? channelModelId,
    int tokens = 0,
    int? responseMs,
  }) async {
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final inserted = await into(messages).insert(
      MessagesCompanion.insert(
        id: id,
        sessionId: sessionId,
        role: role,
        content: content,
        thinkingContent: Value(thinkingContent),
        messageType: Value(messageType),
        channelModelId: Value(channelModelId),
        tokens: Value(tokens),
        responseMs: Value(responseMs),
        createdAt: createdAt,
      ),
    );
    if (messageType == 'original') {
      await _upsertMessageSemanticIndexValues(
        id: id,
        sessionId: sessionId,
        content: content,
      );
      _messageSemanticIndexReady = true;
    }
    return inserted;
  }

  Future<int> insertSummary({
    required String id,
    required String sessionId,
    required String content,
    required String summaryStartId,
    required String summaryEndId,
    int tokens = 0,
  }) {
    return into(messages).insert(
      MessagesCompanion.insert(
        id: id,
        sessionId: sessionId,
        role: 'system',
        content: content,
        messageType: const Value('summary'),
        summaryStartId: Value(summaryStartId),
        summaryEndId: Value(summaryEndId),
        tokens: Value(tokens),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> markAsSummarized(List<String> messageIds) {
    return (update(messages)..where((t) => t.id.isIn(messageIds))).write(
      const MessagesCompanion(isSummarized: Value(true)),
    );
  }

  Future<void> deleteMessage(String id) async {
    await (delete(messages)..where((t) => t.id.equals(id))).go();
    await _deleteMessageSemanticIndexRow(id);
  }

  Future<List<Message>> searchInSession(String sessionId, String query) {
    return (select(messages)
          ..where(
            (t) => t.sessionId.equals(sessionId) & t.content.like('%$query%'),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<Message>> searchAll(String query) {
    return (select(messages)
          ..where((t) => t.content.like('%$query%'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<List<Message>> getOriginalMessagesInTimeRange({
    required DateTime start,
    required DateTime end,
    int limit = 5000,
  }) {
    return (select(messages)
          ..where(
            (t) =>
                t.messageType.equals('original') &
                t.createdAt.isBiggerOrEqualValue(start.millisecondsSinceEpoch) &
                t.createdAt.isSmallerThanValue(end.millisecondsSinceEpoch),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<List<Message>> getLatestOriginalMessagesInTimeRange({
    required DateTime start,
    required DateTime end,
    int limit = 5000,
  }) {
    return (select(messages)
          ..where(
            (t) =>
                t.messageType.equals('original') &
                t.createdAt.isBiggerOrEqualValue(start.millisecondsSinceEpoch) &
                t.createdAt.isSmallerThanValue(end.millisecondsSinceEpoch),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<int> countOriginalMessagesInTimeRange({
    required DateTime start,
    required DateTime end,
  }) {
    final count = messages.id.count();
    return (selectOnly(messages)
          ..addColumns([count])
          ..where(
            messages.messageType.equals('original') &
                messages.createdAt.isBiggerOrEqualValue(
                  start.millisecondsSinceEpoch,
                ) &
                messages.createdAt.isSmallerThanValue(
                  end.millisecondsSinceEpoch,
                ),
          ))
        .map((row) => row.read(count) ?? 0)
        .getSingle();
  }

  Future<List<Message>> getRecentOriginalMessages({int limit = 500}) {
    return (select(messages)
          ..where((t) => t.messageType.equals('original'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<bool> ensureMessageFtsIndex() async {
    if (_messageFtsReady) return true;
    final health = await checkMessageFtsIndexHealth(repairIfNeeded: true);
    return health.isHealthy;
  }

  Future<MessageFtsIndexHealth> prewarmMessageFtsIndex() {
    return checkMessageFtsIndexHealth(repairIfNeeded: true);
  }

  Future<MessageSemanticIndexHealth> prewarmMessageSemanticIndex() {
    return checkMessageSemanticIndexHealth(repairIfNeeded: true);
  }

  Future<MessageSemanticIndexHealth> checkMessageSemanticIndexHealth({
    bool repairIfNeeded = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _createMessageSemanticIndexObjects();

      final originalMessages = await _getAllOriginalMessagesForSemanticIndex();
      var indexedRows = await _getMessageSemanticIndexRows();
      var staleCount = _countStaleSemanticRows(originalMessages, indexedRows);
      var extraCount = _countExtraSemanticRows(originalMessages, indexedRows);
      var rebuilt = false;

      if ((staleCount > 0 ||
              extraCount > 0 ||
              indexedRows.length != originalMessages.length) &&
          repairIfNeeded) {
        await rebuildMessageSemanticIndex(originalMessages);
        rebuilt = true;
        indexedRows = await _getMessageSemanticIndexRows();
        staleCount = _countStaleSemanticRows(originalMessages, indexedRows);
        extraCount = _countExtraSemanticRows(originalMessages, indexedRows);
      }

      final consistent =
          indexedRows.length == originalMessages.length &&
          staleCount == 0 &&
          extraCount == 0;
      _messageSemanticIndexReady = consistent;
      stopwatch.stop();
      return MessageSemanticIndexHealth(
        isAvailable: true,
        isConsistent: consistent,
        originalMessageCount: originalMessages.length,
        indexedRowCount: indexedRows.length,
        staleIndexCount: staleCount,
        extraIndexCount: extraCount,
        rebuilt: rebuilt,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      _messageSemanticIndexReady = false;
      stopwatch.stop();
      return MessageSemanticIndexHealth.unavailable(
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  Future<MessageFtsIndexHealth> checkMessageFtsIndexHealth({
    bool repairIfNeeded = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _createMessageFtsObjects();

      var ftsCount = await _countMessageFtsRows();
      final originalCount = await _countOriginalMessages();
      var rebuilt = false;
      if (ftsCount != originalCount && repairIfNeeded) {
        await rebuildMessageFtsIndex();
        rebuilt = true;
        ftsCount = await _countMessageFtsRows();
      }

      final consistent = ftsCount == originalCount;
      _messageFtsReady = consistent;
      stopwatch.stop();
      return MessageFtsIndexHealth(
        isAvailable: true,
        isConsistent: consistent,
        originalMessageCount: originalCount,
        indexedRowCount: ftsCount,
        rebuilt: rebuilt,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      _messageFtsReady = false;
      stopwatch.stop();
      return MessageFtsIndexHealth.unavailable(
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  Future<void> _createMessageFtsObjects() async {
    await customStatement(
      "CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5("
      "message_id UNINDEXED, "
      "session_id UNINDEXED, "
      "content, "
      "tokenize = 'unicode61'"
      ")",
    );
    await customStatement('''
CREATE TRIGGER IF NOT EXISTS messages_fts_ai
AFTER INSERT ON messages
WHEN new.message_type = 'original'
BEGIN
  INSERT INTO messages_fts(rowid, message_id, session_id, content)
  VALUES (new.rowid, new.id, new.session_id, new.content);
END;
''');
    await customStatement('''
CREATE TRIGGER IF NOT EXISTS messages_fts_ad
AFTER DELETE ON messages
BEGIN
  DELETE FROM messages_fts WHERE rowid = old.rowid;
END;
''');
    await customStatement('''
CREATE TRIGGER IF NOT EXISTS messages_fts_au
AFTER UPDATE OF content, message_type, session_id ON messages
BEGIN
  DELETE FROM messages_fts WHERE rowid = old.rowid;
  INSERT INTO messages_fts(rowid, message_id, session_id, content)
  SELECT new.rowid, new.id, new.session_id, new.content
  WHERE new.message_type = 'original';
END;
''');
  }

  Future<void> rebuildMessageFtsIndex() async {
    await customStatement('DELETE FROM messages_fts');
    await customStatement('''
INSERT INTO messages_fts(rowid, message_id, session_id, content)
SELECT rowid, id, session_id, content
FROM messages
WHERE message_type = 'original'
''');
  }

  Future<void> _createMessageSemanticIndexObjects() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS message_semantic_index (
  message_id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  vector_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_message_semantic_session '
      'ON message_semantic_index(session_id)',
    );
  }

  Future<void> rebuildMessageSemanticIndex([
    List<Message>? originalMessages,
  ]) async {
    await _createMessageSemanticIndexObjects();
    final source =
        originalMessages ?? await _getAllOriginalMessagesForSemanticIndex();
    await customStatement('DELETE FROM message_semantic_index');
    for (final message in source) {
      await _upsertMessageSemanticIndexRow(message);
    }
    _messageSemanticIndexReady = true;
  }

  Future<List<MessageSearchHit>> searchOriginalMessagesFullText(
    List<String> tokens, {
    int limit = 200,
  }) async {
    if (tokens.isEmpty) return const [];
    final ftsQuery = buildMessageFtsQuery(tokens);
    if (ftsQuery == null) return const [];
    final ready = await ensureMessageFtsIndex();
    if (!ready) return const [];

    try {
      final rows = await customSelect(
        '''
SELECT m.id AS message_id, messages_fts.rank AS rank
FROM messages_fts
JOIN messages AS m ON m.rowid = messages_fts.rowid
WHERE messages_fts MATCH ?
  AND m.message_type = 'original'
ORDER BY messages_fts.rank
LIMIT ?
''',
        variables: [Variable.withString(ftsQuery), Variable.withInt(limit)],
        readsFrom: {messages},
      ).get();
      if (rows.isEmpty) return const [];

      final ranks = <String, double>{};
      final ids = <String>[];
      for (final row in rows) {
        final id = row.data['message_id'] as String?;
        if (id == null) continue;
        ids.add(id);
        ranks[id] = ((row.data['rank'] as num?) ?? 0).toDouble();
      }
      if (ids.isEmpty) return const [];

      final foundMessages = await (select(
        messages,
      )..where((t) => t.id.isIn(ids))).get();
      final byId = {for (final message in foundMessages) message.id: message};
      return ids
          .map((id) {
            final message = byId[id];
            if (message == null) return null;
            return MessageSearchHit(message: message, rank: ranks[id] ?? 0);
          })
          .whereType<MessageSearchHit>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<MessageSemanticSearchHit>> searchOriginalMessagesSemantic(
    Map<String, double> queryVector, {
    double threshold = 0.22,
    int limit = 200,
  }) async {
    if (queryVector.isEmpty) return const [];
    if (!_messageSemanticIndexReady) {
      final health = await checkMessageSemanticIndexHealth(
        repairIfNeeded: true,
      );
      if (!health.isHealthy) return const [];
    }

    final rows = await _getMessageSemanticSearchRows();
    final scored = <_SemanticScore>[];
    for (final row in rows) {
      final vector = decodeMessageSemanticVector(row.vectorJson);
      final similarity = cosineSimilarity(queryVector, vector);
      if (similarity < threshold) continue;
      scored.add(_SemanticScore(row.messageId, similarity));
    }
    if (scored.isEmpty) return const [];
    scored.sort((a, b) => b.similarity.compareTo(a.similarity));
    final top = scored.take(limit).toList(growable: false);
    final ids = top.map((item) => item.messageId).toList(growable: false);
    final foundMessages = await (select(
      messages,
    )..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final message in foundMessages) message.id: message};
    return top
        .map((item) {
          final message = byId[item.messageId];
          if (message == null) return null;
          return MessageSemanticSearchHit(
            message: message,
            similarity: item.similarity,
          );
        })
        .whereType<MessageSemanticSearchHit>()
        .toList(growable: false);
  }

  Future<int> _countMessageFtsRows() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS total FROM messages_fts',
    ).getSingle();
    return row.data['total'] as int;
  }

  Future<int> _countOriginalMessages() async {
    final row = await customSelect(
      "SELECT COUNT(*) AS total FROM messages WHERE message_type = 'original'",
      readsFrom: {messages},
    ).getSingle();
    return row.data['total'] as int;
  }

  Future<List<Message>> _getAllOriginalMessagesForSemanticIndex() {
    return (select(messages)
          ..where((t) => t.messageType.equals('original'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<_MessageSemanticIndexRow>> _getMessageSemanticIndexRows() async {
    final rows = await customSelect(
      'SELECT message_id, content_hash FROM message_semantic_index',
    ).get();
    return rows
        .map(
          (row) => _MessageSemanticIndexRow(
            messageId: row.data['message_id'] as String,
            contentHash: row.data['content_hash'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<List<_MessageSemanticSearchRow>>
  _getMessageSemanticSearchRows() async {
    final rows = await customSelect(
      'SELECT message_id, vector_json FROM message_semantic_index',
    ).get();
    return rows
        .map(
          (row) => _MessageSemanticSearchRow(
            messageId: row.data['message_id'] as String,
            vectorJson: row.data['vector_json'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _upsertMessageSemanticIndexRow(Message message) async {
    await _upsertMessageSemanticIndexValues(
      id: message.id,
      sessionId: message.sessionId,
      content: message.content,
    );
  }

  Future<void> _upsertMessageSemanticIndexValues({
    required String id,
    required String sessionId,
    required String content,
  }) async {
    await _createMessageSemanticIndexObjects();
    final vector = buildLocalSemanticVector(content);
    await customStatement(
      '''
INSERT OR REPLACE INTO message_semantic_index (
  message_id, session_id, content_hash, vector_json, updated_at
) VALUES (?, ?, ?, ?, ?)
''',
      [
        id,
        sessionId,
        _messageContentHash(content),
        encodeMessageSemanticVector(vector),
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> _deleteMessageSemanticIndexRow(String messageId) async {
    await _createMessageSemanticIndexObjects();
    await customStatement(
      'DELETE FROM message_semantic_index WHERE message_id = ?',
      [messageId],
    );
    _messageSemanticIndexReady = false;
  }
}

String? buildMessageFtsQuery(List<String> tokens) {
  final terms = tokens
      .map((token) => token.trim().replaceAll('"', '""'))
      .where((token) => token.length >= 2)
      .take(12)
      .map((token) => '"$token"')
      .toList();
  if (terms.isEmpty) return null;
  return terms.join(' OR ');
}

String encodeMessageSemanticVector(Map<String, double> vector) {
  final sortedKeys = vector.keys.toList()..sort();
  return jsonEncode({
    for (final key in sortedKeys)
      key: double.parse(vector[key]!.toStringAsFixed(6)),
  });
}

Map<String, double> decodeMessageSemanticVector(String vectorJson) {
  final decoded = jsonDecode(vectorJson);
  if (decoded is! Map) return const {};
  return decoded.map((key, value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return MapEntry('$key', parsed ?? 0);
  })..removeWhere((_, value) => value == 0);
}

int _countStaleSemanticRows(
  List<Message> originalMessages,
  List<_MessageSemanticIndexRow> indexedRows,
) {
  final indexById = {for (final row in indexedRows) row.messageId: row};
  var count = 0;
  for (final message in originalMessages) {
    final indexed = indexById[message.id];
    if (indexed == null ||
        indexed.contentHash != _messageContentHash(message.content)) {
      count++;
    }
  }
  return count;
}

int _countExtraSemanticRows(
  List<Message> originalMessages,
  List<_MessageSemanticIndexRow> indexedRows,
) {
  final messageIds = originalMessages.map((message) => message.id).toSet();
  return indexedRows.where((row) => !messageIds.contains(row.messageId)).length;
}

String _messageContentHash(String content) {
  return sha256.convert(utf8.encode(content)).toString();
}

class _MessageSemanticIndexRow {
  const _MessageSemanticIndexRow({
    required this.messageId,
    required this.contentHash,
  });

  final String messageId;
  final String contentHash;
}

class _MessageSemanticSearchRow {
  const _MessageSemanticSearchRow({
    required this.messageId,
    required this.vectorJson,
  });

  final String messageId;
  final String vectorJson;
}

class _SemanticScore {
  const _SemanticScore(this.messageId, this.similarity);

  final String messageId;
  final double similarity;
}
