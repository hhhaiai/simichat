import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat provider context limit helpers', () {
    test('recognizes common provider context-limit errors', () {
      expect(
        isContextLimitErrorForTesting(
          "This model's maximum context length is 8192 tokens.",
        ),
        true,
      );
      expect(
        isContextLimitErrorForTesting(
          'context_length_exceeded: input tokens exceed the model limit',
        ),
        true,
      );
      expect(isContextLimitErrorForTesting('too many tokens in request'), true);
      expect(isContextLimitErrorForTesting('connection timeout'), false);
    });

    test('formats actionable context-limit message for the user', () {
      final message = contextLimitUserMessageForTesting();

      expect(message, contains('上下文'));
      expect(message, contains('更大上下文'));
      expect(message, isNot(contains('context_length_exceeded')));
    });

    test('combines key point memory with local reflection prompt', () {
      final now = DateTime.utc(2026, 7, 6, 22);
      final prompt = buildLocalContextPromptForTesting(
        memoryPrompt: '## 长期记忆\n- [偏好] 用户偏好中文。',
        reflectionReport: ReflectionReport(
          dayKey: '2026-07-06',
          generatedAt: now,
          sourceDigestDayKey: '2026-07-06',
          sessionCount: 1,
          originalMessageCount: 8,
          userMessageCount: 5,
          assistantMessageCount: 3,
          pendingProfileProposalCount: 0,
          insights: const [
            ReflectionInsight(
              category: '任务推进',
              text: '需要优先收口项目推进。',
              priority: 'high',
            ),
          ],
          actionItems: const ['下次回复先给当前项目下一步。'],
        ),
      );

      expect(prompt, isNotNull);
      expect(prompt, contains('长期记忆'));
      expect(prompt, contains(kAssistantReflectionPromptTitle));
      expect(prompt, contains('下次回复先给当前项目下一步'));
    });

    test('can disable local reflection prompt while keeping memory', () {
      final now = DateTime.utc(2026, 7, 6, 22);
      final prompt = buildLocalContextPromptForTesting(
        memoryPrompt: '## 长期记忆\n- [偏好] 用户偏好中文。',
        reflectionPromptEnabled: false,
        reflectionReport: ReflectionReport(
          dayKey: '2026-07-06',
          generatedAt: now,
          sourceDigestDayKey: '2026-07-06',
          sessionCount: 1,
          originalMessageCount: 8,
          userMessageCount: 5,
          assistantMessageCount: 3,
          pendingProfileProposalCount: 0,
          insights: const [
            ReflectionInsight(
              category: '任务推进',
              text: '需要优先收口项目推进。',
              priority: 'high',
            ),
          ],
          actionItems: const ['下次回复先给当前项目下一步。'],
        ),
      );

      expect(prompt, contains('长期记忆'));
      expect(prompt, isNot(contains(kAssistantReflectionPromptTitle)));
      expect(prompt, isNot(contains('下次回复先给当前项目下一步')));
    });
  });
}
