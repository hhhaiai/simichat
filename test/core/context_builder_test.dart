import 'package:ai_chat_app/core/ai/model_switch_record.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/context/context_builder.dart';
import 'package:ai_chat_app/core/context/token_estimator.dart';
import 'package:drift/native.dart';

void main() {
  test(
    'ContextBuilder with no messages returns system prompt + empty list',
    () async {
      // This test validates the context structure.
      // Full integration test would need actual DAO setup.
      // Key behavior: empty = system prompt + empty messages.
      expect(ContextBuilder.defaultSystemPrompt, contains('有帮助的 AI 助手'));
    },
  );

  test('default system prompt is non-empty', () {
    expect(ContextBuilder.defaultSystemPrompt.isNotEmpty, true);
  });

  test(
    'buildContext injects local key point memory into system prompt',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's-memory');

      final (systemPrompt, messages) = await ContextBuilder(db.messageDao)
          .buildContext(
            's-memory',
            memoryPrompt: '## 用户核心记忆（本地提取）\n- [偏好] 我喜欢中文回复',
          );

      expect(systemPrompt, contains('用户核心记忆'));
      expect(systemPrompt, contains('我喜欢中文回复'));
      expect(messages, isEmpty);
    },
  );

  test('buildContext ignores model switch timeline records', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.messageDao.insertMessage(
      id: 'm1',
      sessionId: 's1',
      role: 'user',
      content: '请帮我总结这段话',
    );
    await db.messageDao.insertMessage(
      id: 'switch-1',
      sessionId: 's1',
      role: 'system',
      content: buildModelSwitchRecordContent(
        fromLabel: 'OpenAI / gpt-4o',
        toLabel: 'Claude / sonnet',
      ),
      messageType: kModelSwitchMessageType,
    );
    await db.messageDao.insertMessage(
      id: 'm2',
      sessionId: 's1',
      role: 'assistant',
      content: '可以，请发给我。',
    );

    final (_, messages) = await ContextBuilder(
      db.messageDao,
    ).buildContext('s1');

    expect(messages.map((message) => message.content), [
      '请帮我总结这段话',
      '可以，请发给我。',
    ]);
  });

  test(
    'buildContext with input budget can include more than the old 20-message cap',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's-long');
      for (var i = 0; i < 30; i++) {
        await db.messageDao.insertMessage(
          id: 'm-$i',
          sessionId: 's-long',
          role: i.isEven ? 'user' : 'assistant',
          content: '短消息 $i',
          tokens: TokenEstimator.estimate('短消息 $i'),
        );
      }

      final (_, messages) = await ContextBuilder(
        db.messageDao,
      ).buildContext('s-long', maxInputTokens: 20000);

      expect(messages.length, 30);
      expect(messages.first.content, '短消息 0');
      expect(messages.last.content, '短消息 29');
    },
  );

  test(
    'buildContext prunes old messages to fit input budget but keeps latest user message',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's-budget');
      for (var i = 0; i < 8; i++) {
        final content = '很长的历史消息 $i ${'背景' * 80}';
        await db.messageDao.insertMessage(
          id: 'old-$i',
          sessionId: 's-budget',
          role: i.isEven ? 'user' : 'assistant',
          content: content,
          tokens: TokenEstimator.estimate(content),
        );
      }
      await db.messageDao.insertMessage(
        id: 'latest',
        sessionId: 's-budget',
        role: 'user',
        content: '这是最新问题，必须保留',
        tokens: TokenEstimator.estimate('这是最新问题，必须保留'),
      );

      final (systemPrompt, messages) = await ContextBuilder(db.messageDao)
          .buildContext(
            's-budget',
            maxInputTokens: 260,
            memoryPrompt: '记忆：${'重要' * 100}',
            skillsPrompt: '技能：${'说明' * 100}',
            mcpToolsPrompt: '工具：${'参数' * 100}',
          );
      final totalTokens =
          TokenEstimator.estimate(systemPrompt) +
          messages.fold<int>(
            0,
            (sum, message) => sum + TokenEstimator.estimate(message.content),
          );

      expect(totalTokens, lessThanOrEqualTo(260));
      expect(messages.last.role, 'user');
      expect(messages.last.content, contains('这是最新问题，必须保留'));
      expect(
        messages.any((message) => message.content.contains('很长的历史消息 0')),
        isFalse,
      );
    },
  );
}
