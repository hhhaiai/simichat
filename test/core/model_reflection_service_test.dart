import 'dart:async';

import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/model_reflection_service.dart';
import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model reflection safely merges strict JSON with local fallback', () {
    final local = _localReport();
    final enhanced = const ModelReflectionService().enhanceFromResponse(
      localReport: local,
      response: '''
```json
{
  "insights": [
    {"category":"任务推进","text":"下一轮先确认用户尚未完成的移动端后台验证。","priority":"high"}
  ],
  "actionItems": ["先复核系统后台权限，再继续真机验证。"]
}
```
''',
    );

    expect(enhanced.generationMode, kReflectionGenerationModeModel);
    expect(enhanced.insights.last.category, '任务推进');
    expect(enhanced.insights, contains(local.insights.first));
    expect(enhanced.actionItems.last, contains('后台权限'));
    expect(enhanced.actionItems, contains(local.actionItems.first));
  });

  test(
    'model reflection uses the first complete object from repeated output',
    () {
      final enhanced = const ModelReflectionService().enhanceFromResponse(
        localReport: _localReport(),
        response: '''
<think>先分析，但这些文字不能进入结构化结果。</think>
{"insights":[{"category":"远程稳定性","text":"非流式响应需要重复质量验证","priority":"high"}],"actionItems":["连续执行三轮远程反思质量门禁"]}
```json
{"insights":[{"category":"重复对象","text":"这一份重复输出不应与首个对象拼接","priority":"normal"}],"actionItems":["忽略重复的第二个 JSON 对象"]}
```
''',
      );

      expect(enhanced.insights.last.category, '远程稳定性');
      expect(enhanced.actionItems.last, '连续执行三轮远程反思质量门禁');
      expect(enhanced.insights.any((item) => item.category == '重复对象'), isFalse);
    },
  );

  test('model reflection repairs one stray action list brace', () {
    final enhanced = const ModelReflectionService().enhanceFromResponse(
      localReport: _localReport(),
      response: '''
{"insights":[],"actionItems":["先检查移动端后台状态"}]}
''',
    );

    expect(enhanced.generationMode, kReflectionGenerationModeModel);
    expect(enhanced.actionItems.last, '先检查移动端后台状态');
  });

  test('model reflection repairs a stray brace with missing root close', () {
    final enhanced = const ModelReflectionService().enhanceFromResponse(
      localReport: _localReport(),
      response: '{"insights":[],"actionItems":["继续验证反思"}]',
    );

    expect(enhanced.actionItems.last, '继续验证反思');
  });

  test('model reflection repairs trailing object commas', () {
    final enhanced = const ModelReflectionService().enhanceFromResponse(
      localReport: _localReport(),
      response: '''
{"insights":[{"category":"任务推进","text":"继续验证跨日任务","priority":"high",}],"actionItems":[]}
''',
    );

    expect(enhanced.insights.last.text, '继续验证跨日任务');
  });

  test('model reflection repairs a full-width closing parenthesis', () {
    final enhanced = const ModelReflectionService().enhanceFromResponse(
      localReport: _localReport(),
      response: '{"insights":[],"actionItems":["继续验证移动端反思"]）',
    );

    expect(enhanced.actionItems.last, '继续验证移动端反思');
  });

  test('model reflection accepts safe action objects from small models', () {
    final enhanced = const ModelReflectionService().enhanceFromResponse(
      localReport: _localReport(),
      response: '''
{"insights":[],"actionItems":[{"text":"确认移动端后台状态","priority":"normal"}]}
''',
    );

    expect(enhanced.generationMode, kReflectionGenerationModeModel);
    expect(enhanced.actionItems.last, '确认移动端后台状态');
  });

  test('model reflection accepts common small-model action keys', () {
    final enhanced = const ModelReflectionService().enhanceFromResponse(
      localReport: _localReport(),
      response: '''
{"insights":[],"actionItems":[{"nextStep":"检查跨日任务"},{"nextAction":"复核反思历史"}]}
''',
    );

    expect(enhanced.actionItems, contains('检查跨日任务'));
    expect(enhanced.actionItems, contains('复核反思历史'));
  });

  test('model reflection rejects schema placeholder content', () {
    expect(
      () => const ModelReflectionService().enhanceFromResponse(
        localReport: _localReport(),
        response:
            '{"insights":[{"category":"反思","text":"结论",'
            '"priority":"high|normal|low"}],"actionItems":[]}',
      ),
      throwsA(isA<ModelReflectionFormatException>()),
    );
  });

  test('model reflection cannot displace the local safety baseline', () {
    final local = _localReportWithItems(6);
    final enhanced = const ModelReflectionService().enhanceFromResponse(
      localReport: local,
      response: '''
{
  "insights": [
    {"category":"模型 1","text":"模型结论 1","priority":"normal"},
    {"category":"模型 2","text":"模型结论 2","priority":"normal"},
    {"category":"模型 3","text":"模型结论 3","priority":"normal"},
    {"category":"模型 4","text":"模型结论 4","priority":"normal"},
    {"category":"模型 5","text":"模型结论 5","priority":"normal"},
    {"category":"模型 6","text":"模型结论 6","priority":"normal"},
    {"category":"模型 7","text":"模型结论 7","priority":"normal"},
    {"category":"模型 8","text":"模型结论 8","priority":"normal"}
  ],
  "actionItems": [
    "模型行动 1", "模型行动 2", "模型行动 3", "模型行动 4",
    "模型行动 5", "模型行动 6", "模型行动 7", "模型行动 8"
  ]
}
''',
    );

    expect(enhanced.insights, hasLength(8));
    expect(enhanced.actionItems, hasLength(8));
    for (final item in local.insights) {
      expect(enhanced.insights, contains(item));
    }
    for (final item in local.actionItems) {
      expect(enhanced.actionItems, contains(item));
    }
    expect(
      enhanced.insights.where((item) => item.category.startsWith('模型')),
      hasLength(2),
    );
    expect(
      enhanced.actionItems.where((item) => item.startsWith('模型行动')),
      hasLength(2),
    );
  });

  test('model reflection rejects duplicate-only enhancement', () {
    expect(
      () => const ModelReflectionService().enhanceFromResponse(
        localReport: _localReport(),
        response: '''
{
  "insights": [
    {"category":"回应质量","text":"继续保持回答可验证。","priority":"normal"}
  ],
  "actionItems": ["继续执行现有稳定门禁。"]
}
''',
      ),
      throwsA(isA<ModelReflectionFormatException>()),
    );
  });

  test('model reflection enforces one total timeout for slow chunks', () async {
    final controller = StreamController<String>();
    var timeoutCancelledSource = false;
    late final Timer chunkTimer;
    chunkTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      controller.add('x');
    });
    addTearDown(() async {
      chunkTimer.cancel();
      if (!controller.isClosed) await controller.close();
    });

    await expectLater(
      const ModelReflectionService().collectResponse(
        chunks: controller.stream,
        timeout: const Duration(milliseconds: 80),
        onTimeout: () {
          timeoutCancelledSource = true;
          chunkTimer.cancel();
          unawaited(controller.close());
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(timeoutCancelledSource, isTrue);
  });

  test('model reflection drops unsafe output and rejects empty result', () {
    expect(
      () => const ModelReflectionService().enhanceFromResponse(
        localReport: _localReport(),
        response: '''
{"insights":[{"category":"密钥","text":"Bearer sk-secret-token","priority":"high"}],"actionItems":["api_key=raw-secret"]}
''',
      ),
      throwsA(isA<ModelReflectionFormatException>()),
    );
  });

  test('model reflection drops URL and local path output', () {
    expect(
      () => const ModelReflectionService().enhanceFromResponse(
        localReport: _localReport(),
        response: '''
{"insights":[{"category":"来源","text":"查看 https://example.test/private","priority":"high"}],"actionItems":["读取 /Users/test/private.txt"]}
''',
      ),
      throwsA(isA<ModelReflectionFormatException>()),
    );
  });

  test('model reflection prompt is bounded and redacts obvious secrets', () {
    final systemPrompt = const ModelReflectionService().systemPrompt;
    final digest = _digest(
      highlight:
          'Bearer sk-secret-token https://example.test/private '
          '/data/user/0/top.simitalk.aichat/private.txt '
          '${List.filled(3000, '很长内容').join()}',
    );
    final prompt = const ModelReflectionService().buildUserPrompt(
      digest: digest,
      localReport: _localReport(),
    );

    expect(prompt.length, lessThanOrEqualTo(kModelReflectionMaxPromptChars));
    expect(prompt, isNot(contains('sk-secret-token')));
    expect(prompt, contains('Bearer ***'));
    expect(prompt, isNot(contains('example.test')));
    expect(prompt, isNot(contains('/data/user/0')));
    expect(prompt, contains('[链接]'));
    expect(prompt, contains('[本机路径]'));
    expect(systemPrompt, contains('不能输出 high|normal|low'));
    expect(systemPrompt, contains('不要照抄“分类”或“结论”'));
    expect(systemPrompt, contains('actionItems 至少 1 条'));
  });
}

