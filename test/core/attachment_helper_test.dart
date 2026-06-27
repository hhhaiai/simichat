import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/attachment_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loadAttachments reads supported image data urls without file IO',
    () async {
      final loaded = await loadAttachments(const [
        Attachment(
          type: 'image',
          path: 'data:image/png;base64,UEFZTE9BRE1BUktFUg',
        ),
      ]);

      expect(loaded, hasLength(1));
      expect(loaded.single.type, 'image');
      expect(loaded.single.mimeType, 'image/png');
      expect(loaded.single.base64, 'UEFZTE9BRE1BUktFUg==');
    },
  );

  test('loadAttachments does not read or base64 encode audio files', () async {
    final loaded = await loadAttachments(const [
      Attachment(type: 'audio', path: '/missing/voice.mp3'),
    ]);

    expect(loaded, hasLength(1));
    expect(loaded.single.type, 'audio');
    expect(loaded.single.mimeType, 'audio/mpeg');
    expect(loaded.single.base64, isEmpty);
  });
}
