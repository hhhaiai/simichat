import 'dart:io';

import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioTranscriptArchive', () {
    late Directory tempDir;
    late AudioTranscriptArchive archive;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'simichat_audio_transcript_',
      );
      archive = AudioTranscriptArchive(rootDirectory: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes transcript draft without exposing audio local path', () async {
      final file = await archive.writeDraft(
        messageId: 'message:1',
        attachmentId: 'attachment:1',
        fileName: 'voice.m4a',
        fileSize: 4096,
        transcript: '今天的语音内容',
        createdAt: DateTime(2026, 6, 27, 2, 40),
      );

      expect(await file.exists(), true);
      expect(file.path, contains('message_1'));
      expect(file.path, contains('attachment_1.md'));

      final markdown = await file.readAsString();
      expect(markdown, contains('# 语音转写稿件'));
      expect(markdown, contains('- status: `ready`'));
      expect(markdown, contains('voice.m4a'));
      expect(markdown, contains('今天的语音内容'));
      expect(markdown, isNot(contains('/tmp/voice.m4a')));
    });

    test('marks missing transcript as pending', () {
      final markdown = AudioTranscriptArchive.renderTranscript(
        messageId: 'm1',
        attachmentId: 'a1',
        fileName: 'empty.wav',
        fileSize: 1,
        createdAt: DateTime(2026, 6, 27),
      );

      expect(markdown, contains('- status: `pending`'));
      expect(markdown, contains('等待语音转文字完成'));
    });

    test('marks completed empty transcript explicitly', () {
      final markdown = AudioTranscriptArchive.renderTranscript(
        messageId: 'm1',
        attachmentId: 'a1',
        fileName: 'empty.wav',
        fileSize: 1,
        transcript: '',
        createdAt: DateTime(2026, 6, 27),
      );

      expect(markdown, contains('- status: `empty`'));
      expect(markdown, contains('未识别到文字'));
      expect(markdown, isNot(contains('等待语音转文字完成')));
    });

    test('writes failed transcript with sanitized error', () async {
      final file = await archive.writeFailure(
        messageId: 'message:fail',
        attachmentId: 'attachment:fail',
        fileName: 'voice.m4a',
        fileSize: 4096,
        error:
            'provider failed sk-secret-token path=/Users/sanbo/audio/voice.m4a api_key=raw-key https://example.com/stt?token=raw',
        createdAt: DateTime(2026, 6, 27, 3, 10),
      );

      final markdown = await file.readAsString();
      expect(markdown, contains('- status: `failed`'));
      expect(markdown, contains('## 转写状态'));
      expect(markdown, contains('[已隐藏路径]'));
      expect(markdown, contains('[已隐藏密钥]'));
      expect(markdown, contains('[已隐藏链接]'));
      expect(markdown, isNot(contains('/Users/sanbo')));
      expect(markdown, isNot(contains('sk-secret-token')));
      expect(markdown, isNot(contains('token=raw')));
    });

    test('reads transcript status from markdown sidecar', () async {
      await archive.writeDraft(
        messageId: 'message:ready',
        attachmentId: 'attachment:ready',
        fileName: 'voice.m4a',
        fileSize: 4096,
        transcript: '已完成转写',
        createdAt: DateTime(2026, 6, 27, 3, 20),
      );

      expect(
        await archive.readStatus(
          messageId: 'message:ready',
          attachmentId: 'attachment:ready',
        ),
        AudioTranscriptStatus.ready,
      );
      expect(
        AudioTranscriptArchive.parseStatus('- status: `failed`'),
        AudioTranscriptStatus.failed,
      );
      expect(AudioTranscriptArchive.parseStatus('- status: `unknown`'), isNull);
    });

    test('reads transcript details for viewing and copying', () async {
      await archive.writeDraft(
        messageId: 'message:detail',
        attachmentId: 'attachment:detail',
        fileName: 'voice.m4a',
        fileSize: 4096,
        transcript: '第一句转写。\n第二句转写。',
        createdAt: DateTime(2026, 6, 27, 3, 30),
      );

      final details = await archive.readDetails(
        messageId: 'message:detail',
        attachmentId: 'attachment:detail',
      );

      expect(details, isNotNull);
      expect(details!.status, AudioTranscriptStatus.ready);
      expect(details.hasCopyableTranscript, true);
      expect(details.transcriptText, '第一句转写。\n第二句转写。');
      expect(details.displayText, '第一句转写。\n第二句转写。');
      expect(details.displayText, isNot(contains('/Users/sanbo')));
    });

    test('failed transcript details do not expose copyable body', () async {
      await archive.writeFailure(
        messageId: 'message:fail-detail',
        attachmentId: 'attachment:fail-detail',
        fileName: 'voice.m4a',
        fileSize: 4096,
        error: 'provider failed for /Users/sanbo/audio/voice.m4a',
        createdAt: DateTime(2026, 6, 27, 3, 40),
      );

      final details = await archive.readDetails(
        messageId: 'message:fail-detail',
        attachmentId: 'attachment:fail-detail',
      );

      expect(details, isNotNull);
      expect(details!.status, AudioTranscriptStatus.failed);
      expect(details.hasCopyableTranscript, false);
      expect(details.transcriptText, isNull);
      expect(details.displayText, contains('[已隐藏路径]'));
      expect(details.displayText, isNot(contains('/Users/sanbo')));
    });
  });
}
