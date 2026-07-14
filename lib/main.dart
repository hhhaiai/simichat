import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/generated/app_localizations.dart';

import 'features/chat/chat_page.dart';
import 'features/settings/settings_page.dart';
import 'features/marketplace/marketplace_page.dart';
import 'features/search/search_sheet.dart';
import 'core/background/dreaming_background_workmanager.dart';
import 'core/deep_link/deep_link_service.dart';
import 'core/database/app_database.dart';
import 'core/skills/skill.dart' show builtInSkills;
import 'core/notification/notification_service.dart';
import 'core/smoke/release_background_smoke_harness.dart';
import 'core/smoke/release_deep_link_smoke_harness.dart';
import 'core/smoke/release_network_smoke_harness.dart';
import 'core/smoke/release_send_smoke_harness.dart';
import 'core/smoke/dreaming_reflection_smoke_harness.dart';
import 'core/smoke/android_background_dreaming_smoke_harness.dart';
import 'core/smoke/ios_background_dreaming_smoke_harness.dart';
import 'core/database/dao/channel_dao.dart';
import 'shared/widgets/sidebar.dart';
import 'shared/providers/chat_provider.dart';
import 'shared/providers/channel_provider.dart';
import 'shared/providers/connectivity_provider.dart';
import 'shared/providers/database_provider.dart';
import 'shared/providers/dreaming_provider.dart';
import 'shared/providers/session_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/reflection_provider.dart';
import 'shared/providers/user_profile_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (iosBackgroundDreamingSmokeEnabled) {
    await runIosBackgroundDreamingSmokeApp();
    return;
  }
  if (androidBackgroundDreamingSmokeEnabled) {
    await runAndroidBackgroundDreamingSmokeApp();
    return;
  }
  if (dreamingReflectionSmokeEnabled) {
    dreamingDigestCompleteNotifier =
        ({
          required String dayKey,
          required int originalMessageCount,
          int? totalOriginalMessageCount,
          required int memoryCandidateCount,
          int profileProposalCount = 0,
        }) async {};
    dreamingDigestFailedNotifier = ({required String dayKey}) async {};
    await runDreamingReflectionSmokeApp(child: const AiChatApp());
    return;
  }
  if (releaseSendSmokeEnabled) {
    await runReleaseSendSmokeApp(child: const AiChatApp());
    return;
  }
  if (releaseBackgroundSmokeEnabled) {
    await runReleaseBackgroundSmokeApp(child: const AiChatApp());
    return;
  }
  if (releaseNetworkSmokeEnabled) {
    await runReleaseNetworkSmokeApp(child: const AiChatApp());
    return;
  }
  if (releaseDeepLinkSmokeEnabled) {
    await runReleaseDeepLinkSmokeApp(
      buildApp: (observers) => AiChatApp(navigatorObservers: observers),
    );
    return;
  }

  try {
    await syncDreamingBackgroundScheduleFromStorage();
  } catch (e) {
    debugPrint('Background Dreaming schedule failed: $e');
  }

  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init failed: $e');
  }

  // 初始化数据库并植入内置 Skills
  final db = AppDatabase();
  try {
    await _seedBuiltInSkills(db);
  } catch (e) {
    debugPrint('Seed built-in skills failed: $e');
  }
  await db.close();

  runApp(const ProviderScope(child: AiChatApp()));
}

/// 首次启动时植入内置 Skills（幂等：已存在则跳过）
Future<void> _seedBuiltInSkills(AppDatabase db) async {
  for (final skill in builtInSkills) {
    final existing = await db.skillDao.getSkill(skill.id);
    if (existing == null) {
      await db.skillDao.insertSkill(
        id: skill.id,
        name: skill.name,
        description: skill.description,
        instructions: skill.instructions,
        isEnabled: false, // 默认不启用，用户手动开启
      );
    }
  }
}

typedef DreamingDigestCompleteNotifier =
    Future<void> Function({
      required String dayKey,
      required int originalMessageCount,
      int? totalOriginalMessageCount,
      required int memoryCandidateCount,
      int profileProposalCount,
    });

