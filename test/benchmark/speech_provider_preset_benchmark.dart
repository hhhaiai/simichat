import 'package:ai_chat_app/core/media/speech_provider_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speech provider preset inference benchmark', () {
    const iterations = 10000;
    var matches = 0;
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      if (inferSpeechToTextPreset(
            baseUrl: i.isEven
                ? 'https://api.openai.com/v1'
                : 'https://api.groq.com/openai/v1/',
            model: i.isEven ? 'whisper-1' : 'whisper-large-v3-turbo',
          ) !=
          null) {
        matches++;
      }
      if (inferTextToSpeechPreset(
            baseUrl: 'https://api.openai.com/v1',
            model: i.isEven ? 'tts-1' : 'tts-1',
            voice: i.isEven ? 'alloy' : 'alloy',
          ) !=
          null) {
        matches++;
      }
    }
    stopwatch.stop();

    // ignore: avoid_print
    print(
      'speech_provider_preset_benchmark iterations=$iterations '
      'infer_ms=${stopwatch.elapsedMilliseconds} matches=$matches',
    );
    expect(matches, iterations * 2);
  });
}
