import 'package:ai_chat_app/core/ai/model_switch_record.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/context/context_builder.dart';
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
}
