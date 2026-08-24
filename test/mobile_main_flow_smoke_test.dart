import 'dart:async';
import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/dreaming_provider.dart';
import 'package:ai_chat_app/shared/providers/reflection_provider.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:ai_chat_app/shared/providers/user_profile_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    resetDreamingAutoRunStateForTesting();
    resetAssistantReflectionRetryStateForTesting();
    resetDreamingForegroundCheckIntervalForTesting();
  });
  tearDown(() {
    resetBackgroundInterruptedPersistDelayForTesting();
    resetDreamingAutoRunStateForTesting();
    resetAssistantReflectionRetryStateForTesting();
    resetDreamingDigestCompleteNotifierForTesting();
    resetDreamingForegroundCheckIntervalForTesting();
  });

  Future<AppDatabase> pumpMobileApp(
    WidgetTester tester, {
    Future<void> Function(AppDatabase db)? seed,
    Map<String, Object>? initialPrefs,
    List<Override> Function(AppDatabase db)? overrides,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs ?? {});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    if (seed != null) {
      await seed(db);
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final providerOverrides = <Override>[
      databaseProvider.overrideWithValue(db),
      if (overrides != null) ...overrides(db),
    ];
    await tester.pumpWidget(
      ProviderScope(overrides: providerOverrides, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('mobile main flow smoke: session, settings, send guard', (
    tester,
  ) async {
    final db = await pumpMobileApp(tester);

    expect(find.text('SimiAIChat'), findsWidgets);
    expect(find.text('未选择模型'), findsOneWidget);
    expect(await db.sessionDao.getAllSessions(), hasLength(1));

    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    expect(await db.sessionDao.getAllSessions(), hasLength(2));

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    // 设置页首部 SimiRouter 推广卡片占位较高，滚动到目标分区。
    await tester.scrollUntilVisible(
      find.text('数据与档案'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('数据与档案'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '你好 SimiChat');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('还没有可用模型'), findsOneWidget);
    expect(find.text('请先去设置里添加模型渠道和模型，然后再发送消息。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile history smoke: drawer search selects existing session', (
    tester,
  ) async {
    final db = await pumpMobileApp(tester);
    final sessionId = (await db.sessionDao.getAllSessions()).single.id;
    await db.sessionDao.updateTitle(sessionId, '项目复盘记录');
    await db.messageDao.insertMessage(
      id: 'message-1',
      sessionId: sessionId,
      role: 'user',
      content: '今天复盘移动端主链路',
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final drawerSearch = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索会话...',
    );
    expect(drawerSearch, findsOneWidget);

    await tester.enterText(drawerSearch, '项目复盘');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('项目复盘记录'), findsOneWidget);
    await tester.tap(find.text('项目复盘记录'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile due dreaming persists reflection', (tester) async {
    await pumpMobileApp(
      tester,
      initialPrefs: {
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 0,
          'minute': 0,
        }),
      },
      seed: (db) async {
        await db.sessionDao.createSession(id: 'session-dreaming');
        await db.messageDao.insertMessage(
          id: 'message-dreaming-1',
          sessionId: 'session-dreaming',
          role: 'user',
          content: '请记住我喜欢移动端优先和本地隐私。',
        );
      },
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    _expectStoredReflectionMatchesDreaming(prefs);
    expect(prefs.getString(kUserProfileStorageKey), isNull);
    final proposals = decodeUserProfileChangeProposals(
      prefs.getString(kUserProfileChangeProposalsStorageKey),
    );
    expect(proposals, hasLength(1));
    expect(proposals.single.diff.hasChanges, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile startup retries pending reflection', (tester) async {
    final now = DateTime.utc(2026, 7, 6, 22);
    final digest = DreamingDigest(
      day: now,
      generatedAt: now,
      sessionCount: 1,
      originalMessageCount: 2,
      userMessageCount: 1,
      assistantMessageCount: 1,
      sessions: [
        DreamingSessionDigest(
          sessionId: 'pending-reflection-session',
          title: '反思恢复',
          messageCount: 2,
          userMessageCount: 1,
          assistantMessageCount: 1,
          highlights: const ['移动端恢复待处理反思'],
          firstMessageAt: now.subtract(const Duration(minutes: 1)),
          lastMessageAt: now,
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['恢复'],
      elapsedMs: 1,
    );

    await pumpMobileApp(
      tester,
      initialPrefs: {
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': false,
          'hour': 22,
          'minute': 0,
        }),
        kDreamingDigestStorageKey: jsonEncode(digest.toJson()),
        kAssistantReflectionPendingStorageKey: jsonEncode({
          'sourceDigestDayKey': digest.dayKey,
          'updatedAt': now.toIso8601String(),
          'attemptCount': 1,
        }),
      },
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    _expectStoredReflectionMatchesDreaming(prefs);
    expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile resume recovers reflection after follow-up failure', (
    tester,
  ) async {
    final reflectionService = _FailingOnceReflectionService();
    await pumpMobileApp(
      tester,
      initialPrefs: {
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 0,
          'minute': 0,
        }),
      },
      seed: (db) async {
        await db.sessionDao.createSession(id: 'reflection-retry-session');
        await db.messageDao.insertMessage(
          id: 'reflection-retry-message',
          sessionId: 'reflection-retry-session',
          role: 'user',
          content: '请记住移动端反思失败后需要在恢复前台时重试。',
        );
      },
      overrides: (db) => [
        reflectionServiceProvider.overrideWithValue(reflectionService),
      ],
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
    expect(prefs.getString(kAssistantReflectionStorageKey), isNull);
    expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNotNull);
    expect(reflectionService.attemptCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    prefs = await SharedPreferences.getInstance();
    _expectStoredReflectionMatchesDreaming(prefs);
    expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNull);
    expect(reflectionService.attemptCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile resume runs dreaming reflection', (tester) async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 'session-dreaming-resume');
    await db.messageDao.insertMessage(
      id: 'message-dreaming-resume-1',
      sessionId: 'session-dreaming-resume',
      role: 'user',
      content: '请记住应用恢复前台时也要执行当天 Dreaming。',
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNull);

    await container.read(dreamingScheduleProvider.notifier).setEnabled(true);
    await container
        .read(dreamingScheduleProvider.notifier)
        .setTime(hour: 0, minute: 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    prefs = await SharedPreferences.getInstance();
    _expectStoredReflectionMatchesDreaming(prefs);
    final proposals = decodeUserProfileChangeProposals(
      prefs.getString(kUserProfileChangeProposalsStorageKey),
    );
    expect(proposals, hasLength(1));
    expect(proposals.single.diff.hasChanges, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile foreground timer runs dreaming reflection', (
    tester,
  ) async {
    dreamingForegroundCheckInterval = const Duration(milliseconds: 30);
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 'session-dreaming-foreground');
    await db.messageDao.insertMessage(
      id: 'message-dreaming-foreground-1',
      sessionId: 'session-dreaming-foreground',
      role: 'user',
      content: '请记住应用一直在前台时也要按时执行 Dreaming。',
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNull);

    await container.read(dreamingScheduleProvider.notifier).setEnabled(true);
    await container
        .read(dreamingScheduleProvider.notifier)
        .setTime(hour: 0, minute: 0);

    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    prefs = await SharedPreferences.getInstance();
    _expectStoredReflectionMatchesDreaming(prefs);
    final proposals = decodeUserProfileChangeProposals(
      prefs.getString(kUserProfileChangeProposalsStorageKey),
    );
    expect(proposals, hasLength(1));
    expect(proposals.single.diff.hasChanges, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile inactive lifecycle cancels foreground dreaming timer', (
    tester,
  ) async {
    dreamingForegroundCheckInterval = const Duration(milliseconds: 30);
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 'session-dreaming-inactive');
    await db.messageDao.insertMessage(
      id: 'message-dreaming-inactive-1',
      sessionId: 'session-dreaming-inactive',
      role: 'user',
      content: '请记住应用进入非活跃状态后不要继续执行 Dreaming 重任务。',
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    await container.read(dreamingScheduleProvider.notifier).setEnabled(true);
    await container
        .read(dreamingScheduleProvider.notifier)
        .setTime(hour: 0, minute: 0);

    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNull);
    expect(
      decodeUserProfileChangeProposals(
        prefs.getString(kUserProfileChangeProposalsStorageKey),
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);

    await container.read(dreamingScheduleProvider.notifier).setEnabled(false);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNull);
  });

  testWidgets('mobile inactive lifecycle cancels active streaming response', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const sessionId = 'session-background-streaming';
    await db.sessionDao.createSession(id: sessionId);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), sessionId);
    container
        .read(streamStateProvider(sessionId).notifier)
        .state = const StreamState(
      isStreaming: true,
      currentContent: 'partial background reply',
      isWaitingForFirstToken: false,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    final state = container.read(streamStateProvider(sessionId));
    expect(state.isStreaming, isFalse);
    expect(state.currentContent, isEmpty);
    expect(state.isWaitingForFirstToken, isFalse);
    expect(state.error, backgroundStreamingInterruptedMessage);
    expect(find.text(backgroundStreamingInterruptedMessage), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), sessionId);
    expect(prefs.getStringList(kBackgroundInterruptedSessionsStorageKey), [
      sessionId,
    ]);
    expect(tester.takeException(), isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('已停止后台生成，可点“重试”继续'), findsOneWidget);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), isNull);
    expect(
      prefs.getStringList(kBackgroundInterruptedSessionsStorageKey),
      isNull,
    );
  });

  testWidgets('mobile inactive lifecycle cancels all streaming sessions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const activeSessionId = 'session-background-active-stream';
    const otherSessionId = 'session-background-other-stream';
    await db.sessionDao.createSession(id: activeSessionId);
    await db.sessionDao.createSession(id: otherSessionId);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    container.read(activeSessionIdProvider.notifier).state = activeSessionId;
    await tester.pumpAndSettle();
    expect(container.read(activeSessionIdProvider), activeSessionId);
    for (final sessionId in [activeSessionId, otherSessionId]) {
      container
          .read(streamStateProvider(sessionId).notifier)
          .state = const StreamState(
        isStreaming: true,
        currentContent: 'partial background reply',
        isWaitingForFirstToken: false,
      );
    }

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    for (final sessionId in [activeSessionId, otherSessionId]) {
      final state = container.read(streamStateProvider(sessionId));
      expect(state.isStreaming, isFalse);
      expect(state.currentContent, isEmpty);
      expect(state.error, backgroundStreamingInterruptedMessage);
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(kBackgroundInterruptedSessionsStorageKey), [
      activeSessionId,
      otherSessionId,
    ]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('已停止 2 个后台生成，可点“重试全部”继续'), findsOneWidget);
    expect(find.text('重试全部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile network loss cancels active streaming response', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final connectivity = StreamController<List<ConnectivityResult>>();
    addTearDown(connectivity.close);

    const sessionId = 'session-network-streaming';
    await db.sessionDao.createSession(id: sessionId);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWith((ref) => connectivity.stream),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), sessionId);
    container
        .read(streamStateProvider(sessionId).notifier)
        .state = const StreamState(
      isStreaming: true,
      currentContent: 'partial network reply',
      isWaitingForFirstToken: false,
    );

    connectivity.add([ConnectivityResult.none]);
    await tester.pump();
    await tester.pumpAndSettle();

    final state = container.read(streamStateProvider(sessionId));
    expect(state.isStreaming, isFalse);
    expect(state.currentContent, isEmpty);
    expect(state.isWaitingForFirstToken, isFalse);
    expect(state.error, networkStreamingInterruptedMessage);
    expect(find.text(networkStreamingInterruptedMessage), findsOneWidget);
    expect(find.text('网络连接断开，已停止生成，联网后可重试'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), isNull);
    expect(
      prefs.getStringList(kBackgroundInterruptedSessionsStorageKey),
      isNull,
    );

    connectivity.add([ConnectivityResult.wifi]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('网络已恢复，可点“重试”继续'), findsOneWidget);
    expect(find.text('重试'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile network loss cancels all streaming sessions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final connectivity = StreamController<List<ConnectivityResult>>();
    addTearDown(connectivity.close);

    const activeSessionId = 'session-network-active-stream';
    const otherSessionId = 'session-network-other-stream';
    await db.sessionDao.createSession(id: activeSessionId);
    await db.sessionDao.createSession(id: otherSessionId);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWith((ref) => connectivity.stream),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    container.read(activeSessionIdProvider.notifier).state = activeSessionId;
    await tester.pumpAndSettle();
    for (final sessionId in [activeSessionId, otherSessionId]) {
      container
          .read(streamStateProvider(sessionId).notifier)
          .state = const StreamState(
        isStreaming: true,
        currentContent: 'partial network reply',
        isWaitingForFirstToken: false,
      );
    }

    connectivity.add([ConnectivityResult.none]);
    await tester.pump();
    await tester.pumpAndSettle();

    for (final sessionId in [activeSessionId, otherSessionId]) {
      final state = container.read(streamStateProvider(sessionId));
      expect(state.isStreaming, isFalse);
      expect(state.currentContent, isEmpty);
      expect(state.error, networkStreamingInterruptedMessage);
    }

    connectivity.add([ConnectivityResult.wifi]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('网络已恢复，2 个会话可点“重试全部”继续'), findsOneWidget);
    expect(find.text('重试全部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile inactive lifecycle sanitizes background retry markers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const sessionId = 'session-background-marker-sanitize';
    await db.sessionDao.createSession(id: sessionId);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), sessionId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kBackgroundInterruptedSessionsStorageKey, [
      '',
      '  $sessionId  ',
      '   ',
    ]);
    container.read(streamStateProvider(sessionId).notifier).state =
        const StreamState(isStreaming: true);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), sessionId);
    expect(prefs.getStringList(kBackgroundInterruptedSessionsStorageKey), [
      sessionId,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile resume waits for delayed background retry marker cleanup',
    (tester) async {
      backgroundInterruptedPersistDelayForTesting = const Duration(
        milliseconds: 50,
      );
      SharedPreferences.setMockInitialValues({
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': false,
          'hour': 0,
          'minute': 0,
        }),
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      const sessionId = 'session-background-marker-race';
      await db.sessionDao.createSession(id: sessionId);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AiChatApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(activeSessionIdProvider), sessionId);
      container.read(streamStateProvider(sessionId).notifier).state =
          const StreamState(isStreaming: true);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), isNull);
      expect(
        prefs.getStringList(kBackgroundInterruptedSessionsStorageKey),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile startup restores persisted background retry marker', (
    tester,
  ) async {
    const sessionId = 'session-persisted-background-retry';
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
      kBackgroundInterruptedSessionStorageKey: sessionId,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: sessionId);
    await db.messageDao.insertMessage(
      id: 'message-persisted-background-user',
      sessionId: sessionId,
      role: 'user',
      content: '请在应用重启后提醒我可以重试后台中断的请求。',
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), sessionId);
    final state = container.read(streamStateProvider(sessionId));
    expect(state.isStreaming, isFalse);
    expect(state.error, backgroundStreamingInterruptedMessage);
    expect(find.text(backgroundStreamingInterruptedMessage), findsOneWidget);
    expect(find.text('已恢复上次后台中断，可点“重试”继续'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile startup switches to persisted background retry session', (
    tester,
  ) async {
    const interruptedSessionId = 'session-persisted-background-retry-target';
    const newestSessionId = 'session-newer-without-marker';
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
      kBackgroundInterruptedSessionStorageKey: interruptedSessionId,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: interruptedSessionId);
    await db.sessionDao.updateTitle(interruptedSessionId, '后台中断会话');
    await db.messageDao.insertMessage(
      id: 'message-persisted-background-switch-user',
      sessionId: interruptedSessionId,
      role: 'user',
      content: '请在应用重启后切回这条后台中断的会话。',
    );
    await db.sessionDao.createSession(id: newestSessionId);
    await db.customStatement(
      'UPDATE sessions SET last_message_at = ? WHERE id = ?',
      [1000, interruptedSessionId],
    );
    await db.customStatement(
      'UPDATE sessions SET last_message_at = ? WHERE id = ?',
      [2000, newestSessionId],
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), interruptedSessionId);
    final state = container.read(streamStateProvider(interruptedSessionId));
    expect(state.isStreaming, isFalse);
    expect(state.error, backgroundStreamingInterruptedMessage);
    expect(find.text('后台中断会话'), findsOneWidget);
    expect(find.text(backgroundStreamingInterruptedMessage), findsOneWidget);
    expect(find.text('已恢复上次后台中断，可点“重试”继续'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile startup clears stale background retry marker', (
    tester,
  ) async {
    const staleSessionId = 'session-deleted-background-retry';
    const existingSessionId = 'session-existing-after-stale-marker';
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
      kBackgroundInterruptedSessionStorageKey: staleSessionId,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: existingSessionId);
    await db.sessionDao.updateTitle(existingSessionId, '仍然存在的会话');

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), existingSessionId);
    expect(find.text('仍然存在的会话'), findsOneWidget);
    expect(find.text(backgroundStreamingInterruptedMessage), findsNothing);
    expect(find.text('已恢复上次后台中断，可点“重试”继续'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile startup restores multiple background retry markers', (
    tester,
  ) async {
    const firstInterruptedSessionId = 'session-background-retry-queue-a';
    const secondInterruptedSessionId = 'session-background-retry-queue-b';
    const newestSessionId = 'session-background-retry-queue-newest';
    const missingSessionId = 'session-background-retry-queue-missing';
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
      kBackgroundInterruptedSessionsStorageKey: [
        firstInterruptedSessionId,
        '',
        firstInterruptedSessionId,
        secondInterruptedSessionId,
        '   ',
        missingSessionId,
      ],
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: firstInterruptedSessionId);
    await db.sessionDao.updateTitle(firstInterruptedSessionId, '第一条待重试会话');
    await db.messageDao.insertMessage(
      id: 'message-background-retry-queue-a-user',
      sessionId: firstInterruptedSessionId,
      role: 'user',
      content: '请重试第一条后台中断请求。',
    );
    await db.sessionDao.createSession(id: secondInterruptedSessionId);
    await db.sessionDao.updateTitle(secondInterruptedSessionId, '第二条待重试会话');
    await db.messageDao.insertMessage(
      id: 'message-background-retry-queue-b-user',
      sessionId: secondInterruptedSessionId,
      role: 'user',
      content: '请重试第二条后台中断请求。',
    );
    await db.sessionDao.createSession(id: newestSessionId);
    await db.customStatement(
      'UPDATE sessions SET last_message_at = ? WHERE id = ?',
      [1000, firstInterruptedSessionId],
    );
    await db.customStatement(
      'UPDATE sessions SET last_message_at = ? WHERE id = ?',
      [2000, secondInterruptedSessionId],
    );
    await db.customStatement(
      'UPDATE sessions SET last_message_at = ? WHERE id = ?',
      [3000, newestSessionId],
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), firstInterruptedSessionId);
    expect(find.text('第一条待重试会话'), findsOneWidget);
    expect(
      container.read(streamStateProvider(firstInterruptedSessionId)).error,
      backgroundStreamingInterruptedMessage,
    );
    expect(
      container.read(streamStateProvider(secondInterruptedSessionId)).error,
      backgroundStreamingInterruptedMessage,
    );
    expect(find.text(backgroundStreamingInterruptedMessage), findsOneWidget);
    expect(find.text('已恢复 2 个后台中断会话，可点“重试全部”继续'), findsOneWidget);
    expect(find.text('重试全部'), findsOneWidget);

    await tester.tap(find.text('重试全部'));
    await tester.pumpAndSettle();
    expect(
      container.read(streamStateProvider(firstInterruptedSessionId)).error,
      '请先选择一个模型',
    );
    expect(
      container.read(streamStateProvider(secondInterruptedSessionId)).error,
      '请先选择一个模型',
    );

    container.read(activeSessionIdProvider.notifier).state =
        secondInterruptedSessionId;
    await tester.pumpAndSettle();
    expect(find.text('第二条待重试会话'), findsOneWidget);
    expect(find.text('请先选择一个模型'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), isNull);
    expect(
      prefs.getStringList(kBackgroundInterruptedSessionsStorageKey),
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile startup prompts for unresolved dreaming failure', (
    tester,
  ) async {
    await pumpMobileApp(
      tester,
      initialPrefs: {
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': false,
          'hour': 0,
          'minute': 0,
        }),
      },
      seed: (db) async {
        final failedDay = DateTime(2026, 7, 6, 22);
        await db.dreamingDao.createJob(
          id: 'startup-failed-dreaming-job',
          dayKey: '2026-07-06',
          scheduledFor: failedDay.millisecondsSinceEpoch,
          trigger: 'foreground_due',
          createdAt: failedDay.millisecondsSinceEpoch,
        );
        await db.dreamingDao.markJobRunning(
          'startup-failed-dreaming-job',
          startedAt: failedDay
              .add(const Duration(milliseconds: 100))
              .millisecondsSinceEpoch,
        );
        await db.dreamingDao.markJobFailed(
          'startup-failed-dreaming-job',
          error: 'simulated startup failure',
          finishedAt: failedDay
              .add(const Duration(milliseconds: 200))
              .millisecondsSinceEpoch,
        );
      },
    );

    expect(find.text('上次 Dreaming 失败，可到设置页重试'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();

    // 设置页首部 SimiRouter AI 推广卡片增加了页首高度，先滚动到 Dreaming tile。
    await tester.scrollUntilVisible(
      find.text('Dreaming 夜间整理'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Dreaming 夜间整理'), findsOneWidget);
    await tester.tap(find.text('Dreaming 夜间整理'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最近 Dreaming 失败：2026-07-06'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile resume prompts for unresolved dreaming failure', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': false,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('上次 Dreaming 失败，可到设置页重试'), findsNothing);

    final failedDay = DateTime(2026, 7, 7, 22);
    await db.dreamingDao.createJob(
      id: 'resume-failed-dreaming-job',
      dayKey: '2026-07-07',
      scheduledFor: failedDay.millisecondsSinceEpoch,
      trigger: 'foreground_due',
      createdAt: failedDay.millisecondsSinceEpoch,
    );
    await db.dreamingDao.markJobRunning(
      'resume-failed-dreaming-job',
      startedAt: failedDay
          .add(const Duration(milliseconds: 100))
          .millisecondsSinceEpoch,
    );
    await db.dreamingDao.markJobFailed(
      'resume-failed-dreaming-job',
      error: 'simulated resume failure',
      finishedAt: failedDay
          .add(const Duration(milliseconds: 200))
          .millisecondsSinceEpoch,
    );
    container.invalidate(latestFailedDreamingJobProvider);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('上次 Dreaming 失败，可到设置页重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile due dreaming failure sends local failure notification', (
    tester,
  ) async {
    var failedNotificationDayKey = '';
    dreamingDigestFailedNotifier = ({required String dayKey}) async {
      failedNotificationDayKey = dayKey;
    };

    final db = await pumpMobileApp(
      tester,
      initialPrefs: {
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 0,
          'minute': 0,
        }),
      },
      seed: (db) async {
        await db.sessionDao.createSession(id: 'session-dreaming-failed-notify');
        await db.messageDao.insertMessage(
          id: 'message-dreaming-failed-notify-1',
          sessionId: 'session-dreaming-failed-notify',
          role: 'user',
          content: '请记住 Dreaming 自动整理失败时也要通知我可以重试。',
        );
      },
      overrides: (db) => [
        dreamingServiceProvider.overrideWithValue(
          _FailingDreamingService(db: db),
        ),
      ],
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final failedJob = await db.dreamingDao.getLatestUnresolvedFailedJob();
    expect(failedJob, isNotNull);
    expect(failedNotificationDayKey, failedJob!.dayKey);
    expect(find.text('上次 Dreaming 失败，可到设置页重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile disposed shell skips dreaming follow-up work', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': true,
        'hour': 0,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 'session-dreaming-dispose');
    await db.messageDao.insertMessage(
      id: 'message-dreaming-dispose-1',
      sessionId: 'session-dreaming-dispose',
      role: 'user',
      content: '请记住 Dreaming 完成前页面销毁时不要继续使用已销毁的 ref。',
    );

    final digestStarted = Completer<void>();
    final digestGate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dreamingServiceProvider.overrideWithValue(
          _GateDreamingService(
            db: db,
            started: digestStarted,
            gate: digestGate,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pump();
    await digestStarted.future;

    await tester.pumpWidget(const SizedBox.shrink());
    digestGate.complete();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
    expect(
      decodeUserProfileChangeProposals(
        prefs.getString(kUserProfileChangeProposalsStorageKey),
      ),
      isEmpty,
    );
    expect(prefs.getString(kAssistantReflectionStorageKey), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile disposed shell skips dreaming notification after proposal wait',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 0,
          'minute': 0,
        }),
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 'session-dreaming-proposal-wait');
      await db.messageDao.insertMessage(
        id: 'message-dreaming-proposal-wait-1',
        sessionId: 'session-dreaming-proposal-wait',
        role: 'user',
        content: '请记住我希望 Dreaming 画像提案等待期间页面销毁后不要再发完成通知。',
      );

      final proposalStarted = Completer<void>();
      final proposalGate = Completer<void>();
      var notificationCount = 0;
      dreamingDigestCompleteNotifier =
          ({
            required String dayKey,
            required int originalMessageCount,
            int? totalOriginalMessageCount,
            required int memoryCandidateCount,
            int profileProposalCount = 0,
          }) async {
            notificationCount++;
          };

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          userProfileChangeProposalsProvider.overrideWith(
            (ref) => _GateUserProfileChangeProposalsNotifier(
              started: proposalStarted,
              gate: proposalGate,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AiChatApp(),
        ),
      );
      await tester.pump();
      await proposalStarted.future;

      await tester.pumpWidget(const SizedBox.shrink());
      proposalGate.complete();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
      expect(notificationCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile model switch smoke: keeps switch out of timeline', (
    tester,
  ) async {
    final db = await pumpMobileApp(
      tester,
      seed: (db) async {
        await db.channelDao.createChannel(
          id: 'channel-openai',
          name: 'OpenAI',
          baseUrl: 'https://example.invalid',
          apiKeyEncrypted: KeyEncryptor.encrypt('test-api-key'),
          protocol: 'openai_chat',
        );
        await db.channelDao.addModel(
          id: 'model-gpt-4o',
          channelId: 'channel-openai',
          modelName: 'gpt-4o',
        );
        await db.channelDao.addModel(
          id: 'model-gpt-4o-mini',
          channelId: 'channel-openai',
          modelName: 'gpt-4o-mini',
        );
        await db.sessionDao.createSession(
          id: 'session-1',
          defaultChannelModelId: 'model-gpt-4o',
        );
      },
    );

    // Mobile header deliberately keeps the compact model name visible; the
    // channel prefix remains available in the menu and message metadata.
    expect(find.text('gpt-4o'), findsOneWidget);

    await tester.tap(find.text('gpt-4o'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-4o-mini').last);
    await tester.pumpAndSettle();

    final session = await db.sessionDao.getSession('session-1');
    expect(session?.defaultChannelModelId, 'model-gpt-4o-mini');

    final messages = await db.messageDao.getMessagesBySession('session-1');
    expect(messages, isEmpty);
    expect(find.textContaining('已切换模型'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

void _expectStoredReflectionMatchesDreaming(SharedPreferences prefs) {
  final rawDigest = prefs.getString(kDreamingDigestStorageKey);
  expect(rawDigest, isNotNull);
  final digest = DreamingDigest.fromJson(
    (jsonDecode(rawDigest!) as Map).cast<String, dynamic>(),
  );
  final reflection = decodeReflectionReport(
    prefs.getString(kAssistantReflectionStorageKey),
  );
  final reflectionHistory = decodeReflectionReportHistory(
    prefs.getString(kAssistantReflectionHistoryStorageKey),
  );
  expect(reflection?.hasContent, isTrue);
  expect(reflection?.sourceDigestDayKey, digest.dayKey);
  expect(reflectionHistory, isNotEmpty);
}

class _GateDreamingService extends DreamingService {
  _GateDreamingService({
    required AppDatabase db,
    required this.started,
    required this.gate,
  }) : super(sessionDao: db.sessionDao, messageDao: db.messageDao);

  final Completer<void> started;
  final Completer<void> gate;

  @override
  Future<DreamingDigest> runDailyDigest({
    DateTime? day,
    int maxMessages = 5000,
    int maxMemoryCandidates = 40,
  }) async {
    if (!started.isCompleted) started.complete();
    await gate.future;
    return super.runDailyDigest(
      day: day,
      maxMessages: maxMessages,
      maxMemoryCandidates: maxMemoryCandidates,
    );
  }
}

class _FailingOnceReflectionService extends ReflectionService {
  int attemptCount = 0;

  @override
  ReflectionReport buildDailyReflection({
    required DreamingDigest digest,
    UserProfile? profile,
    int pendingProfileProposalCount = 0,
  }) {
    attemptCount += 1;
    if (attemptCount == 1) {
      throw StateError('simulated reflection follow-up failure');
    }
    return super.buildDailyReflection(
      digest: digest,
      profile: profile,
      pendingProfileProposalCount: pendingProfileProposalCount,
    );
  }
}

class _FailingDreamingService extends DreamingService {
  _FailingDreamingService({required AppDatabase db})
    : super(sessionDao: db.sessionDao, messageDao: db.messageDao);

  @override
  Future<DreamingDigest> runDailyDigest({
    DateTime? day,
    int maxMessages = 5000,
    int maxMemoryCandidates = 40,
  }) async {
    throw StateError('simulated Dreaming failure');
  }
}

class _GateUserProfileChangeProposalsNotifier
    extends UserProfileChangeProposalsNotifier {
  _GateUserProfileChangeProposalsNotifier({
    required this.started,
    required this.gate,
  });

  final Completer<void> started;
  final Completer<void> gate;

  @override
  Future<void> add(UserProfileChangeProposal proposal) async {
    if (!started.isCompleted) started.complete();
    await gate.future;
    await super.add(proposal);
  }
}
