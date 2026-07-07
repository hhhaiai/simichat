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

  testWidgets('mobile background restore smoke keeps composer draft', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final lifecycle = _LifecycleProbe();
    WidgetsBinding.instance.addObserver(lifecycle);
    addTearDown(() => WidgetsBinding.instance.removeObserver(lifecycle));

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await db.channelDao.createChannel(
      id: 'background-restore-channel',
      name: 'Background Restore Mock',
      baseUrl: 'https://example.invalid/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('background-restore-test-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'background-restore-model',
      channelId: 'background-restore-channel',
      modelName: 'background-restore-model',
    );
    await db.sessionDao.createSession(
      id: 'background-restore-session',
      defaultChannelModelId: 'background-restore-model',
    );
    await db.sessionDao.updateTitle('background-restore-session', '后台恢复 smoke');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    const draft = 'mobile background restore draft 20260706';
    await tester.enterText(find.byType(TextField).last, draft);
    await tester.pump();
    expect(find.text(draft), findsOneWidget);

    // scripts/smoke_android_background_restore.sh waits for this marker before
    // pressing Home and launching the app again.
    // ignore: avoid_print
    print('SIMICHAT_BACKGROUND_RESTORE_READY');

    await _pumpUntil(
      tester,
      () async => lifecycle.sawNonResumed,
      timeout: const Duration(seconds: 30),
    );
    await _pumpUntil(
      tester,
      () async =>
          lifecycle.sawNonResumed &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      timeout: const Duration(seconds: 60),
    );

    await tester.pumpAndSettle();
    expect(find.text(draft), findsOneWidget);
    expect(
      await db.messageDao.getMessagesBySession('background-restore-session'),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}

class _LifecycleProbe with WidgetsBindingObserver {
  bool sawNonResumed = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      sawNonResumed = true;
    }
  }
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
