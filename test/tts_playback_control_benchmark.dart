import 'dart:async';
import 'dart:io';

import 'package:ai_chat_app/core/media/audio_player.dart';
import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tts playback stop control benchmark', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'simichat_tts_stop_benchmark_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final player = _CountingAudioPlayer();
    final service = TextToSpeechService(
      engine: _StaticTextToSpeechEngine(),
      player: player,
      outputDirectory: () async => tempDir,
    );

    const iterations = 1000;
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await service.stop();
    }
    stopwatch.stop();

    // ignore: avoid_print
    print(
      'tts_playback_control_benchmark iterations=$iterations '
      'stop_ms=${stopwatch.elapsedMilliseconds} stops=${player.stops}',
    );
    expect(player.stops, iterations);
  });
}

class _StaticTextToSpeechEngine implements TextToSpeechEngine {
  @override
  Future<List<int>> synthesize(
    TextToSpeechInput input, {
    CancelToken? cancelToken,
  }) async => [1, 2, 3];
}

class _CountingAudioPlayer implements AudioPlayerPlatform {
  final _events = StreamController<AudioPlaybackEvent>.broadcast();
  var stops = 0;

  @override
  Stream<AudioPlaybackEvent> get events => _events.stream;

  @override
  Future<void> playFile(String audioPath) async {}

  @override
  Future<void> stop() async {
    stops++;
  }
}