typedef DreamingDigestFailedNotifier =
    Future<void> Function({required String dayKey});

Future<void> _defaultDreamingDigestCompleteNotifier({
  required String dayKey,
  required int originalMessageCount,
  int? totalOriginalMessageCount,
  required int memoryCandidateCount,
  int profileProposalCount = 0,
}) {
  return NotificationService().showDreamingDigestComplete(
    dayKey: dayKey,
    originalMessageCount: originalMessageCount,
    totalOriginalMessageCount: totalOriginalMessageCount,
    memoryCandidateCount: memoryCandidateCount,
    profileProposalCount: profileProposalCount,
  );
}

Future<void> _defaultDreamingDigestFailedNotifier({required String dayKey}) {
  return NotificationService().showDreamingDigestFailed(dayKey: dayKey);
}

@visibleForTesting
DreamingDigestCompleteNotifier dreamingDigestCompleteNotifier =
    _defaultDreamingDigestCompleteNotifier;

@visibleForTesting
DreamingDigestFailedNotifier dreamingDigestFailedNotifier =
    _defaultDreamingDigestFailedNotifier;

@visibleForTesting
void resetDreamingDigestCompleteNotifierForTesting() {
  dreamingDigestCompleteNotifier = _defaultDreamingDigestCompleteNotifier;
  dreamingDigestFailedNotifier = _defaultDreamingDigestFailedNotifier;
}

class AiChatApp extends ConsumerWidget {
  const AiChatApp({super.key, this.navigatorObservers = const []});

  final List<NavigatorObserver> navigatorObservers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);

    return MaterialApp(
      title: 'SimiAIChat',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      theme: _buildAppTheme(Brightness.light),
      darkTheme: _buildAppTheme(Brightness.dark),
      themeMode: themeMode,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(normalizeFontScale(fontScale)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      navigatorObservers: navigatorObservers,
      routes: {
        '/': (_) => const ResponsiveShell(),
        '/settings': (_) => const SettingsPage(),
        '/marketplace': (_) => const MarketplacePage(),
      },
    );
  }
}

ThemeData _buildAppTheme(Brightness brightness) {
  return ThemeData(
    colorSchemeSeed: const Color(0xFF10A37F),
    brightness: brightness,
    useMaterial3: true,
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: EdgeInsets.fromLTRB(16, 8, 16, 120),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
  );
}

