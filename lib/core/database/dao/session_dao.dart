import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'session_dao.g.dart';

@DriftAccessor(tables: [Sessions, Messages])
class SessionDao extends DatabaseAccessor<AppDatabase> with _$SessionDaoMixin {
  SessionDao(super.db);

  Future<List<Session>> getAllSessions() {
    // 置顶会话优先于最近活跃时间排序，源头保证所有调用方一致。
    return (select(sessions)
          ..orderBy([
            (t) => OrderingTerm.desc(t.isPinned),
            (t) => OrderingTerm.desc(t.lastMessageAt),
          ]))
        .get();
  }

  Future<List<Session>> getSessionsByFolder(String folderId) {
    return (select(sessions)
          ..where((t) => t.folderId.equals(folderId))
          ..orderBy([(t) => OrderingTerm.desc(t.lastMessageAt)]))
        .get();
  }

  Future<Session?> getSession(String id) {
    return (select(sessions)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> createSession({
    required String id,
    String? folderId,
    String? defaultChannelModelId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(sessions).insert(SessionsCompanion.insert(
      id: id,
      folderId: Value(folderId),
      defaultChannelModelId: Value(defaultChannelModelId),
      createdAt: now,
      lastMessageAt: now,
    ));
  }

  Future<void> updateTitle(String id, String title) {
    return (update(sessions)..where((t) => t.id.equals(id)))
        .write(SessionsCompanion(title: Value(title)));
  }

  Future<void> updateLastMessageAt(String id) {
    return (update(sessions)..where((t) => t.id.equals(id))).write(
      SessionsCompanion(lastMessageAt: Value(DateTime.now().millisecondsSinceEpoch)),
    );
  }

  Future<void> updateTotalTokens(String id, int tokens) {
    return (update(sessions)..where((t) => t.id.equals(id)))
        .write(SessionsCompanion(totalTokens: Value(tokens)));
  }

  Future<void> updateDefaultModel(String id, String? channelModelId) {
    return (update(sessions)..where((t) => t.id.equals(id)))
        .write(SessionsCompanion(defaultChannelModelId: Value(channelModelId)));
  }

  Future<void> moveToFolder(String sessionId, String? folderId) {
    return (update(sessions)..where((t) => t.id.equals(sessionId)))
        .write(SessionsCompanion(folderId: Value(folderId)));
  }

  Future<void> setPinned(String id, bool isPinned) {
    return (update(sessions)..where((t) => t.id.equals(id)))
        .write(SessionsCompanion(isPinned: Value(isPinned)));
  }

  Future<void> deleteSession(String id) async {
    // Messages are cascade-deleted via onDelete: KeyAction.cascade in tables.dart
    await (delete(sessions)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Session>> searchSessions(String query, {int limit = 200}) {
    return (select(sessions)
          ..where((t) => t.title.like('%$query%'))
          ..orderBy([(t) => OrderingTerm.desc(t.lastMessageAt)])
          ..limit(limit.clamp(1, 500).toInt()))
        .get();
  }
}
