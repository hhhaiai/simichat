import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/ai/model_tester.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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

  testWidgets('batch import dialog defaults to preset-based example', (
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

    await tester.tap(find.text('批量导入渠道'));
    await tester.pumpAndSettle();

    final importField = tester.widget<TextField>(find.byType(TextField).last);
    final initialJson = importField.controller!.text;
    expect(initialJson, contains('"presetId": "groq"'));
    expect(initialJson, contains('"apiKey": "在这里粘贴自己的 Groq Key"'));
    expect(initialJson, contains('"models": ['));
    expect(initialJson, isNot(contains('api.example.com')));
    expect(find.textContaining('presetId/provider'), findsOneWidget);
    expect(find.textContaining('渠道对象、数组'), findsOneWidget);
    expect(find.textContaining('model/modelName'), findsOneWidget);
  });

  testWidgets('batch import dialog copies safe preset example json', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('批量导入渠道'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '{"apiKey":"sk-live-should-not-copy"}',
    );

    await tester.tap(find.text('复制示例 JSON'));
    await tester.pumpAndSettle();

    expect(copiedText, contains('"presetId": "groq"'));
    expect(copiedText, contains('"apiKey": "在这里粘贴自己的 Groq Key"'));
    expect(copiedText, isNot(contains('sk-live-should-not-copy')));
    expect(find.text('示例 JSON 已复制'), findsOneWidget);
  });

  testWidgets('batch import dialog restores safe preset example json', (
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

    await tester.tap(find.text('批量导入渠道'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '{"apiKey":"sk-live-should-not-restore"}',
    );

    await tester.tap(find.text('恢复示例'));
    await tester.pumpAndSettle();

    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.controller.text, contains('"presetId": "groq"'));
    expect(
      editableText.controller.text,
      contains('"apiKey": "在这里粘贴自己的 Groq Key"'),
    );
    expect(editableText.controller.text, isNot(contains('sk-live')));
    expect(find.text('已恢复示例 JSON'), findsOneWidget);
  });

  testWidgets('batch import dialog pastes json from clipboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const clipboardJson =
        '{"channels":[{"presetId":"mistral","apiKey":"paste-test-key","models":["mistral-small-latest"]}]}';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboardJson};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('批量导入渠道'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '{}');

    await tester.tap(find.text('粘贴剪贴板'));
    await tester.pumpAndSettle();

    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.controller.text, clipboardJson);
    expect(find.text('已从剪贴板粘贴 JSON'), findsOneWidget);
  });

  testWidgets(
    'settings page deletes a channel with existing model references',
    (tester) async {
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
      final messages = await db.messageDao.getMessagesBySession(
        'delete-session',
      );
      expect(messages.single.channelModelId, isNull);
    },
  );

  testWidgets('provider preset hint shows recommended starter models', (
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

    await tester.tap(find.text('添加渠道'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kimi / Moonshot AI').last);
    await tester.pumpAndSettle();

    expect(find.text('建议模型名'), findsOneWidget);
    expect(find.textContaining('kimi-k2-0711-preview'), findsOneWidget);
    expect(find.textContaining('moonshot-v1-8k'), findsOneWidget);
  });

  testWidgets('provider preset hint copies recommended starter models', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加渠道'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kimi / Moonshot AI').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('复制建议模型名'));
    await tester.pumpAndSettle();

    expect(copiedText, 'kimi-k2-0711-preview\nmoonshot-v1-8k');
    expect(find.text('建议模型名已复制'), findsOneWidget);
  });

  testWidgets('provider preset hint copies provider docs link', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加渠道'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kimi / Moonshot AI').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('复制文档链接'));
    await tester.pumpAndSettle();

    expect(copiedText, 'https://platform.kimi.ai/docs/api/overview');
    expect(find.text('文档链接已复制'), findsOneWidget);
  });

  testWidgets('provider preset hint copies provider base url', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加渠道'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kimi / Moonshot AI').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('复制 Base URL'));
    await tester.pumpAndSettle();

    expect(copiedText, 'https://api.moonshot.ai/v1');
    expect(find.text('Base URL 已复制'), findsOneWidget);
  });

  testWidgets('add model dialog fills recommended model from channel preset', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.channelDao.createChannel(
      id: 'moonshot-channel',
      name: 'Kimi Channel',
      baseUrl: 'https://api.moonshot.ai/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('moonshot-test-key'),
      protocol: 'openai_chat',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kimi Channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动添加模型'));
    await tester.pumpAndSettle();

    expect(find.text('预设推荐模型'), findsOneWidget);
    await tester.tap(find.text('kimi-k2-0711-preview'));
    await tester.pumpAndSettle();

    final editableText = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(EditableText),
      ),
    );
    expect(editableText.controller.text, 'kimi-k2-0711-preview');
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

    // 设置页首部 SimiRouter 推广卡片占位较高，先滚动到渠道 tile 再点击。
    await tester.scrollUntilVisible(
      find.text('Prune Channel'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prune Channel'));
    await tester.pumpAndSettle();
    expect(find.text('一键测试并剔除不可用'), findsOneWidget);

    await tester.tap(find.text('一键测试并剔除不可用'));
    await tester.pumpAndSettle();

    // 删除前必须经过确认对话框：列出待删模型与原因。
    expect(find.text('确认剔除不可用模型'), findsOneWidget);
    expect(find.textContaining('• bad-model'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-prune-models')));
    await tester.pumpAndSettle();

    final models = await db.channelDao.getModelsByChannel('prune-channel');
    expect(models.map((m) => m.modelName), contains('good-model'));
    expect(models.map((m) => m.modelName), isNot(contains('bad-model')));
    expect(find.textContaining('已剔除 1 个不可用模型'), findsOneWidget);
  });

  testWidgets('prune keeps transient failures and skipped media models', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.channelDao.createChannel(
      id: 'prune-keep-channel',
      name: 'Prune Keep Channel',
      baseUrl: 'https://api.example.com/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'ok-model-id',
      channelId: 'prune-keep-channel',
      modelName: 'ok-model',
    );
    await db.channelDao.addModel(
      id: 'flaky-model-id',
      channelId: 'prune-keep-channel',
      modelName: 'flaky-model',
    );
    await db.channelDao.addModel(
      id: 'video-model-id',
      channelId: 'prune-keep-channel',
      modelName: 'grok-imagine-video',
      capability: 'video',
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
                  if (model == 'ok-model') {
                    return ModelTestResult.success();
                  }
                  if (model == 'flaky-model') {
                    return ModelTestResult.failure('[429] too many requests');
                  }
                  // grok-imagine-video 是 video 能力：即使 runner 被调用，
                  // 也会因能力拦截返回 skipped。
                  return ModelTestResult.success();
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Prune Keep Channel'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prune Keep Channel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('一键测试并剔除不可用'));
    await tester.pumpAndSettle();

    // 临时失败与媒体模型都不进确认删除对话框：无永久失败直接提示保留。
    expect(find.text('确认剔除不可用模型'), findsNothing);
    expect(find.textContaining('无需剔除'), findsOneWidget);

    final models = await db.channelDao.getModelsByChannel(
      'prune-keep-channel',
    );
    expect(models.map((m) => m.modelName).toSet(), {
      'ok-model',
      'flaky-model',
      'grok-imagine-video',
    });
  });
}
