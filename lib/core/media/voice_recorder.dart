import 'dart:async';

import 'package:flutter/services.dart';

const String kVoiceRecorderChannelName = 'simichat/voice_recorder';

class VoiceRecordingResult {
  const VoiceRecordingResult({
    required this.path,
    required this.fileName,
    required this.mimeType,
    this.fileSize,
    this.durationMs,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int? fileSize;
  final int? durationMs;

  static VoiceRecordingResult fromMap(Map<dynamic, dynamic> map) {
    final path = map['path'];
    final fileName = map['fileName'];
    final mimeType = map['mimeType'];
    if (path is! String || path.trim().isEmpty) {
      throw const VoiceRecordingException('录音结果缺少文件路径');
    }
    if (fileName is! String || fileName.trim().isEmpty) {
      throw const VoiceRecordingException('录音结果缺少文件名');
    }
    return VoiceRecordingResult(
      path: path,
      fileName: fileName,
      mimeType: mimeType is String && mimeType.trim().isNotEmpty
          ? mimeType
          : 'audio/mp4',
      fileSize: _asInt(map['fileSize']),
      durationMs: _asInt(map['durationMs']),
    );
  }
}

class VoiceRecordingException implements Exception {
  const VoiceRecordingException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class VoiceRecorderPlatform {
  Future<void> startRecording();

  Future<VoiceRecordingResult> stopRecording();

  Future<void> cancelRecording();
}

class MethodChannelVoiceRecorder implements VoiceRecorderPlatform {
  const MethodChannelVoiceRecorder({
    MethodChannel channel = const MethodChannel(kVoiceRecorderChannelName),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> startRecording() async {
    try {
      await _channel.invokeMethod<void>('startRecording');
    } on PlatformException catch (e) {
      throw VoiceRecordingException(_messageForPlatformException(e));
    }
  }

  @override
  Future<VoiceRecordingResult> stopRecording() async {
    try {
      final result = await _channel.invokeMethod<Object?>('stopRecording');
      if (result is Map) return VoiceRecordingResult.fromMap(result);
      throw const VoiceRecordingException('录音结束失败：原生返回格式异常');
    } on PlatformException catch (e) {
      throw VoiceRecordingException(_messageForPlatformException(e));
    }
  }

  @override
  Future<void> cancelRecording() async {
    try {
      await _channel.invokeMethod<void>('cancelRecording');
    } on PlatformException catch (e) {
      throw VoiceRecordingException(_messageForPlatformException(e));
    }
  }

  static String _messageForPlatformException(PlatformException e) {
    return switch (e.code) {
      'PERMISSION_DENIED' => '麦克风权限被拒绝，请在系统设置中开启麦克风权限',
      'ALREADY_RECORDING' => '正在录音中，请先结束当前录音',
      'NOT_RECORDING' => '当前没有正在进行的录音',
      'RECORDING_TOO_SHORT' => '录音时间太短，请重新录制',
      _ => e.message?.trim().isNotEmpty == true ? e.message! : '录音失败：${e.code}',
    };
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
