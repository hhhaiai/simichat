import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/memory/model_user_profile_service.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model profile only appends safe grounded candidate signals', () {
    final local = _localCandidate();
    final digest = _digest();

    final enhanced = const ModelUserProfileService().enhanceFromResponse(
      digest: digest,
      localCandidate: local,
      response: '''
{
  "additions": [
    {
      "section": "styleSignals",
      "value": "偏好先给结论，再给可验证证据",
      "evidence": "我希望回答先给结论，再给可验证证据"
    },
    {
      "section": "profileFacts",
      "value": "用户是移动端工程师",
      "evidence": "我希望回答先给结论，再给可验证证据"
    },
    {
      "section": "goals",
      "value": "虚构的无证据目标",
      "evidence": "不存在的来源"
    },
    {
      "section": "tasks",
      "value": "查看 https://example.test/private",
      "evidence": "移动端 Dreaming 和 Reflection 必须稳定"
    },
    {
      "section": "preferences",
      "value": "我喜欢中文回复",
      "evidence": "我喜欢中文回复"
    }
  ]
}
''',
    );

    expect(enhanced.preferences, local.preferences);
    expect(enhanced.goals, local.goals);
    expect(enhanced.tasks, local.tasks);
    expect(enhanced.profileFacts, local.profileFacts);
    expect(enhanced.styleSignals, contains('偏好先给结论，再给可验证证据'));
    expect(enhanced.styleSignals, containsAll(local.styleSignals));
    expect(enhanced.toMarkdown(), isNot(contains('example.test')));
    expect(enhanced.toMarkdown(), isNot(contains('虚构的无证据目标')));
    expect(enhanced.sourceCount, local.sourceCount);
    expect(enhanced.digestDayKey, local.digestDayKey);
  });

  test('model profile rejects unsafe or ungrounded-only output', () {
    expect(
      () => const ModelUserProfileService().enhanceFromResponse(
        digest: _digest(),
        localCandidate: _localCandidate(),
        response: '''
{
  "additions": [
    {
      "section": "profileFacts",
      "value": "用户患有焦虑症",
      "evidence": "移动端 Dreaming 和 Reflection 必须稳定"
    },
    {
      "section": "goals",
      "value": "Bearer sk-secret-token",
      "evidence": "不存在的来源"
    }
  ]
}
''',
      ),
      throwsA(isA<ModelUserProfileFormatException>()),
    );
  });

  test('model profile bounds additions without displacing local signals', () {
    final additions = List.generate(
      10,
      (index) =>
          '''
        {
          "section": "tasks",
          "value": "候选任务 ${index + 1}",
          "evidence": "移动端 Dreaming 和 Reflection 必须稳定"
        }''',
    ).join(',');
    final local = _localCandidate();

    final enhanced = const ModelUserProfileService().enhanceFromResponse(
      digest: _digest(),
      localCandidate: local,
      response: '{"additions":[$additions]}',
    );

    expect(enhanced.preferences, containsAll(local.preferences));
    expect(enhanced.goals, containsAll(local.goals));
    expect(enhanced.tasks.length - local.tasks.length, lessThanOrEqualTo(2));
    expect(
      enhanced.totalSignalCount - local.totalSignalCount,
      lessThanOrEqualTo(kModelUserProfileMaxAdditionalItems),
    );
  });

  test(
    'model profile prompt is bounded, redacted and contains no raw chat',
    () {
      final prompt = const ModelUserProfileService().buildUserPrompt(
        digest: _digest(
          highlight:
              'Bearer sk-secret-token https://example.test/private '
              '/data/user/0/top.simitalk.aichat/private.txt '
              '${List.filled(4000, '很长摘要').join()}',
        ),
        localCandidate: _localCandidate(),
      );

      expect(prompt.length, lessThanOrEqualTo(kModelUserProfileMaxPromptChars));
      expect(prompt, isNot(contains('sk-secret-token')));
      expect(prompt, isNot(contains('example.test')));
      expect(prompt, isNot(contains('/data/user/0')));
      expect(prompt, contains('[链接]'));
      expect(prompt, contains('[本机路径]'));
      expect(prompt, contains('只允许引用下列 Dreaming / 本地候选证据'));
    },
  );
}

UserProfile _localCandidate() {
  final now = DateTime.utc(2026, 7, 14, 22);
  return UserProfile(
    updatedAt: now,
    sourceCount: 3,
    preferences: const ['我喜欢中文回复'],
    goals: const ['目标是把智能助理移动端做稳定'],
    tasks: const ['移动端 Dreaming 和 Reflection 必须稳定'],
    profileFacts: const [],
    styleSignals: const ['我喜欢中文回复'],
    scheduleSignals: const [],
    keywords: const ['移动端', 'dreaming'],
    digestDayKey: '2026-07-14',
  );
}

DreamingDigest _digest({String highlight = '移动端 Dreaming 和 Reflection 必须稳定'}) {
  final now = DateTime.utc(2026, 7, 14, 22);
  return DreamingDigest(
    day: now,
    generatedAt: now,
    sessionCount: 1,
    originalMessageCount: 4,
    userMessageCount: 2,
    assistantMessageCount: 2,
    sessions: [
      DreamingSessionDigest(
        sessionId: 's1',
        title: '移动端稳定性',
        messageCount: 4,
        userMessageCount: 2,
        assistantMessageCount: 2,
        highlights: [highlight],
        firstMessageAt: now.subtract(const Duration(minutes: 5)),
        lastMessageAt: now,
      ),
    ],
    memoryCandidates: [
      KeyPointMemoryItem(
        id: 'm1',
        sessionId: 's1',
        sourceMessageId: 'source-1',
        category: 'preference',
        content: '我希望回答先给结论，再给可验证证据',
        keywords: const ['结论', '证据'],
        confidence: 0.9,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    keywords: const ['移动端', 'dreaming'],
    elapsedMs: 1,
  );
}
