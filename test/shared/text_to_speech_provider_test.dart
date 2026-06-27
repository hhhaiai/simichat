import 'dart:convert';

import 'package:ai_chat_app/core/archive/structured_data_backup.dart';
import 'package:ai_chat_app/core/media/speech_provider_preset.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('TTS config persists encrypted key and builds engine/service', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(textToSpeechConfigProvider.notifier);
    await notifier.ready;

    expect(container.read(textToSpeechEngineProvider), isNull);
    expect(container.read(textToSpeechServiceProvider), isNull);

    await notifier.saveOpenAiCompatible(
      enabled: true,
      baseUrl: 'api.openai.com/v1/',
      model: ' tts-1 ',
      voice: ' alloy ',
      apiKey: 'tts-secret-key',
    );

    final state = container.read(textToSpeechConfigProvider);
    expect(state.isConfigured, true);
    expect(state.baseUrl, 'https://api.openai.com');
    expect(state.model, 'tts-1');
    expect(state.voice, 'alloy');
    expect(container.read(textToSpeechEngineProvider), isNotNull);
    expect(container.read(textToSpeechServiceProvider), isNotNull);

    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString(kTextToSpeechApiKeyStorageKey);
    expect(storedKey, isNotNull);
    expect(storedKey, isNot('tts-secret-key'));
    expect(prefs.getKeys(), contains(kTextToSpeechApiKeyStorageKey));

    final exported = await const StructuredDataBackupService()
        .exportSharedPreferences();
    if (exported != null) {
      final exportedText = utf8.decode(exported);
      expect(exportedText, isNot(contains('tts-secret-key')));
      expect(exportedText, isNot(contains(kTextToSpeechApiKeyStorageKey)));
      expect(exportedText, isNot(contains(kTextToSpeechBaseUrlStorageKey)));
      expect(exportedText, isNot(contains(kTextToSpeechVoiceStorageKey)));
    }
  });

  test('saving enabled TTS without key is rejected', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(textToSpeechConfigProvider.notifier);
    await notifier.ready;

    await expectLater(
      notifier.saveOpenAiCompatible(
        enabled: true,
        baseUrl: 'https://api.openai.com',
        model: 'tts-1',
        voice: 'alloy',
        apiKey: '',
      ),
      throwsA(anything),
    );
    expect(container.read(textToSpeechEngineProvider), isNull);
    expect(container.read(textToSpeechServiceProvider), isNull);
  });

  test('TTS config can be saved from a provider preset', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(textToSpeechConfigProvider.notifier);
    await notifier.ready;
    final openAi = findSpeechProviderPreset('openai')!;

    await notifier.saveOpenAiCompatible(
      enabled: true,
      baseUrl: openAi.baseUrl,
      model: openAi.ttsModel!,
      voice: openAi.ttsVoice!,
      apiKey: 'tts-secret-key',
    );

    final state = container.read(textToSpeechConfigProvider);
    expect(state.baseUrl, 'https://api.openai.com');
    expect(state.model, 'tts-1');
    expect(state.voice, 'alloy');
    expect(state.isConfigured, true);
    expect(
      inferTextToSpeechPreset(
        baseUrl: state.baseUrl,
        model: state.model,
        voice: state.voice,
      )?.id,
      'openai',
    );
  });

  test('TTS keys are not part of structured backup allowlist', () async {
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechEnabledStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechProviderStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechBaseUrlStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechModelStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechVoiceStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechApiKeyStorageKey)),
    );
  });
}
