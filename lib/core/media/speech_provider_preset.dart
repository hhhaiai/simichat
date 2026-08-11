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
    id: 'dwchainless',
    name: 'SimiRouter AI',
    baseUrl: 'https://api.dwchainless.com',
    sttModel: 'mimo-v2.5-asr',
    ttsModel: 'mimo-v2.5-tts',
    ttsVoice: 'alloy',
    description: 'SimiRouter 语音：mimo TTS 三种模式（合成 / 声音设计 / 声音克隆）+ mimo ASR 识别。',
    docsUrl: 'https://api.dwchainless.com/',
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

/// SimiRouter mimo TTS 的三种模型模式。
enum SimiRouterTtsMode {
  /// 普通语音合成：voice 音色。
  standard,

  /// 声音设计：style 文字描述生成音色。
  voiceDesign,

  /// 声音克隆：voice 传参考音频（base64 data URI）。
  voiceClone,
}

/// 根据模型名判断 SimiRouter mimo TTS 模式；非 SimiRouter 模型返回 null。
SimiRouterTtsMode? simiRouterTtsModeOf(String model) {
  final normalized = model.trim().toLowerCase();
  return switch (normalized) {
    'mimo-v2.5-tts' => SimiRouterTtsMode.standard,
    'mimo-v2.5-tts-voicedesign' => SimiRouterTtsMode.voiceDesign,
    'mimo-v2.5-tts-voiceclone' => SimiRouterTtsMode.voiceClone,
    _ => null,
  };
}

/// SimiRouter mimo ASR 的精确、大小写不敏感识别。
///
/// 不使用 `contains`，避免把未知后缀模型误当成已经适配的 ASR 协议。
bool isSimiRouterAsrModel(String model) =>
    model.trim().toLowerCase() == 'mimo-v2.5-asr';

/// SimiRouter mimo TTS 预设音色（中文名 + API voice 值）。
class SimiRouterTtsVoice {
  const SimiRouterTtsVoice(this.label, this.value);

  final String label;
  final String value;
}

const kSimiRouterTtsVoices = [
  SimiRouterTtsVoice('冰糖 · 活泼少女', 'alloy'),
  SimiRouterTtsVoice('茉莉 · 知性女生', 'echo'),
  SimiRouterTtsVoice('mia · 活泼英文女生', 'nova'),
  SimiRouterTtsVoice('Chioe · 甜美梦幻', 'shimmer'),
  SimiRouterTtsVoice('苏打 · 阳光少年', 'onyx'),
  SimiRouterTtsVoice('白桦 · 成熟男生', 'fable'),
  SimiRouterTtsVoice('milo · 阳光英文男生', 'milo'),
  SimiRouterTtsVoice('Dean · 沉稳温柔', 'dean'),
];

/// mimo TTS 支持的速度范围与输出格式。
const kSimiRouterTtsMinSpeed = 0.25;
const kSimiRouterTtsMaxSpeed = 4.0;
const kSimiRouterTtsResponseFormats = ['mp3', 'wav', 'opus', 'aac', 'flac'];

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
  final normalizedModel = model.trim().toLowerCase();
  for (final preset in speechToTextPresets()) {
    if (_normalizeComparableUrl(preset.baseUrl) == normalizedBaseUrl &&
        preset.sttModel?.toLowerCase() == normalizedModel) {
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
  final normalizedModel = model.trim().toLowerCase();
  final normalizedVoice = voice.trim().toLowerCase();
  for (final preset in textToSpeechPresets()) {
    if (_normalizeComparableUrl(preset.baseUrl) == normalizedBaseUrl &&
        preset.ttsModel?.toLowerCase() == normalizedModel &&
        preset.ttsVoice?.toLowerCase() == normalizedVoice) {
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
