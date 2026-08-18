import 'dart:convert';
import 'dart:io';

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

  test('loadAttachments reads audio files as base64 payloads', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'simichat_audio_attachment_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final audio = File('${tempDir.path}/voice.m4a');
    await audio.writeAsBytes([0x01, 0x02, 0x03, 0x04]);

    final loaded = await loadAttachments([
      Attachment(type: 'audio', path: audio.path),
    ]);

    expect(loaded, hasLength(1));
    expect(loaded.single.type, 'audio');
    expect(loaded.single.mimeType, 'audio/mp4');
    expect(loaded.single.audioFormat, 'm4a');
    expect(loaded.single.base64, base64Encode([0x01, 0x02, 0x03, 0x04]));
  });

  test('loads audio data URLs and keeps the format metadata', () async {
    final loaded = await loadAttachments(const [
      Attachment(type: 'audio', path: 'data:audio/wav;base64,AQIDBA'),
    ]);

    expect(loaded.single.mimeType, 'audio/wav');
    expect(loaded.single.audioFormat, 'wav');
    expect(loaded.single.base64, 'AQIDBA==');
  });

  test('builds native OpenAI Chat audio parts instead of text fallbacks', () {
    final part = buildOpenAiChatAudioPart(
      const AttachmentData(
        type: 'audio',
        base64: 'AQID',
        mimeType: 'audio/wav',
        audioFormat: 'wav',
      ),
    );

    expect(part, {
      'type': 'input_audio',
      'input_audio': {'data': 'AQID', 'format': 'wav'},
    });
    expect(jsonEncode(part), isNot(contains('mime_type')));
  });

  test('rejects an empty native audio payload with a typed exception', () {
    expect(
      () => buildOpenAiChatAudioPart(
        const AttachmentData(type: 'audio', base64: '', mimeType: 'audio/wav'),
      ),
      throwsA(
        isA<UnsupportedAttachmentException>()
            .having((error) => error.attachmentType, 'type', 'audio')
            .having((error) => error.protocol, 'protocol', 'openai_chat'),
      ),
    );
  });
}
