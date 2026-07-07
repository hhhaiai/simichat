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

  testWidgets('Android external ai-chat deep links open settings and session', (
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
      id: 'deep-link-channel',
      name: 'Deep Link Mock',
      baseUrl: 'https://example.invalid/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('deep-link-test-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'deep-link-model',
      channelId: 'deep-link-channel',
      modelName: 'deep-link-model',
    );
    await db.sessionDao.createSession(
      id: 'deep-link-default-session',
      defaultChannelModelId: 'deep-link-model',
    );
    await db.sessionDao.updateTitle(
      'deep-link-default-session',
      'Deep Link Default Smoke',
    );
    await db.sessionDao.createSession(
      id: 'deep-link-target-session',
      defaultChannelModelId: 'deep-link-model',
    );
    await db.sessionDao.updateTitle(
      'deep-link-target-session',
      'Deep Link Target Smoke',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsWidgets);
    expect(tester.takeException(), isNull);

    // scripts/smoke_android_deep_link.sh waits for this marker, then opens
    // ai-chat://settings through Android's external VIEW intent path.
    // ignore: avoid_print
    print('SIMICHAT_DEEP_LINK_READY');

    await _pumpUntil(
      tester,
      () async => find.text('设置').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    expect(find.text('设置'), findsWidgets);
    expect(tester.takeException(), isNull);

    // The host script waits for this marker, then opens
    // ai-chat://session/deep-link-target-session from adb.
    // ignore: avoid_print
    print('SIMICHAT_DEEP_LINK_SETTINGS_OK');

    await _pumpUntil(
      tester,
      () async => find.text('Deep Link Target Smoke').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    expect(find.text('Deep Link Target Smoke'), findsOneWidget);
    expect(find.text('已打开链接中的会话'), findsOneWidget);
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
  final texts = find
      .byType(Text)
      .evaluate()
      .map((element) {
        final widget = element.widget as Text;
        return widget.data ?? widget.textSpan?.toPlainText() ?? '<rich>';
      })
      .toList(growable: false);
  // ignore: avoid_print
  print('SIMICHAT_DEEP_LINK_TIMEOUT_TEXTS ${texts.join(' | ')}');
  fail('Timed out waiting for condition');
}
