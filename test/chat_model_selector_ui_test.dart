import 'dart:async';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/database/dao/channel_dao.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
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
