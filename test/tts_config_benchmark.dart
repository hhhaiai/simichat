import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('tts config load and engine creation benchmark', () async {
    SharedPreferences.setMockInitialValues({
      kTextToSpeechEnabledStorageKey: true,
      kTextToSpeechProviderStorageKey: kTextToSpeechProviderOpenAiCompatible,
      kTextToSpeechBaseUrlStorageKey: 'https://api.openai.com',
      kTextToSpeechModelStorageKey: 'tts-1',
      kTextToSpeechVoiceStorageKey: 'alloy',
      kTextToSpeechApiKeyStorageKey: KeyEncryptor.encrypt('tts-benchmark-key'),
    });

    const iterations = 100;
    final stopwatch = Stopwatch()..start();
    var engines = 0;
    var services = 0;
    for (var i = 0; i < iterations; i++) {
      final container = ProviderContainer();
      await container.read(textToSpeechConfigProvider.notifier).ready;
      final engine = container.read(textToSpeechEngineProvider);
      final service = container.read(textToSpeechServiceProvider);
      if (engine != null) engines++;
      if (service != null) services++;
      container.dispose();
    }
    stopwatch.stop();

    // ignore: avoid_print
    print(
      'tts_config_benchmark iterations=$iterations '
      'load_ms=${stopwatch.elapsedMilliseconds} '
      'engines=$engines services=$services',
    );
    expect(engines, iterations);
    expect(services, iterations);
  });
}
