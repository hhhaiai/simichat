import 'package:ai_chat_app/core/media/speech_provider_preset.dart';
import 'package:ai_chat_app/core/media/xai_speech_provider_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speech provider presets cover OpenAI compatible STT and TTS setup', () {
    final sttPresets = speechToTextPresets();
    final ttsPresets = textToSpeechPresets();

    expect(
      sttPresets.map((preset) => preset.id),
      containsAll(['openai', 'groq', 'custom_openai_compatible']),
    );
    expect(
      ttsPresets.map((preset) => preset.id),
      containsAll(['openai', 'dwchainless', 'custom_openai_compatible']),
    );

    final openAi = findSpeechProviderPreset('openai')!;
    expect(openAi.baseUrl, 'https://api.openai.com');
    expect(openAi.sttModel, 'whisper-1');
    expect(openAi.ttsModel, 'tts-1');
    expect(openAi.ttsVoice, 'alloy');
    expect(openAi.docsUrl, startsWith('https://'));

    final groq = findSpeechProviderPreset('groq')!;
    expect(groq.supportsStt, true);
    expect(groq.supportsTts, false);
    expect(groq.baseUrl, 'https://api.groq.com/openai');
    expect(groq.sttModel, 'whisper-large-v3-turbo');

    final xai = findSpeechProviderPreset('xai')!;
    expect(xai.supportsVoiceDesign, isFalse);
    expect(xai.supportsVoiceClone, isFalse);

    final simiRouter = findSpeechProviderPreset('dwchainless')!;
    expect(simiRouter.supportsVoiceDesign, isTrue);
    expect(simiRouter.supportsVoiceClone, isTrue);
  });

  test('presets expose explicit synthesis, clone, and design boundaries', () {
    final openAi = findSpeechProviderPreset('openai')!;
    expect(openAi.capabilities.supportsStt, isTrue);
    expect(openAi.capabilities.supportsTts, isTrue);
    expect(openAi.capabilities.voiceClone, isEmpty);
    expect(openAi.capabilities.voiceDesign, isEmpty);

    final groq = findSpeechProviderPreset('groq')!;
    expect(groq.capabilities.supportsStt, isTrue);
    expect(groq.capabilities.supportsTts, isFalse);
    expect(groq.capabilities.voiceClone, isEmpty);
    expect(groq.capabilities.voiceDesign, isEmpty);

    final simiRouter = findSpeechProviderPreset('dwchainless')!;
    expect(simiRouter.capabilities.supportsStt, isTrue);
    expect(simiRouter.capabilities.supportsTts, isTrue);
    expect(
      simiRouter.capabilities.voiceClone,
      contains(SpeechVoiceCloneSupport.referenceAudioInline),
    );
    expect(
      simiRouter.capabilities.voiceDesign,
      contains(SpeechVoiceDesignSupport.stylePrompt),
    );

    final xai = findSpeechProviderPreset(kXaiSpeechProviderId)!;
    expect(xai.capabilities.supportsStt, isTrue);
    expect(xai.capabilities.supportsTts, isTrue);
    expect(
      xai.capabilities.voiceClone,
      contains(SpeechVoiceCloneSupport.externalVoiceId),
    );
    expect(
      xai.capabilities.voiceClone,
      contains(SpeechVoiceCloneSupport.multipartUpload),
    );
    expect(xai.capabilities.voiceDesign, isEmpty);
    expect(xai.description, contains('custom voice ID'));

    final custom = findSpeechProviderPreset('custom_openai_compatible')!;
    expect(custom.capabilities.supportsStt, isTrue);
    expect(custom.capabilities.supportsTts, isTrue);
    expect(custom.capabilities.voiceClone, isEmpty);
    expect(custom.capabilities.voiceDesign, isEmpty);
  });

  test('speech provider preset inference normalizes /v1 suffix', () {
    expect(
      inferSpeechToTextPreset(
        baseUrl: 'https://api.groq.com/openai/v1/',
        model: 'whisper-large-v3-turbo',
      )?.id,
      'groq',
    );
    expect(
      inferTextToSpeechPreset(
        baseUrl: 'https://api.openai.com/v1',
        model: 'tts-1',
        voice: 'alloy',
      )?.id,
      'openai',
    );
    expect(
      inferSpeechToTextPreset(
        baseUrl: 'https://local.example/v1',
        model: 'x',
      )?.id,
      'custom_openai_compatible',
    );
  });

  test('simirouter speech preset covers mimo tts and asr', () {
    final preset = findSpeechProviderPreset('dwchainless');

    expect(preset, isNotNull);
    expect(preset!.baseUrl, 'https://api.dwchainless.com');
    expect(preset.sttModel, 'mimo-v2.5-asr');
    expect(preset.ttsModel, 'mimo-v2.5-tts');
    expect(preset.ttsVoice, 'alloy');
    expect(preset.supportsStt, isTrue);
    expect(preset.supportsTts, isTrue);
    expect(
      inferTextToSpeechPreset(
        baseUrl: 'https://api.dwchainless.com/v1',
        model: 'mimo-v2.5-tts',
        voice: 'alloy',
      )?.id,
      'dwchainless',
    );
    expect(
      inferTextToSpeechPreset(
        baseUrl: 'https://api.dwchainless.com/v1',
        model: 'MIMO-V2.5-TTS',
        voice: 'ALLOY',
      )?.id,
      'dwchainless',
    );
  });

  test('simirouter tts mode detection covers three models', () {
    expect(simiRouterTtsModeOf('mimo-v2.5-tts'), SimiRouterTtsMode.standard);
    expect(
      simiRouterTtsModeOf('mimo-v2.5-tts-voicedesign'),
      SimiRouterTtsMode.voiceDesign,
    );
    expect(
      simiRouterTtsModeOf('mimo-v2.5-tts-voiceclone'),
      SimiRouterTtsMode.voiceClone,
    );
    expect(
      simiRouterTtsModeOf('MIMO-V2.5-TTS-VoiceClone'),
      SimiRouterTtsMode.voiceClone,
    );
    expect(simiRouterTtsModeOf('mimo-v2.5-tts-unknown'), isNull);
    expect(simiRouterTtsModeOf('prefix-mimo-v2.5-tts'), isNull);
    expect(simiRouterTtsModeOf('tts-1'), isNull);
    expect(simiRouterTtsModeOf('whisper-1'), isNull);
    expect(isSimiRouterAsrModel('mimo-v2.5-asr'), isTrue);
    expect(isSimiRouterAsrModel(' MIMO-V2.5-ASR '), isTrue);
    expect(isSimiRouterAsrModel('mimo-v2.5-asr-preview'), isFalse);
  });

  test('simirouter preset voices expose 8 labelled options', () {
    expect(kSimiRouterTtsVoices, hasLength(8));
    expect(kSimiRouterTtsVoices.map((voice) => (voice.label, voice.value)), [
      ('冰糖 · 活泼少女', 'alloy'),
      ('茉莉 · 知性女声', 'echo'),
      ('Mia · 活泼英文女声', 'nova'),
      ('Chloe · 甜美梦幻', 'shimmer'),
      ('苏打 · 阳光少年', 'onyx'),
      ('白桦 · 成熟男声', 'fable'),
      ('Milo · 阳光英文男声', 'milo'),
      ('Dean · 沉稳温柔', 'dean'),
    ]);
    expect(simiRouterTtsVoiceLabel('alloy'), '冰糖 · 活泼少女');
    expect(simiRouterTtsVoiceLabel('echo'), '茉莉 · 知性女声');
    expect(simiRouterTtsVoiceLabel('nova'), 'Mia · 活泼英文女声');
    expect(simiRouterTtsVoiceLabel('shimmer'), 'Chloe · 甜美梦幻');
    expect(simiRouterTtsVoiceLabel('onyx'), '苏打 · 阳光少年');
    expect(simiRouterTtsVoiceLabel('fable'), '白桦 · 成熟男声');
    expect(simiRouterTtsVoiceLabel('milo'), 'Milo · 阳光英文男声');
    expect(simiRouterTtsVoiceLabel('dean'), 'Dean · 沉稳温柔');
    expect(simiRouterTtsVoiceLabel(' ALLOY '), '冰糖 · 活泼少女');
    expect(simiRouterTtsVoiceLabel('custom_voice'), 'custom_voice');
    expect(simiRouterTtsVoiceLabel('  '), isEmpty);
    expect(kSimiRouterTtsVoices.first.label, contains('冰糖'));
    expect(kSimiRouterTtsVoices.first.value, 'alloy');
    expect(kSimiRouterTtsVoices.last.label, contains('Dean'));
    expect(kSimiRouterTtsVoices.last.value, 'dean');
    expect(
      kSimiRouterTtsVoices.map((v) => v.value).toSet(),
      hasLength(8),
      reason: '音色 value 不应重复',
    );
    expect(kSimiRouterTtsMinSpeed, 0.25);
    expect(kSimiRouterTtsMaxSpeed, 4.0);
    expect(
      kSimiRouterTtsResponseFormats,
      containsAll(['mp3', 'wav', 'opus', 'aac', 'flac']),
    );
  });
}
