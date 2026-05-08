import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/ai/openai_chat_protocol.dart';

void main() {
  group('OpenAiChatProtocol.extractChunksFromEventData', () {
    test('parses grok-style reasoning and content deltas', () {
      final reasoningChunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"index":0,"delta":{"role":"assistant","reasoning_content":"Understanding\\n"}}]}',
      );
      final contentChunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"}}]}',
      );

      expect(reasoningChunks.single.thinking, 'Understanding\n');
      expect(contentChunks.single.content, 'Hello');
    });

    test('parses mimo-style reasoning and content deltas', () {
      final reasoningChunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"delta":{"content":null,"role":null,"tool_calls":null,"reasoning_content":"嗯，用户"}}]}',
      );
      final contentChunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"delta":{"content":"你好","role":null,"tool_calls":null,"reasoning_content":null}}]}',
      );

      expect(reasoningChunks.single.thinking, '嗯，用户');
      expect(contentChunks.single.content, '你好');
    });

    test('parses message fallback payloads', () {
      final chunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"choices":[{"message":{"role":"assistant","content":"Hello!","reasoning_content":"thinking"}}]}',
      );

      expect(chunks.length, 2);
      expect(chunks.first.thinking, 'thinking');
      expect(chunks.last.content, 'Hello!');
    });

    test('parses full chat completion payloads from non-stream responses', () {
      final chunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"message":{"content":"Hi there! 👋 How are you doing today?","role":"assistant","tool_calls":null,"reasoning_content":"The user is asking me to say hi."}}]}',
      );

      expect(chunks.length, 2);
      expect(chunks.first.thinking, 'The user is asking me to say hi.');
      expect(chunks.last.content, 'Hi there! 👋 How are you doing today?');
    });
  });
}
