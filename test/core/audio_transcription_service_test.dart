import 'dart:io';

import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:ai_chat_app/core/media/audio_transcription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioTranscriptionService', () {
    late Directory tempDir;
    late AudioTranscriptArchive archive;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'simichat_audio_transcription_',
      );
      archive = AudioTranscriptArchive(rootDirectory: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('transcribes audio and updates transcript markdown', () async {
      final engine = _FakeSpeechToTextEngine('  这是自动转写结果  ');
      final service = AudioTranscriptionService(
        archive: archive,
        engine: engine,
      );

      final result = await service.transcribeAndArchive(
        const AudioTranscriptionJob(
          messageId: 'message:1',
          attachmentId: 'attachment:1',
          audioPath: '/private/audio/voice.m4a',
          fileName: 'voice.m4a',
          fileSize: 2048,
        ),
      );

      expect(result.transcript, '这是自动转写结果');
      expect(engine.lastInput?.fileName, 'voice.m4a');
      expect(engine.lastInput?.fileSize, 2048);
      expect(engine.lastInput?.audioPath, '/private/audio/voice.m4a');

      final markdown = await result.transcriptFile.readAsString();
      expect(markdown, contains('- status: `ready`'));
      expect(markdown, contains('这是自动转写结果'));
      expect(markdown, isNot(contains('/private/audio/voice.m4a')));
    });

    test(
      'keeps transcript draft pending when engine returns empty text',
      () async {
        final service = AudioTranscriptionService(
          archive: archive,
          engine: _FakeSpeechToTextEngine('   '),
        );

        final result = await service.transcribeAndArchive(
          const AudioTranscriptionJob(
            messageId: 'message:empty',
            attachmentId: 'attachment:empty',
            audioPath: '/private/audio/empty.wav',
            fileName: 'empty.wav',
            fileSize: 1024,
          ),
        );

        expect(result.transcript, isEmpty);
        final markdown = await result.transcriptFile.readAsString();
        expect(markdown, contains('- status: `empty`'));
        expect(markdown, contains('未识别到文字'));
      },
    );

    test('sanitizes engine failures before surfacing them', () async {
      final service = AudioTranscriptionService(
        archive: archive,
        engine: _ThrowingSpeechToTextEngine(),
      );

      await expectLater(
        service.transcribeAndArchive(
          const AudioTranscriptionJob(
            messageId: 'message:fail',
            attachmentId: 'attachment:fail',
            audioPath: '/private/audio/fail.wav',
            fileName: 'fail.wav',
            fileSize: 1024,
          ),
        ),
        throwsA(
          isA<AudioTranscriptionException>()
              .having((e) => e.toString(), 'message', '语音转文字失败')
              .having(
                (e) => e.toString(),
                'does not expose local path',
                isNot(contains('/private/audio/fail.wav')),
              ),
        ),
      );

      final failedFile = archive.transcriptFile(
        messageId: 'message:fail',
        attachmentId: 'attachment:fail',
      );
      expect(await failedFile.exists(), true);
      final markdown = await failedFile.readAsString();
      expect(markdown, contains('- status: `failed`'));
      expect(markdown, contains('语音转文字失败'));
      expect(markdown, isNot(contains('/private/audio/fail.wav')));
    });

    test(
      'sanitizes custom transcription errors in archive and exception',
      () async {
        final service = AudioTranscriptionService(
          archive: archive,
          engine: _ThrowingAudioTranscriptionExceptionEngine(),
        );

        await expectLater(
          service.transcribeAndArchive(
            const AudioTranscriptionJob(
              messageId: 'message:custom-fail',
              attachmentId: 'attachment:custom-fail',
              audioPath: '/private/audio/custom.wav',
              fileName: 'custom.wav',
              fileSize: 1024,
            ),
          ),
          throwsA(
            isA<AudioTranscriptionException>()
                .having(
                  (e) => e.toString(),
                  'does not expose api key',
                  isNot(contains('sk-secret-token')),
                )
                .having(
                  (e) => e.toString(),
                  'does not expose local path',
                  isNot(contains('/private/audio/custom.wav')),
                ),
          ),
        );

        final failedFile = archive.transcriptFile(
          messageId: 'message:custom-fail',
          attachmentId: 'attachment:custom-fail',
        );
        final markdown = await failedFile.readAsString();
        expect(markdown, contains('- status: `failed`'));
        expect(markdown, contains('[已隐藏密钥]'));
        expect(markdown, contains('[已隐藏路径]'));
        expect(markdown, isNot(contains('sk-secret-token')));
        expect(markdown, isNot(contains('/private/audio/custom.wav')));
      },
    );
  });
}

class _FakeSpeechToTextEngine implements SpeechToTextEngine {
  final String transcript;
  AudioTranscriptionInput? lastInput;

  _FakeSpeechToTextEngine(this.transcript);

  @override
  Future<String> transcribe(AudioTranscriptionInput input) async {
    lastInput = input;
    return transcript;
  }
}

class _ThrowingSpeechToTextEngine implements SpeechToTextEngine {
  @override
  Future<String> transcribe(AudioTranscriptionInput input) async {
    throw Exception('provider failed for ${input.audioPath}');
  }
}

class _ThrowingAudioTranscriptionExceptionEngine implements SpeechToTextEngine {
  @override
  Future<String> transcribe(AudioTranscriptionInput input) async {
    throw AudioTranscriptionException(
      'STT provider rejected sk-secret-token for ${input.audioPath}',
    );
  }
}
