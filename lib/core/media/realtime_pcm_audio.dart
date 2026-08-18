import 'dart:async';

import 'package:flutter/services.dart';

const kRealtimePcmAudioChannelName = 'simichat/realtime_pcm_audio';
const kRealtimePcmAudioEventChannelName = 'simichat/realtime_pcm_audio/events';

const kRealtimePcmInputSampleRate = 16000;
const kRealtimePcmOutputSampleRate = 24000;
const kRealtimePcmChannels = 1;
const kRealtimePcmBitsPerSample = 16;

enum RealtimePcmAudioErrorKind {
  unsupported,
  permission,
  invalidState,
  transport,
}

class RealtimePcmAudioException implements Exception {
  const RealtimePcmAudioException({
    required this.message,
    required this.kind,
    this.code,
  });

  final String message;
  final RealtimePcmAudioErrorKind kind;
  final String? code;

  @override
  String toString() => message;
}

/// Platform boundary for a realtime PCM16 microphone and speaker.
///
/// Input and output intentionally use different sample rates because the
/// current RealtimeVoiceConfig uses 16 kHz input and 24 kHz output.  The
/// platform implementation must not write these chunks to a file or expose
/// credentials through the channel.
abstract interface class RealtimePcmAudioPlatform {
  Stream<Uint8List> get inputPcm;

  Future<void> startCapture({
    int sampleRate = kRealtimePcmInputSampleRate,
    int channels = kRealtimePcmChannels,
    int bitsPerSample = kRealtimePcmBitsPerSample,
  });

  Future<void> stopCapture();

  Future<void> startPlayback({
    int sampleRate = kRealtimePcmOutputSampleRate,
    int channels = kRealtimePcmChannels,
    int bitsPerSample = kRealtimePcmBitsPerSample,
  });

  Future<void> writePlayback(Uint8List bytes);

  Future<void> stopPlayback();
}

/// Flutter platform-channel implementation used by Android and future iOS
/// native PCM adapters.
class MethodChannelRealtimePcmAudio implements RealtimePcmAudioPlatform {
  MethodChannelRealtimePcmAudio({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(kRealtimePcmAudioChannelName),
       _eventChannel =
           eventChannel ??
           const EventChannel(kRealtimePcmAudioEventChannelName);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<Uint8List>? _inputPcm;

  @override
  Stream<Uint8List> get inputPcm {
    return _inputPcm ??= _eventChannel.receiveBroadcastStream().map((value) {
      if (value is Uint8List) return Uint8List.fromList(value);
      if (value is List<int>) return Uint8List.fromList(value);
      throw const RealtimePcmAudioException(
        message: '实时 PCM 输入数据格式异常',
        kind: RealtimePcmAudioErrorKind.transport,
        code: 'INVALID_PCM_EVENT',
      );
    });
  }

  @override
  Future<void> startCapture({
    int sampleRate = kRealtimePcmInputSampleRate,
    int channels = kRealtimePcmChannels,
    int bitsPerSample = kRealtimePcmBitsPerSample,
  }) => _invokeUnit('startCapture', <String, Object>{
    'sampleRate': sampleRate,
    'channels': channels,
    'bitsPerSample': bitsPerSample,
  });

  @override
  Future<void> stopCapture() => _invokeUnit('stopCapture');

  @override
  Future<void> startPlayback({
    int sampleRate = kRealtimePcmOutputSampleRate,
    int channels = kRealtimePcmChannels,
    int bitsPerSample = kRealtimePcmBitsPerSample,
  }) => _invokeUnit('startPlayback', <String, Object>{
    'sampleRate': sampleRate,
    'channels': channels,
    'bitsPerSample': bitsPerSample,
  });

  @override
  Future<void> writePlayback(Uint8List bytes) async {
    if (bytes.isEmpty) return;
    await _invokeUnit('writePlayback', <String, Object>{'bytes': bytes});
  }

  @override
  Future<void> stopPlayback() => _invokeUnit('stopPlayback');

  Future<void> _invokeUnit(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    try {
      await _methodChannel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    } on MissingPluginException {
      throw const RealtimePcmAudioException(
        message: '当前平台未接入实时 PCM 音频能力',
        kind: RealtimePcmAudioErrorKind.unsupported,
        code: 'UNSUPPORTED_PLATFORM',
      );
    } catch (error) {
      throw RealtimePcmAudioException(
        message: '实时 PCM 音频操作失败',
        kind: RealtimePcmAudioErrorKind.transport,
        code: error.runtimeType.toString(),
      );
    }
  }

  RealtimePcmAudioException _mapPlatformException(PlatformException error) {
    final code = error.code.trim();
    final kind = switch (code) {
      'PERMISSION_DENIED' => RealtimePcmAudioErrorKind.permission,
      'UNSUPPORTED_PLATFORM' => RealtimePcmAudioErrorKind.unsupported,
      'INVALID_STATE' ||
      'ALREADY_CAPTURING' ||
      'ALREADY_PLAYING' => RealtimePcmAudioErrorKind.invalidState,
      _ => RealtimePcmAudioErrorKind.transport,
    };
    final message = switch (code) {
      'PERMISSION_DENIED' => '麦克风权限被拒绝，请在系统设置中开启麦克风权限',
      'UNSUPPORTED_PLATFORM' => '当前平台未接入实时 PCM 音频能力',
      'ALREADY_CAPTURING' => '实时麦克风已经在运行',
      'ALREADY_PLAYING' => '实时音频播放已经在运行',
      'INVALID_STATE' => '实时 PCM 音频当前状态不允许此操作',
      _ =>
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : '实时 PCM 音频操作失败',
    };
    return RealtimePcmAudioException(message: message, kind: kind, code: code);
  }
}

/// Test and non-native fallback.  It makes unsupported behavior explicit
/// instead of silently pretending that a file recorder is a PCM stream.
class UnsupportedRealtimePcmAudio implements RealtimePcmAudioPlatform {
  const UnsupportedRealtimePcmAudio();

  @override
  Stream<Uint8List> get inputPcm => const Stream<Uint8List>.empty();

  @override
  Future<void> startCapture({
    int sampleRate = kRealtimePcmInputSampleRate,
    int channels = kRealtimePcmChannels,
    int bitsPerSample = kRealtimePcmBitsPerSample,
  }) => _unsupported();

  @override
  Future<void> stopCapture() => _unsupported();

  @override
  Future<void> startPlayback({
    int sampleRate = kRealtimePcmOutputSampleRate,
    int channels = kRealtimePcmChannels,
    int bitsPerSample = kRealtimePcmBitsPerSample,
  }) => _unsupported();

  @override
  Future<void> writePlayback(Uint8List bytes) => _unsupported();

  @override
  Future<void> stopPlayback() => _unsupported();

  Future<void> _unsupported() async {
    throw const RealtimePcmAudioException(
      message: '当前平台未接入实时 PCM 音频能力',
      kind: RealtimePcmAudioErrorKind.unsupported,
      code: 'UNSUPPORTED_PLATFORM',
    );
  }
}
