import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user profile builder extracts local profile dimensions', () {
    final now = DateTime.utc(2026, 6, 27, 22);
    final profile = const UserProfileBuilder().build(
      keyPoints: [
        _memory('preference', '我喜欢中文回复和结构化总结', now),
        _memory('goal', '我的目标是把 SimiChat 做成移动端优先的 AI 伙伴', now),
        _memory('task', 'todo: 下周提醒我复盘本地记忆系统', now),
        _memory('profile', '我的工作是独立开发 AI 产品', now),
        _memory('preference', '我的作息是晚上 11 点睡觉，早上 7 点起床', now),
      ],
      digest: DreamingDigest(
        day: now,
        generatedAt: now,
        sessionCount: 1,
        originalMessageCount: 5,
        userMessageCount: 5,
        assistantMessageCount: 0,
        sessions: const [],
        memoryCandidates: [_memory('preference', '我偏好详细但不要啰嗦的回答风格', now)],
        keywords: const ['SimiChat', '数字孪生'],
        elapsedMs: 8,
      ),
      now: now,
    );

    expect(profile.hasContent, isTrue);
    expect(profile.sourceCount, 6);
    expect(profile.preferences.join('\n'), contains('中文回复'));
    expect(profile.goals.join('\n'), contains('移动端优先'));
    expect(profile.tasks.join('\n'), contains('复盘本地记忆系统'));
    expect(profile.profileFacts.join('\n'), contains('独立开发'));
    expect(profile.styleSignals.join('\n'), contains('结构化'));
    expect(profile.scheduleSignals.join('\n'), contains('晚上 11 点'));
    expect(profile.keywords, contains('simichat'));
    expect(profile.keywords, contains('数字孪生'));
    expect(profile.conflicts, isEmpty);
    expect(profile.digestDayKey, '2026-06-27');
  });

  test('user profile builder detects preference conflicts', () {
    final now = DateTime.utc(2026, 6, 27);
    final profile = const UserProfileBuilder().build(
      keyPoints: [
        _memory('preference', '我喜欢中文回复和详细解释', now),
        _memory('preference', '我不喜欢中文回复太啰嗦', now),
      ],
      now: now,
    );

    expect(profile.conflicts, isNotEmpty);
    expect(profile.conflicts.single, contains('可能冲突'));
    expect(profile.toMarkdown(), contains('冲突提示'));
  });

  test('user profile builder skips secret-like content', () {
    final now = DateTime.utc(2026, 6, 27);
    final profile = const UserProfileBuilder().build(
      keyPoints: [
        _memory(
          'preference',
          '我的 API Key 是 ${'sk-test-'}secret-1234567890，请记住它',
          now,
        ),
        _memory('goal', '我的目标是保持本地隐私', now),
      ],
      now: now,
    );

    expect(profile.sourceCount, 1);
    expect(profile.toMarkdown(), isNot(contains('secret-1234567890')));
    expect(profile.toMarkdown(), isNot(contains('API Key')));
    expect(profile.goals.single, contains('本地隐私'));
  });

  test('user profile controls edit and hide local signals', () {
    final now = DateTime.utc(2026, 6, 27);
    final controls = const UserProfileControls()
        .editSignal('我喜欢中文回复', '我喜欢中文回复，并且偏好简洁结构化')
        .hideSignal('我的目标是保持本地隐私')
        .editSignal('我的工作是开发者', '我的 API Key 是 TEST-SECRET-123456');

    final profile = const UserProfileBuilder().build(
      keyPoints: [
        _memory('preference', '我喜欢中文回复', now),
        _memory('goal', '我的目标是保持本地隐私', now),
        _memory('profile', '我的工作是开发者', now),
      ],
      controls: controls,
      now: now,
    );

    final markdown = profile.toMarkdown();
    expect(markdown, contains('偏好简洁结构化'));
    expect(markdown, isNot(contains('我的目标是保持本地隐私')));
    expect(markdown, isNot(contains('TEST-SECRET-123456')));
    expect(markdown, isNot(contains('API Key')));
    expect(profile.sourceCount, 2);
  });

  test('user profile json round trips safely', () {
    final now = DateTime.utc(2026, 6, 27);
    final profile = UserProfile(
      updatedAt: now,
      sourceCount: 2,
      preferences: const ['我喜欢中文回复'],
      goals: const ['目标是移动端优先'],
      tasks: const ['提醒我复盘'],
      profileFacts: const ['我的工作是开发者'],
      styleSignals: const ['偏好结构化'],
      scheduleSignals: const ['晚上整理'],
      keywords: const ['simichat'],
      conflicts: const ['可能冲突：A ↔ B'],
      digestDayKey: '2026-06-27',
    );

    final decoded = decodeUserProfile(encodeUserProfile(profile));

    expect(decoded, isNotNull);
    expect(decoded!.updatedAt, now);
    expect(decoded.preferences, profile.preferences);
    expect(decoded.conflicts.single, contains('可能冲突'));
    expect(decoded.digestDayKey, '2026-06-27');
  });

  test('user profile controls json round trips safely', () {
    final controls = const UserProfileControls()
        .hideSignal('我喜欢英文回复')
        .editSignal('我喜欢中文回复', '我喜欢中文和 Markdown');

    final decoded = decodeUserProfileControls(
      encodeUserProfileControls(controls),
    );

    expect(decoded.hiddenSignals, contains('我喜欢英文回复'));
    expect(decoded.editedSignals['我喜欢中文回复'], '我喜欢中文和 Markdown');
    expect(decoded.applyToSignal('我喜欢英文回复'), isNull);
    expect(decoded.applyToSignal('我喜欢中文回复'), '我喜欢中文和 Markdown');
  });

  test('user profile diff summarizes historical changes', () {
    final now = DateTime.utc(2026, 6, 27);
    final current = UserProfile(
      updatedAt: now,
      sourceCount: 2,
      preferences: const ['我喜欢中文回复', '我喜欢短句总结'],
      goals: const ['目标是移动端优先'],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const ['simichat'],
    );
    final candidate = current.copyWith(
      preferences: const ['我喜欢中文回复', '我喜欢详细解释'],
      goals: const [],
      keywords: const ['simichat', '数字孪生'],
    );

    final diff = diffUserProfiles(current: current, candidate: candidate);

    expect(diff.hasChanges, isTrue);
    expect(diff.addedCount, 2);
    expect(diff.removedCount, 2);
    expect(diff.summary, contains('新增 2'));
    expect(diff.changedSections.first.title, '偏好');
    expect(diff.changedSections.first.added, contains('我喜欢详细解释'));
    expect(diff.changedSections.first.removed, contains('我喜欢短句总结'));
    expect(diff.items.map((item) => item.signedValue), contains('+ 我喜欢详细解释'));

    final accepted = applyUserProfileChangeItem(
      current,
      const UserProfileChangeItem(
        sectionTitle: '偏好',
        type: UserProfileChangeType.added,
        value: '我喜欢详细解释',
      ),
    );
    expect(accepted.preferences, contains('我喜欢详细解释'));

    final discardedCandidate = discardUserProfileChangeItem(
      candidate,
      const UserProfileChangeItem(
        sectionTitle: '偏好',
        type: UserProfileChangeType.added,
        value: '我喜欢详细解释',
      ),
    );
    expect(discardedCandidate.preferences, isNot(contains('我喜欢详细解释')));
  });

  test('user profile change proposal json round trips', () {
    final now = DateTime.utc(2026, 6, 27);
    final base = UserProfile.empty(updatedAt: now);
    final candidate = base.copyWith(preferences: const ['我喜欢中文回复']);
    final proposal = UserProfileChangeProposal(
      id: 'p1',
      createdAt: now,
      reason: 'profile_proposal',
      baseProfile: base,
      candidateProfile: candidate,
    );

    final decoded = decodeUserProfileChangeProposals(
      encodeUserProfileChangeProposals([proposal]),
    );

    expect(decoded, hasLength(1));
    expect(decoded.single.id, 'p1');
    expect(decoded.single.summary, contains('待确认画像变更'));
    expect(decoded.single.diff.addedCount, 1);
    expect(decoded.single.diff.removedCount, 0);
  });

  test('user profile history json round trips', () {
    final now = DateTime.utc(2026, 6, 27);
    final profile = UserProfile.empty(updatedAt: now);
    final history = [
      UserProfileHistoryEntry(
        id: 'h1',
        createdAt: now,
        reason: 'manual_rebuild',
        profile: profile,
      ),
    ];

    final decoded = decodeUserProfileHistory(encodeUserProfileHistory(history));

    expect(decoded, hasLength(1));
    expect(decoded.single.id, 'h1');
    expect(decoded.single.summary, contains('手动重建'));
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
