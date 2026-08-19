import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';
import '../../core/media/audio_transcription_service.dart';
import '../../core/media/openai_speech_to_text_engine.dart';
import '../../core/media/xai_speech_provider_profile.dart';
import '../../core/media/xai_speech_to_text_engine.dart';

const kSpeechToTextEnabledStorageKey = 'stt_enabled_v1';
const kSpeechToTextProviderStorageKey = 'stt_provider_v1';
const kSpeechToTextBaseUrlStorageKey = 'stt_base_url_v1';
const kSpeechToTextModelStorageKey = 'stt_model_v1';
const kSpeechToTextApiKeyStorageKey = 'stt_api_key_encrypted_v1';
const kSpeechToTextLanguageStorageKey = 'stt_language_v1';
const kSpeechToTextProviderOpenAiCompatible = 'openai_compatible';
const kSpeechToTextProviderXai = kXaiSpeechProviderId;
// Compatibility alias for callers that spell the vendor acronym in caps.
const kSpeechToTextProviderXAI = kSpeechToTextProviderXai;

/// STT 识别语言：auto / zh（中文）/ en（英文）。mimo-v2.5-asr 使用。
const kSpeechToTextLanguages = ['auto', 'zh', 'en'];

String _inferProviderFromBaseUrl(String baseUrl) {
  try {
    final host = Uri.parse(normalizeSpeechToTextBaseUrl(baseUrl)).host;
    if (host.toLowerCase() == 'api.x.ai' ||
        host.toLowerCase().endsWith('.x.ai')) {
      return kSpeechToTextProviderXai;
    }
  } catch (_) {}
  return kSpeechToTextProviderOpenAiCompatible;
}

class SpeechToTextConfig {
  const SpeechToTextConfig({
    this.enabled = false,
    this.provider = kSpeechToTextProviderOpenAiCompatible,
    this.baseUrl = kDefaultSpeechToTextBaseUrl,
    this.model = kDefaultSpeechToTextModel,
    this.apiKeyEncrypted,
    this.language = 'auto',
  });

  final bool enabled;
  final String provider;
  final String baseUrl;
  final String model;
  final String? apiKeyEncrypted;

  /// 识别语言：auto（自动）/ zh（中文）/ en（英文）。
  final String language;

  bool get hasApiKey => apiKeyEncrypted != null && apiKeyEncrypted!.isNotEmpty;

  bool get isXai => isXaiSpeechProvider(provider);

  bool get isConfigured =>
      enabled &&
      (provider == kSpeechToTextProviderOpenAiCompatible || isXai) &&
      baseUrl.trim().isNotEmpty &&
      (isXai || model.trim().isNotEmpty) &&
      hasApiKey;

  String get providerLabel => isXai ? 'xAI STT' : 'OpenAI 兼容 STT';

  String get statusLabel {
    if (!enabled) return '未启用';
    if (provider != kSpeechToTextProviderOpenAiCompatible && !isXai) {
      return '不支持的 STT 厂商';
    }
    if (!hasApiKey) return '缺少 API Key';
    return isXai
        ? '$providerLabel 已配置 · /v1/stt · 无模型字段'
        : '$providerLabel 已配置 · $model';
  }

  SpeechToTextConfig copyWith({
    bool? enabled,
    String? provider,
    String? baseUrl,
    String? model,
    String? apiKeyEncrypted,
    String? language,
    bool clearApiKey = false,
  }) {
    return SpeechToTextConfig(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKeyEncrypted: clearApiKey
          ? null
          : (apiKeyEncrypted ?? this.apiKeyEncrypted),
      language: language ?? this.language,
    );
  }
}

final speechToTextConfigProvider =
    StateNotifierProvider<SpeechToTextConfigNotifier, SpeechToTextConfig>((
      ref,
    ) {
      return SpeechToTextConfigNotifier();
    });

