import 'package:ai_chat_app/core/ai/model_switch_record.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dreaming service builds local daily digest and memory candidates',
    () async {
      final now = DateTime.now();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's1');
      await db.sessionDao.updateTitle('s1', '长期目标');
      await db.messageDao.insertMessage(
        id: 'm1',
        sessionId: 's1',
        role: 'user',
        content: '请记住我喜欢中文回复，我的目标是把 SimiChat 做成移动端优先的 AI 伙伴。',
      );
      await db.messageDao.insertMessage(
        id: 'm2',
        sessionId: 's1',
        role: 'assistant',
        content: '已记录你的偏好。',
      );
      await db.messageDao.insertMessage(
        id: 'switch',
        sessionId: 's1',
        role: 'system',
        content: buildModelSwitchRecordContent(
          fromLabel: 'OpenAI',
          toLabel: 'Claude',
        ),
        messageType: kModelSwitchMessageType,
      );

      final digest = await DreamingService(
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
        now: () => now,
      ).runDailyDigest(day: now);

      expect(digest.hasContent, isTrue);
      expect(digest.sessionCount, 1);
      expect(digest.originalMessageCount, 2);
      expect(digest.userMessageCount, 1);
      expect(digest.assistantMessageCount, 1);
      expect(digest.sessions.single.title, '长期目标');
      expect(digest.sessions.single.highlights.single, contains('中文回复'));
      expect(
        digest.memoryCandidates.map((item) => item.content).join('\n'),
        contains('移动端优先'),
      );
      expect(digest.toMarkdown(), contains('Dreaming 日报'));
      expect(digest.toMarkdown(), isNot(contains('Claude')));
    },
  );

  test('dreaming service skips secret-like content from highlights', () async {
    final now = DateTime.now();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.messageDao.insertMessage(
      id: 'secret-message',
      sessionId: 's1',
      role: 'user',
      content: '我的 API Key 是 ${'sk-test-'}secret-1234567890，请记住它。',
    );

    final digest = await DreamingService(
      sessionDao: db.sessionDao,
      messageDao: db.messageDao,
      now: () => now,
    ).runDailyDigest(day: now);

    expect(digest.originalMessageCount, 1);
    expect(digest.sessions.single.highlights, isEmpty);
    expect(digest.memoryCandidates, isEmpty);
    expect(digest.toMarkdown(), isNot(contains('secret-1234567890')));
  });
}
