import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/shared/providers/key_point_memory_provider.dart';
import 'package:ai_chat_app/shared/providers/user_profile_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('UserProfileNotifier persists local profile', () async {
    final now = DateTime.utc(2026, 6, 27);
    final notifier = UserProfileNotifier();
    await notifier.ready;

    final profile = UserProfile(
      updatedAt: now,
      sourceCount: 1,
      preferences: const ['我喜欢中文回复'],
      goals: const ['目标是移动端优先'],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const ['偏好结构化'],
      scheduleSignals: const [],
      keywords: const ['simichat'],
    );

    await notifier.save(profile);
    expect(notifier.state?.hasContent, isTrue);

    final reloaded = UserProfileNotifier();
    await reloaded.ready;
    expect(reloaded.state?.preferences.single, '我喜欢中文回复');
    expect(reloaded.state?.keywords.single, 'simichat');
  });

  test('UserProfileNotifier clears local profile', () async {
    final notifier = UserProfileNotifier();
    await notifier.ready;
    await notifier.save(
      UserProfile.empty(updatedAt: DateTime.utc(2026, 6, 27)),
    );

    await notifier.clear();

    expect(notifier.state, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kUserProfileStorageKey), isNull);
  });

  test(
    'UserProfileControlsNotifier persists edits and hidden signals',
    () async {
      final notifier = UserProfileControlsNotifier();
      await notifier.ready;

      expect(await notifier.hideSignal('我喜欢英文回复'), isTrue);
      expect(await notifier.editSignal('我喜欢中文回复', '我喜欢中文和 Markdown'), isTrue);
      expect(
        await notifier.editSignal('我的工作是开发者', 'token: TEST-SECRET-123456'),
        isFalse,
      );

      final reloaded = UserProfileControlsNotifier();
      await reloaded.ready;

      expect(reloaded.state.hiddenSignals, contains('我喜欢英文回复'));
      expect(reloaded.state.editedSignals['我喜欢中文回复'], '我喜欢中文和 Markdown');
      expect(
        reloaded.state.editedSignals.values.join('\n'),
        isNot(contains('token')),
      );

      await reloaded.clearControls();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kUserProfileControlsStorageKey), isNull);
    },
  );

  testWidgets(
    'profile change proposals can be proposed accepted and rejected',
    (tester) async {
      final now = DateTime.utc(2026, 6, 27);
      SharedPreferences.setMockInitialValues({
        kKeyPointMemoryStorageKey: encodeKeyPointMemoryItems([
          _memory('preference', '我喜欢待确认画像变更', now),
        ]),
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

      final proposal = await proposeUserProfileChanges(
        capturedRef,
        now: now,
        reason: 'profile_proposal',
      );

      expect(proposal, isNotNull);
      expect(capturedRef.read(userProfileProvider), isNull);
      expect(
        capturedRef.read(userProfileChangeProposalsProvider),
        hasLength(1),
      );

      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kUserProfileChangeProposalsStorageKey), isNotNull);

      final accepted = await acceptUserProfileProposal(
        capturedRef,
        proposal!.id,
        now: now.add(const Duration(minutes: 1)),
      );

      expect(accepted, isNotNull);
      expect(accepted!.preferences.single, contains('待确认画像变更'));
      expect(capturedRef.read(userProfileChangeProposalsProvider), isEmpty);
      expect(
        capturedRef.read(userProfileHistoryProvider).first.summary,
        contains('采纳画像变更'),
      );

      final manualProposal = UserProfileChangeProposal(
        id: 'reject-me',
        createdAt: now.add(const Duration(minutes: 2)),
        reason: 'profile_proposal',
        baseProfile: accepted,
        candidateProfile: accepted.copyWith(goals: const ['目标是审阅后再更新画像']),
      );
      await capturedRef
          .read(userProfileChangeProposalsProvider.notifier)
          .add(manualProposal);
      expect(
        capturedRef.read(userProfileChangeProposalsProvider),
        hasLength(1),
      );

      expect(await rejectUserProfileProposal(capturedRef, 'reject-me'), isTrue);
      expect(capturedRef.read(userProfileChangeProposalsProvider), isEmpty);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kUserProfileChangeProposalsStorageKey), isNull);
    },
  );

  testWidgets('profile change proposal items can be accepted and rejected', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 6, 27);
    final current = UserProfile(
      updatedAt: now,
      sourceCount: 1,
      preferences: const ['我喜欢当前偏好'],
      goals: const [],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const [],
    );
    final candidate = current.copyWith(
      sourceCount: 2,
      preferences: const [],
      goals: const ['目标是逐项确认画像变更'],
    );
    final proposal = UserProfileChangeProposal(
      id: 'proposal-items',
      createdAt: now,
      reason: 'profile_proposal',
      baseProfile: current,
      candidateProfile: candidate,
    );
    SharedPreferences.setMockInitialValues({
      kUserProfileStorageKey: encodeUserProfile(current),
      kUserProfileChangeProposalsStorageKey: encodeUserProfileChangeProposals([
        proposal,
      ]),
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

    final addedGoal = proposal.diff.items.singleWhere(
      (item) =>
          item.sectionTitle == '目标' && item.type == UserProfileChangeType.added,
    );
    final removedPreference = proposal.diff.items.singleWhere(
      (item) =>
          item.sectionTitle == '偏好' &&
          item.type == UserProfileChangeType.removed,
    );

    final accepted = await acceptUserProfileProposalItem(
      capturedRef,
      proposalId: proposal.id,
      item: addedGoal,
      now: now.add(const Duration(minutes: 1)),
    );

    expect(accepted, isNotNull);
    expect(accepted!.goals, contains('目标是逐项确认画像变更'));
    expect(accepted.preferences, contains('我喜欢当前偏好'));
    expect(accepted.sourceCount, 2);
    expect(
      capturedRef.read(userProfileHistoryProvider).first.summary,
      contains('采纳单条画像变更'),
    );

    var proposals = capturedRef.read(userProfileChangeProposalsProvider);
    expect(proposals, hasLength(1));
    expect(proposals.single.diff.addedCount, 0);
    expect(proposals.single.diff.removedCount, 1);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kUserProfileChangeProposalsStorageKey), isNotNull);

    final rejected = await rejectUserProfileProposalItem(
      capturedRef,
      proposalId: proposal.id,
      item: removedPreference,
    );

    expect(rejected, isTrue);
    expect(
      capturedRef.read(userProfileProvider)!.preferences,
      contains('我喜欢当前偏好'),
    );
    expect(
      capturedRef.read(userProfileProvider)!.goals,
      contains('目标是逐项确认画像变更'),
    );
    expect(capturedRef.read(userProfileChangeProposalsProvider), isEmpty);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kUserProfileChangeProposalsStorageKey), isNull);
  });

  testWidgets('restoreUserProfileFromHistory restores snapshot locally', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 6, 27);
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

    final current = UserProfile(
      updatedAt: now,
      sourceCount: 1,
      preferences: const ['我喜欢当前画像'],
      goals: const [],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const [],
    );
    final historical = current.copyWith(
      preferences: const ['我喜欢历史画像'],
      keywords: const ['history'],
    );

    await capturedRef.read(userProfileProvider.notifier).save(current);
    await capturedRef
        .read(userProfileHistoryProvider.notifier)
        .record(historical, reason: 'manual_rebuild');

    final historyId = capturedRef.read(userProfileHistoryProvider).single.id;
    final restored = await restoreUserProfileFromHistory(
      capturedRef,
      historyId,
      now: now.add(const Duration(hours: 1)),
    );

    expect(restored, isNotNull);
    expect(restored!.preferences.single, '我喜欢历史画像');
    expect(restored.keywords, contains('history'));
    expect(restored.updatedAt, now.add(const Duration(hours: 1)));
    expect(
      capturedRef.read(userProfileProvider)!.preferences.single,
      '我喜欢历史画像',
    );
    expect(
      capturedRef.read(userProfileHistoryProvider).first.summary,
      contains('恢复历史版本'),
    );
  });

  test('UserProfileHistoryNotifier records bounded local history', () async {
    final notifier = UserProfileHistoryNotifier();
    await notifier.ready;
    final now = DateTime.utc(2026, 6, 27);

    for (var i = 0; i < 25; i++) {
      await notifier.record(
        UserProfile(
          updatedAt: now.add(Duration(minutes: i)),
          sourceCount: i,
          preferences: ['偏好 $i'],
          goals: const [],
          tasks: const [],
          profileFacts: const [],
          styleSignals: const [],
          scheduleSignals: const [],
          keywords: const [],
        ),
        reason: 'manual_rebuild',
      );
    }

    expect(notifier.state, hasLength(20));
    expect(notifier.state.first.reason, 'manual_rebuild');

    final reloaded = UserProfileHistoryNotifier();
    await reloaded.ready;
    expect(reloaded.state, hasLength(20));
    expect(reloaded.state.first.summary, contains('手动重建'));

    await reloaded.clearHistory();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kUserProfileHistoryStorageKey), isNull);
  });
}

KeyPointMemoryItem _memory(String category, String content, DateTime now) {
  return KeyPointMemoryItem(
    id: makeMemoryItemId('s1', content),
    sessionId: 's1',
    sourceMessageId: 'm-${content.hashCode}',
    category: category,
    content: content,
    keywords: extractMemoryKeywords(content),
    confidence: 0.8,
    createdAt: now,
    updatedAt: now,
  );
}
