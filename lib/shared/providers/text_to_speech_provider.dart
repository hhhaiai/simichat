import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';
import '../../core/media/audio_player.dart';
import '../../core/media/openai_text_to_speech_engine.dart';
import '../../core/media/reference_audio_store.dart';
import '../../core/media/speech_provider_preset.dart';
import '../../core/media/text_to_speech_service.dart';

const kTextToSpeechEnabledStorageKey = 'tts_enabled_v1';
const kTextToSpeechProviderStorageKey = 'tts_provider_v1';
const kTextToSpeechBaseUrlStorageKey = 'tts_base_url_v1';
const kTextToSpeechModelStorageKey = 'tts_model_v1';
const kTextToSpeechVoiceStorageKey = 'tts_voice_v1';
const kTextToSpeechApiKeyStorageKey = 'tts_api_key_encrypted_v1';
const kTextToSpeechSpeedStorageKey = 'tts_speed_v1';
const kTextToSpeechResponseFormatStorageKey = 'tts_response_format_v1';
const kTextToSpeechStyleStorageKey = 'tts_style_v1';
const kTextToSpeechReferenceAudioPathStorageKey = 'tts_reference_audio_path_v1';
const kTextToSpeechProviderOpenAiCompatible = 'openai_compatible';

const kTextToSpeechDefaultSpeed = '1.0';
const kTextToSpeechDefaultResponseFormat = 'mp3';

class TextToSpeechConfig {
  const TextToSpeechConfig({
    this.enabled = false,
    this.provider = kTextToSpeechProviderOpenAiCompatible,
    this.baseUrl = kDefaultTextToSpeechBaseUrl,
    this.model = kDefaultTextToSpeechModel,
    this.voice = kDefaultTextToSpeechVoice,
    this.apiKeyEncrypted,
    this.speed = kTextToSpeechDefaultSpeed,
    this.responseFormat = kTextToSpeechDefaultResponseFormat,
    this.style = '',
    this.referenceAudioPath,
  });

  final bool enabled;
  final String provider;
  final String baseUrl;
  final String model;
  final String voice;
  final String? apiKeyEncrypted;

  /// mimo TTS 语速（0.25-4，字符串存储避免浮点精度问题）。
  final String speed;

  /// 输出格式：mp3 / wav / opus / aac / flac。
  final String responseFormat;

  /// 声音设计模式的音色文字描述（mimo-v2.5-tts-voicedesign）。
  final String style;

  /// 声音克隆模式的参考音频本地路径（mimo-v2.5-tts-voiceclone）。
  final String? referenceAudioPath;

  bool get hasApiKey => apiKeyEncrypted != null && apiKeyEncrypted!.isNotEmpty;

