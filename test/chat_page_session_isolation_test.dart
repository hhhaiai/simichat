import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/chat/chat_page.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
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

  testWidgets('Composer drafts stay isolated when switching sessions', (
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
    const channelId = 'session-isolation-channel';
    const modelId = 'session-isolation-model';
    await db.channelDao.createChannel(
      id: channelId,
      name: 'Session isolation test',
      baseUrl: 'https://example.test/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('session-isolation-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: modelId,
      channelId: channelId,
      modelName: 'session-isolation-model-name',
    );
    await db.sessionDao.createSession(
      id: 'session-isolation-a',
      defaultChannelModelId: modelId,
    );
    await db.sessionDao.createSession(
      id: 'session-isolation-b',
      defaultChannelModelId: modelId,
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        activeSessionIdProvider.overrideWith((ref) => 'session-isolation-a'),
        selectedModelIdProvider.overrideWith((ref) => modelId),
      ],
    );
    addTearDown(container.dispose);
    // ChatPage waits for the MCP manager during cold start. Resolve the empty
    // test manager before interacting with the composer so this test covers
    // draft ownership rather than startup timing.
    await container.read(mcpManagerProvider.notifier).ready;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChatPage())),
      ),
    );
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);
    await tester.enterText(textField, 'A 的草稿');
    await tester.pump();

    container.read(activeSessionIdProvider.notifier).state =
        'session-isolation-b';
    await tester.pump();
    expect(tester.widget<TextField>(textField).controller?.text, isEmpty);

    await tester.enterText(textField, 'B 必须保留的草稿');
    await tester.pump();

    container.read(activeSessionIdProvider.notifier).state =
        'session-isolation-a';
    await tester.pump();
    expect(
      tester.widget<TextField>(textField).controller?.text,
      'A 的草稿',
    );

    container.read(activeSessionIdProvider.notifier).state =
        'session-isolation-b';
    await tester.pump();
    expect(
      tester.widget<TextField>(textField).controller?.text,
      'B 必须保留的草稿',
    );
    expect(tester.takeException(), isNull);
  });
}
