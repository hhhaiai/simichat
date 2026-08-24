import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/context/context_budget_trimmer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounded context keeps rolling summary and the newest user request', () {
    final messages = <AiMessage>[
      const AiMessage(
        role: 'assistant',
        content: '[历史摘要] 长期关键事实：项目代号 Aurora，交付颜色是蓝色。',
      ),
      for (var i = 0; i < 8; i++)
        AiMessage(
          role: i.isEven ? 'user' : 'assistant',
          content: '普通历史 $i ${'x' * 500}',
        ),
      AiMessage(role: 'user', content: '最新问题：项目代号是什么？${'y' * 500}'),
    ];

    final trimmed = trimAiMessagesToTokenBudget(
      systemPrompt: 'system',
      messages: messages,
      maxInputTokens: 300,
    );
    final content = trimmed.map((message) => message.content).join('\n');

    expect(content, contains('项目代号 Aurora'));
    expect(content, contains('最新问题：项目代号是什么'));
    expect(
      estimateContextInputTokens(systemPrompt: 'system', messages: trimmed),
      lessThanOrEqualTo(300),
    );
    expect(trimmed.first.role, 'user');
  });
}
