import 'dart:convert';

import 'package:ai_chat_app/core/archive/structured_data_backup.dart';
import 'package:ai_chat_app/core/media/audio_transcription_service.dart';
import 'package:ai_chat_app/core/media/speech_provider_preset.dart';
import 'package:ai_chat_app/shared/providers/audio_transcription_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('STT config persists encrypted key and builds engine', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechToTextConfigProvider.notifier);
    await notifier.ready;

    expect(container.read(speechToTextEngineProvider), isNull);

    await notifier.saveOpenAiCompatible(
      enabled: true,
      baseUrl: 'api.openai.com/v1/',
      model: ' whisper-1 ',
      apiKey: 'stt-secret-key',
    );

    final state = container.read(speechToTextConfigProvider);
    expect(state.isConfigured, true);
    expect(state.baseUrl, 'https://api.openai.com');
    expect(state.model, 'whisper-1');
    expect(container.read(speechToTextEngineProvider), isNotNull);

    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString(kSpeechToTextApiKeyStorageKey);
    expect(storedKey, isNotNull);
    expect(storedKey, isNot('stt-secret-key'));
    expect(prefs.getKeys(), contains(kSpeechToTextApiKeyStorageKey));

    final exported = await const StructuredDataBackupService()
        .exportSharedPreferences();
    if (exported != null) {
      final exportedText = utf8.decode(exported);
      expect(exportedText, isNot(contains('stt-secret-key')));
      expect(exportedText, isNot(contains(kSpeechToTextApiKeyStorageKey)));
      expect(exportedText, isNot(contains(kSpeechToTextBaseUrlStorageKey)));
    }
  });

  test('saving enabled STT without key is rejected', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechToTextConfigProvider.notifier);
    await notifier.ready;

    await expectLater(
      notifier.saveOpenAiCompatible(
        enabled: true,
        baseUrl: 'https://api.openai.com',
        model: 'whisper-1',
        apiKey: '',
      ),
      throwsA(anything),
    );
    expect(container.read(speechToTextEngineProvider), isNull);
  });

  test('STT config can be saved from a provider preset', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechToTextConfigProvider.notifier);
    await notifier.ready;
    final groq = findSpeechProviderPreset('groq')!;

    await notifier.saveOpenAiCompatible(
      enabled: true,
      baseUrl: groq.baseUrl,
      model: groq.sttModel!,
      apiKey: 'groq-secret-key',
    );

    final state = container.read(speechToTextConfigProvider);
    expect(state.baseUrl, 'https://api.groq.com/openai');
    expect(state.model, 'whisper-large-v3-turbo');
    expect(state.isConfigured, true);
    expect(
      inferSpeechToTextPreset(baseUrl: state.baseUrl, model: state.model)?.id,
      'groq',
    );
  });

  test('mimo asr language persists and validates', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(speechToTextConfigProvider.notifier).ready;

    await container
        .read(speechToTextConfigProvider.notifier)
        .saveOpenAiCompatible(
          enabled: true,
          baseUrl: 'https://api.dwchainless.com',
          model: 'mimo-v2.5-asr',
          apiKey: 'test-key',
          language: 'zh',
        );
    final config = container.read(speechToTextConfigProvider);
    expect(config.language, 'zh');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kSpeechToTextLanguageStorageKey), 'zh');

    await expectLater(
      container
          .read(speechToTextConfigProvider.notifier)
          .saveOpenAiCompatible(
            enabled: true,
            baseUrl: 'https://api.dwchainless.com',
            model: 'mimo-v2.5-asr',
            apiKey: 'test-key',
            language: 'jp',
          ),
      throwsA(isA<AudioTranscriptionException>()),
    );
  });
}