/// 键盘快捷键定义
class _NewSessionIntent extends Intent {
  const _NewSessionIntent();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _CancelStreamingIntent extends Intent {
  const _CancelStreamingIntent();
}

const _kDefaultDreamingForegroundCheckInterval = Duration(minutes: 1);

@visibleForTesting
Duration dreamingForegroundCheckInterval =
    _kDefaultDreamingForegroundCheckInterval;

@visibleForTesting
void resetDreamingForegroundCheckIntervalForTesting() {
  dreamingForegroundCheckInterval = _kDefaultDreamingForegroundCheckInterval;
}

@visibleForTesting
Duration backgroundInterruptedPersistDelayForTesting = Duration.zero;

@visibleForTesting
void resetBackgroundInterruptedPersistDelayForTesting() {
  backgroundInterruptedPersistDelayForTesting = Duration.zero;
}

/// 响应式外壳：桌面端固定侧边栏，移动端 Drawer
class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({super.key});

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell>
    with WidgetsBindingObserver {
  static const _kDesktopBreakpoint = 720.0;
  final MethodChannelSimiDeepLinkService _deepLinkService =
      MethodChannelSimiDeepLinkService();
  bool _autoSelectingSession = false;
  Timer? _dreamingForegroundTimer;
  StreamSubscription<SimiDeepLink>? _deepLinkSubscription;
  List<String> _backgroundInterruptedSessionIds = const [];
  List<String> _networkInterruptedSessionIds = const [];
  Future<void>? _backgroundInterruptedPersistFuture;
  String? _lastPromptedDreamingFailedJobId;
  String? _lastNotifiedDreamingFailedDayKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDreamingForegroundTimer();
    _deepLinkSubscription = _deepLinkService.links.listen((link) {
      unawaited(_handleDeepLink(link));
    });
    // 首次启动时，如果没有会话则自动创建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupTasks());
    });
  }

  @override
  void dispose() {
    _dreamingForegroundTimer?.cancel();
    unawaited(_deepLinkSubscription?.cancel());
    unawaited(_deepLinkService.dispose());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startDreamingForegroundTimer();
      unawaited(
        _runDueDreamingIfNeeded().whenComplete(
          _showDreamingFailedJobPromptIfNeeded,
        ),
      );
      _showBackgroundInterruptedRetryPromptIfNeeded();
    } else {
      _dreamingForegroundTimer?.cancel();
      _dreamingForegroundTimer = null;
      final streamingSessionIds =
          _streamingSessionIdsForLifecycleCancellation();
      if (streamingSessionIds.isNotEmpty) {
        _backgroundInterruptedSessionIds = streamingSessionIds;
        final persistFuture = _persistBackgroundInterruptedSessions(
          streamingSessionIds,
        );
        _backgroundInterruptedPersistFuture = persistFuture;
        unawaited(
          persistFuture.whenComplete(() {
            if (identical(_backgroundInterruptedPersistFuture, persistFuture)) {
              _backgroundInterruptedPersistFuture = null;
            }
          }),
        );
        for (final sessionId in streamingSessionIds) {
          cancelStreaming(
            ref,
            sessionId,
            error: backgroundStreamingInterruptedMessage,
          );
        }
      }
    }
  }

  void _handleNetworkBecameOffline() {
    final streamingSessionIds = _streamingSessionIdsForLifecycleCancellation();
    if (streamingSessionIds.isEmpty) return;
    _networkInterruptedSessionIds = streamingSessionIds;
    for (final sessionId in streamingSessionIds) {
      cancelStreaming(
        ref,
        sessionId,
        error: networkStreamingInterruptedMessage,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.fixed,
          content: Text('网络连接断开，已停止生成，联网后可重试'),
        ),
      );
  }

  void _showNetworkInterruptedRetryPromptIfNeeded() {
    if (!mounted) return;
    final interruptedSessionIds = _networkInterruptedSessionIds;
    if (interruptedSessionIds.isEmpty) return;
    final retryableSessionIds = interruptedSessionIds
        .where(
          (sessionId) =>
              ref.read(streamStateProvider(sessionId)).error ==
              networkStreamingInterruptedMessage,
        )
        .toList();
    _networkInterruptedSessionIds = const [];
    if (retryableSessionIds.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.fixed,
          content: Text(
            _networkInterruptedRestoredSnackBarText(retryableSessionIds.length),
          ),
          action: SnackBarAction(
            label: _backgroundInterruptedRestoredSnackBarActionText(
              retryableSessionIds.length,
            ),
            onPressed: () =>
                _retryBackgroundInterruptedSessions(retryableSessionIds),
          ),
        ),
      );
  }

  String _networkInterruptedRestoredSnackBarText(int count) {
    if (count <= 1) {
      return '网络已恢复，可点“重试”继续';
    }
    return '网络已恢复，$count 个会话可点“重试全部”继续';
  }

  void _startDreamingForegroundTimer() {
    _dreamingForegroundTimer?.cancel();
    _dreamingForegroundTimer = Timer.periodic(dreamingForegroundCheckInterval, (
      _,
    ) {
      if (mounted) {
        _runDueDreamingIfNeeded();
      }
    });
  }

  Future<void> _runStartupTasks() async {
    await _autoSelectOrCreateSession();
    await _restorePersistedBackgroundInterruptedRetryIfNeeded();
    unawaited(
      _runDueDreamingIfNeeded().whenComplete(
        _showDreamingFailedJobPromptIfNeeded,
      ),
    );
    unawaited(_handleInitialDeepLinkIfNeeded());
  }

  Future<void> _handleInitialDeepLinkIfNeeded() async {
    try {
      final link = await _deepLinkService.getInitialLink();
      if (link == null || !mounted) return;
      await _handleDeepLink(link);
    } catch (_) {
      // 深度链接失败不影响正常启动。
    }
  }

  Future<void> _handleDeepLink(SimiDeepLink link) async {
    if (!mounted) return;
    switch (link.action) {
      case SimiDeepLinkAction.home:
        _popToHome();
        return;
      case SimiDeepLinkAction.newChat:
        _popToHome();
        await createNewSession(ref);
        if (!mounted) return;
        _showDeepLinkSnackBar('已通过链接新建会话');
        return;
      case SimiDeepLinkAction.settings:
        _popToHome();
        if (!mounted) return;
        await _pushDeepLinkRoute('/settings');
        return;
      case SimiDeepLinkAction.marketplace:
        _popToHome();
        if (!mounted) return;
        await _pushDeepLinkRoute('/marketplace');
        return;
      case SimiDeepLinkAction.session:
        final sessionId = link.sessionId;
        if (sessionId == null) return;
        final session = await ref
            .read(sessionDaoProvider)
            .getSession(sessionId);
        if (!mounted) return;
        if (session == null) {
          _showDeepLinkSnackBar('链接中的会话不存在或已删除');
          return;
        }
        _popToHome();
        ref.read(activeSessionIdProvider.notifier).state = session.id;
        refreshSessions(ref);
        _showDeepLinkSnackBar('已打开链接中的会话');
        return;
    }
  }

  Future<void> _pushDeepLinkRoute(String routeName) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).pushNamed(routeName);
  }

  void _popToHome() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  void _showDeepLinkSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _streamingSessionIdsForLifecycleCancellation() {
    final sessionIds = <String>[];
    void addIfStreaming(String? sessionId) {
      if (sessionId == null || sessionIds.contains(sessionId)) return;
      if (!ref.read(streamStateProvider(sessionId)).isStreaming) return;
      sessionIds.add(sessionId);
    }

    addIfStreaming(ref.read(activeSessionIdProvider));
    for (final session
        in ref.read(sessionsProvider).valueOrNull ?? const <Session>[]) {
      addIfStreaming(session.id);
    }
    return sessionIds;
  }

  Future<void> _persistBackgroundInterruptedSessions(
    List<String> sessionIds,
  ) async {
    try {
      if (backgroundInterruptedPersistDelayForTesting > Duration.zero) {
        await Future<void>.delayed(backgroundInterruptedPersistDelayForTesting);
      }
      final prefs = await SharedPreferences.getInstance();
      final persistedSessionIds = _readPersistedBackgroundInterruptedSessionIds(
        prefs,
      );
      for (final sessionId in sessionIds) {
        if (!persistedSessionIds.contains(sessionId)) {
          persistedSessionIds.add(sessionId);
        }
      }
      await prefs.setStringList(
        kBackgroundInterruptedSessionsStorageKey,
        persistedSessionIds,
      );
      await prefs.setString(
        kBackgroundInterruptedSessionStorageKey,
        sessionIds.first,
      );
    } catch (_) {
      // 持久化失败不能影响后台切出取消流式请求。
    }
  }

  Future<void> _restorePersistedBackgroundInterruptedRetryIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final interruptedSessionIds =
          _readPersistedBackgroundInterruptedSessionIds(prefs);
      if (interruptedSessionIds.isEmpty) return;
      if (!mounted) return;

      final restoredSessionIds = <String>[];
      final sessionDao = ref.read(sessionDaoProvider);
      for (final sessionId in interruptedSessionIds) {
        final interruptedSession = await sessionDao.getSession(sessionId);
        if (!mounted) return;
        if (interruptedSession == null) {
          continue;
        }
        restoredSessionIds.add(sessionId);
        ref.read(streamStateProvider(sessionId).notifier).state =
            const StreamState(error: backgroundStreamingInterruptedMessage);
      }

      await _clearPersistedBackgroundInterruptedSession();
      if (!mounted || restoredSessionIds.isEmpty) return;

      final primarySessionId = restoredSessionIds.first;
      if (ref.read(activeSessionIdProvider) != primarySessionId) {
        ref.read(activeSessionIdProvider.notifier).state = primarySessionId;
      }
      if (!mounted || ref.read(activeSessionIdProvider) != primarySessionId) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.fixed,
            content: Text(
              _backgroundInterruptedRestoredSnackBarText(
                restoredSessionIds.length,
              ),
            ),
            action: SnackBarAction(
              label: _backgroundInterruptedRestoredSnackBarActionText(
                restoredSessionIds.length,
              ),
              onPressed: () =>
                  _retryBackgroundInterruptedSessions(restoredSessionIds),
            ),
          ),
        );
    } catch (_) {
      // 恢复提示失败不能影响应用启动。
    }
  }

  String _backgroundInterruptedRestoredSnackBarText(int count) {
    if (count <= 1) {
      return '已恢复上次后台中断，可点“重试”继续';
    }
    return '已恢复 $count 个后台中断会话，可点“重试全部”继续';
  }

  String _backgroundInterruptedRestoredSnackBarActionText(int count) {
    if (count <= 1) {
      return '重试';
    }
    return '重试全部';
  }

  void _retryBackgroundInterruptedSessions(List<String> sessionIds) {
    for (final sessionId in sessionIds) {
      retryLastUserMessage(ref, sessionId: sessionId);
    }
  }

  List<String> _readPersistedBackgroundInterruptedSessionIds(
    SharedPreferences prefs,
  ) {
    final sessionIds = <String>[];
    void addSessionId(String? value) {
      final sessionId = value?.trim();
      if (sessionId == null ||
          sessionId.isEmpty ||
          sessionIds.contains(sessionId)) {
        return;
      }
      sessionIds.add(sessionId);
    }

    for (final sessionId
        in prefs.getStringList(kBackgroundInterruptedSessionsStorageKey) ??
            const <String>[]) {
      addSessionId(sessionId);
    }
    addSessionId(prefs.getString(kBackgroundInterruptedSessionStorageKey));
    return sessionIds;
  }

  void _showBackgroundInterruptedRetryPromptIfNeeded() {
    if (!mounted) return;
    final interruptedSessionIds = _backgroundInterruptedSessionIds;
    if (interruptedSessionIds.isEmpty) {
      return;
    }
    final retryableSessionIds = interruptedSessionIds
        .where(
          (sessionId) =>
              ref.read(streamStateProvider(sessionId)).error ==
              backgroundStreamingInterruptedMessage,
        )
        .toList();
    if (retryableSessionIds.isEmpty) {
      _backgroundInterruptedSessionIds = const [];
      return;
    }
    _backgroundInterruptedSessionIds = const [];
    unawaited(_clearPersistedBackgroundInterruptedSession());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.fixed,
          content: Text(
            _backgroundInterruptedResumedSnackBarText(
              retryableSessionIds.length,
            ),
          ),
          action: SnackBarAction(
            label: _backgroundInterruptedRestoredSnackBarActionText(
              retryableSessionIds.length,
            ),
            onPressed: () =>
                _retryBackgroundInterruptedSessions(retryableSessionIds),
          ),
        ),
      );
  }

  String _backgroundInterruptedResumedSnackBarText(int count) {
    if (count <= 1) {
      return '已停止后台生成，可点“重试”继续';
    }
    return '已停止 $count 个后台生成，可点“重试全部”继续';
  }

  Future<void> _showDreamingFailedJobPromptIfNeeded() async {
    try {
      final failedJob = await ref.read(latestFailedDreamingJobProvider.future);
      if (!mounted || failedJob == null) return;
      if (_lastPromptedDreamingFailedJobId == failedJob.id) return;
      _lastPromptedDreamingFailedJobId = failedJob.id;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.fixed,
          content: const Text('上次 Dreaming 失败，可到设置页重试'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: () {
              if (!mounted) return;
              unawaited(
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).pushNamed('/settings'),
              );
            },
          ),
        ),
      );
    } catch (_) {
      // Dreaming 失败提示读取失败不能影响主聊天入口。
    }
  }

  Future<void> _clearPersistedBackgroundInterruptedSession() async {
    final pendingPersist = _backgroundInterruptedPersistFuture;
    if (pendingPersist != null) {
      try {
        await pendingPersist;
      } catch (_) {
        // 即使上一次 marker 写入失败，也继续执行清理。
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kBackgroundInterruptedSessionStorageKey);
      await prefs.remove(kBackgroundInterruptedSessionsStorageKey);
    } catch (_) {
      // 清理失败只会导致下次启动再次提示，不影响当前恢复。
    }
  }

  Future<void> _autoSelectOrCreateSession() async {
    if (_autoSelectingSession || ref.read(activeSessionIdProvider) != null) {
      return;
    }
    _autoSelectingSession = true;
    try {
      final sessions = await ref.read(sessionsProvider.future);
      if (!mounted || ref.read(activeSessionIdProvider) != null) return;
      if (sessions.isEmpty) {
        await createNewSession(ref);
      } else {
        ref.read(activeSessionIdProvider.notifier).state = sessions.first.id;
      }
    } finally {
      _autoSelectingSession = false;
    }
  }

  Future<void> _runDueDreamingIfNeeded() async {
    try {
      await retryPendingAssistantReflection(ref);
    } catch (_) {
      // 待处理反思重试失败不能影响新的 Dreaming 检查；pending 会保留供下次恢复。
    }
    if (!mounted) return;
    try {
      final digest = await maybeRunDueDreaming(ref);
      if (!mounted) return;
      if (digest != null && digest.hasContent) {
        var profileProposalCount = 0;
        try {
          final proposal = await proposeUserProfileChanges(
            ref,
            reason: 'profile_proposal',
          );
          profileProposalCount = proposal?.diff.items.length ?? 0;
        } catch (_) {
          // 画像候选生成失败也不影响 Dreaming 完成通知。
        }
        if (!mounted) return;
        try {
          await runAssistantReflection(
            ref,
            digest: digest,
            pendingProfileProposalCount: profileProposalCount,
          );
        } catch (_) {
          // 本地反思失败不能影响 Dreaming 完成通知。
        }
        if (!mounted) return;
        await dreamingDigestCompleteNotifier(
          dayKey: digest.dayKey,
          originalMessageCount: digest.originalMessageCount,
          totalOriginalMessageCount: digest.totalOriginalMessageCount,
          memoryCandidateCount: digest.memoryCandidates.length,
          profileProposalCount: profileProposalCount,
        );
      }
    } catch (_) {
      if (!mounted) return;
      await _notifyDreamingFailedIfNeeded();
    }
  }

  Future<void> _notifyDreamingFailedIfNeeded() async {
    try {
      ref.invalidate(latestFailedDreamingJobProvider);
      final failedJob = await ref.read(latestFailedDreamingJobProvider.future);
      if (!mounted || failedJob == null) return;
      if (_lastNotifiedDreamingFailedDayKey == failedJob.dayKey) return;
      _lastNotifiedDreamingFailedDayKey = failedJob.dayKey;
      await dreamingDigestFailedNotifier(dayKey: failedJob.dayKey);
    } catch (_) {
      // 前台到期整理失败通知也不能影响聊天主链路；用户仍可在设置页手动重试。
    }
  }

  @override
  Widget build(BuildContext context) {
    // watch 以保持响应式（子组件依赖这些 provider）
    ref.watch(sessionsProvider);
    ref.watch(activeSessionIdProvider);
    ref.listen<bool>(isOnlineProvider, (previous, next) {
      if (previous == true && !next) {
        _handleNetworkBecameOffline();
      } else if (previous == false && next) {
        _showNetworkInterruptedRetryPromptIfNeeded();
      }
    });

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
            const _NewSessionIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const _NewSessionIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyK,
        ): const _SearchIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyK,
        ): const _SearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape):
            const _CancelStreamingIntent(),
      },
      child: Actions(
        actions: {
          _NewSessionIntent: CallbackAction<_NewSessionIntent>(
            onInvoke: (_) {
              createNewSession(ref);
              return null;
            },
          ),
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) {
              showSearchSheet(context);
              return null;
            },
          ),
          _CancelStreamingIntent: CallbackAction<_CancelStreamingIntent>(
            onInvoke: (_) {
              final activeId = ref.read(activeSessionIdProvider);
              if (activeId != null) {
                cancelStreaming(ref, activeId);
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > _kDesktopBreakpoint;
              if (isDesktop) {
                return _buildDesktopLayout(context, ref);
              } else {
                return _buildMobileLayout(context, ref);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Row(
        children: [
          // 侧边栏（固定 280px）
          const SizedBox(width: 280, child: Sidebar()),
          // 分隔线
          VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          // 对话区
          Expanded(
            child: Scaffold(
              appBar: _buildChatAppBar(context, ref),
              body: const ChatPage(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: _buildChatAppBar(context, ref, showMenuButton: true),
      drawer: const Drawer(child: SafeArea(child: Sidebar())),
      body: const ChatPage(),
    );
  }

  /// AppBar 标题：会话名 + 当前模型（桌面端与移动端统一可切换）
  Widget _buildChatTitle(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Session?> activeSession,
  ) {
    final modelsAsync = ref.watch(allModelsProvider);
    final selectedId = ref.watch(selectedModelIdProvider);
    final sessionDefaultModelId = activeSession.whenOrNull(
      data: (session) => session?.defaultChannelModelId,
    );
    final currentModelId = selectedId ?? sessionDefaultModelId;

    final modelLabel = modelsAsync.whenOrNull(
      data: (models) {
        if (currentModelId != null) {
          final match = models
              .where((m) => m.channelModel.id == currentModelId)
              .firstOrNull;
          if (match != null) return match.displayLabel;
        }
        return null;
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          activeSession.whenOrNull(data: (session) => session?.title) ??
              'SimiAIChat',
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        modelsAsync.when(
          loading: () => Text(
            '加载模型中…',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          error: (_, _) => Text(
            '未选择模型',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          data: (models) {
            if (models.isEmpty) {
              return Text(
                '未选择模型',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              );
            }

            return PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              tooltip: '切换模型',
              onSelected: (modelId) async {
                final target = models
                    .where((m) => m.channelModel.id == modelId)
                    .firstOrNull;
                final targetLabel =
                    target?.displayLabel ??
                    target?.channelModel.modelName ??
                    modelId;
                try {
                  final result = await switchConversationModel(
                    ref: ref,
                    modelId: modelId,
                    modelLabel: targetLabel,
                    previousModelId: currentModelId,
                    previousModelLabel: modelLabel,
                  );
                  if (context.mounted && result.changed) {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            result.recorded
                                ? '已切换模型，记录已写入当前对话'
                                : result.message,
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(SnackBar(content: Text('模型切换失败，已回滚: $e')));
                  }
                }
              },
              itemBuilder: (_) =>
                  _buildMobileModelMenuItems(context, models, currentModelId),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      modelLabel ?? '未选择模型',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more, size: 14, color: Colors.grey[500]),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMobileModelMenuItems(
    BuildContext context,
    List<ChannelModelWithChannel> models,
    String? selectedId,
  ) {
    final items = <PopupMenuEntry<String>>[];
    final grouped = <String, List<ChannelModelWithChannel>>{};

    for (final model in models) {
      grouped.putIfAbsent(model.channel.name, () => []).add(model);
    }

    for (final entry in grouped.entries) {
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            entry.key,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
        ),
      );

      for (final model in entry.value) {
        final isSelected = model.channelModel.id == selectedId;
        items.add(
          PopupMenuItem<String>(
            value: model.channelModel.id,
            child: Row(
              children: [
                if (isSelected)
                  Icon(
                    Icons.check,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    model.channelModel.modelName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return items;
  }

  PreferredSizeWidget _buildChatAppBar(
    BuildContext context,
    WidgetRef ref, {
    bool showMenuButton = false,
  }) {
    final activeSession = ref.watch(activeSessionProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);

    return AppBar(
      leading: showMenuButton
          ? Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          : null,
      title: _buildChatTitle(context, ref, activeSession),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: '新建会话',
          onPressed: () => createNewSession(ref),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '重试回复',
          onPressed: activeSessionId == null
              ? null
              : () => retryLastUserMessage(ref, sessionId: activeSessionId),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: '设置',
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
      ],
    );
  }
}
