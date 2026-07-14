import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/dreaming_provider.dart';
import 'package:ai_chat_app/shared/providers/reflection_provider.dart';
import 'package:ai_chat_app/shared/providers/user_profile_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetAssistantReflectionRetryStateForTesting();
  });

  tearDown(resetAssistantReflectionRetryStateForTesting);

  test(
    'AssistantReflectionNotifier persists and clears local report',
    () async {
      final now = DateTime.utc(2026, 7, 6, 22);
      final notifier = AssistantReflectionNotifier();
      await notifier.ready;

      final report = ReflectionReport(
        dayKey: '2026-07-06',
        generatedAt: now,
        sourceDigestDayKey: '2026-07-06',
        sessionCount: 1,
        originalMessageCount: 2,
        userMessageCount: 1,
        assistantMessageCount: 1,
        pendingProfileProposalCount: 0,
        insights: const [ReflectionInsight(category: '回应质量', text: '轮次均衡')],
        actionItems: const ['继续保持'],
      );

      await notifier.save(report);
      expect(notifier.state?.hasContent, isTrue);

      final reloaded = AssistantReflectionNotifier();
      await reloaded.ready;
      expect(reloaded.state?.insights.single.category, '回应质量');

      await reloaded.clear();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kAssistantReflectionStorageKey), isNull);
    },
  );

  test(
    'AssistantReflectionPromptEnabledNotifier persists local switch',
    () async {
      final notifier = AssistantReflectionPromptEnabledNotifier();
      await notifier.ready;
      expect(notifier.state, isTrue);

      await notifier.setEnabled(false);
      expect(notifier.state, isFalse);

      final reloaded = AssistantReflectionPromptEnabledNotifier();
      await reloaded.ready;
      expect(reloaded.state, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(kAssistantReflectionPromptEnabledStorageKey),
        isFalse,
      );
    },
  );

  test(
    'AssistantReflectionModelEnabledNotifier defaults off and persists',
    () async {
      final notifier = AssistantReflectionModelEnabledNotifier();
      await notifier.ready;
      expect(notifier.state, isFalse);

      await notifier.setEnabled(true);
      expect(notifier.state, isTrue);

      final reloaded = AssistantReflectionModelEnabledNotifier();
      await reloaded.ready;
      expect(reloaded.state, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAssistantReflectionModelEnabledStorageKey), isTrue);
    },
  );

  test(
    'AssistantReflectionPendingNotifier persists attempts and cleans invalid data',
    () async {
      SharedPreferences.setMockInitialValues({
        kAssistantReflectionPendingStorageKey: '{"sourceDigestDayKey":"bad"}',
      });
      var notifier = AssistantReflectionPendingNotifier();
      await notifier.ready;
      var prefs = await SharedPreferences.getInstance();
      expect(notifier.state, isNull);
      expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNull);

      await notifier.markPending('2026-07-06');
      await notifier.markPending('2026-07-06');
      expect(notifier.state?.attemptCount, 2);

      notifier = AssistantReflectionPendingNotifier();
      await notifier.ready;
      expect(notifier.state?.sourceDigestDayKey, '2026-07-06');
      expect(notifier.state?.attemptCount, 2);

      await notifier.clear();
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNull);
    },
  );

  test(
    'AssistantReflectionHistoryNotifier records bounded local history',
    () async {
      final notifier = AssistantReflectionHistoryNotifier();
      await notifier.ready;

      await notifier.record(_report('2026-07-01'));
      await notifier.record(_report('2026-07-01', action: '替换旧报告'));
      expect(notifier.state, hasLength(1));
      expect(notifier.state.single.actionItems.single, '替换旧报告');

      for (var i = 2; i <= 22; i++) {
        await notifier.record(
          _report('2026-07-${i.toString().padLeft(2, '0')}'),
        );
      }

      expect(notifier.state, hasLength(20));
      expect(notifier.state.first.dayKey, '2026-07-22');
      expect(notifier.state.last.dayKey, '2026-07-03');

      final reloaded = AssistantReflectionHistoryNotifier();
      await reloaded.ready;
      expect(reloaded.state, hasLength(20));

      await reloaded.clear();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kAssistantReflectionHistoryStorageKey), isNull);
    },
  );

  test(
    'AssistantReflectionHistoryNotifier removes one report by day and source',
    () async {
      final notifier = AssistantReflectionHistoryNotifier();
      await notifier.ready;

      await notifier.record(
        _report('2026-07-06', sourceDigestDayKey: '2026-07-05'),
      );
      await notifier.record(
        _report('2026-07-06', sourceDigestDayKey: '2026-07-06'),
      );
      await notifier.record(_report('2026-07-05'));
      await notifier.removeReport(
        dayKey: '2026-07-06',
        sourceDigestDayKey: '2026-07-06',
      );

      expect(
        notifier.state.map(
          (item) => '${item.dayKey}/${item.sourceDigestDayKey}',
        ),
        containsAll(['2026-07-06/2026-07-05', '2026-07-05/2026-07-05']),
      );

      final reloaded = AssistantReflectionHistoryNotifier();
      await reloaded.ready;
      expect(
        reloaded.state.map(
          (item) => '${item.dayKey}/${item.sourceDigestDayKey}',
        ),
        containsAll(['2026-07-06/2026-07-05', '2026-07-05/2026-07-05']),
      );
    },
  );

  testWidgets('runAssistantReflection uses latest dreaming and profile', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 6, 22);
    final digest = DreamingDigest(
      day: now,
      generatedAt: now,
      sessionCount: 1,
      originalMessageCount: 4,
      userMessageCount: 2,
      assistantMessageCount: 2,
      sessions: [
        DreamingSessionDigest(
          sessionId: 's1',
          title: '反思',
          messageCount: 4,
          userMessageCount: 2,
          assistantMessageCount: 2,
          highlights: const ['我喜欢中文回复'],
          firstMessageAt: now,
          lastMessageAt: now,
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['中文回复'],
      elapsedMs: 3,
    );
    final profile = UserProfile(
      updatedAt: now,
      sourceCount: 1,
      preferences: const ['我喜欢中文回复'],
      goals: const [],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const ['中文回复'],
    );
    SharedPreferences.setMockInitialValues({
      kDreamingDigestStorageKey: jsonEncode(digest.toJson()),
      kUserProfileStorageKey: encodeUserProfile(profile),
    });

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reflectionServiceProvider.overrideWithValue(
            ReflectionService(now: () => now),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final report = await runAssistantReflection(
      capturedRef,
      pendingProfileProposalCount: 1,
    );

    expect(report, isNotNull);
    expect(report!.sourceDigestDayKey, '2026-07-06');
    expect(report.pendingProfileProposalCount, 1);
    expect(capturedRef.read(assistantReflectionProvider), isNotNull);
    expect(capturedRef.read(assistantReflectionHistoryProvider), hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAssistantReflectionStorageKey), isNotNull);
    expect(prefs.getString(kAssistantReflectionHistoryStorageKey), isNotNull);
  });

  testWidgets('reflection failure keeps pending marker and retry clears it', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 6, 22);
    final digest = _digest(now);
    SharedPreferences.setMockInitialValues({
      kDreamingDigestStorageKey: jsonEncode(digest.toJson()),
    });
    final service = _FailingOnceReflectionService(now: () => now);

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reflectionServiceProvider.overrideWithValue(service)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await expectLater(
      runAssistantReflection(capturedRef, digest: digest),
      throwsStateError,
    );
    final pending = capturedRef.read(assistantReflectionPendingProvider);
    expect(pending?.sourceDigestDayKey, digest.dayKey);
    expect(pending?.attemptCount, 1);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNotNull);

    final report = await retryPendingAssistantReflection(capturedRef);

    expect(report?.sourceDigestDayKey, digest.dayKey);
    expect(capturedRef.read(assistantReflectionPendingProvider), isNull);
    expect(capturedRef.read(assistantReflectionProvider), isNotNull);
    expect(capturedRef.read(assistantReflectionHistoryProvider), hasLength(1));
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAssistantReflectionPendingStorageKey), isNull);
  });

  testWidgets('model reflection enhances the local report when enabled', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 14, 22);
    final digest = _digest(now);
    SharedPreferences.setMockInitialValues({
      kDreamingDigestStorageKey: jsonEncode(digest.toJson()),
      kAssistantReflectionModelEnabledStorageKey: true,
    });

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reflectionServiceProvider.overrideWithValue(
            ReflectionService(now: () => now),
          ),
          assistantReflectionModelEnhancerProvider.overrideWithValue(
            _successfulModelEnhancer,
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final report = await runAssistantReflection(capturedRef, digest: digest);

    expect(report?.generationMode, kReflectionGenerationModeModel);
    expect(capturedRef.read(assistantReflectionPendingProvider), isNull);
    expect(capturedRef.read(assistantReflectionHistoryProvider), hasLength(1));
  });

  testWidgets('model reflection failure safely falls back to local report', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 14, 22);
    final digest = _digest(now);
    SharedPreferences.setMockInitialValues({
      kDreamingDigestStorageKey: jsonEncode(digest.toJson()),
      kAssistantReflectionModelEnabledStorageKey: true,
    });

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reflectionServiceProvider.overrideWithValue(
            ReflectionService(now: () => now),
          ),
          assistantReflectionModelEnhancerProvider.overrideWithValue(
            _failingModelEnhancer,
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final report = await runAssistantReflection(capturedRef, digest: digest);

    expect(report?.generationMode, kReflectionGenerationModeModelFallback);
    expect(capturedRef.read(assistantReflectionPendingProvider), isNull);
    final history = capturedRef.read(assistantReflectionHistoryProvider);
    expect(history, hasLength(1));
    expect(
      history.single.generationMode,
      kReflectionGenerationModeModelFallback,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      decodeReflectionReport(
        prefs.getString(kAssistantReflectionStorageKey),
      )?.generationMode,
      kReflectionGenerationModeModelFallback,
    );
  });

  testWidgets('pending reflection retry restores its dreaming report by day', (
    tester,
  ) async {
    final pendingDay = DateTime.utc(2026, 7, 5, 22);
    final latestDay = DateTime.utc(2026, 7, 6, 22);
    final pendingDigest = _digest(pendingDay);
    final latestDigest = _digest(latestDay);
    SharedPreferences.setMockInitialValues({
      kDreamingDigestStorageKey: jsonEncode(latestDigest.toJson()),
      kAssistantReflectionPendingStorageKey: jsonEncode({
        'sourceDigestDayKey': pendingDigest.dayKey,
        'updatedAt': pendingDay.toIso8601String(),
        'attemptCount': 1,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.dreamingDao.upsertReport(
      id: 'dreaming-report-${pendingDigest.dayKey}',
      dayKey: pendingDigest.dayKey,
      generatedAt: pendingDigest.generatedAt.millisecondsSinceEpoch,
      markdown: pendingDigest.toMarkdown(),
      digestJson: jsonEncode(pendingDigest.toJson()),
      sessionCount: pendingDigest.sessionCount,
      originalMessageCount: pendingDigest.originalMessageCount,
      totalOriginalMessageCount: pendingDigest.totalOriginalMessageCount,
      memoryCandidateCount: pendingDigest.memoryCandidates.length,
    );

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final report = await retryPendingAssistantReflection(capturedRef);

    expect(report?.sourceDigestDayKey, pendingDigest.dayKey);
    expect(report?.sourceDigestDayKey, isNot(latestDigest.dayKey));
    expect(capturedRef.read(assistantReflectionPendingProvider), isNull);
    expect(
      capturedRef.read(dreamingDigestProvider)?.dayKey,
      latestDigest.dayKey,
    );
    expect(
      capturedRef
          .read(dreamingDigestHistoryProvider)
          .map((digest) => digest.dayKey),
      contains(pendingDigest.dayKey),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(kDreamingDigestHistoryStorageKey),
      contains(pendingDigest.dayKey),
    );
  });

  testWidgets('pending reflection retry falls back to dreaming history', (
    tester,
  ) async {
    final pendingDigest = _digest(DateTime.utc(2026, 7, 5, 22));
    final latestDigest = _digest(DateTime.utc(2026, 7, 6, 22));
    SharedPreferences.setMockInitialValues({
      kDreamingDigestStorageKey: jsonEncode(latestDigest.toJson()),
      kDreamingDigestHistoryStorageKey: jsonEncode([
        latestDigest.toJson(),
        pendingDigest.toJson(),
      ]),
      kAssistantReflectionPendingStorageKey: jsonEncode({
        'sourceDigestDayKey': pendingDigest.dayKey,
        'updatedAt': pendingDigest.generatedAt.toIso8601String(),
        'attemptCount': 1,
      }),
    });

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final report = await retryPendingAssistantReflection(capturedRef);

    expect(report?.sourceDigestDayKey, pendingDigest.dayKey);
    expect(capturedRef.read(assistantReflectionPendingProvider), isNull);
  });

  testWidgets(
    'pending reflection retry publishes sqlite digest when current is missing',
    (tester) async {
      final pendingDigest = _digest(DateTime.utc(2026, 7, 5, 22));
      SharedPreferences.setMockInitialValues({
        kAssistantReflectionPendingStorageKey: jsonEncode({
          'sourceDigestDayKey': pendingDigest.dayKey,
          'updatedAt': pendingDigest.generatedAt.toIso8601String(),
          'attemptCount': 1,
        }),
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.dreamingDao.upsertReport(
        id: 'dreaming-report-${pendingDigest.dayKey}',
        dayKey: pendingDigest.dayKey,
        generatedAt: pendingDigest.generatedAt.millisecondsSinceEpoch,
        markdown: pendingDigest.toMarkdown(),
        digestJson: jsonEncode(pendingDigest.toJson()),
        sessionCount: pendingDigest.sessionCount,
        originalMessageCount: pendingDigest.originalMessageCount,
        totalOriginalMessageCount: pendingDigest.totalOriginalMessageCount,
        memoryCandidateCount: pendingDigest.memoryCandidates.length,
      );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final report = await retryPendingAssistantReflection(capturedRef);

      expect(report?.sourceDigestDayKey, pendingDigest.dayKey);
      expect(
        capturedRef.read(dreamingDigestProvider)?.dayKey,
        pendingDigest.dayKey,
      );
      expect(
        capturedRef
            .read(dreamingDigestHistoryProvider)
            .map((digest) => digest.dayKey),
        contains(pendingDigest.dayKey),
      );
      expect(capturedRef.read(assistantReflectionPendingProvider), isNull);
    },
  );
}

DreamingDigest _digest(DateTime now) {
  return DreamingDigest(
    day: now,
    generatedAt: now,
    sessionCount: 1,
    originalMessageCount: 2,
    userMessageCount: 1,
    assistantMessageCount: 1,
    sessions: [
      DreamingSessionDigest(
        sessionId: 's1',
        title: '反思恢复',
        messageCount: 2,
        userMessageCount: 1,
        assistantMessageCount: 1,
        highlights: const ['继续推进反思恢复'],
        firstMessageAt: now.subtract(const Duration(minutes: 1)),
        lastMessageAt: now,
      ),
    ],
    memoryCandidates: const [],
    keywords: const ['恢复'],
    elapsedMs: 1,
  );
}

ReflectionReport _report(
  String dayKey, {
  String action = '继续保持',
  String? sourceDigestDayKey,
}) {
  final date = DateTime.parse('${dayKey}T22:00:00Z');
  return ReflectionReport(
    dayKey: dayKey,
    generatedAt: date,
    sourceDigestDayKey: sourceDigestDayKey ?? dayKey,
    sessionCount: 1,
    originalMessageCount: 2,
    userMessageCount: 1,
    assistantMessageCount: 1,
    pendingProfileProposalCount: 0,
    insights: const [ReflectionInsight(category: '回应质量', text: '轮次均衡')],
    actionItems: [action],
  );
}

class _FailingOnceReflectionService extends ReflectionService {
  _FailingOnceReflectionService({required DateTime Function() now})
    : super(now: now);

  bool _failed = false;

  @override
  ReflectionReport buildDailyReflection({
    required DreamingDigest digest,
    UserProfile? profile,
    int pendingProfileProposalCount = 0,
  }) {
    if (!_failed) {
      _failed = true;
      throw StateError('simulated reflection failure');
    }
    return super.buildDailyReflection(
      digest: digest,
      profile: profile,
      pendingProfileProposalCount: pendingProfileProposalCount,
    );
  }
}

Future<ReflectionReport> _successfulModelEnhancer({
  required DreamingDigest digest,
  required ReflectionReport localReport,
}) async {
  return ReflectionReport(
    dayKey: localReport.dayKey,
    generatedAt: localReport.generatedAt,
    sourceDigestDayKey: localReport.sourceDigestDayKey,
    sessionCount: localReport.sessionCount,
    originalMessageCount: localReport.originalMessageCount,
    userMessageCount: localReport.userMessageCount,
    assistantMessageCount: localReport.assistantMessageCount,
    pendingProfileProposalCount: localReport.pendingProfileProposalCount,
    sourceDigestIsTruncated: localReport.sourceDigestIsTruncated,
    sourceDigestMessageLimit: localReport.sourceDigestMessageLimit,
    sourceDigestTotalOriginalMessageCount:
        localReport.sourceDigestTotalOriginalMessageCount,
    generationMode: kReflectionGenerationModeModel,
    insights: const [ReflectionInsight(category: '模型增强', text: '模型已补充反思。')],
    actionItems: const ['继续验证模型反思。'],
  );
}

Future<ReflectionReport> _failingModelEnhancer({
  required DreamingDigest digest,
  required ReflectionReport localReport,
}) {
  throw StateError('model unavailable');
}
