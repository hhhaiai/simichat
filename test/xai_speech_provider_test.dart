import 'package:ai_chat_app/core/media/speech_provider_preset.dart';
import 'package:ai_chat_app/core/media/xai_speech_provider_profile.dart';
import 'package:ai_chat_app/core/media/xai_speech_to_text_engine.dart';
import 'package:ai_chat_app/core/media/xai_text_to_speech_engine.dart';
import 'package:ai_chat_app/shared/providers/audio_transcription_provider.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('xAI profile exposes REST paths without fabricated model names', () {
    final preset = findSpeechProviderPreset(kXaiSpeechProviderId);
    expect(preset, isNotNull);
    expect(preset!.baseUrl, kXaiSpeechProviderBaseUrl);
    expect(preset.sttModel, isEmpty);
    expect(preset.ttsModel, isEmpty);
    expect(preset.ttsVoice, kXaiDefaultTextToSpeechVoice);
    expect(preset.supportsStt, isTrue);
    expect(preset.supportsTts, isTrue);
    expect(preset.description, contains('/v1/stt'));
    expect(preset.description, contains('/v1/tts'));
    expect(preset.description, contains('WSS'));
  });

  test('STT xAI provider serializes selection and factory type', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechToTextConfigProvider.notifier);
    await notifier.ready;

    await notifier.saveXai(
      enabled: true,
      baseUrl: 'https://api.x.ai/v1/',
      apiKey: 'xai-stt-secret',
      language: 'zh',
    );

    final config = container.read(speechToTextConfigProvider);
    expect(config.provider, kSpeechToTextProviderXai);
    expect(config.model, isEmpty);
    expect(config.language, 'zh');
    expect(config.isConfigured, isTrue);
    expect(config.providerLabel, 'xAI STT');
    expect(config.statusLabel, contains('/v1/stt'));
    expect(config.statusLabel, contains('无模型字段'));
    expect(
      container.read(speechToTextEngineProvider),
      isA<XaiSpeechToTextEngine>(),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(kSpeechToTextProviderStorageKey),
      kSpeechToTextProviderXai,
    );
    expect(prefs.getString(kSpeechToTextModelStorageKey), isEmpty);
    expect(prefs.getString(kSpeechToTextLanguageStorageKey), 'zh');
  });

  test('STT generic settings save infers xAI from official Base URL', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechToTextConfigProvider.notifier);
    await notifier.ready;

    await notifier.saveOpenAiCompatible(
      enabled: true,
      baseUrl: 'https://api.x.ai',
      model: '',
      apiKey: 'xai-stt-secret',
    );

    expect(
      container.read(speechToTextConfigProvider).provider,
      kSpeechToTextProviderXai,
    );
    expect(
      container.read(speechToTextEngineProvider),
      isA<XaiSpeechToTextEngine>(),
    );
  });

  test('TTS xAI provider serializes language and factory type', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(textToSpeechConfigProvider.notifier);
    await notifier.ready;

    await notifier.saveXai(
      enabled: true,
      baseUrl: 'https://api.x.ai/v1',
      voice: 'eve',
      apiKey: 'xai-tts-secret',
      language: 'zh-CN',
      speed: '1.2',
      responseFormat: 'wav',
    );

    final config = container.read(textToSpeechConfigProvider);
    expect(config.provider, kTextToSpeechProviderXai);
    expect(config.model, isEmpty);
    expect(config.voice, 'eve');
    expect(config.language, 'zh-CN');
    expect(config.speed, '1.2');
    expect(config.responseFormat, 'wav');
    expect(config.isConfigured, isTrue);
    expect(config.providerLabel, 'xAI TTS');
    expect(config.statusLabel, contains('/v1/tts'));
    expect(config.statusLabel, contains('zh-CN'));
    expect(
      container.read(textToSpeechEngineProvider),
      isA<XaiTextToSpeechEngine>(),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(kTextToSpeechProviderStorageKey),
      kTextToSpeechProviderXai,
    );
    expect(prefs.getString(kTextToSpeechModelStorageKey), isEmpty);
    expect(prefs.getString(kTextToSpeechLanguageStorageKey), 'zh-CN');
  });

  test('TTS generic settings save infers xAI without a model field', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(textToSpeechConfigProvider.notifier);
    await notifier.ready;

    await notifier.saveOpenAiCompatible(
      enabled: true,
      baseUrl: 'https://api.x.ai',
      model: '',
      voice: 'custom-voice-id',
      apiKey: 'xai-tts-secret',
    );

    expect(
      container.read(textToSpeechConfigProvider).provider,
      kTextToSpeechProviderXai,
    );
    expect(
      container.read(textToSpeechEngineProvider),
      isA<XaiTextToSpeechEngine>(),
    );
  });
}
