import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;

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
  Future<String> transcribe(
    AudioTranscriptionInput input, {
    CancelToken? cancelToken,
  });
}

class FallbackSpeechToTextEngine implements SpeechToTextEngine {
  final List<SpeechToTextEngine> engines;

  const FallbackSpeechToTextEngine(this.engines);

  @override
  Future<String> transcribe(
    AudioTranscriptionInput input, {
    CancelToken? cancelToken,
  }) async {
    if (engines.isEmpty) {
      throw const AudioTranscriptionException('语音转文字引擎未配置');
    }
    if (cancelToken?.isCancelled == true) {
      throw const AudioTranscriptionException('语音转文字请求已取消');
    }

    final errors = <String>[];
    var hasEmptyTranscript = false;
    for (final engine in engines) {
      try {
        final transcript = (await engine.transcribe(
          input,
          cancelToken: cancelToken,
        )).trim();
        if (cancelToken?.isCancelled == true) {
          throw const AudioTranscriptionException('语音转文字请求已取消');
        }
        if (transcript.isNotEmpty) return transcript;
        hasEmptyTranscript = true;
      } on AudioTranscriptionException catch (error) {
        // Do not fall through to a native/fallback engine after cancellation:
        // a later engine succeeding must never turn a cancelled operation into
        // a successful transcript.
        if (cancelToken?.isCancelled == true) rethrow;
        final message = error.message.trim();
        if (message.isNotEmpty && !errors.contains(message)) {
          errors.add(message);
        }
      } catch (_) {
        if (cancelToken?.isCancelled == true) {
          throw const AudioTranscriptionException('语音转文字请求已取消');
        }
        const message = '语音转文字失败';
        if (!errors.contains(message)) errors.add(message);
      }
    }

    // An empty transcript is a valid terminal result only when every engine
    // answered successfully but found no speech. If a later fallback failed,
    // returning empty would hide the provider failure from the caller/UI.
    if (errors.isEmpty && hasEmptyTranscript) return '';
    throw AudioTranscriptionException(
      errors.isEmpty ? '语音转文字失败' : errors.join('；'),
    );
  }
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
    AudioTranscriptionJob job, {
    CancelToken? cancelToken,
  }) async {
    try {
      final transcript = (await engine.transcribe(
        AudioTranscriptionInput(
          audioPath: job.audioPath,
          fileName: job.fileName,
          fileSize: job.fileSize,
        ),
        cancelToken: cancelToken,
      )).trim();
      if (cancelToken?.isCancelled == true) {
        throw const AudioTranscriptionException('语音转文字请求已取消');
      }

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
