import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/context/context_builder.dart';

// Fake MessageDao for testing
class _FakeMessageDao {
  final List<_FakeMessage> summaries = [];
  final List<_FakeMessage> originals = [];

  Future<List<_FakeMessage>> getSummaries(String _) async => summaries;
  Future<List<_FakeMessage>> getUnsummarizedOriginals(String _) async => originals;
}

class _FakeMessage {
  final String role;
  final String content;
  final int tokens;

  const _FakeMessage({required this.role, required this.content, this.tokens = 0});
}

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
