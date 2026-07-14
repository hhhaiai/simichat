import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model fallback generation mode survives storage and markdown', () {
    final now = DateTime.utc(2026, 7, 14, 22);
    final report = ReflectionReport(
      dayKey: '2026-07-14',
      generatedAt: now,
      sourceDigestDayKey: '2026-07-14',
      sessionCount: 1,
      originalMessageCount: 2,
      userMessageCount: 1,
      assistantMessageCount: 1,
      pendingProfileProposalCount: 0,
      generationMode: kReflectionGenerationModeModelFallback,
      insights: const [ReflectionInsight(category: '安全回退', text: '保留本地结论。')],
      actionItems: const ['稍后重试模型增强。'],
    );

    final reloaded = decodeReflectionReport(encodeReflectionReport(report));

    expect(reloaded?.generationMode, kReflectionGenerationModeModelFallback);
    expect(reloaded?.generationModeLabel, '模型失败回退');
    expect(reloaded?.toMarkdown(), contains('模型失败回退'));
  });

  test('reflection service builds local insights and action items', () {
    final now = DateTime.utc(2026, 7, 6, 22);
    final digest = DreamingDigest(
      day: now,
      generatedAt: now,
      sessionCount: 1,
      originalMessageCount: 36,
      userMessageCount: 24,
      assistantMessageCount: 10,
      sessions: [
        DreamingSessionDigest(
          sessionId: 's1',
          title: '长期项目推进',
          messageCount: 34,
          userMessageCount: 23,
          assistantMessageCount: 11,
          highlights: const ['我希望你持续推进智能助理项目'],
          firstMessageAt: now.subtract(const Duration(hours: 2)),
          lastMessageAt: now,
        ),
      ],
      memoryCandidates: [_memory('task', 'todo: 明天复盘反思机制', now)],
      keywords: const ['智能助理', '反思'],
      elapsedMs: 12,
    );
    final profile = UserProfile(
      updatedAt: now,
      sourceCount: 2,
      preferences: const ['我喜欢中文、简洁、结构化回复'],
      goals: const ['目标是把 SimiChat 做成移动端优先的 AI 伙伴'],
      tasks: const ['todo: 明天复盘反思机制'],
      profileFacts: const [],
      styleSignals: const ['偏好结构化'],
      scheduleSignals: const [],
      keywords: const ['simichat'],
    );

    final report = ReflectionService(now: () => now).buildDailyReflection(
      digest: digest,
      profile: profile,
      pendingProfileProposalCount: 2,
    );

    expect(report.hasContent, isTrue);
    expect(report.sourceDigestDayKey, '2026-07-06');
    expect(report.insights.map((item) => item.category), contains('回应质量'));
    expect(report.insights.map((item) => item.category), contains('上下文'));
    expect(report.insights.map((item) => item.category), contains('用户画像'));
    expect(report.actionItems.join('\n'), contains('逐项采纳或拒绝'));
    expect(report.actionItems.join('\n'), contains('明天复盘反思机制'));
    expect(report.toMarkdown(), contains('本地反思报告'));

    final reloaded = decodeReflectionReport(encodeReflectionReport(report));
    expect(reloaded, isNotNull);
    expect(reloaded!.actionItems, report.actionItems);

    final history = decodeReflectionReportHistory(
      encodeReflectionReportHistory([report]),
    );
    expect(history, hasLength(1));
    expect(history.single.sourceDigestDayKey, '2026-07-06');
  });

  test(
    'reflection detects unanswered sessions despite balanced total turns',
    () {
      final now = DateTime.utc(2026, 7, 7, 22);
      final digest = DreamingDigest(
        day: now,
        generatedAt: now,
        sessionCount: 2,
        originalMessageCount: 8,
        userMessageCount: 4,
        assistantMessageCount: 4,
        sessions: [
          DreamingSessionDigest(
            sessionId: 'blocked-session',
            title: '未回复的任务会话',
            messageCount: 3,
            userMessageCount: 3,
            assistantMessageCount: 0,
            highlights: const ['用户追问导出同步是否完成'],
            firstMessageAt: now.subtract(const Duration(hours: 3)),
            lastMessageAt: now.subtract(const Duration(hours: 2)),
          ),
          DreamingSessionDigest(
            sessionId: 'answered-session',
            title: '已回复会话',
            messageCount: 5,
            userMessageCount: 1,
            assistantMessageCount: 4,
            highlights: const ['助手已回复其他问题'],
            firstMessageAt: now.subtract(const Duration(hours: 1)),
            lastMessageAt: now,
          ),
        ],
        memoryCandidates: const [],
        keywords: const ['导出同步'],
        elapsedMs: 6,
      );

      final report = ReflectionService(
        now: () => now,
      ).buildDailyReflection(digest: digest);

      expect(report.insights.map((item) => item.category), contains('未回复会话'));
      final unanswered = report.insights
          .where((item) => item.category == '未回复会话')
          .single;
      expect(unanswered.priority, 'high');
      expect(unanswered.text, contains('未回复的任务会话'));
      expect(unanswered.text, contains('3 条用户消息'));
      expect(report.actionItems.join('\n'), contains('未回复的任务会话'));

      final prompt = buildAssistantReflectionSystemPrompt(report);
      expect(prompt, isNotNull);
      expect(prompt, contains('未回复会话'));
      expect(prompt, contains('未回复的任务会话'));
    },
  );

  test(
    'reflection detects latest user message even when session has assistant replies',
    () {
      final now = DateTime.utc(2026, 7, 7, 22);
      final session = DreamingSessionDigest.fromJson({
        'sessionId': 'last-user-session',
        'title': '最后一问待回复',
        'messageCount': 3,
        'userMessageCount': 2,
        'assistantMessageCount': 1,
        'highlights': ['用户最后追问后台调度什么时候做'],
        'firstMessageAt': now
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
        'lastMessageAt': now.toIso8601String(),
        'lastMessageRole': 'user',
        'latestUserHighlight': '用户最后追问后台调度什么时候做',
      });
      final digest = DreamingDigest(
        day: now,
        generatedAt: now,
        sessionCount: 1,
        originalMessageCount: 3,
        userMessageCount: 2,
        assistantMessageCount: 1,
        sessions: [session],
        memoryCandidates: const [],
        keywords: const ['后台调度'],
        elapsedMs: 5,
      );

      final report = ReflectionService(
        now: () => now,
      ).buildDailyReflection(digest: digest);

      expect(report.insights.map((item) => item.category), contains('最后一问未答'));
      final pending = report.insights
          .where((item) => item.category == '最后一问未答')
          .single;
      expect(pending.priority, 'high');
      expect(pending.text, contains('最后一问待回复'));
      expect(pending.text, contains('最后一条消息来自用户'));
      expect(pending.text, contains('后台调度什么时候做'));
      expect(report.actionItems.join('\n'), contains('最后一问待回复'));

      final prompt = buildAssistantReflectionSystemPrompt(report);
      expect(prompt, isNotNull);
      expect(prompt, contains('最后一问未答'));
      expect(prompt, contains('最后一问待回复'));
    },
  );

  test(
    'reflection detects session follow-up pressure despite balanced totals',
    () {
      final now = DateTime.utc(2026, 7, 7, 22);
      final digest = DreamingDigest(
        day: now,
        generatedAt: now,
        sessionCount: 2,
        originalMessageCount: 10,
        userMessageCount: 5,
        assistantMessageCount: 5,
        sessions: [
          DreamingSessionDigest(
            sessionId: 'follow-up-heavy',
            title: '连续追问会话',
            messageCount: 6,
            userMessageCount: 4,
            assistantMessageCount: 2,
            highlights: const ['用户连续追问后台调度方案'],
            firstMessageAt: now.subtract(const Duration(hours: 2)),
            lastMessageAt: now.subtract(const Duration(minutes: 30)),
            lastMessageRole: 'assistant',
          ),
          DreamingSessionDigest(
            sessionId: 'balanced-by-other-session',
            title: '其他已收口会话',
            messageCount: 4,
            userMessageCount: 1,
            assistantMessageCount: 3,
            highlights: const ['助手回复了其他问题'],
            firstMessageAt: now.subtract(const Duration(hours: 1)),
            lastMessageAt: now,
            lastMessageRole: 'assistant',
          ),
        ],
        memoryCandidates: const [],
        keywords: const ['后台调度'],
        elapsedMs: 5,
      );

      final report = ReflectionService(
        now: () => now,
      ).buildDailyReflection(digest: digest);

      expect(report.insights.map((item) => item.category), contains('会话追问压力'));
      final pressure = report.insights
          .where((item) => item.category == '会话追问压力')
          .single;
      expect(pressure.priority, 'high');
      expect(pressure.text, contains('连续追问会话'));
      expect(pressure.text, contains('多 2 条'));
      expect(report.actionItems.join('\n'), contains('连续追问会话'));

      final prompt = buildAssistantReflectionSystemPrompt(report);
      expect(prompt, isNotNull);
      expect(prompt, contains('会话追问压力'));
    },
  );

  test('reflection detects repeated unresolved user intent in one session', () {
    final now = DateTime.utc(2026, 7, 7, 22);
    final digest = DreamingDigest(
      day: now,
      generatedAt: now,
      sessionCount: 1,
      originalMessageCount: 6,
      userMessageCount: 4,
      assistantMessageCount: 2,
      sessions: [
        DreamingSessionDigest(
          sessionId: 'repeated-question',
          title: '后台调度追问',
          messageCount: 6,
          userMessageCount: 4,
          assistantMessageCount: 2,
          highlights: const [
            'Dreaming 后台调度什么时候做',
            '请明确后台调度到底什么时候做',
            '后台调度现在是否已经有效',
          ],
          firstMessageAt: now.subtract(const Duration(hours: 2)),
          lastMessageAt: now,
          lastMessageRole: 'user',
          latestUserHighlight: '后台调度到底什么时候做',
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['后台调度'],
      elapsedMs: 5,
    );

    final report = ReflectionService(
      now: () => now,
    ).buildDailyReflection(digest: digest);

    expect(report.insights.map((item) => item.category), contains('重复追问'));
    final repeated = report.insights
        .where((item) => item.category == '重复追问')
        .single;
    expect(repeated.priority, 'high');
    expect(repeated.text, contains('后台调度追问'));
    expect(repeated.text, contains('后台调度'));
    expect(report.actionItems.join('\n'), contains('后台调度追问'));
    expect(report.actionItems.join('\n'), contains('明确状态'));

    final prompt = buildAssistantReflectionSystemPrompt(report);
    expect(prompt, isNotNull);
    expect(prompt, contains('重复追问'));
    expect(prompt, contains('后台调度'));
  });

  test('reflection promotes latest user task when profile has no task', () {
    final now = DateTime.utc(2026, 7, 7, 22);
    final digest = DreamingDigest(
      day: now,
      generatedAt: now,
      sessionCount: 1,
      originalMessageCount: 5,
      userMessageCount: 3,
      assistantMessageCount: 2,
      sessions: [
        DreamingSessionDigest(
          sessionId: 'latest-task',
          title: 'iOS 网络切换',
          messageCount: 5,
          userMessageCount: 3,
          assistantMessageCount: 2,
          highlights: const ['用户要求继续推进移动端真机稳定性'],
          firstMessageAt: now.subtract(const Duration(hours: 2)),
          lastMessageAt: now,
          lastMessageRole: 'user',
          latestUserHighlight: '现在继续推进 iOS 网络切换真机复跑',
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['网络切换'],
      elapsedMs: 5,
    );

    final report = ReflectionService(
      now: () => now,
    ).buildDailyReflection(digest: digest);

    expect(report.insights.map((item) => item.category), contains('最新任务推进'));
    final task = report.insights
        .where((item) => item.category == '最新任务推进')
        .single;
    expect(task.priority, 'high');
    expect(task.text, contains('iOS 网络切换真机复跑'));
    expect(report.actionItems.join('\n'), contains('iOS 网络切换真机复跑'));

    final prompt = buildAssistantReflectionSystemPrompt(report);
    expect(prompt, isNotNull);
    expect(prompt, contains('最新任务推进'));
    expect(prompt, contains('iOS 网络切换真机复跑'));
  });

  test(
    'reflection does not promote generic polite question as latest task',
    () {
      final now = DateTime.utc(2026, 7, 7, 22);
      final digest = DreamingDigest(
        day: now,
        generatedAt: now,
        sessionCount: 1,
        originalMessageCount: 3,
        userMessageCount: 2,
        assistantMessageCount: 1,
        sessions: [
          DreamingSessionDigest(
            sessionId: 'generic-question',
            title: '设置说明',
            messageCount: 3,
            userMessageCount: 2,
            assistantMessageCount: 1,
            highlights: const ['用户询问设置含义'],
            firstMessageAt: now.subtract(const Duration(hours: 1)),
            lastMessageAt: now,
            lastMessageRole: 'user',
            latestUserHighlight: '请问这个设置是什么意思',
          ),
        ],
        memoryCandidates: const [],
        keywords: const ['设置'],
        elapsedMs: 4,
      );

      final report = ReflectionService(
        now: () => now,
      ).buildDailyReflection(digest: digest);

      expect(
        report.insights.map((item) => item.category),
        isNot(contains('最新任务推进')),
      );
      expect(report.actionItems.join('\n'), isNot(contains('请问这个设置是什么意思')));

      final prompt = buildAssistantReflectionSystemPrompt(report);
      expect(prompt, anyOf(isNull, isNot(contains('最新任务推进'))));
    },
  );

  test(
    'reflection warns when source dreaming is older than reflection day',
    () {
      final digestDay = DateTime.utc(2026, 7, 5, 22);
      final now = DateTime.utc(2026, 7, 7, 9);
      final digest = DreamingDigest(
        day: digestDay,
        generatedAt: digestDay,
        sessionCount: 1,
        originalMessageCount: 4,
        userMessageCount: 2,
        assistantMessageCount: 2,
        sessions: [
          DreamingSessionDigest(
            sessionId: 's1',
            title: '旧日报',
            messageCount: 4,
            userMessageCount: 2,
            assistantMessageCount: 2,
            highlights: const ['用户继续推进项目'],
            firstMessageAt: digestDay.subtract(const Duration(hours: 1)),
            lastMessageAt: digestDay,
          ),
        ],
        memoryCandidates: const [],
        keywords: const ['项目'],
        elapsedMs: 4,
      );

      final report = ReflectionService(
        now: () => now,
      ).buildDailyReflection(digest: digest);

      expect(report.dayKey, '2026-07-07');
      expect(report.sourceDigestDayKey, '2026-07-05');
      expect(report.insights.map((item) => item.category), contains('来源新鲜度'));
      final freshness = report.insights
          .where((item) => item.category == '来源新鲜度')
          .single;
      expect(freshness.priority, 'high');
      expect(freshness.text, contains('2026-07-05'));
      expect(freshness.text, contains('2026-07-07'));
      expect(report.actionItems.join('\n'), contains('先运行今日 Dreaming'));
      expect(report.toMarkdown(), contains('来源新鲜度'));

      final prompt = buildAssistantReflectionSystemPrompt(report);
      expect(prompt, isNotNull);
      expect(prompt, contains('来源新鲜度'));
      expect(prompt, contains('先运行今日 Dreaming'));
    },
  );

  test('reflection report skips secret-like profile signals', () {
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
          sessionId: 's1',
          title: '安全',
          messageCount: 2,
          userMessageCount: 1,
          assistantMessageCount: 1,
          highlights: const [],
          firstMessageAt: now,
          lastMessageAt: now,
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['安全'],
      elapsedMs: 1,
    );
    final profile = UserProfile(
      updatedAt: now,
      sourceCount: 1,
      preferences: const ['我的 API Key 是 sk-test-secret-1234567890'],
      goals: const [],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const [],
    );

    final report = const ReflectionService().buildDailyReflection(
      digest: digest,
      profile: profile,
    );

    final markdown = report.toMarkdown();
    expect(markdown, isNot(contains('sk-test-secret')));
    expect(markdown, isNot(contains('API Key')));
  });

  test('reflection carries truncated dreaming digest into short prompt', () {
    final now = DateTime.utc(2026, 7, 6, 22);
    final digest = DreamingDigest(
      day: now,
      generatedAt: now,
      sessionCount: 1,
      originalMessageCount: 2,
      totalOriginalMessageCount: 5,
      userMessageCount: 2,
      assistantMessageCount: 0,
      sessions: [
        DreamingSessionDigest(
          sessionId: 's1',
          title: '超长会话',
          messageCount: 2,
          userMessageCount: 2,
          assistantMessageCount: 0,
          highlights: const ['用户持续追加长会话稳定性要求'],
          firstMessageAt: now.subtract(const Duration(hours: 1)),
          lastMessageAt: now,
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['长会话'],
      elapsedMs: 5,
      isTruncated: true,
      messageLimit: 2,
    );

    final report = ReflectionService(
      now: () => now,
    ).buildDailyReflection(digest: digest);

    expect(report.sourceDigestIsTruncated, isTrue);
    expect(report.sourceDigestMessageLimit, 2);
    expect(report.sourceDigestTotalOriginalMessageCount, 5);
    expect(report.insights.map((item) => item.category), contains('整理完整性'));
    expect(
      report.insights.where((item) => item.category == '整理完整性').single.priority,
      'high',
    );
    expect(report.actionItems.join('\n'), contains('不要把本次 Dreaming 当作当天完整画像'));
    expect(report.toMarkdown(), contains('不代表当天全部对话'));
    expect(report.toMarkdown(), contains('2 / 5'));

    final reloaded = decodeReflectionReport(encodeReflectionReport(report));
    expect(reloaded, isNotNull);
    expect(reloaded!.sourceDigestIsTruncated, isTrue);
    expect(reloaded.sourceDigestMessageLimit, 2);
    expect(reloaded.sourceDigestTotalOriginalMessageCount, 5);

    final prompt = buildAssistantReflectionSystemPrompt(report);
    expect(prompt, isNotNull);
    expect(prompt, contains('整理完整性'));
    expect(prompt, contains('2 / 5'));
    expect(prompt, contains('不要把本次 Dreaming 当作当天完整画像'));
  });

  test('reflection system prompt is bounded and redacted', () {
    final now = DateTime.utc(2026, 7, 6, 22);
    final report = ReflectionReport(
      dayKey: '2026-07-06',
      generatedAt: now,
      sourceDigestDayKey: '2026-07-06',
      sessionCount: 1,
      originalMessageCount: 10,
      userMessageCount: 6,
      assistantMessageCount: 4,
      pendingProfileProposalCount: 0,
      insights: const [
        ReflectionInsight(
          category: '回应质量',
          text: '用户多轮追问，需要先补总结。',
          priority: 'high',
        ),
        ReflectionInsight(
          category: '安全',
          text: 'Authorization: Bearer secret',
          priority: 'high',
        ),
      ],
      actionItems: const [
        '下次对话先总结未完成问题。',
        'API Key 是 sk-test-secret-1234567890',
      ],
    );

    final prompt = buildAssistantReflectionSystemPrompt(report);

    expect(prompt, isNotNull);
    expect(prompt, contains(kAssistantReflectionPromptTitle));
    expect(prompt, contains('用户多轮追问'));
    expect(prompt, contains('下次对话先总结未完成问题'));
    expect(prompt, isNot(contains('sk-test-secret')));
    expect(prompt, isNot(contains('Authorization')));
  });

  test('long conversation baseline keeps task follow-up in short prompt', () {
    final now = DateTime.utc(2026, 7, 6, 22);
    final digest = DreamingDigest(
      day: now,
      generatedAt: now,
      sessionCount: 2,
      originalMessageCount: 78,
      userMessageCount: 48,
      assistantMessageCount: 30,
      sessions: [
        DreamingSessionDigest(
          sessionId: 's1',
          title: '长会话项目推进',
          messageCount: 45,
          userMessageCount: 28,
          assistantMessageCount: 17,
          highlights: const ['用户要求持续推进智能助理项目'],
          firstMessageAt: now.subtract(const Duration(hours: 3)),
          lastMessageAt: now.subtract(const Duration(hours: 2)),
        ),
        DreamingSessionDigest(
          sessionId: 's2',
          title: '反思机制复盘',
          messageCount: 33,
          userMessageCount: 20,
          assistantMessageCount: 13,
          highlights: const ['用户希望优化每一个环节及步骤'],
          firstMessageAt: now.subtract(const Duration(hours: 1)),
          lastMessageAt: now,
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['智能助理', '反思', '长会话'],
      elapsedMs: 24,
    );
    final profile = UserProfile(
      updatedAt: now,
      sourceCount: 3,
      preferences: const ['偏好中文、直接、可验证的回复'],
      goals: const ['把 SimiChat 做成对话智能助理软件'],
      tasks: const ['继续推进长会话反思质量基线'],
      profileFacts: const [],
      styleSignals: const ['要求反复检查和确认'],
      scheduleSignals: const [],
      keywords: const ['simichat', 'reflection'],
    );

    final report = ReflectionService(now: () => now).buildDailyReflection(
      digest: digest,
      profile: profile,
      pendingProfileProposalCount: 4,
    );

    final highCategories = report.insights
        .where((item) => item.priority == 'high')
        .map((item) => item.category)
        .toList();
    expect(highCategories, containsAll(['回应质量', '上下文', '任务推进', '用户画像']));
    expect(report.actionItems.join('\n'), contains('长会话'));
    expect(report.actionItems.join('\n'), contains('继续推进长会话反思质量基线'));
    expect(report.actionItems.join('\n'), contains('逐项采纳或拒绝'));

    final prompt = buildAssistantReflectionSystemPrompt(report);
    expect(prompt, isNotNull);
    expect(prompt, contains('长会话'));
    expect(prompt, contains('继续推进长会话反思质量基线'));
    expect(prompt, isNot(contains('逐项采纳或拒绝')));
  });
}

KeyPointMemoryItem _memory(String category, String content, DateTime now) {
  return KeyPointMemoryItem(
    id: '$category-$content',
    category: category,
    content: content,
    keywords: const [],
    confidence: 0.8,
    sessionId: 's1',
    sourceMessageId: 'm1',
    createdAt: now,
    updatedAt: now,
  );
}
