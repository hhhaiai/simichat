import 'dart:convert';

import 'package:ai_chat_app/core/background/dreaming_background_runner.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/dreaming_provider.dart';
import 'package:ai_chat_app/shared/providers/reflection_provider.dart';
import 'package:ai_chat_app/shared/providers/user_profile_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    resetDreamingAutoRunStateForTesting();
    resetAssistantReflectionRetryStateForTesting();
  });

  tearDown(() {
    resetDreamingAutoRunStateForTesting();
    resetAssistantReflectionRetryStateForTesting();
  });

  test('Android background task persists Dreaming and Reflection', () async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': true,
        'hour': 22,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    const sessionId = 'android-background-dreaming';
    const messageId = 'android-background-message';
    final now = DateTime(2026, 7, 14, 22, 30);
    await db.sessionDao.createSession(id: sessionId);
    await db.messageDao.insertMessage(
      id: messageId,
      sessionId: sessionId,
      role: 'user',
      content: '请记住移动端需要在系统后台完成 Dreaming，并在完成后生成反思。',
    );
    await db.customStatement(
      "UPDATE messages SET created_at = ${now.millisecondsSinceEpoch} WHERE id = '$messageId'",
    );

    var completeNotifications = 0;
    var failedNotifications = 0;
    final result = await runDreamingBackgroundTask(
      container: container,
      now: now,
      notifyComplete: ({required digest, required profileProposalCount}) async {
        completeNotifications += 1;
      },
      notifyFailed: ({required dayKey}) async {
        failedNotifications += 1;
      },
    );

    expect(result.status, DreamingBackgroundRunStatus.completed);
    expect(result.digest?.dayKey, '2026-07-14');
    expect(result.reflection?.sourceDigestDayKey, '2026-07-14');
    expect(completeNotifications, 1);
    expect(failedNotifications, 0);

    final jobs = await db.dreamingDao.getJobsByDay('2026-07-14');
    expect(jobs, hasLength(1));
    expect(jobs.single.id, 'dreaming-auto-2026-07-14');
    expect(jobs.single.trigger, 'android_background');
    expect(jobs.single.status, 'completed');
    expect(await db.dreamingDao.getReportByDay('2026-07-14'), isNotNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
    expect(prefs.getString(kAssistantReflectionStorageKey), isNotNull);
    expect(prefs.getString(kAssistantReflectionHistoryStorageKey), isNotNull);
    expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNull);
    expect(
      prefs.getString(kDreamingScheduleStorageKey),
      contains('2026-07-14'),
    );
  });

  test('iOS background task persists the iOS trigger', () async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': true,
        'hour': 22,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    const sessionId = 'ios-background-dreaming';
    const messageId = 'ios-background-message';
    final now = DateTime(2026, 7, 14, 22, 30);
    await db.sessionDao.createSession(id: sessionId);
    await db.messageDao.insertMessage(
      id: messageId,
      sessionId: sessionId,
      role: 'user',
      content: '请在 iOS 系统后台完成 Dreaming 和 Reflection。',
    );
    await db.customStatement(
      "UPDATE messages SET created_at = ${now.millisecondsSinceEpoch} "
      "WHERE id = '$messageId'",
    );

    final result = await runDreamingBackgroundTask(
      container: container,
      now: now,
      trigger: 'ios_background',
      notifyComplete:
          ({required digest, required profileProposalCount}) async {},
      notifyFailed: ({required dayKey}) async {},
    );

    expect(result.status, DreamingBackgroundRunStatus.completed);
    final jobs = await db.dreamingDao.getJobsByDay('2026-07-14');
    expect(jobs, hasLength(1));
    expect(jobs.single.trigger, 'ios_background');
    expect(jobs.single.status, 'completed');
  });

  test(
    'background model profile enhancement remains a pending proposal',
    () async {
      SharedPreferences.setMockInitialValues({
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 22,
          'minute': 0,
        }),
        kUserProfileModelEnabledStorageKey: true,
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          userProfileModelEnhancerProvider.overrideWithValue(({
            required digest,
            required localCandidate,
            required controls,
          }) async {
            return localCandidate.copyWith(
              styleSignals: [...localCandidate.styleSignals, '偏好后台生成后逐项确认画像候选'],
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      const sessionId = 'background-model-profile';
      const messageId = 'background-model-profile-message';
      final now = DateTime(2026, 7, 14, 22, 30);
      await db.sessionDao.createSession(id: sessionId);
      await db.messageDao.insertMessage(
        id: messageId,
        sessionId: sessionId,
        role: 'user',
        content: '我的目标是移动端后台 Dreaming 后生成待确认画像，不要自动修改正式画像。',
      );
      await db.customStatement(
        "UPDATE messages SET created_at = ${now.millisecondsSinceEpoch} WHERE id = '$messageId'",
      );

      var notifiedProposalCount = 0;
      final result = await runDreamingBackgroundTask(
        container: container,
        now: now,
        notifyComplete:
            ({required digest, required profileProposalCount}) async {
              notifiedProposalCount = profileProposalCount;
            },
        notifyFailed: ({required dayKey}) async {},
      );

      expect(result.status, DreamingBackgroundRunStatus.completed);
      expect(result.reflection?.pendingProfileProposalCount, greaterThan(0));
      expect(notifiedProposalCount, greaterThan(0));
      expect(container.read(userProfileProvider), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kUserProfileStorageKey), isNull);
      final proposals = decodeUserProfileChangeProposals(
        prefs.getString(kUserProfileChangeProposalsStorageKey),
      );
      expect(proposals, hasLength(1));
      expect(
        proposals.single.generationMode,
        kUserProfileProposalGenerationModeModel,
      );
      expect(
        proposals.single.candidateProfile.styleSignals,
        contains('偏好后台生成后逐项确认画像候选'),
      );
    },
  );

  test('Android background retry recovers pending Reflection once', () async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': true,
        'hour': 22,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final reflectionService = _FailingOnceReflectionService();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        reflectionServiceProvider.overrideWithValue(reflectionService),
      ],
    );
    addTearDown(container.dispose);

    final now = DateTime(2026, 7, 14, 22, 30);
    await db.sessionDao.createSession(id: 'reflection-retry-session');
    await db.messageDao.insertMessage(
      id: 'reflection-retry-message',
      sessionId: 'reflection-retry-session',
      role: 'user',
      content: '请在后台反思失败后自动恢复，不要重复生成 Dreaming。',
    );
    await db.customStatement(
      'UPDATE messages SET created_at = ${now.millisecondsSinceEpoch}',
    );

    var completeNotifications = 0;
    Future<void> notifyComplete({
      required DreamingDigest digest,
      required int profileProposalCount,
    }) async {
      completeNotifications += 1;
    }

    final first = await runDreamingBackgroundTask(
      container: container,
      now: now,
      notifyComplete: notifyComplete,
      notifyFailed: ({required dayKey}) async {},
    );
    final second = await runDreamingBackgroundTask(
      container: container,
      now: now.add(const Duration(minutes: 15)),
      notifyComplete: notifyComplete,
      notifyFailed: ({required dayKey}) async {},
    );

    expect(first.status, DreamingBackgroundRunStatus.reflectionPending);
    expect(second.status, DreamingBackgroundRunStatus.completed);
    expect(second.digest?.dayKey, '2026-07-14');
    expect(second.reflection?.sourceDigestDayKey, '2026-07-14');
    expect(reflectionService.attemptCount, 2);
    expect(completeNotifications, 1);
    expect(await db.dreamingDao.getJobsByDay('2026-07-14'), hasLength(1));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNull);
    expect(prefs.getString(kAssistantReflectionStorageKey), isNotNull);
  });

  test(
    'background retry rehydrates sqlite digest before completing Reflection',
    () async {
      final now = DateTime(2026, 7, 14, 22, 30);
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
            title: 'SQLite 恢复',
            messageCount: 2,
            userMessageCount: 1,
            assistantMessageCount: 1,
            highlights: const ['从 SQLite 恢复 Dreaming 后继续 Reflection。'],
            firstMessageAt: now.subtract(const Duration(minutes: 1)),
            lastMessageAt: now,
          ),
        ],
        memoryCandidates: const [],
        keywords: const ['恢复'],
        elapsedMs: 1,
      );
      SharedPreferences.setMockInitialValues({
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 22,
          'minute': 0,
        }),
        kAssistantReflectionPendingStorageKey: jsonEncode({
          'sourceDigestDayKey': digest.dayKey,
          'updatedAt': now.toIso8601String(),
          'attemptCount': 1,
        }),
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.dreamingDao.createJob(
        id: 'dreaming-auto-${digest.dayKey}',
        dayKey: digest.dayKey,
        scheduledFor: now.millisecondsSinceEpoch,
        trigger: 'android_background',
      );
      await db.dreamingDao.markJobCompleted('dreaming-auto-${digest.dayKey}');
      await db.dreamingDao.upsertReport(
        id: 'dreaming-report-${digest.dayKey}',
        dayKey: digest.dayKey,
        jobId: 'dreaming-auto-${digest.dayKey}',
        generatedAt: now.millisecondsSinceEpoch,
        markdown: digest.toMarkdown(),
        digestJson: jsonEncode(digest.toJson()),
        sessionCount: digest.sessionCount,
        originalMessageCount: digest.originalMessageCount,
        totalOriginalMessageCount: digest.totalOriginalMessageCount,
        memoryCandidateCount: digest.memoryCandidates.length,
      );
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      var completeNotifications = 0;
      final result = await runDreamingBackgroundTask(
        container: container,
        now: now,
        notifyComplete:
            ({required digest, required profileProposalCount}) async {
              completeNotifications += 1;
            },
        notifyFailed: ({required dayKey}) async {},
      );

      expect(result.status, DreamingBackgroundRunStatus.completed);
      expect(result.digest?.dayKey, digest.dayKey);
      expect(result.reflection?.sourceDigestDayKey, digest.dayKey);
      expect(completeNotifications, 1);
      expect(container.read(dreamingDigestProvider)?.dayKey, digest.dayKey);
      expect(container.read(dreamingDigestHistoryProvider), hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kDreamingDigestStorageKey),
        contains(digest.dayKey),
      );
      expect(
        prefs.getString(kDreamingDigestHistoryStorageKey),
        contains(digest.dayKey),
      );
      expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNull);
    },
  );

  test(
    'Android background retry stays pending when Reflection still fails',
    () async {
      SharedPreferences.setMockInitialValues({
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 22,
          'minute': 0,
        }),
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final reflectionService = _AlwaysFailingReflectionService();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          reflectionServiceProvider.overrideWithValue(reflectionService),
        ],
      );
      addTearDown(container.dispose);

      final now = DateTime(2026, 7, 14, 22, 30);
      await db.sessionDao.createSession(id: 'reflection-still-pending');
      await db.messageDao.insertMessage(
        id: 'reflection-still-pending-message',
        sessionId: 'reflection-still-pending',
        role: 'user',
        content: '反思连续失败时，移动端后台任务必须继续按失败退避重试。',
      );
      await db.customStatement(
        'UPDATE messages SET created_at = ${now.millisecondsSinceEpoch}',
      );

      final first = await runDreamingBackgroundTask(
        container: container,
        now: now,
        notifyComplete:
            ({required digest, required profileProposalCount}) async {},
        notifyFailed: ({required dayKey}) async {},
      );
      final second = await runDreamingBackgroundTask(
        container: container,
        now: now.add(const Duration(minutes: 15)),
        notifyComplete:
            ({required digest, required profileProposalCount}) async {},
        notifyFailed: ({required dayKey}) async {},
      );

      expect(first.status, DreamingBackgroundRunStatus.reflectionPending);
      expect(second.status, DreamingBackgroundRunStatus.reflectionPending);
      expect(second.digest, isNull);
      expect(reflectionService.attemptCount, 2);
      expect(await db.dreamingDao.getJobsByDay('2026-07-14'), hasLength(1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNotNull);
      expect(prefs.getString(kAssistantReflectionStorageKey), isNull);
    },
  );

  test(
    'completion notification failure does not invalidate durable background result',
    () async {
      SharedPreferences.setMockInitialValues({
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 22,
          'minute': 0,
        }),
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final now = DateTime(2026, 7, 14, 22, 30);
      await db.sessionDao.createSession(id: 'notification-failure-session');
      await db.messageDao.insertMessage(
        id: 'notification-failure-message',
        sessionId: 'notification-failure-session',
        role: 'user',
        content: '即使系统通知失败，已经生成的 Dreaming 和 Reflection 也必须保持完成。',
      );
      await db.customStatement(
        'UPDATE messages SET created_at = ${now.millisecondsSinceEpoch}',
      );

      final result = await runDreamingBackgroundTask(
        container: container,
        now: now,
        notifyComplete: ({required digest, required profileProposalCount}) {
          throw StateError('simulated completion notification failure');
        },
        notifyFailed: ({required dayKey}) async {},
      );

      expect(result.status, DreamingBackgroundRunStatus.completed);
      expect(result.digest?.dayKey, '2026-07-14');
      expect(result.reflection?.sourceDigestDayKey, '2026-07-14');
      final jobs = await db.dreamingDao.getJobsByDay('2026-07-14');
      expect(jobs, hasLength(1));
      expect(jobs.single.status, 'completed');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
      expect(prefs.getString(kAssistantReflectionStorageKey), isNotNull);
      expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNull);
    },
  );

  test(
    'failure notification failure preserves failed background result',
    () async {
      SharedPreferences.setMockInitialValues({
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 22,
          'minute': 0,
        }),
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dreamingServiceProvider.overrideWithValue(
            _AlwaysFailingDreamingService(db: db),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await runDreamingBackgroundTask(
        container: container,
        now: DateTime(2026, 7, 14, 22, 30),
        notifyComplete:
            ({required digest, required profileProposalCount}) async {},
        notifyFailed: ({required dayKey}) {
          throw StateError('simulated failure notification failure');
        },
      );

      expect(result.status, DreamingBackgroundRunStatus.failed);
      final jobs = await db.dreamingDao.getJobsByDay('2026-07-14');
      expect(jobs, hasLength(1));
      expect(jobs.single.status, 'failed');
    },
  );
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
    if (attemptCount == 1) throw StateError('simulated Reflection failure');
    return super.buildDailyReflection(
      digest: digest,
      profile: profile,
      pendingProfileProposalCount: pendingProfileProposalCount,
    );
  }
}

class _AlwaysFailingReflectionService extends ReflectionService {
  int attemptCount = 0;

  @override
  ReflectionReport buildDailyReflection({
    required DreamingDigest digest,
    UserProfile? profile,
    int pendingProfileProposalCount = 0,
  }) {
    attemptCount += 1;
    throw StateError('simulated persistent Reflection failure');
  }
}

class _AlwaysFailingDreamingService extends DreamingService {
  _AlwaysFailingDreamingService({required AppDatabase db})
    : super(sessionDao: db.sessionDao, messageDao: db.messageDao);

  @override
  Future<DreamingDigest> runDailyDigest({
    DateTime? day,
    int maxMessages = 5000,
    int maxMemoryCandidates = 40,
  }) async {
    throw StateError('simulated persistent Dreaming failure');
  }
}
