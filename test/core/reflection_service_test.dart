import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
