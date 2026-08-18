import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retry resolver anchors the clicked assistant to its preceding user turn',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      const sessionId = 'session-retry-specific';
      await db.sessionDao.createSession(id: sessionId);
      await db.messageDao.insertMessage(
        id: 'retry-user-a',
        sessionId: sessionId,
        role: 'user',
        content: '第一轮问题',
      );
      await db.messageDao.insertMessage(
        id: 'retry-assistant-a',
        sessionId: sessionId,
        role: 'assistant',
        content: '第一轮回答',
      );
      await db.messageDao.insertMessage(
        id: 'retry-user-b',
        sessionId: sessionId,
        role: 'user',
        content: '第二轮问题',
      );
      await db.messageDao.insertMessage(
        id: 'retry-assistant-b',
        sessionId: sessionId,
        role: 'assistant',
        content: '第二轮回答',
      );

      final messages = await db.messageDao.getMessagesBySession(sessionId);
      expect(
        resolveRetryUserMessageIdForTesting(messages, 'retry-assistant-a'),
        'retry-user-a',
      );
      expect(
        resolveRetryUserMessageIdForTesting(messages, 'retry-assistant-b'),
        'retry-user-b',
      );
      expect(
        resolveRetryUserMessageIdForTesting(messages, 'retry-user-b'),
        isNull,
      );
      expect(
        resolveRetryUserMessageIdForTesting(messages, 'missing-assistant'),
        isNull,
      );
    },
  );

  test(
    'retry model helpers preserve assistant model ids and fallback safely',
    () {
      final messages = [
        _message(
          id: 'retry-model-user-a',
          role: 'user',
          content: '第一轮问题',
          createdAt: 1,
        ),
        _message(
          id: 'retry-model-assistant-a',
          role: 'assistant',
          content: '第一轮回答',
          channelModelId: 'model-a',
          createdAt: 2,
        ),
        _message(
          id: 'retry-model-assistant-a-regenerated',
          role: 'assistant',
          content: '第一轮重新回答',
          channelModelId: ' model-b ',
          createdAt: 3,
        ),
        _message(
          id: 'retry-model-user-b',
          role: 'user',
          content: '第二轮问题',
          createdAt: 4,
        ),
      ];

      expect(
        resolveRetryModelIdForTesting(messages, 'retry-model-assistant-a'),
        'model-a',
      );
      expect(
        resolveRetryModelIdForUserMessageForTesting(
          messages,
          'retry-model-user-a',
        ),
        'model-b',
      );
      expect(
        resolveRetryModelIdForUserMessageForTesting(
          messages,
          'retry-model-user-b',
        ),
        isNull,
      );
      expect(
        resolveRetryModelIdForTesting(messages, 'missing-assistant'),
        isNull,
      );
    },
  );

  testWidgets('retry loads last user message even before messages provider', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const sessionId = 'session-retry-provider-loading';
    await db.sessionDao.createSession(id: sessionId);
    await db.messageDao.insertMessage(
      id: 'message-retry-user',
      sessionId: sessionId,
      role: 'user',
      content: '请重试这条后台中断前的消息',
    );

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.read(streamStateProvider(sessionId).notifier).state =
        const StreamState(error: backgroundStreamingInterruptedMessage);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              return TextButton(
                onPressed: () =>
                    retryLastUserMessage(ref, sessionId: sessionId),
                child: const Text('retry'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();

    expect(container.read(streamStateProvider(sessionId)).error, '请先选择一个模型');
    expect(tester.takeException(), isNull);
  });
}

Message _message({
  required String id,
  required String role,
  required String content,
  required int createdAt,
  String? channelModelId,
}) {
  return Message(
    id: id,
    sessionId: 'retry-model-session',
    role: role,
    content: content,
    messageType: 'original',
    isSummarized: false,
    channelModelId: channelModelId,
    tokens: 0,
    createdAt: createdAt,
  );
}
