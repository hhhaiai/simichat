import 'package:ai_chat_app/core/ai/model_switch_record.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android device directly switches the active chat model', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const firstModelId = 'model-switch-first';
    const secondModelId = 'model-switch-second';
    const sessionId = 'model-switch-session';
    await db.channelDao.createChannel(
      id: 'model-switch-channel',
      name: 'Model Switch Smoke',
      baseUrl: 'https://example.invalid',
      apiKeyEncrypted: KeyEncryptor.encrypt('model-switch-smoke-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: firstModelId,
      channelId: 'model-switch-channel',
      modelName: 'switch-model-a',
    );
    await db.channelDao.addModel(
      id: secondModelId,
      channelId: 'model-switch-channel',
      modelName: 'switch-model-b',
    );
    await db.sessionDao.createSession(
      id: sessionId,
      defaultChannelModelId: firstModelId,
    );
    await db.sessionDao.updateTitle(sessionId, '直接切换模型 smoke');

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    // ChatPage 的 ref.listen 不会回放挂载前的 activeSessionId；smoke 显式
    // 种入初始模型，避免首帧模型状态依赖 listener 的后续变化通知。
    container.read(selectedModelIdProvider.notifier).state = firstModelId;
    container.read(activeSessionIdProvider.notifier).state = sessionId;

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    await _pumpUntil(tester, () async {
      return find.byTooltip('切换模型').evaluate().isNotEmpty &&
          find
              .text('Model Switch Smoke / switch-model-a')
              .evaluate()
              .isNotEmpty &&
          container.read(selectedModelIdProvider) == firstModelId;
    });

    debugPrint(
      'SIMICHAT_MODEL_SWITCH_BASELINE '
      'session=$sessionId defaultChannelModelId=$firstModelId '
      'selectedModelId=${container.read(selectedModelIdProvider)}',
    );

    final topModelSelector = find.byTooltip('切换模型');
    expect(topModelSelector, findsOneWidget);
    await tester.tap(topModelSelector);
    await tester.pumpAndSettle();

    expect(find.text('switch-model-b'), findsOneWidget);
    await tester.tap(find.text('switch-model-b'));
    await tester.pump();
    debugPrint(
      'SIMICHAT_MODEL_SWITCH_UI_ACTION '
      'selector=top_app_bar option=switch-model-b',
    );

    await _pumpUntil(tester, () async {
      final session = await db.sessionDao.getSession(sessionId);
      final messages = await db.messageDao.getMessagesBySession(sessionId);
      return container.read(selectedModelIdProvider) == secondModelId &&
          session?.defaultChannelModelId == secondModelId &&
          messages.any(
            (message) =>
                message.messageType == kModelSwitchMessageType &&
                message.role == 'system' &&
                message.channelModelId == secondModelId,
          );
    });
    await tester.pumpAndSettle();

    final selectedModelId = container.read(selectedModelIdProvider);
    final session = await db.sessionDao.getSession(sessionId);
    final messages = await db.messageDao.getMessagesBySession(sessionId);
    final switchMessages = messages
        .where((message) => message.messageType == kModelSwitchMessageType)
        .toList();

    expect(session?.defaultChannelModelId, secondModelId);
    expect(selectedModelId, secondModelId);
    expect(switchMessages, hasLength(1));
    expect(switchMessages.single.role, 'system');
    expect(switchMessages.single.channelModelId, secondModelId);
    expect(
      switchMessages.single.content,
      contains('Model Switch Smoke / switch-model-a'),
    );
    expect(
      switchMessages.single.content,
      contains('Model Switch Smoke / switch-model-b'),
    );
    expect(find.text('Model Switch Smoke / switch-model-b'), findsOneWidget);
    expect(find.textContaining('已切换模型', findRichText: true), findsWidgets);
    expect(
      find.textContaining('switch-model-b', findRichText: true),
      findsWidgets,
    );

    debugPrint(
      'SIMICHAT_MODEL_SWITCH_DB_EVIDENCE '
      'session=$sessionId defaultChannelModelId=${session?.defaultChannelModelId} '
      'selectedModelId=$selectedModelId messageType=${switchMessages.single.messageType} '
      'messageChannelModelId=${switchMessages.single.channelModelId}',
    );
    expect(tester.takeException(), isNull);
    debugPrint(
      'SIMICHAT_MODEL_SWITCH_SMOKE_PASS '
      'session=$sessionId from=$firstModelId to=$secondModelId '
      'systemMessageCount=${switchMessages.length}',
    );
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for model switch smoke condition');
}
