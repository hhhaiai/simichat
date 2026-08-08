import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'persona_audit_log_dao.g.dart';

/// 审计事件类型常量。
abstract final class PersonaAuditEventType {
  static const authorize = 'authorize';
  static const revoke = 'revoke';
  static const personaReply = 'persona_reply';
}

/// 替身回复审计日志 DAO。
///
/// 记录授权 / 撤销与每次替身回复（会话、消息、摘要），供用户审阅与追溯。
@DriftAccessor(tables: [PersonaAuditLogs])
class PersonaAuditLogDao extends DatabaseAccessor<AppDatabase>
    with _$PersonaAuditLogDaoMixin {
  PersonaAuditLogDao(super.db);

  Future<void> insertLog({
    required String eventType,
    String? sessionId,
    String? messageId,
    String summary = '',
  }) {
    return into(personaAuditLogs).insert(
      PersonaAuditLogsCompanion.insert(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        eventType: eventType,
        sessionId: Value(sessionId),
        messageId: Value(messageId),
        summary: Value(summary),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<List<PersonaAuditLog>> getRecentLogs({int limit = 100}) {
    return (select(personaAuditLogs)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<List<PersonaAuditLog>> getLogsByType(
    String eventType, {
    int limit = 100,
  }) {
    return (select(personaAuditLogs)
          ..where((t) => t.eventType.equals(eventType))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<int> countByType(String eventType) {
    return (selectOnly(personaAuditLogs)
          ..addColumns([personaAuditLogs.id.count()])
          ..where(personaAuditLogs.eventType.equals(eventType)))
        .map((row) => row.read(personaAuditLogs.id.count()) ?? 0)
        .getSingle();
  }

  Future<void> clearLogs() => delete(personaAuditLogs).go();
}
