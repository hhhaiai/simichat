import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'message_dao.g.dart';

@DriftAccessor(tables: [Messages])
class MessageDao extends DatabaseAccessor<AppDatabase> with _$MessageDaoMixin {
  MessageDao(super.db);

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
          ..where((t) =>
              t.sessionId.equals(sessionId) & t.messageType.equals('summary'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<Message>> getUnsummarizedOriginals(String sessionId) {
    return (select(messages)
          ..where((t) =>
              t.sessionId.equals(sessionId) &
              t.isSummarized.equals(false) &
              t.messageType.equals('original'))
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
  }) {
    return into(messages).insert(MessagesCompanion.insert(
      id: id,
      sessionId: sessionId,
      role: role,
      content: content,
      thinkingContent: Value(thinkingContent),
      messageType: Value(messageType),
      channelModelId: Value(channelModelId),
      tokens: Value(tokens),
      responseMs: Value(responseMs),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<int> insertSummary({
    required String id,
    required String sessionId,
    required String content,
    required String summaryStartId,
    required String summaryEndId,
    int tokens = 0,
  }) {
    return into(messages).insert(MessagesCompanion.insert(
      id: id,
      sessionId: sessionId,
      role: 'system',
      content: content,
      messageType: const Value('summary'),
      summaryStartId: Value(summaryStartId),
      summaryEndId: Value(summaryEndId),
      tokens: Value(tokens),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> markAsSummarized(List<String> messageIds) {
    return (update(messages)..where((t) => t.id.isIn(messageIds)))
        .write(const MessagesCompanion(isSummarized: Value(true)));
  }

  Future<void> deleteMessage(String id) {
    return (delete(messages)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Message>> searchInSession(String sessionId, String query) {
    return (select(messages)
          ..where((t) =>
              t.sessionId.equals(sessionId) & t.content.like('%$query%'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<Message>> searchAll(String query) {
    return (select(messages)
          ..where((t) => t.content.like('%$query%'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }
}
