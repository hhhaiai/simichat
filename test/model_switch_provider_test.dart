import 'dart:async';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'switchConversationModel rolls back selection on persistence failure',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      late WidgetRef capturedRef;
      Object? caughtError;
      final done = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return MaterialApp(
                home: Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      try {
                        await switchConversationModel(
                          ref: ref,
                          modelId: 'new-model',
                          modelLabel: 'New / model',
                          previousModelId: 'old-model',
                          previousModelLabel: 'Old / model',
                        );
                      } catch (e) {
                        caughtError = e;
                      } finally {
                        if (!done.isCompleted) done.complete();
                      }
                    },
                    child: const Text('switch'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      capturedRef.read(activeSessionIdProvider.notifier).state = 'session-1';
      capturedRef.read(selectedModelIdProvider.notifier).state = 'old-model';
      await db.channelDao.createChannel(
        id: 'channel-1',
        name: 'Test',
        baseUrl: 'https://example.invalid',
        apiKeyEncrypted: 'encrypted-test-key',
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'old-model',
        channelId: 'channel-1',
        modelName: 'old',
      );
      await db.channelDao.addModel(
        id: 'new-model',
        channelId: 'channel-1',
        modelName: 'new',
      );
      await db.sessionDao.createSession(
        id: 'session-1',
        defaultChannelModelId: 'old-model',
      );
      await db.customStatement('DROP TABLE messages');

      await tester.tap(find.text('switch'));
      await done.future;
      await tester.pump();

      expect(caughtError, isNotNull);
      expect(capturedRef.read(selectedModelIdProvider), 'old-model');
      final session = await db.sessionDao.getSession('session-1');
      expect(session?.defaultChannelModelId, 'old-model');
      await db.close();
    },
  );
}
