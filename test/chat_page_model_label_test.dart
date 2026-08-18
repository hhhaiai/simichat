import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/chat/chat_page.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('assistant reply shows the answering model label', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const channelId = 'model-label-channel';
    const modelId = 'model-label-chat-model';
    await db.channelDao.createChannel(
      id: channelId,
      name: '模型标签渠道',
      baseUrl: 'https://example.test/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('model-label-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: modelId,
      channelId: channelId,
      modelName: 'gpt-4o',
    );
    await db.sessionDao.createSession(
      id: 'model-label-session',
      defaultChannelModelId: modelId,
    );
    final messageDao = db.messageDao;
    await messageDao.insertMessage(
      id: 'model-label-user-msg',
      sessionId: 'model-label-session',
      role: 'user',
      content: '你好',
    );
    await messageDao.insertMessage(
      id: 'model-label-assistant-msg',
      sessionId: 'model-label-session',
      role: 'assistant',
      content: '你好，我是助手。',
      channelModelId: modelId,
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        activeSessionIdProvider.overrideWith((ref) => 'model-label-session'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(mcpManagerProvider.notifier).ready;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChatPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你好，我是助手。'), findsOneWidget);
    // displayLabel = '${channel.name} / ${channelModel.modelName}'
    expect(find.text('模型标签渠道 / gpt-4o'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
