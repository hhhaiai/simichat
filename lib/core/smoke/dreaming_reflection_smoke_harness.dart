import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/providers/database_provider.dart';
import '../../shared/providers/dreaming_provider.dart';
import '../../shared/providers/reflection_provider.dart';
import '../../shared/providers/user_profile_provider.dart';
import '../database/app_database.dart';
import '../memory/dreaming_service.dart';
import '../memory/reflection_service.dart';
import '../memory/user_profile.dart';

const dreamingReflectionSmokeEnabled = bool.fromEnvironment(
  'SIMICHAT_DREAMING_REFLECTION_SMOKE',
);
const dreamingReflectionSqliteRecoverySmokeEnabled = bool.fromEnvironment(
  'SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERY_SMOKE',
);
const _kSqliteRecoverySeededDayKey =
    'dreaming_reflection_sqlite_recovery_seeded_day_v1';

Future<void> runDreamingReflectionSmokeApp({required Widget child}) async {
  if (dreamingReflectionSqliteRecoverySmokeEnabled) {
    await _runDreamingReflectionSqliteRecoverySmokeApp(child: child);
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  for (final key in const [
    kDreamingDigestStorageKey,
    kDreamingDigestHistoryStorageKey,
    kDreamingScheduleStorageKey,
    kAssistantReflectionStorageKey,
    kAssistantReflectionHistoryStorageKey,
    kAssistantReflectionPendingStorageKey,
    kUserProfileChangeProposalsStorageKey,
  ]) {
    await prefs.remove(key);
  }
  await prefs.setString(
    kDreamingScheduleStorageKey,
    jsonEncode({'enabled': true, 'hour': 0, 'minute': 0}),
  );

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.sessionDao.createSession(id: 'device-dreaming-reflection');
  await db.sessionDao.updateTitle(
    'device-dreaming-reflection',
    'Dreaming Reflection 真机恢复',
  );
  await db.messageDao.insertMessage(
    id: 'device-dreaming-reflection-user',
    sessionId: 'device-dreaming-reflection',
    role: 'user',
    content: '请记住移动端 Dreaming 成功但反思失败时，需要在恢复前台后自动补跑。',
  );

  final reflectionService = _FailingOnceReflectionService();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        reflectionServiceProvider.overrideWithValue(reflectionService),
      ],
      child: _DreamingReflectionSmokeMonitor(
        reflectionService: reflectionService,
        child: child,
      ),
    ),
  );
}

Future<void> _runDreamingReflectionSqliteRecoverySmokeApp({
  required Widget child,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final seededDayKey = prefs.getString(_kSqliteRecoverySeededDayKey);
  final db = AppDatabase();
  if (seededDayKey == null) {
    for (final key in const [
      kDreamingDigestStorageKey,
      kDreamingDigestHistoryStorageKey,
      kDreamingScheduleStorageKey,
      kAssistantReflectionStorageKey,
      kAssistantReflectionHistoryStorageKey,
      kAssistantReflectionPendingStorageKey,
      kUserProfileChangeProposalsStorageKey,
    ]) {
      await prefs.remove(key);
    }
    await prefs.setString(
      kDreamingScheduleStorageKey,
      jsonEncode({'enabled': false, 'hour': 0, 'minute': 0}),
    );

    final now = DateTime.now();
    final digest = DreamingDigest(
      day: now,
      generatedAt: now,
      sessionCount: 1,
      originalMessageCount: 2,
      userMessageCount: 1,
      assistantMessageCount: 1,
      sessions: [
        DreamingSessionDigest(
          sessionId: 'sqlite-recovery-session',
          title: 'SQLite 冷启动恢复',
          messageCount: 2,
          userMessageCount: 1,
          assistantMessageCount: 1,
          highlights: const ['从 SQLite 恢复 Dreaming 后继续 Reflection。'],
          firstMessageAt: now.subtract(const Duration(minutes: 1)),
          lastMessageAt: now,
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['SQLite', '恢复'],
      elapsedMs: 1,
    );
    final jobId = 'dreaming-auto-${digest.dayKey}';
    await db.dreamingDao.createJob(
      id: jobId,
      dayKey: digest.dayKey,
      scheduledFor: now.millisecondsSinceEpoch,
      trigger: 'android_background',
    );
    await db.dreamingDao.markJobCompleted(jobId);
    await db.dreamingDao.upsertReport(
      id: 'dreaming-report-${digest.dayKey}',
      dayKey: digest.dayKey,
      jobId: jobId,
      generatedAt: now.millisecondsSinceEpoch,
      markdown: digest.toMarkdown(),
      digestJson: jsonEncode(digest.toJson()),
      sessionCount: digest.sessionCount,
      originalMessageCount: digest.originalMessageCount,
      totalOriginalMessageCount: digest.totalOriginalMessageCount,
      memoryCandidateCount: digest.memoryCandidates.length,
    );
    await prefs.setString(
      kAssistantReflectionPendingStorageKey,
      jsonEncode({
        'sourceDigestDayKey': digest.dayKey,
        'updatedAt': now.toUtc().toIso8601String(),
        'attemptCount': 1,
      }),
    );
    await prefs.setString(_kSqliteRecoverySeededDayKey, digest.dayKey);
    runApp(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text('SQLite recovery smoke ready')),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        'SIMICHAT_DREAMING_REFLECTION_SQLITE_READY dayKey=${digest.dayKey}',
      );
    });
    return;
  }

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: _DreamingReflectionSqliteRecoveryMonitor(
        expectedDayKey: seededDayKey,
        child: child,
      ),
    ),
  );
}

