import 'dart:convert';

import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/shared/providers/dreaming_provider.dart';
import 'package:ai_chat_app/shared/providers/reflection_provider.dart';
import 'package:ai_chat_app/shared/providers/user_profile_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
}

ReflectionReport _report(String dayKey, {String action = '继续保持'}) {
  final date = DateTime.parse('${dayKey}T22:00:00Z');
  return ReflectionReport(
    dayKey: dayKey,
    generatedAt: date,
    sourceDigestDayKey: dayKey,
    sessionCount: 1,
    originalMessageCount: 2,
    userMessageCount: 1,
    assistantMessageCount: 1,
    pendingProfileProposalCount: 0,
    insights: const [ReflectionInsight(category: '回应质量', text: '轮次均衡')],
    actionItems: [action],
  );
}
