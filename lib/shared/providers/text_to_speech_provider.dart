import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';
import '../../core/media/audio_player.dart';
import '../../core/media/openai_text_to_speech_engine.dart';
import '../../core/media/reference_audio_store.dart';
import '../../core/media/speech_provider_preset.dart';
import '../../core/media/text_to_speech_service.dart';
import '../../core/media/xai_custom_voice_adapter.dart';
import '../../core/media/xai_speech_provider_profile.dart';
import '../../core/media/xai_text_to_speech_engine.dart';
import '../../core/database/dao/channel_dao.dart';

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
const kTextToSpeechProviderSimiRouter = kSimiRouterSpeechProviderId;
const kTextToSpeechProviderXai = kXaiSpeechProviderId;
// Compatibility alias for callers that spell the vendor acronym in caps.
const kTextToSpeechProviderXAI = kTextToSpeechProviderXai;
const kTextToSpeechLanguageStorageKey = 'tts_language_v1';
const kTextToSpeechChannelModelIdStorageKey = 'tts_channel_model_id_v1';

const kTextToSpeechDefaultSpeed = '1.0';
const kTextToSpeechDefaultResponseFormat = 'mp3';
const kTextToSpeechDefaultLanguage = kXaiDefaultSpeechLanguage;

typedef TextToSpeechVoiceLoader =
    Future<List<TextToSpeechVoiceOption>> Function(TextToSpeechConfig config);

/// Runtime voice catalog loader used by the chat task sheet.
///
/// Decryption stays in the provider layer; widgets only receive public voice
/// IDs and labels. Tests can override this provider without placing a key on
/// the wire or starting a real server.
final textToSpeechVoiceLoaderProvider = Provider<TextToSpeechVoiceLoader>((
  ref,
) {
  return (config) async {
    final encrypted = config.apiKeyEncrypted?.trim() ?? '';
    if (encrypted.isEmpty) {
      throw const TextToSpeechException('TTS API Key 未配置');
    }
    String apiKey;
    try {
      apiKey = KeyEncryptor.decrypt(encrypted).trim();
    } catch (_) {
      throw const TextToSpeechException('TTS API Key 解密失败，请重新配置');
    }
    if (apiKey.isEmpty) {
      throw const TextToSpeechException('TTS API Key 未配置');
    }
    return fetchTextToSpeechVoices(
      baseUrl: config.baseUrl,
      apiKey: apiKey,
      model: config.model.trim().isEmpty ? null : config.model,
    );
  };
});

String _inferTextToSpeechProviderFromBaseUrl(String baseUrl) {
  try {
    var candidate = baseUrl.trim();
    if (!candidate.contains('://')) candidate = 'https://$candidate';
    final host = Uri.tryParse(candidate)?.host.toLowerCase();
    if (host == 'api.x.ai' || host?.endsWith('.x.ai') == true) {
      return kTextToSpeechProviderXai;
    }
    if (host == 'api.dwchainless.com') {
      return kTextToSpeechProviderSimiRouter;
    }
  } catch (_) {}
  return kTextToSpeechProviderOpenAiCompatible;
}

String _providerForChannelModel(ChannelModelWithChannel model) {
  final id = model.channelModel.modelName.trim().toLowerCase();
  final base = model.channel.baseUrl.toLowerCase();
  if (id.startsWith('mimo-') || base.contains('dwchainless')) {
    return kTextToSpeechProviderSimiRouter;
  }
  return _inferTextToSpeechProviderFromBaseUrl(model.channel.baseUrl);
}

class TextToSpeechConfig {
  const TextToSpeechConfig({
    this.enabled = false,
    this.provider = kTextToSpeechProviderOpenAiCompatible,
    this.baseUrl = kDefaultTextToSpeechBaseUrl,
    this.model = kDefaultTextToSpeechModel,
    this.channelModelId,
    this.voice = kDefaultTextToSpeechVoice,
    this.apiKeyEncrypted,
    this.speed = kTextToSpeechDefaultSpeed,
    this.responseFormat = kTextToSpeechDefaultResponseFormat,
    this.language = kTextToSpeechDefaultLanguage,
    this.style = '',
    this.referenceAudioPath,
  });

