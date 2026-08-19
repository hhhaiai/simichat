import 'dart:async';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/database/dao/channel_dao.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'top selector is reachable in the real mobile AppBar and groups models',
    (tester) async {
      final db = await _createDatabaseWithModels(
        sessionId: 'selector-session',
        sessionTitle: 'Selector UI session',
      );
      addTearDown(db.close);
      final container = _createContainer(
        db,
        sessionId: 'selector-session',
        selectedModelId: 'selector-alpha',
      );
      addTearDown(container.dispose);

      await _pumpMobileApp(tester, container, size: const Size(320, 720));
      final selector = find.byKey(ChatModelSelector.selectorKey);

      expect(selector, findsOneWidget);
      expect(tester.getSize(selector).height, greaterThanOrEqualTo(44));
      expect(
        find.bySemanticsLabel(RegExp('模型选择器，当前模型：Alpha / selector-alpha')),
        findsOneWidget,
      );
      expect(find.byTooltip('切换模型'), findsOneWidget);
      expect(find.text('Selector UI session'), findsOneWidget);

      await tester.tap(selector);
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('selector-alpha'), findsOneWidget);
      expect(find.text('selector-beta'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('当前已选择')), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading selector is visible and keeps the active session intact',
    (tester) async {
      final db = await _createDatabaseWithModels(
        sessionId: 'loading-session',
        sessionTitle: 'Loading UI session',
      );
      addTearDown(db.close);
      final pending = Completer<List<ChannelModelWithChannel>>();
      final container = _createContainer(
        db,
        sessionId: 'loading-session',
        selectedModelId: 'selector-alpha',
        overrides: [allModelsProvider.overrideWith((ref) => pending.future)],
      );
      addTearDown(container.dispose);

      await _pumpMobileApp(tester, container, settle: false);
      final selector = find.byKey(ChatModelSelector.selectorKey);
      expect(selector, findsOneWidget);
      expect(tester.getSize(selector).height, greaterThanOrEqualTo(44));
      expect(find.text('加载模型…'), findsOneWidget);
      expect(find.bySemanticsLabel('模型选择器，正在加载模型列表'), findsOneWidget);
      expect(find.text('Loading UI session'), findsOneWidget);

      pending.complete(await db.channelDao.getChatModels());
      await tester.pumpAndSettle();
      expect(find.text('Alpha / selector-alpha'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty selector gives a clear setup action without replacing the session',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.sessionDao.createSession(
        id: 'empty-model-session',
        defaultChannelModelId: null,
      );
      await db.sessionDao.updateTitle(
        'empty-model-session',
        'No model UI session',
      );
      final container = _createContainer(db, sessionId: 'empty-model-session');
      addTearDown(container.dispose);

      await _pumpMobileApp(tester, container);
      final selector = find.byKey(ChatModelSelector.selectorKey);
      expect(selector, findsOneWidget);
      expect(tester.getSize(selector).height, greaterThanOrEqualTo(44));
      expect(find.text('未选择模型'), findsOneWidget);
      expect(
        find.bySemanticsLabel('模型选择器，当前未选择模型，点击前往设置添加模型渠道'),
        findsOneWidget,
      );
      expect(find.text('No model UI session'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading failure can retry without losing the current session', (
    tester,
  ) async {
    final db = await _createDatabaseWithModels(
      sessionId: 'retry-session',
      sessionTitle: 'Retry UI session',
    );
    addTearDown(db.close);
    final models = await db.channelDao.getChatModels();
    var attempts = 0;
    final container = _createContainer(
      db,
      sessionId: 'retry-session',
      selectedModelId: 'selector-alpha',
      overrides: [
        allModelsProvider.overrideWith((ref) async {
          if (attempts++ == 0) {
            throw StateError('test-only model list failure');
          }
          return models;
        }),
      ],
    );
    addTearDown(container.dispose);

    await _pumpMobileApp(tester, container);
    final selector = find.byKey(ChatModelSelector.selectorKey);
    expect(find.text('模型加载失败 · 重试'), findsOneWidget);
    expect(tester.getSize(selector).height, greaterThanOrEqualTo(44));
    expect(find.text('Retry UI session'), findsOneWidget);

    await tester.tap(selector);
    await tester.pumpAndSettle();

    expect(find.text('Alpha / selector-alpha'), findsOneWidget);
    expect(find.text('Retry UI session'), findsOneWidget);
    expect(find.text('模型加载失败 · 重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switch failure reports feedback and preserves the current model session',
    (tester) async {
      final db = await _createDatabaseWithModels(
        sessionId: 'failure-session',
        sessionTitle: 'Failure UI session',
      );
      addTearDown(db.close);
      // 让 updateDefaultModel 之后的持久化步骤失败；不触发网络，只验证
      // 本地回滚边界。
      await db.customStatement('DROP TABLE messages');
      final container = _createContainer(
        db,
        sessionId: 'failure-session',
        selectedModelId: 'selector-alpha',
      );
      addTearDown(container.dispose);

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

      await tester.tap(find.byKey(ChatModelSelector.selectorKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('selector-beta'));
      await tester.pumpAndSettle();

      expect(find.text('模型切换失败，当前会话保持不变，请重试'), findsOneWidget);
      expect(find.text('Alpha / selector-alpha'), findsOneWidget);
      expect(container.read(selectedModelIdProvider), 'selector-alpha');
      expect(
        (await db.sessionDao.getSession(
          'failure-session',
        ))?.defaultChannelModelId,
        'selector-alpha',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selector shows media models with capability labels, tap configures tools, no MapEntry noise',
    (tester) async {
      final db = await _createDatabaseWithModels(
        sessionId: 'selector-session',
        sessionTitle: 'Selector',
      );
      addTearDown(db.close);
      await db.channelDao.addModel(
        id: 'selector-tts',
        channelId: 'selector-channel-alpha',
        modelName: 'mimo-v2.5-tts',
        capability: 'audio',
      );
      await db.channelDao.addModel(
        id: 'selector-asr',
        channelId: 'selector-channel-alpha',
        modelName: 'mimo-v2.5-asr',
        capability: 'audio',
      );
      await db.channelDao.addModel(
        id: 'selector-image',
        channelId: 'selector-channel-alpha',
        modelName: 'gpt-image-1.5',
        capability: 'image',
      );

      final container = _createContainer(
        db,
        sessionId: 'selector-session',
        selectedModelId: 'selector-alpha',
      );
      addTearDown(container.dispose);
      await _pumpMobileApp(tester, container);

      await tester.tap(find.byKey(ChatModelSelector.selectorKey));
      await tester.pumpAndSettle();

      // 媒体模型可见，带能力标签，且不可点击选择。
      expect(find.text('mimo-v2.5-tts'), findsOneWidget);
      expect(find.text('mimo-v2.5-asr'), findsOneWidget);
      expect(find.text('gpt-image-1.5'), findsOneWidget);
      expect(find.text('Audio 音频'), findsNWidgets(2));
      expect(find.text('Image 图片生成'), findsOneWidget);

      final ttsItem = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('mimo-v2.5-tts'),
          matching: find.byWidgetPredicate(
            (w) => w is PopupMenuItem<String> && w.value == 'selector-tts',
          ),
        ),
      );
      // 媒体模型可点击：点击把它配置到对应工具，而不是切换聊天模型。
      expect(ttsItem.enabled, true);

      // 语义标签不能再包含 MapEntry(...) 垃圾字符串。
      final semantics = tester.getSemantics(
        find.ancestor(
          of: find.text('selector-alpha'),
          matching: find.byWidgetPredicate(
            (w) => w is PopupMenuItem<String>,
          ),
        ),
      );
      expect(semantics.label, isNot(contains('MapEntry')));

      // 点击 TTS 模型：写入 TTS 配置，会话默认聊天模型不变。
      await tester.tap(find.text('mimo-v2.5-tts'));
      await tester.pumpAndSettle();
      expect(
        container.read(textToSpeechConfigProvider).model,
        'mimo-v2.5-tts',
      );
      expect(
        (await db.sessionDao.getSession(
          'selector-session',
        ))?.defaultChannelModelId,
        'selector-alpha',
      );
      expect(
        find.textContaining('已把 mimo-v2.5-tts 设为语音合成'),
        findsOneWidget,
      );
    },
  );
}

Future<AppDatabase> _createDatabaseWithModels({
  required String sessionId,
  required String sessionTitle,
}) async {
  SharedPreferences.setMockInitialValues({});
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.channelDao.createChannel(
    id: 'selector-channel-alpha',
    name: 'Alpha',
    baseUrl: 'https://example.invalid/alpha',
    apiKeyEncrypted: 'local-test-key-alpha',
    protocol: 'openai_chat',
  );
  await db.channelDao.createChannel(
    id: 'selector-channel-beta',
    name: 'Beta',
    baseUrl: 'https://example.invalid/beta',
    apiKeyEncrypted: 'local-test-key-beta',
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'selector-alpha',
    channelId: 'selector-channel-alpha',
    modelName: 'selector-alpha',
  );
  await db.channelDao.addModel(
    id: 'selector-beta',
    channelId: 'selector-channel-beta',
    modelName: 'selector-beta',
  );
  await db.sessionDao.createSession(
    id: sessionId,
    defaultChannelModelId: 'selector-alpha',
  );
  await db.sessionDao.updateTitle(sessionId, sessionTitle);
  return db;
}

ProviderContainer _createContainer(
  AppDatabase db, {
  required String sessionId,
  String? selectedModelId,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db), ...overrides],
  );
  container.read(activeSessionIdProvider.notifier).state = sessionId;
  container.read(selectedModelIdProvider.notifier).state = selectedModelId;
  return container;
}

Future<void> _pumpMobileApp(
  WidgetTester tester,
  ProviderContainer container, {
  bool settle = true,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AiChatApp()),
  );
  await tester.pump();
  if (settle) {
    await tester.pumpAndSettle();
  }
}
