import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';
import '../../core/media/audio_transcription_service.dart';
import '../../core/media/openai_speech_to_text_engine.dart';

const kSpeechToTextEnabledStorageKey = 'stt_enabled_v1';
const kSpeechToTextProviderStorageKey = 'stt_provider_v1';
const kSpeechToTextBaseUrlStorageKey = 'stt_base_url_v1';
const kSpeechToTextModelStorageKey = 'stt_model_v1';
const kSpeechToTextApiKeyStorageKey = 'stt_api_key_encrypted_v1';
const kSpeechToTextLanguageStorageKey = 'stt_language_v1';
const kSpeechToTextProviderOpenAiCompatible = 'openai_compatible';

/// STT 识别语言：auto / zh（中文）/ en（英文）。mimo-v2.5-asr 使用。
const kSpeechToTextLanguages = ['auto', 'zh', 'en'];

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

  bool get isConfigured =>
      enabled &&
      provider == kSpeechToTextProviderOpenAiCompatible &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      hasApiKey;

  String get providerLabel => 'OpenAI 兼容 STT';

  String get statusLabel {
    if (!enabled) return '未启用';
    if (!hasApiKey) return '缺少 API Key';
    return '$providerLabel 已配置 · $model';
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

  Future<void> saveOpenAiCompatible({
    required bool enabled,
    required String baseUrl,
    required String model,
    String? apiKey,
    String? language,
  }) async {
    final normalizedBaseUrl = normalizeSpeechToTextBaseUrl(baseUrl);
    final normalizedModel = normalizeSpeechToTextModel(model);
    final normalizedLanguage = language ?? state.language;
    if (!kSpeechToTextLanguages.contains(normalizedLanguage)) {
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
      provider: kSpeechToTextProviderOpenAiCompatible,
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
    return OpenAiCompatibleSpeechToTextEngine(
      baseUrl: config.baseUrl,
      apiKey: apiKey,
      model: config.model,
      language: config.language,
    );
  } catch (_) {
    return null;
  }
});