  final bool enabled;
  final String provider;
  final String baseUrl;
  final String model;
  final String? channelModelId;
  final String voice;
  final String? apiKeyEncrypted;

  /// mimo TTS 语速（0.25-4，字符串存储避免浮点精度问题）。
  final String speed;

  /// 输出格式：mp3 / wav / opus / aac / flac。
  final String responseFormat;

  /// xAI TTS 要求的 BCP-47 / `auto` 语言值；OpenAI-compatible 与
  /// SimiRouter TTS 保留该配置但不会把它加入旧请求体。
  final String language;

  /// 声音设计模式的音色文字描述（mimo-v2.5-tts-voicedesign）。
  final String style;

  /// 声音克隆模式的参考音频本地路径（mimo-v2.5-tts-voiceclone）。
  final String? referenceAudioPath;

  bool get hasApiKey => apiKeyEncrypted != null && apiKeyEncrypted!.isNotEmpty;

  bool get isXai => isXaiSpeechProvider(provider);

  bool get isSimiRouter =>
      isSimiRouterSpeechProvider(provider: provider, baseUrl: baseUrl);

  SimiRouterTtsMode? get requestedMode => simiRouterTtsModeOf(model);

  bool get requestedModeHasProviderCapability {
    final mode = requestedMode;
    return mode == null || mode == SimiRouterTtsMode.standard || isSimiRouter;
  }

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
        (provider != kTextToSpeechProviderOpenAiCompatible &&
            !isXai &&
            !isSimiRouter) ||
        baseUrl.trim().isEmpty ||
        (isXai ? false : model.trim().isEmpty) ||
        voice.trim().isEmpty ||
        !hasApiKey) {
      return false;
    }
    final mode = simiRouterTtsModeOf(model);
    if (isXai) {
      try {
        normalizeXaiTextToSpeechSpeed(speed);
        normalizeXaiTextToSpeechResponseFormat(responseFormat);
        return true;
      } on TextToSpeechException {
        return false;
      }
    }
    return switch (mode) {
      SimiRouterTtsMode.voiceDesign =>
        style.trim().isNotEmpty && requestedModeHasProviderCapability,
      SimiRouterTtsMode.voiceClone =>
        hasUsableReferenceAudio && requestedModeHasProviderCapability,
      SimiRouterTtsMode.standard || null => true,
    };
  }

  String get providerLabel => isXai
      ? 'xAI TTS'
      : isSimiRouter
      ? 'SimiRouter TTS'
      : 'OpenAI 兼容 TTS';

  String get statusLabel {
    if (!enabled) return '未启用';
    if (provider != kTextToSpeechProviderOpenAiCompatible &&
        !isXai &&
        !isSimiRouter) {
      return '不支持的 TTS 厂商';
    }
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
    final mode = requestedMode;
    if ((mode == SimiRouterTtsMode.voiceDesign ||
            mode == SimiRouterTtsMode.voiceClone) &&
        !requestedModeHasProviderCapability) {
      final label = mode == SimiRouterTtsMode.voiceDesign ? '声音设计' : '声音克隆';
      return '$label已保存 · 当前 provider 未声明该能力，尚未验证';
    }
    if (isXai) {
      return '$providerLabel 已配置 · /v1/tts · voice_id=$voice · $language · $responseFormat · custom voice 创建需团队/Enterprise API 权限';
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
    String? channelModelId,
    String? voice,
    String? apiKeyEncrypted,
    String? speed,
    String? responseFormat,
    String? language,
    String? style,
    String? referenceAudioPath,
    bool clearApiKey = false,
    bool clearChannelModelId = false,
  }) {
    return TextToSpeechConfig(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      channelModelId: clearChannelModelId
          ? null
          : (channelModelId ?? this.channelModelId),
      voice: voice ?? this.voice,
      apiKeyEncrypted: clearApiKey
          ? null
          : (apiKeyEncrypted ?? this.apiKeyEncrypted),
      speed: speed ?? this.speed,
      responseFormat: responseFormat ?? this.responseFormat,
      language: language ?? this.language,
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

  Future<XaiCustomVoiceResult>? _activeXaiCustomVoiceCreation;

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
    final channelModelId = prefs
        .getString(kTextToSpeechChannelModelIdStorageKey)
        ?.trim();
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
    final language =
        prefs.getString(kTextToSpeechLanguageStorageKey) ??
        kTextToSpeechDefaultLanguage;
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
      channelModelId: channelModelId?.isNotEmpty == true
          ? channelModelId
          : null,
      voice: voice,
      apiKeyEncrypted: apiKeyEncrypted?.isEmpty == true
          ? null
          : apiKeyEncrypted,
      speed: speed,
      responseFormat: responseFormat,
      language: language,
      style: style,
      referenceAudioPath: referenceAudioPath,
    );
  }

  /// 模型选择器快捷配置：只替换模型名（如 mimo-v2.5-tts 系列），
  /// 其余 TTS 配置保持不变并持久化。
  Future<void> applyModel(String model) async {
    await ready;
    final trimmed = model.trim();
    if (trimmed.isEmpty || trimmed == state.model) return;
    state = state.copyWith(model: trimmed, clearChannelModelId: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kTextToSpeechModelStorageKey, trimmed);
      await prefs.remove(kTextToSpeechChannelModelIdStorageKey);
    } catch (_) {
      // 持久化失败不阻断本次使用。
    }
  }

  /// Bind TTS to a model already configured in Settings.  The channel keeps
  /// the source of truth for Base URL and encrypted API key; no duplicate
  /// credential form is required in the voice workspace.
  Future<void> applyChannelModel(ChannelModelWithChannel channelModel) async {
    await ready;
    final model = channelModel.channelModel.modelName.trim();
    final id = channelModel.channelModel.id.trim();
    if (model.isEmpty || id.isEmpty) return;
    final provider = _providerForChannelModel(channelModel);
    final next = state.copyWith(
      enabled: true,
      provider: provider,
      baseUrl: channelModel.channel.baseUrl,
      model: model,
      channelModelId: id,
      apiKeyEncrypted: channelModel.channel.apiKeyEncrypted,
    );
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kTextToSpeechEnabledStorageKey, true);
      await prefs.setString(kTextToSpeechProviderStorageKey, provider);
      await prefs.setString(kTextToSpeechBaseUrlStorageKey, next.baseUrl);
      await prefs.setString(kTextToSpeechModelStorageKey, model);
      await prefs.setString(kTextToSpeechChannelModelIdStorageKey, id);
      await prefs.setString(
        kTextToSpeechApiKeyStorageKey,
        channelModel.channel.apiKeyEncrypted,
      );
    } catch (_) {
      // The in-memory route remains usable if persistence is unavailable.
    }
  }

  Future<void> saveOpenAiCompatible({
    required bool enabled,
    required String baseUrl,
    required String model,
    required String voice,
    String? apiKey,
    String? speed,
    String? responseFormat,
    String? language,
    String? style,
    String? referenceAudioPath,
    String? provider,
  }) {
    final selectedProvider = provider?.trim().toLowerCase().isNotEmpty == true
        ? provider!.trim().toLowerCase()
        : _inferTextToSpeechProviderFromBaseUrl(baseUrl);
    return _save(
      enabled: enabled,
      provider: selectedProvider,
      baseUrl: baseUrl,
      model: model,
      voice: voice,
      apiKey: apiKey,
      speed: speed,
      responseFormat: responseFormat,
      language: language,
      style: style,
      referenceAudioPath: referenceAudioPath,
    );
  }

  /// Save xAI's batch REST profile.  xAI uses `voice_id` rather than a model
  /// and does not accept a local reference audio data URI.  Custom voices must
  /// be created separately through xAI `/v1/custom-voices` and then referenced
  /// by their returned voice id.
  Future<void> saveXai({
    required bool enabled,
    required String voice,
    String baseUrl = kXaiSpeechProviderBaseUrl,
    String? apiKey,
    String? language,
    String? speed,
    String? responseFormat,
  }) => _save(
    enabled: enabled,
    provider: kTextToSpeechProviderXai,
    baseUrl: baseUrl,
    model: '',
    voice: voice,
    apiKey: apiKey,
    language: language,
    speed: speed,
    responseFormat: responseFormat,
  );

  /// Creates an xAI custom voice through the real `/v1/custom-voices`
  /// multipart endpoint.  A blank [apiKey] means "use the encrypted key
  /// already stored in the current TTS config"; a non-blank value is only used
  /// for this request and can then be persisted by [saveXai].
  ///
  /// The settings dialog may pass an edited [baseUrl] before saving it.  The
  /// adapter still owns endpoint resolution and response validation, while
  /// this notifier owns decryption and the duplicate-request gate.
  Future<XaiCustomVoiceResult> createXaiCustomVoice({
    required XaiCustomVoiceRequest request,
    String? baseUrl,
    String? apiKey,
    CancelToken? cancelToken,
  }) {
    if (_activeXaiCustomVoiceCreation != null) {
      throw const XaiCustomVoiceException('xAI custom voice 创建正在进行，请稍候');
    }

    final token = _resolveXaiApiKey(apiKey);
    final selectedBaseUrl = baseUrl?.trim().isNotEmpty == true
        ? baseUrl!.trim()
        : state.baseUrl;
    final operation = XaiCustomVoiceAdapter(
      baseUrl: selectedBaseUrl,
      apiKey: token,
    ).createVoice(request, cancelToken: cancelToken);

    late Future<XaiCustomVoiceResult> guardedOperation;
    guardedOperation = operation.whenComplete(() {
      if (identical(_activeXaiCustomVoiceCreation, guardedOperation)) {
        _activeXaiCustomVoiceCreation = null;
      }
    });
    _activeXaiCustomVoiceCreation = guardedOperation;
    return guardedOperation;
  }

  /// Creates a custom voice and only then writes the returned, validated
  /// `voice_id` into the normal xAI TTS configuration.  The reference path is
  /// deliberately not a TTS configuration field: `/v1/tts` receives only the
  /// returned voice ID and never receives the local audio path.
  Future<XaiCustomVoiceResult> createAndSaveXaiCustomVoice({
    required bool enabled,
    required String baseUrl,
    required XaiCustomVoiceRequest request,
    String? apiKey,
    String? language,
    String? speed,
    String? responseFormat,
    CancelToken? cancelToken,
  }) async {
    final result = await createXaiCustomVoice(
      request: request,
      baseUrl: baseUrl,
      apiKey: apiKey,
      cancelToken: cancelToken,
    );
    await saveXai(
      enabled: enabled,
      baseUrl: baseUrl,
      voice: result.voiceId,
      apiKey: apiKey,
      language: language,
      speed: speed,
      responseFormat: responseFormat,
    );
    return result;
  }

  String _resolveXaiApiKey(String? apiKey) {
    final inlineKey = apiKey?.trim() ?? '';
    if (inlineKey.isNotEmpty) return inlineKey;

    final encryptedKey = state.apiKeyEncrypted?.trim() ?? '';
    if (encryptedKey.isEmpty) {
      throw const XaiCustomVoiceException('TTS API Key 未配置，请先填写 API Key');
    }
    try {
      final decryptedKey = KeyEncryptor.decrypt(encryptedKey).trim();
      if (decryptedKey.isEmpty) {
        throw const FormatException('empty key');
      }
      return decryptedKey;
    } catch (_) {
      throw const XaiCustomVoiceException('TTS API Key 解密失败，请重新输入 API Key');
    }
  }

  Future<void> _save({
    required bool enabled,
    required String provider,
    required String baseUrl,
    required String model,
    required String voice,
    String? apiKey,
    String? speed,
    String? responseFormat,
    String? language,
    String? style,
    String? referenceAudioPath,
  }) async {
    final normalizedBaseUrl = normalizeTextToSpeechBaseUrl(baseUrl);
    final xai = isXaiSpeechProvider(provider);
    final simiRouter = isSimiRouterSpeechProvider(
      provider: provider,
      baseUrl: normalizedBaseUrl,
    );
    final normalizedModel = xai ? '' : normalizeTextToSpeechModel(model);
    final normalizedVoice = normalizeTextToSpeechVoice(voice);
    final normalizedSpeed = xai
        ? normalizeXaiTextToSpeechSpeed(
            speed ??
                (isXaiSpeechProvider(state.provider)
                    ? state.speed
                    : kTextToSpeechDefaultSpeed),
          )
        : speed == null
        ? state.speed
        : normalizeTextToSpeechSpeed(speed);
    final normalizedFormat = xai
        ? normalizeXaiTextToSpeechResponseFormat(
            responseFormat ??
                (isXaiSpeechProvider(state.provider)
                    ? state.responseFormat
                    : kTextToSpeechDefaultResponseFormat),
          )
        : responseFormat == null
        ? state.responseFormat
        : normalizeTextToSpeechResponseFormat(responseFormat);
    final normalizedLanguage = xai
        ? normalizeXaiTextToSpeechLanguage(language ?? state.language)
        : language ?? state.language;
    // xAI's REST body has no style/reference-audio fields.  A custom voice is
    // represented only by its voice_id returned by /v1/custom-voices.
    final normalizedStyle = xai ? '' : (style ?? state.style).trim();
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
    final mode = xai ? null : simiRouterTtsModeOf(normalizedModel);
    final preservesChannelBinding =
        state.channelModelId != null &&
        state.model.trim() == normalizedModel &&
        state.baseUrl.trim() == normalizedBaseUrl &&
        state.provider ==
            (xai
                ? kTextToSpeechProviderXai
                : (simiRouter ? kTextToSpeechProviderSimiRouter : provider));
    if (enabled &&
        mode == SimiRouterTtsMode.voiceDesign &&
        normalizedStyle.isEmpty) {
      throw const TextToSpeechException('声音设计模式需要填写声音风格描述');
    }
    final requestedReferenceAudioPath = xai
        ? null
        : referenceAudioPath ?? state.referenceAudioPath;
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
      provider: xai
          ? kTextToSpeechProviderXai
          : (simiRouter ? kTextToSpeechProviderSimiRouter : provider),
      baseUrl: normalizedBaseUrl,
      model: normalizedModel,
      channelModelId: preservesChannelBinding ? state.channelModelId : null,
      voice: normalizedVoice,
      apiKeyEncrypted: encryptedKey,
      speed: normalizedSpeed,
      responseFormat: normalizedFormat,
      language: normalizedLanguage,
      style: normalizedStyle,
      referenceAudioPath: archivedReferenceAudioPath,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kTextToSpeechEnabledStorageKey, next.enabled);
    await prefs.setString(kTextToSpeechProviderStorageKey, next.provider);
    await prefs.setString(kTextToSpeechBaseUrlStorageKey, next.baseUrl);
    await prefs.setString(kTextToSpeechModelStorageKey, next.model);
    if (next.channelModelId == null) {
      await prefs.remove(kTextToSpeechChannelModelIdStorageKey);
    } else {
      await prefs.setString(
        kTextToSpeechChannelModelIdStorageKey,
        next.channelModelId!,
      );
    }
    await prefs.setString(kTextToSpeechVoiceStorageKey, next.voice);
    await prefs.setString(kTextToSpeechSpeedStorageKey, next.speed);
    await prefs.setString(
      kTextToSpeechResponseFormatStorageKey,
      next.responseFormat,
    );
    await prefs.setString(kTextToSpeechLanguageStorageKey, next.language);
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
    await prefs.remove(kTextToSpeechChannelModelIdStorageKey);
    await prefs.remove(kTextToSpeechVoiceStorageKey);
    await prefs.remove(kTextToSpeechApiKeyStorageKey);
    await prefs.remove(kTextToSpeechSpeedStorageKey);
    await prefs.remove(kTextToSpeechResponseFormatStorageKey);
    await prefs.remove(kTextToSpeechLanguageStorageKey);
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
    if (config.isXai) {
      return XaiTextToSpeechEngine(
        baseUrl: config.baseUrl,
        apiKey: apiKey,
        language: config.language,
        speed: config.speed,
        responseFormat: config.responseFormat,
      );
    }
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
  final service = TextToSpeechService(
    engine: engine,
    player: ref.watch(audioPlayerProvider),
    // The request engine sends `response_format` for every supported profile.
    // Persisting a WAV/AAC/FLAC/Opus response with a stale `.mp3` suffix makes
    // Android's player select the wrong decoder and presents as a silent play
    // failure. Keep the saved file extension identical to the wire contract.
    audioFileExtension: config.responseFormat,
  );
  ref.onDispose(service.dispose);
  return service;
});
