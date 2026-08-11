import 'package:ai_chat_app/core/media/speech_provider_preset.dart';
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
      containsAll(['openai', 'custom_openai_compatible']),
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
