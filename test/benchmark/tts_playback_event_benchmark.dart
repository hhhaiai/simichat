import 'package:ai_chat_app/core/media/audio_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tts playback native event parsing benchmark', () {
    const iterations = 10000;
    var parsed = 0;
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      final event = AudioPlaybackEvent.fromMethodCall(
        MethodCall('playbackCompleted', {'path': '/app/cache/tts-$i.mp3'}),
      );
      if (event?.type == AudioPlaybackEventType.completed &&
          event?.path == '/app/cache/tts-$i.mp3') {
        parsed++;
      }
    }
    stopwatch.stop();

    // ignore: avoid_print
    print(
      'tts_playback_event_benchmark iterations=$iterations '
      'parse_ms=${stopwatch.elapsedMilliseconds} parsed=$parsed',
    );
    expect(parsed, iterations);
  });
}
