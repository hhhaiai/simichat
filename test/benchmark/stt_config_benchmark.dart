import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/shared/providers/audio_transcription_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stt config load and engine creation benchmark', () async {
    SharedPreferences.setMockInitialValues({
      kSpeechToTextEnabledStorageKey: true,
      kSpeechToTextProviderStorageKey: kSpeechToTextProviderOpenAiCompatible,
      kSpeechToTextBaseUrlStorageKey: 'https://api.openai.com',
      kSpeechToTextModelStorageKey: 'whisper-1',
      kSpeechToTextApiKeyStorageKey: KeyEncryptor.encrypt('stt-benchmark-key'),
    });

    const iterations = 100;
    final stopwatch = Stopwatch()..start();
    var engines = 0;
    for (var i = 0; i < iterations; i++) {
      final container = ProviderContainer();
      await container.read(speechToTextConfigProvider.notifier).ready;
      final engine = container.read(speechToTextEngineProvider);
      if (engine != null) engines++;
      container.dispose();
    }
    stopwatch.stop();

    // ignore: avoid_print
    print(
      'stt_config_benchmark iterations=$iterations '
      'load_ms=${stopwatch.elapsedMilliseconds} engines=$engines',
    );
    expect(engines, iterations);
  });
}
