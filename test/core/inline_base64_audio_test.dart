import 'dart:convert';

import 'package:ai_chat_app/core/media/inline_base64_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inline base64 audio extraction', () {
    test('extracts data URL audio and removes raw base64 from prompt', () {
      final bytes = <int>[
        0x52,
        0x49,
        0x46,
        0x46,
        0x24,
        0x00,
        0x00,
        0x00,
        0x57,
        0x41,
        0x56,
        0x45,
      ];
      final base64Audio = base64Encode(bytes);
      final result = extractInlineBase64Audio(
        '请识别这段：data:audio/wav;base64,$base64Audio',
      );

      expect(result.audio, isNotNull);
      expect(result.audio!.bytes, bytes);
      expect(result.audio!.mimeType, 'audio/wav');
      expect(result.audio!.extension, 'wav');
      expect(result.cleanedContent, contains('已接收 base64 语音'));
      expect(result.cleanedContent, isNot(contains(base64Audio)));
    });

    test('extracts Chinese marker payload and infers m4a audio', () {
      final bytes = <int>[
        0x00,
        0x00,
        0x00,
        0x18,
        0x66,
        0x74,
        0x79,
        0x70,
        0x4d,
        0x34,
        0x41,
        0x20,
      ];
      final base64Audio = base64Encode(bytes);
      final result = extractInlineBase64Audio(
        '这段语音帮我识别下，这是 base64 的语音字符：$base64Audio',
      );

      expect(result.audio, isNotNull);
      expect(result.audio!.bytes, bytes);
      expect(result.audio!.mimeType, 'audio/mp4');
      expect(result.audio!.extension, 'm4a');
      expect(result.cleanedContent, startsWith('这段语音帮我识别下'));
      expect(result.cleanedContent, isNot(contains(base64Audio)));
    });

    test('rejects invalid marker payload before it can be sent as text', () {
      expect(
        () => extractInlineBase64Audio(
          '这段语音帮我识别下，这是 base64 的语音字符：not-valid-base64',
        ),
        throwsA(
          isA<InlineBase64AudioException>().having(
            (error) => error.message,
            'message',
            contains('base64'),
          ),
        ),
      );
    });

    test('rejects oversized decoded audio', () {
      final base64Audio = base64Encode(List<int>.filled(16, 1));

      expect(
        () =>
            extractInlineBase64Audio('audio base64: $base64Audio', maxBytes: 8),
        throwsA(
          isA<InlineBase64AudioException>().having(
            (error) => error.message,
            'message',
            contains('过大'),
          ),
        ),
      );
    });
  });
}
