import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/ai/openai_response_protocol.dart';

void main() {
  group('OpenAiResponseProtocol.extractChunksFromEventData', () {
    test('parses output_text delta events', () {
      final chunks = OpenAiResponseProtocol.extractChunksFromEventData(
        '{"output_index":0,"content_index":0,"delta":"Hi there! ","type":"response.output_text.delta"}',
        allowCompletedFallback: false,
      );

      expect(chunks.length, 1);
      expect(chunks.single.content, 'Hi there! ');
    });

    test('parses completed response fallback payloads', () {
      final chunks = OpenAiResponseProtocol.extractChunksFromEventData(
        '{"response":{"output":[{"type":"message","content":[{"type":"output_text","text":"Hi there! 👋 I\'m MiMo."}]}]},"type":"response.completed"}',
      );

      expect(chunks.length, 1);
      expect(chunks.single.content, "Hi there! 👋 I'm MiMo.");
    });

    test('parses output_item done payloads', () {
      final chunks = OpenAiResponseProtocol.extractChunksFromEventData(
        '{"output_index":0,"item":{"type":"message","content":[{"type":"output_text","text":"Hi there! 👋"}],"status":"completed"},"type":"response.output_item.done"}',
      );

      expect(chunks.length, 1);
      expect(chunks.single.content, 'Hi there! 👋');
    });
  });
}
