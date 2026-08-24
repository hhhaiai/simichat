import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preferred chat model keeps an explicit valid choice', () async {
    final db = await _databaseWithDefaultCandidates();
    addTearDown(db.close);
    final models = await db.channelDao.getChatModels();

    expect(
      resolvePreferredChatModelId(
        models,
        selectedModelId: 'other-chat-model-id',
      ),
      'other-chat-model-id',
    );
  });

  test(
    'preferred chat model falls back to gpt-5.3-codex-spark when unselected',
    () async {
      final db = await _databaseWithDefaultCandidates();
      addTearDown(db.close);
      final models = await db.channelDao.getChatModels();

      expect(
        resolvePreferredChatModelId(models, selectedModelId: null),
        'spark-chat-model-id',
      );
      expect(
        resolvePreferredChatModelId(
          models,
          selectedModelId: 'removed-model-id',
        ),
        'spark-chat-model-id',
      );
    },
  );

  testWidgets(
    'new conversation persists gpt-5.3-codex-spark without opening a picker',
    (tester) async {
      final db = await _databaseWithDefaultCandidates();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => FilledButton(
                  onPressed: () => createNewSession(ref),
                  child: const Text('新建默认会话'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('新建默认会话'));
      await tester.pumpAndSettle();

      final sessionId = container.read(activeSessionIdProvider);
      expect(sessionId, isNotNull);
      final session = await db.sessionDao.getSession(sessionId!);
      expect(session?.defaultChannelModelId, 'spark-chat-model-id');
      expect(container.read(selectedModelIdProvider), 'spark-chat-model-id');
    },
  );

  testWidgets(
    'top selector displays gpt-5.3-codex-spark for an unbound conversation',
    (tester) async {
      final db = await _databaseWithDefaultCandidates();
      addTearDown(db.close);
      await db.sessionDao.createSession(id: 'unbound-session');
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      container.read(activeSessionIdProvider.notifier).state =
          'unbound-session';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                toolbarHeight: 72,
                title: const ChatModelSelector(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(kDefaultChatModelName), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('模型选择器，当前模型：$kDefaultChatModelName')),
        findsOneWidget,
      );
    },
  );
}

Future<AppDatabase> _databaseWithDefaultCandidates() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.channelDao.createChannel(
    id: 'other-channel',
    name: 'A other',
    baseUrl: 'https://example.invalid/v1',
    apiKeyEncrypted: 'test-only',
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'other-chat-model-id',
    channelId: 'other-channel',
    modelName: 'another-chat-model',
  );
  await db.channelDao.createChannel(
    id: 'spark-channel',
    name: 'Z spark',
    baseUrl: 'https://example.invalid/v1',
    apiKeyEncrypted: 'test-only',
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'spark-chat-model-id',
    channelId: 'spark-channel',
    modelName: kDefaultChatModelName,
  );
  return db;
}
