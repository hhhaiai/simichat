import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_chat_app/core/media/realtime_pcm_audio.dart';
import 'package:ai_chat_app/core/media/realtime_voice_session.dart';
import 'package:ai_chat_app/shared/providers/realtime_voice_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSocket implements RealtimeVoiceSocket {
  final StreamController<Object?> incomingController =
      StreamController<Object?>.broadcast(sync: true);
  final List<Object> sent = <Object>[];

  @override
  Stream<Object?> get incoming => incomingController.stream;

  @override
  void add(Object message) => sent.add(message);

  void emit(Object message) => incomingController.add(message);

  @override
  Future<void> close({int? code, String? reason}) async {
    await incomingController.close();
  }
}

class _FakePcmAudio implements RealtimePcmAudioPlatform {
  final StreamController<Uint8List> inputController =
      StreamController<Uint8List>.broadcast(sync: true);
  final List<Uint8List> played = <Uint8List>[];
  int startCaptureCount = 0;
  int stopCaptureCount = 0;
  int startPlaybackCount = 0;
  int stopPlaybackCount = 0;

  @override
  Stream<Uint8List> get inputPcm => inputController.stream;

  @override
  Future<void> startCapture({
    int sampleRate = kRealtimePcmInputSampleRate,
    int channels = kRealtimePcmChannels,
    int bitsPerSample = kRealtimePcmBitsPerSample,
  }) async {
    expect(sampleRate, kRealtimePcmInputSampleRate);
    expect(channels, kRealtimePcmChannels);
    expect(bitsPerSample, kRealtimePcmBitsPerSample);
    startCaptureCount++;
  }

  @override
  Future<void> stopCapture() async => stopCaptureCount++;

  @override
  Future<void> startPlayback({
    int sampleRate = kRealtimePcmOutputSampleRate,
    int channels = kRealtimePcmChannels,
    int bitsPerSample = kRealtimePcmBitsPerSample,
  }) async {
    expect(sampleRate, kRealtimePcmOutputSampleRate);
    expect(channels, kRealtimePcmChannels);
    expect(bitsPerSample, kRealtimePcmBitsPerSample);
    startPlaybackCount++;
  }

  @override
  Future<void> writePlayback(Uint8List bytes) async {
    played.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> stopPlayback() async => stopPlaybackCount++;

  Future<void> dispose() => inputController.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unsupported platform is explicit', () async {
    const platform = UnsupportedRealtimePcmAudio();
    expect(
      platform.startCapture(),
      throwsA(
        isA<RealtimePcmAudioException>().having(
          (error) => error.kind,
          'kind',
          RealtimePcmAudioErrorKind.unsupported,
        ),
      ),
    );
  });

  test('controller streams capture PCM and queues output PCM', () async {
    SharedPreferences.setMockInitialValues({});
    final socket = _FakeSocket();
    final pcm = _FakePcmAudio();
    final controller = RealtimeVoiceController(
      connector: (_) async => socket,
      pcmAudio: pcm,
    );
    addTearDown(() async {
      controller.dispose();
      await pcm.dispose();
    });
    await controller.ready;
    await controller.saveConfig(
      controller.state.config.copyWith(
        endpoint: 'wss://example.test/v1/realtime',
        model: 'realtime-test-model',
        token: 'test-token',
      ),
    );
    await controller.connect();
    expect(controller.state.isConnected, isTrue);
    expect(controller.state.nativeAudioActive, isFalse);

    await controller.startNativeAudio();
    expect(controller.state.nativeAudioActive, isTrue);
    expect(pcm.startCaptureCount, 1);
    expect(pcm.startPlaybackCount, 1);

    final input = Uint8List.fromList([1, 2, 3, 4]);
    pcm.inputController.add(input);
    await Future<void>.delayed(Duration.zero);
    final inputEvents = socket.sent
        .whereType<String>()
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .where((event) => event['type'] == 'input_audio_buffer.append')
        .toList();
    expect(inputEvents, hasLength(1));
    expect(inputEvents.single['audio'], base64Encode(input));

    socket.emit(
      jsonEncode({
        'type': 'response.audio.delta',
        'delta': base64Encode([9, 8, 7]),
      }),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(pcm.played, [
      Uint8List.fromList([9, 8, 7]),
    ]);
    expect(controller.state.receivedAudioBytes, 3);

    await controller.stopNativeAudio();
    expect(controller.state.nativeAudioActive, isFalse);
    expect(pcm.stopCaptureCount, 1);
    expect(pcm.stopPlaybackCount, 1);
    await controller.disconnect();
  });

  test('controller refuses native audio before websocket connection', () async {
    SharedPreferences.setMockInitialValues({});
    final pcm = _FakePcmAudio();
    final controller = RealtimeVoiceController(pcmAudio: pcm);
    addTearDown(() async {
      controller.dispose();
      await pcm.dispose();
    });
    await controller.ready;

    expect(
      controller.startNativeAudio(),
      throwsA(isA<RealtimeVoiceSessionException>()),
    );
    expect(pcm.startCaptureCount, 0);
    expect(pcm.startPlaybackCount, 0);
  });
}