class SpeechToTextConfigNotifier extends StateNotifier<SpeechToTextConfig> {
  SpeechToTextConfigNotifier() : super(const SpeechToTextConfig()) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(kSpeechToTextEnabledStorageKey) ?? false;
    final provider =
        prefs.getString(kSpeechToTextProviderStorageKey) ??
        kSpeechToTextProviderOpenAiCompatible;
    final baseUrl =
        prefs.getString(kSpeechToTextBaseUrlStorageKey) ??
        kDefaultSpeechToTextBaseUrl;
    final model =
        prefs.getString(kSpeechToTextModelStorageKey) ??
        kDefaultSpeechToTextModel;
    final apiKeyEncrypted = prefs.getString(kSpeechToTextApiKeyStorageKey);
    final language = prefs.getString(kSpeechToTextLanguageStorageKey) ?? 'auto';
    state = SpeechToTextConfig(
      enabled: enabled,
      provider: provider,
      baseUrl: baseUrl,
      model: model,
      apiKeyEncrypted: apiKeyEncrypted?.isEmpty == true
          ? null
          : apiKeyEncrypted,
      language: language,
    );
  }

  /// 模型选择器快捷配置：只替换模型名（如 mimo-v2.5-asr），
  /// 其余 STT 配置保持不变并持久化。
  Future<void> applyModel(String model) async {
    await ready;
    final trimmed = model.trim();
    if (trimmed.isEmpty || trimmed == state.model) return;
    state = state.copyWith(model: trimmed);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kSpeechToTextModelStorageKey, trimmed);
    } catch (_) {
      // 持久化失败不阻断本次使用。
    }
  }

  Future<void> saveOpenAiCompatible({
    required bool enabled,
    required String baseUrl,
    required String model,
    String? apiKey,
    String? language,
    String? provider,
  }) {
    final selectedProvider = provider?.trim().toLowerCase().isNotEmpty == true
        ? provider!.trim().toLowerCase()
        : _inferProviderFromBaseUrl(baseUrl);
    return _save(
      enabled: enabled,
      provider: selectedProvider,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
      language: language,
    );
  }

  /// Save the xAI batch REST profile.  xAI STT has no model parameter; the
  /// persisted model string is intentionally empty and never reaches the
  /// `/v1/stt` request body.
  Future<void> saveXai({
    required bool enabled,
    String baseUrl = kXaiSpeechProviderBaseUrl,
    String? apiKey,
    String? language,
  }) => _save(
    enabled: enabled,
    provider: kSpeechToTextProviderXai,
    baseUrl: baseUrl,
    model: '',
    apiKey: apiKey,
    language: language,
  );

  Future<void> _save({
    required bool enabled,
    required String provider,
    required String baseUrl,
    required String model,
    String? apiKey,
    String? language,
  }) async {
    final normalizedBaseUrl = normalizeSpeechToTextBaseUrl(baseUrl);
    final xai = isXaiSpeechProvider(provider);
    final normalizedModel = xai ? '' : normalizeSpeechToTextModel(model);
    final normalizedLanguage = xai
        ? normalizeXaiSpeechLanguage(language ?? state.language)
        : language ?? state.language;
    if (!xai && !kSpeechToTextLanguages.contains(normalizedLanguage)) {
      throw const AudioTranscriptionException('不支持的识别语言');
    }
    final trimmedKey = apiKey?.trim() ?? '';
    final encryptedKey = trimmedKey.isNotEmpty
        ? KeyEncryptor.encrypt(trimmedKey)
        : state.apiKeyEncrypted;
    if (enabled && (encryptedKey == null || encryptedKey.isEmpty)) {
      throw const AudioTranscriptionException('请填写 STT API Key');
    }

    final next = SpeechToTextConfig(
      enabled: enabled,
      provider: xai ? kSpeechToTextProviderXai : provider,
      baseUrl: normalizedBaseUrl,
      model: normalizedModel,
      apiKeyEncrypted: encryptedKey,
      language: normalizedLanguage,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSpeechToTextEnabledStorageKey, next.enabled);
    await prefs.setString(kSpeechToTextProviderStorageKey, next.provider);
    await prefs.setString(kSpeechToTextBaseUrlStorageKey, next.baseUrl);
    await prefs.setString(kSpeechToTextModelStorageKey, next.model);
    await prefs.setString(kSpeechToTextLanguageStorageKey, next.language);
    if (next.apiKeyEncrypted == null) {
      await prefs.remove(kSpeechToTextApiKeyStorageKey);
    } else {
      await prefs.setString(
        kSpeechToTextApiKeyStorageKey,
        next.apiKeyEncrypted!,
      );
    }
    state = next;
  }

  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kSpeechToTextEnabledStorageKey);
    await prefs.remove(kSpeechToTextProviderStorageKey);
    await prefs.remove(kSpeechToTextBaseUrlStorageKey);
    await prefs.remove(kSpeechToTextModelStorageKey);
    await prefs.remove(kSpeechToTextApiKeyStorageKey);
    await prefs.remove(kSpeechToTextLanguageStorageKey);
    state = const SpeechToTextConfig();
  }
}

final speechToTextEngineProvider = Provider<SpeechToTextEngine?>((ref) {
  final config = ref.watch(speechToTextConfigProvider);
  if (!config.isConfigured || config.apiKeyEncrypted == null) return null;
  try {
    final apiKey = KeyEncryptor.decrypt(config.apiKeyEncrypted!);
    if (apiKey.trim().isEmpty) return null;
    // 单次语言覆盖优先：录音按钮长按选择只影响接下来的转录，不改设置。
    final language =
        ref.watch(sttLanguageOverrideProvider) ?? config.language;
    if (config.isXai) {
      return XaiSpeechToTextEngine(
        baseUrl: config.baseUrl,
        apiKey: apiKey,
        language: language,
      );
    }
    return OpenAiCompatibleSpeechToTextEngine(
      baseUrl: config.baseUrl,
      apiKey: apiKey,
      model: config.model,
      language: language,
    );
  } catch (_) {
    return null;
  }
});

/// 单次识别语言覆盖（auto / zh / en）。录音按钮长按选择后生效一次，
/// 发送转录后自动清除；为空表示沿用设置中的语言。
final sttLanguageOverrideProvider =
    StateNotifierProvider<SttLanguageOverrideNotifier, String?>((ref) {
      return SttLanguageOverrideNotifier();
    });

class SttLanguageOverrideNotifier extends StateNotifier<String?> {
  SttLanguageOverrideNotifier() : super(null);

  void set(String? language) {
    state = language;
  }

  void clear() {
    state = null;
  }
}
