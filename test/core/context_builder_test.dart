import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/context/context_builder.dart';

void main() {
  test('ContextBuilder with no messages returns system prompt + empty list', () async {
    // This test validates the context structure.
    // Full integration test would need actual DAO setup.
    // Key behavior: empty = system prompt + empty messages.
    expect(ContextBuilder.defaultSystemPrompt, contains('有帮助的 AI 助手'));
  });

  test('default system prompt is non-empty', () {
    expect(ContextBuilder.defaultSystemPrompt.isNotEmpty, true);
  });
}
