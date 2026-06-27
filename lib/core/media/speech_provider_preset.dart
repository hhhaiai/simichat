class SpeechProviderPreset {
  const SpeechProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.description,
    required this.docsUrl,
    this.sttModel,
    this.ttsModel,
    this.ttsVoice,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String description;
  final String docsUrl;
  final String? sttModel;
  final String? ttsModel;
  final String? ttsVoice;

  bool get supportsStt => sttModel != null;
  bool get supportsTts => ttsModel != null && ttsVoice != null;
}

const kSpeechProviderPresets = [
  SpeechProviderPreset(
    id: 'openai',
    name: 'OpenAI 官方',
    baseUrl: 'https://api.openai.com',
    sttModel: 'whisper-1',
    ttsModel: 'tts-1',
    ttsVoice: 'alloy',
    description: '官方 OpenAI Audio API，覆盖 STT 转写和 TTS 语音生成。',
    docsUrl: 'https://platform.openai.com/docs/guides/audio',
  ),
  SpeechProviderPreset(
    id: 'groq',
    name: 'Groq STT',
    baseUrl: 'https://api.groq.com/openai',
    sttModel: 'whisper-large-v3-turbo',
    description: 'Groq OpenAI 兼容音频转写接口，适合快速语音转文字。',
    docsUrl: 'https://console.groq.com/docs/speech-to-text',
  ),
  SpeechProviderPreset(
    id: 'custom_openai_compatible',
    name: '自定义 OpenAI 兼容',
    baseUrl: 'https://api.openai.com',
    sttModel: 'whisper-1',
    ttsModel: 'tts-1',
    ttsVoice: 'alloy',
    description: '用于兼容 /v1/audio/transcriptions 与 /v1/audio/speech 的自定义服务。',
    docsUrl: '',
  ),
];

List<SpeechProviderPreset> speechToTextPresets() => kSpeechProviderPresets
    .where((preset) => preset.supportsStt)
    .toList(growable: false);

List<SpeechProviderPreset> textToSpeechPresets() => kSpeechProviderPresets
    .where((preset) => preset.supportsTts)
    .toList(growable: false);

SpeechProviderPreset? findSpeechProviderPreset(String id) {
  for (final preset in kSpeechProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

SpeechProviderPreset? inferSpeechToTextPreset({
  required String baseUrl,
  required String model,
}) {
  final normalizedBaseUrl = _normalizeComparableUrl(baseUrl);
  final normalizedModel = model.trim();
  for (final preset in speechToTextPresets()) {
    if (_normalizeComparableUrl(preset.baseUrl) == normalizedBaseUrl &&
        preset.sttModel == normalizedModel) {
      return preset;
    }
  }
  return findSpeechProviderPreset('custom_openai_compatible');
}

SpeechProviderPreset? inferTextToSpeechPreset({
  required String baseUrl,
  required String model,
  required String voice,
}) {
  final normalizedBaseUrl = _normalizeComparableUrl(baseUrl);
  final normalizedModel = model.trim();
  final normalizedVoice = voice.trim();
  for (final preset in textToSpeechPresets()) {
    if (_normalizeComparableUrl(preset.baseUrl) == normalizedBaseUrl &&
        preset.ttsModel == normalizedModel &&
        preset.ttsVoice == normalizedVoice) {
      return preset;
    }
  }
  return findSpeechProviderPreset('custom_openai_compatible');
}

String _normalizeComparableUrl(String value) {
  var normalized = value.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized.endsWith('/v1')) {
    normalized = normalized.substring(0, normalized.length - 3);
  }
  return normalized.toLowerCase();
}
