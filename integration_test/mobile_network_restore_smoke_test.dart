import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile network restore smoke keeps offline draft', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await db.channelDao.createChannel(
      id: 'network-restore-channel',
      name: 'Network Restore Mock',
      baseUrl: 'http://127.0.0.1:9',
      apiKeyEncrypted: KeyEncryptor.encrypt('network-restore-test-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'network-restore-model',
      channelId: 'network-restore-channel',
      modelName: 'network-restore-model',
    );
    await db.sessionDao.createSession(
      id: 'network-restore-session',
      defaultChannelModelId: 'network-restore-model',
    );
    await db.sessionDao.updateTitle('network-restore-session', '网络恢复 smoke');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );

    await _pumpUntil(
      tester,
      () async => find.text('网络已断开').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 25),
    );

    const draft = 'mobile network restore smoke draft 20260706';
    await tester.enterText(find.byType(TextField).last, draft);
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text(draft), findsOneWidget);
    expect(find.text('当前网络不可用，已保留输入，联网后可重试'), findsOneWidget);
    expect(
      await db.messageDao.getMessagesBySession('network-restore-session'),
      isEmpty,
    );

    // scripts/smoke_android_network_restore.sh watches this marker and only
    // restores Wi-Fi/data after the app has proven it is in the blocked-offline
    // state. That avoids fixed-delay races during build/install startup.
    // ignore: avoid_print
    print('SIMICHAT_NETWORK_RESTORE_READY');

    await _pumpUntil(
      tester,
      () async => find.text('网络已恢复，可发送保留的输入').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
    );

    expect(find.text(draft), findsOneWidget);
    expect(find.text('网络已断开'), findsNothing);
    expect(
      await db.messageDao.getMessagesBySession('network-restore-session'),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('Timed out waiting for condition');
}
