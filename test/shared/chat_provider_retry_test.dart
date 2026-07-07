import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
