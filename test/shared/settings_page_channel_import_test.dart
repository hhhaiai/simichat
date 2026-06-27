import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/ai/model_tester.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings page imports multiple model channels from json', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('批量导入渠道'), findsOneWidget);
    await tester.tap(find.text('批量导入渠道'));
    await tester.pumpAndSettle();

    expect(find.text('渠道 JSON'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '''
    {
      "channels": [
        {
          "name": "Free Router",
          "baseUrl": "free.example.com/v1",
          "protocol": "openai_chat",
          "apiKey": "free-test-key",
          "models": [
            {"name": "free-chat", "capability": "chat"},
            {"name": "free-vision", "capability": "vision"},
            {"name": "free-embed", "capability": "embedding"}
          ]
        },
        {
          "name": "Local Ollama",
          "baseUrl": "localhost:11434",
          "protocol": "ollama",
          "models": ["llama3.1"]
        }
      ]
    }
    ''');

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    final channels = await db.channelDao.getAllChannels();
    expect(
      channels.map((c) => c.name),
      containsAll(['Free Router', 'Local Ollama']),
    );

    final freeChannel = channels.firstWhere((c) => c.name == 'Free Router');
    expect(freeChannel.baseUrl, 'https://free.example.com/v1');
    expect(KeyEncryptor.decrypt(freeChannel.apiKeyEncrypted), 'free-test-key');
    final freeModels = await db.channelDao.getModelsByChannel(freeChannel.id);
    expect(
      freeModels.map((m) => m.modelName),
      containsAll(['free-chat', 'free-vision', 'free-embed']),
    );
    expect(
      freeModels.map((m) => m.capability),
      containsAll(['chat', 'vision', 'embedding']),
    );

    final ollama = channels.firstWhere((c) => c.name == 'Local Ollama');
    expect(ollama.baseUrl, 'http://localhost:11434');
    expect(KeyEncryptor.decrypt(ollama.apiKeyEncrypted), isEmpty);
    final ollamaModels = await db.channelDao.getModelsByChannel(ollama.id);
    expect(ollamaModels.single.modelName, 'llama3.1');

    expect(find.textContaining('已导入 2 个渠道、4 个模型'), findsOneWidget);
    expect(find.textContaining('free-test-key'), findsNothing);
  });

  testWidgets('settings page deletes a channel with existing model references', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'delete-channel',
      name: 'Delete Me',
      baseUrl: 'https://delete.example.com/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('delete-test-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'delete-model',
      channelId: 'delete-channel',
      modelName: 'delete-model-name',
    );
    await db.sessionDao.createSession(
      id: 'delete-session',
      defaultChannelModelId: 'delete-model',
    );
    await db.messageDao.insertMessage(
      id: 'delete-message',
      sessionId: 'delete-session',
      role: 'assistant',
      content: 'ok',
      channelModelId: 'delete-model',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete Me'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Me'), findsNothing);
    expect(await db.channelDao.getAllChannels(), isEmpty);
    expect(await db.channelDao.getModelsByChannel('delete-channel'), isEmpty);
    final session = await db.sessionDao.getSession('delete-session');
    expect(session!.defaultChannelModelId, isNull);
    final messages = await db.messageDao.getMessagesBySession('delete-session');
    expect(messages.single.channelModelId, isNull);
  });

  testWidgets('settings page one-tap test prunes unavailable models', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.channelDao.createChannel(
      id: 'prune-channel',
      name: 'Prune Channel',
      baseUrl: 'https://api.example.com/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'good-model-id',
      channelId: 'prune-channel',
      modelName: 'good-model',
    );
    await db.channelDao.addModel(
      id: 'bad-model-id',
      channelId: 'prune-channel',
      modelName: 'bad-model',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: SettingsPage(
            modelTestRunner:
                ({
                  required protocol,
                  required baseUrl,
                  required apiKey,
                  required model,
                  required capability,
                }) async {
                  if (model == 'good-model') {
                    return ModelTestResult.success();
                  }
                  return ModelTestResult.failure('HTTP 404 model not found');
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Prune Channel'));
    await tester.pumpAndSettle();
    expect(find.text('一键测试并剔除不可用'), findsOneWidget);

    await tester.tap(find.text('一键测试并剔除不可用'));
    await tester.pumpAndSettle();

    final models = await db.channelDao.getModelsByChannel('prune-channel');
    expect(models.map((m) => m.modelName), contains('good-model'));
    expect(models.map((m) => m.modelName), isNot(contains('bad-model')));
    expect(find.textContaining('已剔除 1 个不可用模型'), findsOneWidget);
  });
}
