import 'xai_speech_provider_profile.dart';

/// Voice cloning is not one interchangeable feature across vendors.
///
/// `externalVoiceId` means the TTS adapter accepts an identifier created
/// elsewhere (for example in a vendor console). `referenceAudioInline` means
/// the current OpenAI-compatible adapter embeds local reference audio. The
/// `multipartUpload` flag means this project has a protocol adapter for
/// creating a vendor voice; it does not imply that the configured account is
/// entitled to use that vendor endpoint.
enum SpeechVoiceCloneSupport {
  externalVoiceId,
  referenceAudioInline,
  multipartUpload,
}

enum SpeechVoiceDesignSupport { stylePrompt }

/// Explicit capability contract used by provider selection and settings.
///
/// This is intentionally independent from `sttModel` / `ttsModel`: xAI Voice
/// REST batch endpoints do not take a model field at all.
class SpeechProviderCapabilities {
  const SpeechProviderCapabilities({
    this.supportsStt = false,
    this.supportsTts = false,
    this.voiceClone = const <SpeechVoiceCloneSupport>{},
    this.voiceDesign = const <SpeechVoiceDesignSupport>{},
    this.supportsRealtime = false,
  });

  final bool supportsStt;
  final bool supportsTts;
  final Set<SpeechVoiceCloneSupport> voiceClone;
  final Set<SpeechVoiceDesignSupport> voiceDesign;
  final bool supportsRealtime;

  bool get supportsVoiceClone => voiceClone.isNotEmpty;
  bool get supportsVoiceDesign => voiceDesign.isNotEmpty;
}

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
    this.supportsVoiceDesign = false,
    this.supportsVoiceClone = false,
    this.capabilities = const SpeechProviderCapabilities(),
  });

  final String id;
  final String name;
  final String baseUrl;
  final String description;
  final String docsUrl;
  final String? sttModel;
  final String? ttsModel;
  final String? ttsVoice;
  final bool supportsVoiceDesign;
  final bool supportsVoiceClone;
  final SpeechProviderCapabilities capabilities;

  bool get supportsStt => capabilities.supportsStt;
  bool get supportsTts => capabilities.supportsTts;
}

const kSpeechProviderPresets = [
  SpeechProviderPreset(
    id: 'openai',
    name: 'OpenAI 官方',
    baseUrl: 'https://api.openai.com',
    sttModel: 'whisper-1',
    ttsModel: 'tts-1',
    ttsVoice: 'alloy',
    capabilities: SpeechProviderCapabilities(
      supportsStt: true,
      supportsTts: true,
    ),
    description: '官方 OpenAI Audio API，覆盖 STT 转写和 TTS 语音生成。',
    docsUrl: 'https://platform.openai.com/docs/guides/audio',
  ),
  SpeechProviderPreset(
    id: 'groq',
    name: 'Groq STT',
    baseUrl: 'https://api.groq.com/openai',
    sttModel: 'whisper-large-v3-turbo',
    capabilities: SpeechProviderCapabilities(supportsStt: true),
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
    supportsVoiceDesign: true,
    supportsVoiceClone: true,
    capabilities: SpeechProviderCapabilities(
      supportsStt: true,
      supportsTts: true,
      voiceClone: {SpeechVoiceCloneSupport.referenceAudioInline},
      voiceDesign: {SpeechVoiceDesignSupport.stylePrompt},
    ),
    description: 'SimiRouter 语音：mimo TTS 三种模式（合成 / 声音设计 / 声音克隆）+ mimo ASR 识别。',
    docsUrl: 'https://api.dwchainless.com/',
  ),
  SpeechProviderPreset(
    id: kXaiSpeechProviderId,
    name: 'xAI Voice',
    baseUrl: kXaiSpeechProviderBaseUrl,
    // xAI batch STT/TTS deliberately has no model parameter.  Empty strings
    // keep the existing settings form selectable without fabricating a model;
    // the xAI adapters omit the field from the wire request.
    sttModel: '',
    ttsModel: '',
    ttsVoice: kXaiDefaultTextToSpeechVoice,
    capabilities: SpeechProviderCapabilities(
      supportsStt: true,
      supportsTts: true,
      voiceClone: {
        SpeechVoiceCloneSupport.externalVoiceId,
        SpeechVoiceCloneSupport.multipartUpload,
      },
    ),
    description:
        'xAI / Grok Voice REST：STT 使用 /v1/stt，TTS 使用 /v1/tts（text、voice_id、language）；custom voice ID 可由 /v1/custom-voices adapter 创建。当前不接入实时 WSS 与声音设计。',
    docsUrl: 'https://docs.x.ai/developers/rest-api-reference/inference/voice',
  ),
  SpeechProviderPreset(
    id: 'custom_openai_compatible',
    name: '自定义 OpenAI 兼容',
    baseUrl: 'https://api.openai.com',
    sttModel: 'whisper-1',
    ttsModel: 'tts-1',
    ttsVoice: 'alloy',
    capabilities: SpeechProviderCapabilities(
      supportsStt: true,
      supportsTts: true,
    ),
    description: '用于兼容 /v1/audio/transcriptions 与 /v1/audio/speech 的自定义服务。',
    docsUrl: '',
  ),
];

const kSimiRouterSpeechProviderId = 'dwchainless';

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

/// Returns true only for the explicit SimiRouter preset or its official host.
/// A generic OpenAI-compatible endpoint must not be treated as a provider for
/// SimiRouter-only voice design/clone fields merely because its model string
/// happens to contain `mimo`.
bool isSimiRouterSpeechProvider({String? provider, String? baseUrl}) {
  if (provider?.trim().toLowerCase() == kSimiRouterSpeechProviderId) {
    return true;
  }
  final candidate = baseUrl?.trim() ?? '';
  if (candidate.isEmpty) return false;
  try {
    var normalized = candidate;
    if (!normalized.contains('://')) normalized = 'https://$normalized';
    final host = Uri.tryParse(normalized)?.host.toLowerCase();
    return host == 'api.dwchainless.com';
  } catch (_) {
    return false;
  }
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
