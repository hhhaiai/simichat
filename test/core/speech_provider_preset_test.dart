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
}