ReflectionReport _localReport() {
  final now = DateTime.utc(2026, 7, 14, 22);
  return ReflectionReport(
    dayKey: '2026-07-14',
    generatedAt: now,
    sourceDigestDayKey: '2026-07-14',
    sessionCount: 1,
    originalMessageCount: 2,
    userMessageCount: 1,
    assistantMessageCount: 1,
    pendingProfileProposalCount: 0,
    insights: const [ReflectionInsight(category: '回应质量', text: '继续保持回答可验证。')],
    actionItems: const ['继续执行现有稳定门禁。'],
  );
}

ReflectionReport _localReportWithItems(int count) {
  final base = _localReport();
  return ReflectionReport(
    dayKey: base.dayKey,
    generatedAt: base.generatedAt,
    sourceDigestDayKey: base.sourceDigestDayKey,
    sessionCount: base.sessionCount,
    originalMessageCount: base.originalMessageCount,
    userMessageCount: base.userMessageCount,
    assistantMessageCount: base.assistantMessageCount,
    pendingProfileProposalCount: base.pendingProfileProposalCount,
    insights: List.generate(
      count,
      (index) => ReflectionInsight(
        category: '本地 ${index + 1}',
        text: '本地结论 ${index + 1}',
      ),
    ),
    actionItems: List.generate(count, (index) => '本地行动 ${index + 1}'),
  );
}

DreamingDigest _digest({required String highlight}) {
  final now = DateTime.utc(2026, 7, 14, 22);
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
        title: '模型反思',
        messageCount: 2,
        userMessageCount: 1,
        assistantMessageCount: 1,
        highlights: [highlight],
        firstMessageAt: now.subtract(const Duration(minutes: 1)),
        lastMessageAt: now,
      ),
    ],
    memoryCandidates: const [],
    keywords: const ['反思'],
    elapsedMs: 1,
  );
}
