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
  });
}