class _DreamingReflectionSqliteRecoveryMonitor extends ConsumerStatefulWidget {
  const _DreamingReflectionSqliteRecoveryMonitor({
    required this.expectedDayKey,
    required this.child,
  });

  final String expectedDayKey;
  final Widget child;

  @override
  ConsumerState<_DreamingReflectionSqliteRecoveryMonitor> createState() =>
      _DreamingReflectionSqliteRecoveryMonitorState();
}

class _DreamingReflectionSqliteRecoveryMonitorState
    extends ConsumerState<_DreamingReflectionSqliteRecoveryMonitor> {
  bool _reported = false;

  @override
  Widget build(BuildContext context) {
    final digest = ref.watch(dreamingDigestProvider);
    final digestHistory = ref.watch(dreamingDigestHistoryProvider);
    final pending = ref.watch(assistantReflectionPendingProvider);
    final report = ref.watch(assistantReflectionProvider);
    final reflectionHistory = ref.watch(assistantReflectionHistoryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reported) return;
      if (digest?.dayKey == widget.expectedDayKey &&
          digestHistory.any((item) => item.dayKey == widget.expectedDayKey) &&
          pending == null &&
          report?.sourceDigestDayKey == widget.expectedDayKey &&
          reflectionHistory.any(
            (item) => item.sourceDigestDayKey == widget.expectedDayKey,
          )) {
        _reported = true;
        debugPrint(
          'SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERED '
          'dayKey=${widget.expectedDayKey} '
          'dreamingHistory=${digestHistory.length} '
          'reflectionHistory=${reflectionHistory.length}',
        );
      }
    });
    return widget.child;
  }
}

class _DreamingReflectionSmokeMonitor extends ConsumerStatefulWidget {
  const _DreamingReflectionSmokeMonitor({
    required this.reflectionService,
    required this.child,
  });

  final _FailingOnceReflectionService reflectionService;
  final Widget child;

  @override
  ConsumerState<_DreamingReflectionSmokeMonitor> createState() =>
      _DreamingReflectionSmokeMonitorState();
}

class _DreamingReflectionSmokeMonitorState
    extends ConsumerState<_DreamingReflectionSmokeMonitor> {
  bool _pendingReported = false;
  bool _recoveredReported = false;

  @override
  Widget build(BuildContext context) {
    final digest = ref.watch(dreamingDigestProvider);
    final pending = ref.watch(assistantReflectionPendingProvider);
    final report = ref.watch(assistantReflectionProvider);
    final history = ref.watch(assistantReflectionHistoryProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_pendingReported &&
          digest != null &&
          pending?.sourceDigestDayKey == digest.dayKey &&
          report == null &&
          widget.reflectionService.attemptCount == 1) {
        _pendingReported = true;
        debugPrint(
          'SIMICHAT_DREAMING_REFLECTION_PENDING '
          'dayKey=${pending?.sourceDigestDayKey} attempts=${pending?.attemptCount}',
        );
      }
      if (!_recoveredReported &&
          _pendingReported &&
          digest != null &&
          pending == null &&
          report?.hasContent == true &&
          report?.sourceDigestDayKey == digest.dayKey &&
          history.isNotEmpty &&
          widget.reflectionService.attemptCount == 2) {
        _recoveredReported = true;
        debugPrint(
          'SIMICHAT_DREAMING_REFLECTION_RECOVERED '
          'dayKey=${report?.sourceDigestDayKey} '
          'attempts=${widget.reflectionService.attemptCount} '
          'history=${history.length}',
        );
      }
    });

    return widget.child;
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
      throw StateError('simulated device Reflection failure');
    }
    return super.buildDailyReflection(
      digest: digest,
      profile: profile,
      pendingProfileProposalCount: pendingProfileProposalCount,
    );
  }
}
