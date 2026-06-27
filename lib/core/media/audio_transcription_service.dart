import 'dart:io';

import 'audio_transcript_archive.dart';

class AudioTranscriptionInput {
  final String audioPath;
  final String fileName;
  final int fileSize;

  const AudioTranscriptionInput({
    required this.audioPath,
    required this.fileName,
    required this.fileSize,
  });
}

abstract interface class SpeechToTextEngine {
  Future<String> transcribe(AudioTranscriptionInput input);
}

class AudioTranscriptionJob {
  final String messageId;
  final String attachmentId;
  final String audioPath;
  final String fileName;
  final int fileSize;

  const AudioTranscriptionJob({
    required this.messageId,
    required this.attachmentId,
    required this.audioPath,
    required this.fileName,
    required this.fileSize,
  });
}

class AudioTranscriptionResult {
  final String transcript;
  final File transcriptFile;

  const AudioTranscriptionResult({
    required this.transcript,
    required this.transcriptFile,
  });
}

class AudioTranscriptionException implements Exception {
  final String message;

  const AudioTranscriptionException(this.message);

  @override
  String toString() => message;
}

class AudioTranscriptionService {
  final AudioTranscriptArchive archive;
  final SpeechToTextEngine engine;

  const AudioTranscriptionService({
    required this.archive,
    required this.engine,
  });

  Future<AudioTranscriptionResult> transcribeAndArchive(
    AudioTranscriptionJob job,
  ) async {
    try {
      final transcript = (await engine.transcribe(
        AudioTranscriptionInput(
          audioPath: job.audioPath,
          fileName: job.fileName,
          fileSize: job.fileSize,
        ),
      )).trim();

      final transcriptFile = await archive.writeDraft(
        messageId: job.messageId,
        attachmentId: job.attachmentId,
        fileName: job.fileName,
        fileSize: job.fileSize,
        transcript: transcript,
      );
      return AudioTranscriptionResult(
        transcript: transcript,
        transcriptFile: transcriptFile,
      );
    } on AudioTranscriptionException catch (error) {
      await archive.writeFailure(
        messageId: job.messageId,
        attachmentId: job.attachmentId,
        fileName: job.fileName,
        fileSize: job.fileSize,
        error: error,
      );
      throw AudioTranscriptionException(
        AudioTranscriptArchive.sanitizeErrorMessage(error.message),
      );
    } catch (_) {
      await archive.writeFailure(
        messageId: job.messageId,
        attachmentId: job.attachmentId,
        fileName: job.fileName,
        fileSize: job.fileSize,
        error: '语音转文字失败，请检查 STT 配置或稍后重试。',
      );
      throw const AudioTranscriptionException('语音转文字失败');
    }
  }
}