  bool get hasUsableReferenceAudio {
    final path = referenceAudioPath?.trim();
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  bool get isConfigured {
    if (!enabled ||
        provider != kTextToSpeechProviderOpenAiCompatible ||
        baseUrl.trim().isEmpty ||
        model.trim().isEmpty ||
        voice.trim().isEmpty ||
        !hasApiKey) {
      return false;
    }
    return switch (simiRouterTtsModeOf(model)) {
      SimiRouterTtsMode.voiceDesign => style.trim().isNotEmpty,
      SimiRouterTtsMode.voiceClone => hasUsableReferenceAudio,
      SimiRouterTtsMode.standard || null => true,
    };
  }

  String get providerLabel => 'OpenAI 兼容 TTS';

  String get statusLabel {
    if (!enabled) return '未启用';
    if (!hasApiKey) return '缺少 API Key';
    if (simiRouterTtsModeOf(model) == SimiRouterTtsMode.voiceDesign &&
        style.trim().isEmpty) {
      return '缺少声音风格描述';
    }
    if (simiRouterTtsModeOf(model) == SimiRouterTtsMode.voiceClone &&
        !hasUsableReferenceAudio) {
      return referenceAudioPath?.trim().isNotEmpty == true
          ? '参考音频已失效，请重新选择'
          : '缺少声音克隆参考音频';
    }
    final modeLabel = switch (simiRouterTtsModeOf(model)) {
      SimiRouterTtsMode.voiceDesign => '声音设计',
      SimiRouterTtsMode.voiceClone => '声音克隆',
      SimiRouterTtsMode.standard || null => voice,
    };
    return '$providerLabel 已配置 · $model · $modeLabel';
  }

  TextToSpeechConfig copyWith({
    bool? enabled,
    String? provider,
    String? baseUrl,
    String? model,
    String? voice,
    String? apiKeyEncrypted,
    String? speed,
    String? responseFormat,
    String? style,
    String? referenceAudioPath,
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
      speed: speed ?? this.speed,
      responseFormat: responseFormat ?? this.responseFormat,
      style: style ?? this.style,
      referenceAudioPath: referenceAudioPath ?? this.referenceAudioPath,
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
  TextToSpeechConfigNotifier({ReferenceAudioStore? referenceAudioStore})
    : _referenceAudioStore = referenceAudioStore ?? const ReferenceAudioStore(),
      super(const TextToSpeechConfig()) {
    ready = _load();
  }

  final ReferenceAudioStore _referenceAudioStore;

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
    final speed =
        prefs.getString(kTextToSpeechSpeedStorageKey) ??
        kTextToSpeechDefaultSpeed;
    final responseFormat =
        prefs.getString(kTextToSpeechResponseFormatStorageKey) ??
        kTextToSpeechDefaultResponseFormat;
    final style = prefs.getString(kTextToSpeechStyleStorageKey) ?? '';
    var referenceAudioPath = prefs.getString(
      kTextToSpeechReferenceAudioPathStorageKey,
    );
    if (simiRouterTtsModeOf(model) == SimiRouterTtsMode.voiceClone &&
        referenceAudioPath?.isNotEmpty == true) {
      try {
        final archivedPath = await _referenceAudioStore.archiveWav(
          referenceAudioPath!,
        );
        referenceAudioPath = archivedPath;
        await prefs.setString(
          kTextToSpeechReferenceAudioPathStorageKey,
          archivedPath,
        );
      } on TextToSpeechException {
        // 缓存源已失效时清理配置；若只是私有目录暂时不可写，
        // 保留仍可读的原路径，避免一次存储异常丢失用户配置。
        final path = referenceAudioPath!;
        var sourceStillUsable = false;
        try {
          final file = File(path);
          final length = file.existsSync() ? file.lengthSync() : 0;
          sourceStillUsable =
              path.toLowerCase().endsWith('.wav') &&
              length > 0 &&
              length <= kTextToSpeechMaxReferenceAudioBytes;
        } catch (_) {}
        if (!sourceStillUsable) {
          referenceAudioPath = null;
          await prefs.remove(kTextToSpeechReferenceAudioPathStorageKey);
        }
      }
    }
    state = TextToSpeechConfig(
      enabled: enabled,
      provider: provider,
      baseUrl: baseUrl,
      model: model,
      voice: voice,
      apiKeyEncrypted: apiKeyEncrypted?.isEmpty == true
          ? null
          : apiKeyEncrypted,
      speed: speed,
      responseFormat: responseFormat,
      style: style,
      referenceAudioPath: referenceAudioPath,
    );
  }

  Future<void> saveOpenAiCompatible({
    required bool enabled,
    required String baseUrl,
    required String model,
    required String voice,
    String? apiKey,
    String? speed,
    String? responseFormat,
    String? style,
    String? referenceAudioPath,
  }) async {
    final normalizedBaseUrl = normalizeTextToSpeechBaseUrl(baseUrl);
    final normalizedModel = normalizeTextToSpeechModel(model);
    final normalizedVoice = normalizeTextToSpeechVoice(voice);
    final normalizedSpeed = speed == null
        ? state.speed
        : normalizeTextToSpeechSpeed(speed);
    final normalizedFormat = responseFormat == null
        ? state.responseFormat
        : normalizeTextToSpeechResponseFormat(responseFormat);
    final normalizedStyle = (style ?? state.style).trim();
    if (normalizedStyle.length > 500) {
      throw const TextToSpeechException('声音风格描述过长（最多 500 字）');
    }
    final trimmedKey = apiKey?.trim() ?? '';
    final encryptedKey = trimmedKey.isNotEmpty
        ? KeyEncryptor.encrypt(trimmedKey)
        : state.apiKeyEncrypted;
    if (enabled && (encryptedKey == null || encryptedKey.isEmpty)) {
      throw const TextToSpeechException('请填写 TTS API Key');
    }
    final mode = simiRouterTtsModeOf(normalizedModel);
    if (enabled &&
        mode == SimiRouterTtsMode.voiceDesign &&
        normalizedStyle.isEmpty) {
      throw const TextToSpeechException('声音设计模式需要填写声音风格描述');
    }
    final requestedReferenceAudioPath =
        referenceAudioPath ?? state.referenceAudioPath;
    if (enabled &&
        mode == SimiRouterTtsMode.voiceClone &&
        requestedReferenceAudioPath?.isNotEmpty != true) {
      throw const TextToSpeechException('声音克隆需要选择参考音频');
    }

    final previousReferenceAudioPath = state.referenceAudioPath;
    String? archivedReferenceAudioPath;
    if (mode == SimiRouterTtsMode.voiceClone &&
        requestedReferenceAudioPath?.isNotEmpty == true) {
      archivedReferenceAudioPath = await _referenceAudioStore.archiveWav(
        requestedReferenceAudioPath!,
      );
    }

    final next = TextToSpeechConfig(
      enabled: enabled,
      provider: kTextToSpeechProviderOpenAiCompatible,
      baseUrl: normalizedBaseUrl,
      model: normalizedModel,
      voice: normalizedVoice,
      apiKeyEncrypted: encryptedKey,
      speed: normalizedSpeed,
      responseFormat: normalizedFormat,
      style: normalizedStyle,
      referenceAudioPath: archivedReferenceAudioPath,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kTextToSpeechEnabledStorageKey, next.enabled);
    await prefs.setString(kTextToSpeechProviderStorageKey, next.provider);
    await prefs.setString(kTextToSpeechBaseUrlStorageKey, next.baseUrl);
    await prefs.setString(kTextToSpeechModelStorageKey, next.model);
    await prefs.setString(kTextToSpeechVoiceStorageKey, next.voice);
    await prefs.setString(kTextToSpeechSpeedStorageKey, next.speed);
    await prefs.setString(
      kTextToSpeechResponseFormatStorageKey,
      next.responseFormat,
    );
    await prefs.setString(kTextToSpeechStyleStorageKey, next.style);
    if (next.referenceAudioPath == null || next.referenceAudioPath!.isEmpty) {
      await prefs.remove(kTextToSpeechReferenceAudioPathStorageKey);
    } else {
      await prefs.setString(
        kTextToSpeechReferenceAudioPathStorageKey,
        next.referenceAudioPath!,
      );
    }
    if (next.apiKeyEncrypted == null) {
      await prefs.remove(kTextToSpeechApiKeyStorageKey);
    } else {
      await prefs.setString(
        kTextToSpeechApiKeyStorageKey,
        next.apiKeyEncrypted!,
      );
    }
    state = next;
    if (previousReferenceAudioPath != next.referenceAudioPath) {
      try {
        await _referenceAudioStore.deleteManaged(previousReferenceAudioPath);
      } catch (_) {
        // 配置已成功持久化，旧文件清理失败不应误报“保存失败”。
      }
    }
  }

  Future<void> clearConfig() async {
    final previousReferenceAudioPath = state.referenceAudioPath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kTextToSpeechEnabledStorageKey);
    await prefs.remove(kTextToSpeechProviderStorageKey);
    await prefs.remove(kTextToSpeechBaseUrlStorageKey);
    await prefs.remove(kTextToSpeechModelStorageKey);
    await prefs.remove(kTextToSpeechVoiceStorageKey);
    await prefs.remove(kTextToSpeechApiKeyStorageKey);
    await prefs.remove(kTextToSpeechSpeedStorageKey);
    await prefs.remove(kTextToSpeechResponseFormatStorageKey);
    await prefs.remove(kTextToSpeechStyleStorageKey);
    await prefs.remove(kTextToSpeechReferenceAudioPathStorageKey);
    state = const TextToSpeechConfig();
    try {
      await _referenceAudioStore.deleteManaged(previousReferenceAudioPath);
    } catch (_) {
      // 用户配置已清除，不让孤立文件清理失败阻断主交互。
    }
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
      speed: config.speed,
      responseFormat: config.responseFormat,
      style: config.style,
      referenceAudioPath: config.referenceAudioPath,
    );
  } catch (_) {
    return null;
  }
});

final audioPlayerProvider = Provider<AudioPlayerPlatform>((ref) {
  return const MethodChannelAudioPlayer();
});

final textToSpeechServiceProvider = Provider<TextToSpeechService?>((ref) {
  final config = ref.watch(textToSpeechConfigProvider);
  final engine = ref.watch(textToSpeechEngineProvider);
  if (engine == null) return null;
  return TextToSpeechService(
    engine: engine,
    player: ref.watch(audioPlayerProvider),
    audioFileExtension: simiRouterTtsModeOf(config.model) == null
        ? 'mp3'
        : config.responseFormat,
  );
});
