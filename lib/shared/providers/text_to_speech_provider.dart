import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';
import '../../core/media/audio_player.dart';
import '../../core/media/openai_text_to_speech_engine.dart';
import '../../core/media/text_to_speech_service.dart';

const kTextToSpeechEnabledStorageKey = 'tts_enabled_v1';
const kTextToSpeechProviderStorageKey = 'tts_provider_v1';
const kTextToSpeechBaseUrlStorageKey = 'tts_base_url_v1';
const kTextToSpeechModelStorageKey = 'tts_model_v1';
const kTextToSpeechVoiceStorageKey = 'tts_voice_v1';
const kTextToSpeechApiKeyStorageKey = 'tts_api_key_encrypted_v1';
const kTextToSpeechProviderOpenAiCompatible = 'openai_compatible';

class TextToSpeechConfig {
  const TextToSpeechConfig({
    this.enabled = false,
    this.provider = kTextToSpeechProviderOpenAiCompatible,
    this.baseUrl = kDefaultTextToSpeechBaseUrl,
    this.model = kDefaultTextToSpeechModel,
    this.voice = kDefaultTextToSpeechVoice,
    this.apiKeyEncrypted,
  });

  final bool enabled;
  final String provider;
  final String baseUrl;
  final String model;
  final String voice;
  final String? apiKeyEncrypted;

  bool get hasApiKey => apiKeyEncrypted != null && apiKeyEncrypted!.isNotEmpty;

  bool get isConfigured =>
      enabled &&
      provider == kTextToSpeechProviderOpenAiCompatible &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      voice.trim().isNotEmpty &&
      hasApiKey;

  String get providerLabel => 'OpenAI 兼容 TTS';

  String get statusLabel {
    if (!enabled) return '未启用';
    if (!hasApiKey) return '缺少 API Key';
    return '$providerLabel 已配置 · $model · $voice';
  }

  TextToSpeechConfig copyWith({
    bool? enabled,
    String? provider,
    String? baseUrl,
    String? model,
    String? voice,
    String? apiKeyEncrypted,
    bool clearApiKey = false,
  }) {
    return TextToSpeechConfig(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      voice: voice ?? this.voice,
      apiKeyEncrypted: clearApiKey
          ? null
          : (apiKeyEncrypted ?? this.apiKeyEncrypted),
    );
  }
}

final textToSpeechConfigProvider =
    StateNotifierProvider<TextToSpeechConfigNotifier, TextToSpeechConfig>((
      ref,
    ) {
      return TextToSpeechConfigNotifier();
    });

class TextToSpeechConfigNotifier extends StateNotifier<TextToSpeechConfig> {
  TextToSpeechConfigNotifier() : super(const TextToSpeechConfig()) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(kTextToSpeechEnabledStorageKey) ?? false;
    final provider =
        prefs.getString(kTextToSpeechProviderStorageKey) ??
        kTextToSpeechProviderOpenAiCompatible;
    final baseUrl =
        prefs.getString(kTextToSpeechBaseUrlStorageKey) ??
        kDefaultTextToSpeechBaseUrl;
    final model =
        prefs.getString(kTextToSpeechModelStorageKey) ??
        kDefaultTextToSpeechModel;
    final voice =
        prefs.getString(kTextToSpeechVoiceStorageKey) ??
        kDefaultTextToSpeechVoice;
    final apiKeyEncrypted = prefs.getString(kTextToSpeechApiKeyStorageKey);
    state = TextToSpeechConfig(
      enabled: enabled,
      provider: provider,
      baseUrl: baseUrl,
      model: model,
      voice: voice,
      apiKeyEncrypted: apiKeyEncrypted?.isEmpty == true
          ? null
          : apiKeyEncrypted,
    );
  }

  Future<void> saveOpenAiCompatible({
    required bool enabled,
    required String baseUrl,
    required String model,
    required String voice,
    String? apiKey,
  }) async {
    final normalizedBaseUrl = normalizeTextToSpeechBaseUrl(baseUrl);
    final normalizedModel = normalizeTextToSpeechModel(model);
    final normalizedVoice = normalizeTextToSpeechVoice(voice);
    final trimmedKey = apiKey?.trim() ?? '';
    final encryptedKey = trimmedKey.isNotEmpty
        ? KeyEncryptor.encrypt(trimmedKey)
        : state.apiKeyEncrypted;
    if (enabled && (encryptedKey == null || encryptedKey.isEmpty)) {
      throw const TextToSpeechException('请填写 TTS API Key');
    }

    final next = TextToSpeechConfig(
      enabled: enabled,
      provider: kTextToSpeechProviderOpenAiCompatible,
      baseUrl: normalizedBaseUrl,
      model: normalizedModel,
      voice: normalizedVoice,
      apiKeyEncrypted: encryptedKey,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kTextToSpeechEnabledStorageKey, next.enabled);
    await prefs.setString(kTextToSpeechProviderStorageKey, next.provider);
    await prefs.setString(kTextToSpeechBaseUrlStorageKey, next.baseUrl);
    await prefs.setString(kTextToSpeechModelStorageKey, next.model);
    await prefs.setString(kTextToSpeechVoiceStorageKey, next.voice);
    if (next.apiKeyEncrypted == null) {
      await prefs.remove(kTextToSpeechApiKeyStorageKey);
    } else {
      await prefs.setString(
        kTextToSpeechApiKeyStorageKey,
        next.apiKeyEncrypted!,
      );
    }
    state = next;
  }

  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kTextToSpeechEnabledStorageKey);
    await prefs.remove(kTextToSpeechProviderStorageKey);
    await prefs.remove(kTextToSpeechBaseUrlStorageKey);
    await prefs.remove(kTextToSpeechModelStorageKey);
    await prefs.remove(kTextToSpeechVoiceStorageKey);
    await prefs.remove(kTextToSpeechApiKeyStorageKey);
    state = const TextToSpeechConfig();
  }
}

final textToSpeechEngineProvider = Provider<TextToSpeechEngine?>((ref) {
  final config = ref.watch(textToSpeechConfigProvider);
  if (!config.isConfigured || config.apiKeyEncrypted == null) return null;
  try {
    final apiKey = KeyEncryptor.decrypt(config.apiKeyEncrypted!);
    if (apiKey.trim().isEmpty) return null;
    return OpenAiCompatibleTextToSpeechEngine(
      baseUrl: config.baseUrl,
      apiKey: apiKey,
      model: config.model,
    );
  } catch (_) {
    return null;
  }
});

final audioPlayerProvider = Provider<AudioPlayerPlatform>((ref) {
  return const MethodChannelAudioPlayer();
});

final textToSpeechServiceProvider = Provider<TextToSpeechService?>((ref) {
  final engine = ref.watch(textToSpeechEngineProvider);
  if (engine == null) return null;
  return TextToSpeechService(
    engine: engine,
    player: ref.watch(audioPlayerProvider),
  );
});
