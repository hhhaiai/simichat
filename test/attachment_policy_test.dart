import 'package:ai_chat_app/core/attachments/attachment_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('attachment policy', () {
    test('infers image, audio, video, pdf, and document attachment types', () {
      expect(inferAttachmentType('photo.PNG'), 'image');
      expect(inferAttachmentType('voice.M4A'), 'audio');
      expect(inferAttachmentType('recording.wav'), 'audio');
      expect(inferAttachmentType('movie.MP4'), 'video');
      expect(inferAttachmentType('clip.webm'), 'video');
      expect(inferAttachmentType('report.pdf'), 'pdf');
      expect(inferAttachmentType('notes.md'), 'document');
      expect(inferAttachmentType(null), 'document');
    });

    test('formats attachment size for user-facing errors', () {
      expect(formatAttachmentSize(512), '512 B');
      expect(formatAttachmentSize(1536), '1.5 KB');
      expect(formatAttachmentSize(2 * 1024 * 1024), '2.0 MB');
    });

    test('rejects too many attachments', () {
      final error = validateAttachmentMetadata(
        fileName: 'photo.png',
        fileType: 'image',
        fileSize: 1024,
        currentCount: kMaxAttachmentsPerMessage,
      );

      expect(error, contains('最多添加'));
    });

    test('rejects attachments above the single-file size limit', () {
      final error = validateAttachmentMetadata(
        fileName: 'large.mov',
        fileType: 'document',
        fileSize: kMaxAttachmentBytes + 1,
        currentCount: 0,
      );

      expect(error, contains('附件过大'));
      expect(error, contains('25.0 MB'));
    });

    test('accepts valid attachment metadata', () {
      final error = validateAttachmentMetadata(
        fileName: 'voice.m4a',
        fileType: 'audio',
        fileSize: 1024,
        currentCount: 0,
      );

      expect(error, isNull);

      expect(
        validateAttachmentMetadata(
          fileName: 'movie.mp4',
          fileType: 'video',
          fileSize: 1024,
          currentCount: 0,
        ),
        isNull,
      );
    });
  });
}
