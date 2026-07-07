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
      expect(
        digest.sessions.single.toJson(),
        containsPair('lastMessageRole', 'assistant'),
      );
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

  test('dreaming service redacts secret-like session titles', () async {
    final now = DateTime(2026, 7, 7, 21);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.sessionDao.updateTitle('s1', '临时会话 sk-test-secret-1234567890');
    await db.messageDao.insertMessage(
      id: 'safe-message',
      sessionId: 's1',
      role: 'user',
      content: '请继续推进本地反思。',
    );
    await db.customStatement(
      "UPDATE messages SET created_at = ${now.millisecondsSinceEpoch} WHERE id = 'safe-message'",
    );

    final digest = await DreamingService(
      sessionDao: db.sessionDao,
      messageDao: db.messageDao,
      now: () => now,
    ).runDailyDigest(day: now);

    expect(digest.sessions.single.toJson(), containsPair('title', '敏感会话'));
    expect(digest.toMarkdown(), contains('敏感会话'));
    expect(digest.toMarkdown(), isNot(contains('sk-test-secret')));

    final reloaded = DreamingDigest.fromJson({
      ...digest.toJson(),
      'sessions': [
        {
          ...digest.sessions.single.toJson(),
          'title': 'Authorization Bearer secret-token',
        },
      ],
    });
    expect(reloaded.sessions.single.toJson(), containsPair('title', '敏感会话'));
  });

  test(
    'dreaming service keeps latest user highlight beyond first highlights',
    () async {
      final now = DateTime(2026, 7, 7, 22);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's1');
      await db.sessionDao.updateTitle('s1', '多轮追问');
      for (var i = 0; i < 4; i++) {
        await db.messageDao.insertMessage(
          id: 'u$i',
          sessionId: 's1',
          role: 'user',
          content: '第 $i 轮：请继续推进 Dreaming 后台调度方案。',
        );
        await db.customStatement(
          "UPDATE messages SET created_at = ${now.add(Duration(minutes: i)).millisecondsSinceEpoch} WHERE id = 'u$i'",
        );
      }

      final digest = await DreamingService(
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
        now: () => now,
      ).runDailyDigest(day: now);

      expect(digest.sessions.single.highlights, hasLength(3));
      expect(
        digest.sessions.single.highlights.join('\n'),
        isNot(contains('第 3 轮')),
      );
      expect(
        digest.sessions.single.toJson(),
        containsPair('latestUserHighlight', contains('第 3 轮')),
      );
      expect(digest.toMarkdown(), contains('最新用户问题'));
      expect(digest.toMarkdown(), contains('第 3 轮'));

      final reloaded = DreamingDigest.fromJson(digest.toJson());
      expect(
        reloaded.sessions.single.toJson(),
        containsPair('latestUserHighlight', contains('第 3 轮')),
      );
    },
  );

  test(
    'dreaming service extracts latest explicit task as memory candidate',
    () async {
      final now = DateTime(2026, 7, 7, 22);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's1');
      await db.sessionDao.updateTitle('s1', '最新任务');
      await db.messageDao.insertMessage(
        id: 'task-message',
        sessionId: 's1',
        role: 'user',
        content: '现在继续推进 iOS 网络切换真机复跑。',
      );
      await db.customStatement(
        "UPDATE messages SET created_at = ${now.millisecondsSinceEpoch} WHERE id = 'task-message'",
      );

      final digest = await DreamingService(
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
        now: () => now,
      ).runDailyDigest(day: now);

      final candidates = digest.memoryCandidates;
      expect(candidates.map((item) => item.category), contains('task'));
      expect(
        candidates.map((item) => item.content).join('\n'),
        contains('iOS 网络切换真机复跑'),
      );
    },
  );

  test(
    'dreaming service does not backfill latest user highlight when latest is sensitive',
    () async {
      final now = DateTime(2026, 7, 7, 23);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's1');
      await db.messageDao.insertMessage(
        id: 'safe',
        sessionId: 's1',
        role: 'user',
        content: '请继续推进 Dreaming 后台调度方案。',
      );
      await db.customStatement(
        "UPDATE messages SET created_at = ${now.millisecondsSinceEpoch} WHERE id = 'safe'",
      );
      await db.messageDao.insertMessage(
        id: 'secret',
        sessionId: 's1',
        role: 'user',
        content: '我的 API Key 是 ${'sk-test-'}secret-1234567890，请不要泄露。',
      );
      await db.customStatement(
        "UPDATE messages SET created_at = ${now.add(const Duration(minutes: 1)).millisecondsSinceEpoch} WHERE id = 'secret'",
      );

      final digest = await DreamingService(
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
        now: () => now,
      ).runDailyDigest(day: now);

      expect(digest.sessions.single.highlights.single, contains('后台调度方案'));
      expect(
        digest.sessions.single.toJson(),
        isNot(contains('latestUserHighlight')),
      );
      expect(digest.toMarkdown(), isNot(contains('最新用户问题')));
      expect(digest.toMarkdown(), isNot(contains('secret-1234567890')));
    },
  );

  test(
    'dreaming service keeps latest messages when daily messages are truncated',
    () async {
      final now = DateTime(2026, 7, 6, 22);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's1');
      for (var i = 0; i < 3; i++) {
        await db.messageDao.insertMessage(
          id: 'm$i',
          sessionId: 's1',
          role: 'user',
          content: '请记住第 $i 条移动端稳定性重点。',
        );
        await db.customStatement(
          "UPDATE messages SET created_at = ${now.add(Duration(minutes: i)).millisecondsSinceEpoch} WHERE id = 'm$i'",
        );
      }

      final digest = await DreamingService(
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
        now: () => now,
      ).runDailyDigest(day: now, maxMessages: 2);

      expect(digest.isTruncated, isTrue);
      expect(digest.messageLimit, 2);
      expect(digest.originalMessageCount, 2);
      expect(digest.totalOriginalMessageCount, 3);
      expect(digest.userMessageCount, 2);
      expect(digest.sessions.single.messageCount, 2);
      expect(digest.sessions.single.highlights.join('\n'), contains('第 1 条'));
      expect(digest.sessions.single.highlights.join('\n'), contains('第 2 条'));
      expect(
        digest.sessions.single.highlights.join('\n'),
        isNot(contains('第 0 条')),
      );
      expect(digest.toMarkdown(), contains('只整理最近 2 条原始消息'));
      expect(digest.toMarkdown(), contains('当天共有 3 条原始消息'));
      expect(digest.toMarkdown(), contains('第 2 条移动端稳定性重点'));
      expect(digest.toMarkdown(), isNot(contains('第 0 条移动端稳定性重点')));

      final reloaded = DreamingDigest.fromJson(digest.toJson());
      expect(reloaded.isTruncated, isTrue);
      expect(reloaded.messageLimit, 2);
      expect(reloaded.totalOriginalMessageCount, 3);
      expect(
        reloaded.sessions.single.toJson(),
        containsPair('lastMessageRole', 'user'),
      );
    },
  );
}
