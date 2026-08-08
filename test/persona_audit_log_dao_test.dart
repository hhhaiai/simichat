import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/database/dao/persona_audit_log_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PersonaAuditLogDao', () {
    test('inserts and queries persona reply audit logs', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.personaAuditLogDao.insertLog(
        eventType: PersonaAuditEventType.authorize,
        summary: '授权',
      );
      await db.personaAuditLogDao.insertLog(
        eventType: PersonaAuditEventType.personaReply,
        sessionId: 's1',
        messageId: 'm1',
        summary: '替身回复 12 字符',
      );
      await db.personaAuditLogDao.insertLog(
        eventType: PersonaAuditEventType.revoke,
        summary: '撤销',
      );

      final all = await db.personaAuditLogDao.getRecentLogs();
      expect(all, hasLength(3));
      expect(
        all.map((e) => e.eventType),
        containsAll([
          PersonaAuditEventType.authorize,
          PersonaAuditEventType.personaReply,
          PersonaAuditEventType.revoke,
        ]),
      );

      final replies = await db.personaAuditLogDao.getLogsByType(
        PersonaAuditEventType.personaReply,
      );
      expect(replies, hasLength(1));
      expect(replies.first.sessionId, 's1');
      expect(replies.first.messageId, 'm1');

      expect(
        await db.personaAuditLogDao.countByType(
          PersonaAuditEventType.authorize,
        ),
        1,
      );
    });

    test('clearLogs removes all records', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.personaAuditLogDao.insertLog(
        eventType: PersonaAuditEventType.authorize,
      );
      await db.personaAuditLogDao.clearLogs();

      expect(await db.personaAuditLogDao.getRecentLogs(), isEmpty);
    });
  });
}
