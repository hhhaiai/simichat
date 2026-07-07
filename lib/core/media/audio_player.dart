import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class AudioPlayerPlatform {
  Stream<AudioPlaybackEvent> get events;

  Future<void> playFile(String audioPath);
  Future<void> stop();
}

enum AudioPlaybackEventType { completed, stopped, error }

class AudioPlaybackEvent {
  const AudioPlaybackEvent({required this.type, this.path, this.message});

  final AudioPlaybackEventType type;
  final String? path;
  final String? message;

  static AudioPlaybackEvent? fromMethodCall(MethodCall call) {
    final type = switch (call.method) {
      'playbackCompleted' => AudioPlaybackEventType.completed,
      'playbackStopped' => AudioPlaybackEventType.stopped,
      'playbackError' => AudioPlaybackEventType.error,
      _ => null,
    };
    if (type == null) return null;

    final arguments = call.arguments;
    String? path;
    String? message;
    if (arguments is Map) {
      final rawPath = arguments['path'];
      final rawMessage = arguments['message'];
      path = rawPath is String && rawPath.trim().isNotEmpty
          ? rawPath.trim()
          : null;
      message = rawMessage is String && rawMessage.trim().isNotEmpty
          ? rawMessage.trim()
          : null;
    }
    return AudioPlaybackEvent(type: type, path: path, message: message);
  }
}

class AudioPlaybackException implements Exception {
  final String message;

  const AudioPlaybackException(this.message);

  @override
  String toString() => message;
}

class MethodChannelAudioPlayer implements AudioPlayerPlatform {
  static const MethodChannel _channel = MethodChannel('simichat/audio_player');
  static final StreamController<AudioPlaybackEvent> _eventsController =
      StreamController<AudioPlaybackEvent>.broadcast();
  static var _methodCallHandlerRegistered = false;

  const MethodChannelAudioPlayer();

  @override
  Stream<AudioPlaybackEvent> get events {
    _ensureMethodCallHandler();
    return _eventsController.stream;
  }

  @override
  Future<void> playFile(String audioPath) async {
    await _playFile(audioPath);
  }

  Future<void> playFileForTesting(
    String audioPath, {
    bool skipAudioFocusRequest = false,
  }) async {
    // Flutter integration tests call this channel outside the normal user-tap
    // foreground flow. Production code must use playFile(), which requires the
    // native side to obtain audio focus before playback.
    await _playFile(audioPath, skipAudioFocusRequest: skipAudioFocusRequest);
  }

  Future<void> _playFile(
    String audioPath, {
    bool skipAudioFocusRequest = false,
  }) async {
    final path = audioPath.trim();
    if (path.isEmpty) {
      throw const AudioPlaybackException('缺少语音文件路径');
    }
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const AudioPlaybackException('语音文件不存在');
    }
    try {
      await _channel.invokeMethod<bool>('playFile', {
        'path': path,
        if (skipAudioFocusRequest)
          'skipAudioFocusRequest': skipAudioFocusRequest,
      });
    } on PlatformException catch (error) {
      throw AudioPlaybackException(_safePlatformError(error));
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } on PlatformException catch (error) {
      throw AudioPlaybackException(_safePlatformError(error));
    }
  }

  static void _ensureMethodCallHandler() {
    if (_methodCallHandlerRegistered) return;
    _methodCallHandlerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      final event = AudioPlaybackEvent.fromMethodCall(call);
      if (event != null) {
        _eventsController.add(event);
      }
    });
  }

  String _safePlatformError(PlatformException error) {
    switch (error.code) {
      case 'FILE_NOT_FOUND':
        return '语音文件不存在';
      case 'OUTSIDE_APP_DATA':
        return '只能播放应用私有目录内的语音文件';
      case 'AUDIO_FOCUS_DENIED':
        return '无法获取音频播放焦点';
      case 'PLAY_FAILED':
        return '语音播放失败，请稍后重试';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : '语音播放失败';
    }
  }
}
