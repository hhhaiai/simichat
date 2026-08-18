import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_transcription_service.dart';

const String kNativeSpeechToTextChannelName = 'simichat/native_speech_to_text';

class NativeSpeechToTextEngine implements SpeechToTextEngine {
  const NativeSpeechToTextEngine({
    MethodChannel channel = const MethodChannel(kNativeSpeechToTextChannelName),
    this.localeIdentifier = 'zh-CN',
    this.enforceIosPlatform = true,
  }) : _channel = channel;

  final MethodChannel _channel;
  final String localeIdentifier;

  @visibleForTesting
  final bool enforceIosPlatform;

  @override
  Future<String> transcribe(
    AudioTranscriptionInput input, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw const AudioTranscriptionException('系统语音识别请求已取消');
    }
    if (enforceIosPlatform && !Platform.isIOS) {
      throw const AudioTranscriptionException('系统语音识别仅支持 iOS');
    }

    final path = input.audioPath.trim();
    if (path.isEmpty) {
      throw const AudioTranscriptionException('语音文件路径为空，无法转写');
    }
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const AudioTranscriptionException('语音文件不存在，无法转写');
    }

    try {
      final result = await _channel.invokeMethod<Object?>('transcribeFile', {
        'path': path,
        'localeIdentifier': localeIdentifier,
      });
      if (cancelToken?.isCancelled == true) {
        throw const AudioTranscriptionException('系统语音识别请求已取消');
      }
      return _extractText(result).trim();
    } on PlatformException catch (error) {
      throw AudioTranscriptionException(_safePlatformError(error));
    } catch (_) {
      throw const AudioTranscriptionException('系统语音识别失败，请稍后重试');
    }
  }

  static String _extractText(Object? result) {
    if (result is String) return result;
    if (result is Map) {
      final text = result['text'] ?? result['transcript'];
      if (text is String) return text;
    }
    return '';
  }

  static String _safePlatformError(PlatformException error) {
    switch (error.code) {
      case 'PERMISSION_DENIED':
        return '系统语音识别权限被拒绝，请在系统设置中允许语音识别';
      case 'PERMISSION_RESTRICTED':
        return '当前设备限制使用系统语音识别';
      case 'RECOGNIZER_UNAVAILABLE':
        return '系统语音识别暂不可用，请检查网络或稍后重试';
      case 'FILE_NOT_FOUND':
        return '语音文件不存在，无法转写';
      case 'OUTSIDE_APP_DATA':
        return '只能识别应用私有目录内的语音文件';
      case 'TIMEOUT':
        return '系统语音识别超时，请重新录制更清晰的语音';
      case 'RECOGNITION_FAILED':
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : '系统语音识别失败，请重新录制更清晰的语音';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : '系统语音识别失败';
    }
  }
}
