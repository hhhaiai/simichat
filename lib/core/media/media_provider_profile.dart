import '../ai/model_capabilities.dart';
import 'media_model_capability.dart';
import 'media_request_options.dart';

/// 经过校验的 Options 到厂商 wire fields 的唯一映射位置。
///
/// profile 不保存 API Key、Base URL 或本地附件字节。图片 / 音频路径继续由
/// 网络 adapter 在最后一个请求边界转换为 multipart 或 data URI，避免本地路径
/// 泄漏进 JSON。
class MediaRequestProviderProfile {
  const MediaRequestProviderProfile({
    required this.id,
    required this.capability,
    this.modelCapabilities = const ModelCapabilities(),
    this.imageCountField,
    this.imageAspectRatioField,
    this.imageResolutionField,
    this.imageSizeField,
    this.imageQualityField,
    this.videoDurationField,
    this.videoAspectRatioField,
    this.videoResolutionField,
    this.referenceImagesField,
    this.firstFrameField,
    this.referenceAudioField,
  });

  static const openAiImageGeneration = MediaRequestProviderProfile(
    id: 'openai_images',
    capability: MediaModelCapability(
      supportedAspectRatios: [
        '1:1',
        '16:9',
        '9:16',
        '3:2',
        '2:3',
        '4:3',
        '3:4',
      ],
      supportedResolutions: ['1K', '2K', '4K'],
      supportedSizes: ['1024x1024', '1536x1024', '1024x1536'],
      supportedQualities: ['auto', 'low', 'medium', 'high'],
      maxReferenceImages: 4,
      supportsMultipleOutputs: true,
      minOutputs: 1,
      maxOutputs: 10,
    ),
    modelCapabilities: ModelCapabilities(
      providerId: 'openai_images',
      imageGenerationSupport: CapabilityState.supported,
      maxReferenceImages: 4,
      supportedImageCounts: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      supportedImageResolutions: ['1K', '2K', '4K'],
      supportedImageSizes: ['1024x1024', '1536x1024', '1024x1536'],
      supportedImageQualities: ['auto', 'low', 'medium', 'high'],
    ),
    imageCountField: 'n',
    imageAspectRatioField: 'aspect_ratio',
    imageResolutionField: 'resolution',
    imageSizeField: 'size',
    imageQualityField: 'quality',
    referenceImagesField: 'image',
  );

  /// xAI/Grok Imagine Images as exposed by the configured gateway.
  ///
  /// The mobile product contract explicitly exposes per-request quality,
  /// aspect ratio and 1K/2K/4K resolution for the Grok image rows returned by
  /// that gateway. Keep their wire names separate from OpenAI Images (`size`)
  /// so a visible selection is never silently discarded or renamed.
  static const xAiGrokImage = MediaRequestProviderProfile(
    id: 'xai_grok_images',
    capability: MediaModelCapability(
      supportedAspectRatios: [
        '1:1',
        '16:9',
        '9:16',
        '3:2',
        '2:3',
        '4:3',
        '3:4',
      ],
      supportedResolutions: ['1K', '2K', '4K'],
      supportedQualities: ['auto', 'low', 'medium', 'high'],
      maxReferenceImages: 1,
      supportsMultipleOutputs: true,
      minOutputs: 1,
      maxOutputs: 4,
    ),
    modelCapabilities: ModelCapabilities(
      providerId: 'xai_grok_images',
      imageGenerationSupport: CapabilityState.supported,
      maxReferenceImages: 1,
      supportedImageCounts: [1, 2, 3, 4],
      supportedAspectRatios: [
        '1:1',
        '16:9',
        '9:16',
        '3:2',
        '2:3',
        '4:3',
        '3:4',
      ],
      supportedImageResolutions: ['1K', '2K', '4K'],
      supportedImageQualities: ['auto', 'low', 'medium', 'high'],
    ),
    imageCountField: 'n',
    imageAspectRatioField: 'aspect_ratio',
    imageResolutionField: 'resolution',
    imageQualityField: 'quality',
    referenceImagesField: 'image',
  );

  /// Conservative OpenAI-compatible Images contract for an explicitly
  /// image-capable channel whose advanced profile is unknown. Text-to-image,
  /// one optional edit input and one output remain usable; unsupported fields
  /// are hidden rather than optimistically forwarded.
  static const openAiCompatibleImage = MediaRequestProviderProfile(
    id: 'openai_compatible_images',
    capability: MediaModelCapability(maxReferenceImages: 1),
    modelCapabilities: ModelCapabilities(
      providerId: 'openai_compatible_images',
      imageGenerationSupport: CapabilityState.supported,
      maxReferenceImages: 1,
      supportedImageCounts: [1],
    ),
    imageCountField: 'n',
    referenceImagesField: 'image',
  );

  static const openAiSoraVideo = MediaRequestProviderProfile(
    id: 'openai_sora_video',
    capability: MediaModelCapability(
      supportedAspectRatios: ['1:1', '16:9', '9:16'],
      supportedResolutions: ['480p', '720p', '1080p'],
      supportedDurations: [4, 8, 12],
      // The typed task keeps every selected reference. Providers that only
      // accept one can still narrow this in their channel capability; the
      // built-in OpenAI-compatible multipart contract supports repeated parts.
      maxReferenceImages: 4,
      supportsFirstFrame: true,
    ),
    modelCapabilities: ModelCapabilities(
      providerId: 'openai_sora_video',
      videoGenerationSupport: CapabilityState.supported,
      maxReferenceImages: 4,
      supportsFirstFrame: CapabilityState.supported,
      supportedVideoDurations: [4, 8, 12],
      supportedVideoAspectRatios: ['1:1', '16:9', '9:16'],
      supportedVideoResolutions: ['480p', '720p', '1080p'],
    ),
    videoDurationField: 'seconds',
    videoAspectRatioField: 'aspect_ratio',
    videoResolutionField: 'resolution',
    referenceImagesField: 'input_reference',
    firstFrameField: 'input_reference',
  );

  /// Generic OpenAI-compatible video route used by custom relay deployments.
  /// It deliberately declares explicit attachment field names so a typed task
  /// never falls back to a provider-specific guess or serializes local paths.
  static const openAiCompatibleVideo = MediaRequestProviderProfile(
    id: 'openai_compatible_video',
    capability: MediaModelCapability(
      supportedAspectRatios: ['1:1', '16:9', '9:16', '4:3', '3:4'],
      supportedResolutions: ['480p', '720p', '1080p'],
      supportedDurations: [4, 6, 8, 10, 12],
      maxReferenceImages: 4,
      supportsFirstFrame: true,
      supportsReferenceAudio: true,
    ),
    modelCapabilities: ModelCapabilities(
      providerId: 'openai_compatible_video',
      videoGenerationSupport: CapabilityState.supported,
      maxReferenceImages: 4,
      supportsFirstFrame: CapabilityState.supported,
      supportsReferenceAudio: CapabilityState.supported,
      supportedVideoDurations: [4, 6, 8, 10, 12],
      supportedVideoAspectRatios: ['1:1', '16:9', '9:16', '4:3', '3:4'],
      supportedVideoResolutions: ['480p', '720p', '1080p'],
    ),
    videoDurationField: 'duration',
    videoAspectRatioField: 'aspect_ratio',
    videoResolutionField: 'resolution',
    referenceImagesField: 'reference_images',
    firstFrameField: 'first_frame',
    referenceAudioField: 'reference_audio',
  );

  static const customAsyncVideo = MediaRequestProviderProfile(
    id: 'custom_async_video',
    capability: MediaModelCapability(
      supportedAspectRatios: ['1:1', '16:9', '9:16', '4:3', '3:4'],
      supportedResolutions: ['480p', '720p', '1080p'],
      supportedDurations: [4, 6, 8, 10, 12],
      maxReferenceImages: 4,
      supportsFirstFrame: true,
      supportsReferenceAudio: true,
    ),
    modelCapabilities: ModelCapabilities(
      providerId: 'custom_async_video',
      videoGenerationSupport: CapabilityState.supported,
      maxReferenceImages: 4,
      supportsFirstFrame: CapabilityState.supported,
      supportsReferenceAudio: CapabilityState.supported,
      supportedVideoDurations: [4, 6, 8, 10, 12],
      supportedVideoAspectRatios: ['1:1', '16:9', '9:16', '4:3', '3:4'],
      supportedVideoResolutions: ['480p', '720p', '1080p'],
    ),
    videoDurationField: 'duration',
    videoAspectRatioField: 'aspect_ratio',
    videoResolutionField: 'resolution',
    referenceImagesField: 'reference_images',
    firstFrameField: 'first_frame',
    referenceAudioField: 'reference_audio',
  );

  static const xAiGrokVideo = MediaRequestProviderProfile(
    id: 'xai_grok_video',
    capability: MediaModelCapability(
      supportedAspectRatios: ['1:1', '16:9', '9:16'],
      supportedResolutions: ['480p', '720p', '1080p'],
      supportedDurations: [4, 6, 8, 10],
      maxReferenceImages: 1,
    ),
    modelCapabilities: ModelCapabilities(
      providerId: 'xai_grok_video',
      videoGenerationSupport: CapabilityState.supported,
      maxReferenceImages: 1,
      supportsFirstFrame: CapabilityState.unsupported,
      supportsReferenceAudio: CapabilityState.unsupported,
      supportedVideoDurations: [4, 6, 8, 10],
      supportedVideoAspectRatios: ['1:1', '16:9', '9:16'],
      supportedVideoResolutions: ['480p', '720p', '1080p'],
    ),
    videoDurationField: 'duration',
    videoAspectRatioField: 'aspect_ratio',
    videoResolutionField: 'resolution',
    referenceImagesField: 'image',
  );

  static const openAiCompatibleSpeech = MediaRequestProviderProfile(
    id: 'openai_compatible_speech',
    capability: MediaModelCapability(
      supportedOutputFormats: ['mp3', 'wav', 'opus', 'aac', 'flac'],
      supportsReferenceAudio: true,
    ),
    modelCapabilities: ModelCapabilities(
      providerId: 'openai_compatible_speech',
      speechSynthesisSupport: CapabilityState.supported,
      voiceDesignSupport: CapabilityState.supported,
      voiceCloneSupport: CapabilityState.supported,
      supportedAudioOutputFormats: ['mp3', 'wav', 'opus', 'aac', 'flac'],
      supportsReferenceAudio: CapabilityState.supported,
    ),
    referenceAudioField: 'voice',
  );

  static const openAiCompatible = MediaRequestProviderProfile(
    id: 'openai_compatible',
    capability: MediaModelCapability.undeclared,
  );

  static const customAsync = MediaRequestProviderProfile(
    id: 'custom_async',
    capability: MediaModelCapability.undeclared,
  );

  /// 旧 Composer 还会传入时长 / 分辨率 Map；在 P2 面板全面改用
  /// [VideoGenerationOptions] 前，此函数是唯一的迁移桥。xAI 绝不能继续
  /// 从旧 `seconds` 字段直通上游，未知字段也不会被混入 xAI 请求。
  static Map<String, dynamic> normalizeLegacyVideoFields({
    required String profileId,
    required Map<String, dynamic> rawFields,
  }) {
    final normalizedId = profileId.trim().toLowerCase();
    if (normalizedId == 'xai_grok_video') {
      final duration = rawFields['duration'] ?? rawFields['seconds'];
      final aspectRatio = rawFields['aspect_ratio'] ?? rawFields['aspectRatio'];
      final resolution = rawFields['resolution'];
      return <String, dynamic>{
        if (duration is int && duration > 0) 'duration': duration,
        if (aspectRatio is String && aspectRatio.trim().isNotEmpty)
          'aspect_ratio': aspectRatio.trim(),
        if (resolution is String && resolution.trim().isNotEmpty)
          'resolution': resolution.trim(),
      };
    }
    if (normalizedId == 'openai_sora') {
      final seconds = rawFields['seconds'] ?? rawFields['duration'];
      final aspectRatio = rawFields['aspect_ratio'] ?? rawFields['aspectRatio'];
      final resolution = rawFields['resolution'];
      return <String, dynamic>{
        if (seconds is int && seconds > 0) 'seconds': seconds,
        if (aspectRatio is String && aspectRatio.trim().isNotEmpty)
          'aspect_ratio': aspectRatio.trim(),
        if (resolution is String && resolution.trim().isNotEmpty)
          'resolution': resolution.trim(),
      };
    }
    // Custom profiles retain pre-existing explicit user configuration until
    // their typed field map is configured in settings. New task panels never
    // call this migration method.
    return Map<String, dynamic>.unmodifiable(rawFields);
  }

  final String id;
  final MediaModelCapability capability;

  /// Full product-level capability set used by selectors and long-content
  /// delivery. [capability] stays as the compact P0 media validator until all
  /// existing call sites migrate to this three-state model.
  final ModelCapabilities modelCapabilities;
  final String? imageCountField;
  final String? imageAspectRatioField;
  final String? imageResolutionField;
  final String? imageSizeField;
  final String? imageQualityField;
  final String? videoDurationField;
  final String? videoAspectRatioField;
  final String? videoResolutionField;
  final String? referenceImagesField;
  final String? firstFrameField;
  final String? referenceAudioField;

  Map<String, dynamic> serializeSpeechSynthesis(
    SpeechSynthesisOptions options,
  ) {
    _throwIfInvalid(options.validationErrors(capability: capability));
    return <String, dynamic>{
      'input': options.input.trim(),
      'voice': options.voice.trim(),
      'speed': options.speed,
      if (_has(options.responseFormat))
        'response_format': options.responseFormat!.trim(),
    };
  }

  Map<String, dynamic> serializeVoiceDesign(VoiceDesignOptions options) {
    _throwIfInvalid(options.validationErrors(capability: capability));
    return <String, dynamic>{
      'input': options.input.trim(),
      'style': options.style.trim(),
      'speed': options.speed,
      if (_has(options.responseFormat))
        'response_format': options.responseFormat!.trim(),
    };
  }

  /// 参考音频字节由 transport 的显式音频附件字段编码；这个 mapper 只
  /// 输出已校验的文本参数，绝不会把本地 [VoiceCloneOptions.referenceAudio]
  /// 路径放进 JSON。
  Map<String, dynamic> serializeVoiceClone(VoiceCloneOptions options) {
    _throwIfInvalid(options.validationErrors(capability: capability));
    return <String, dynamic>{
      'input': options.input.trim(),
      'speed': options.speed,
      if (_has(options.responseFormat))
        'response_format': options.responseFormat!.trim(),
    };
  }

  Map<String, dynamic> serializeSpeechRecognition(
    SpeechRecognitionOptions options,
  ) {
    _throwIfInvalid(options.validationErrors(capability: capability));
    return <String, dynamic>{
      if (options.language.wireLanguage != null)
        'language': options.language.wireLanguage,
    };
  }

  Map<String, dynamic> serializeImageGeneration(
    ImageGenerationOptions options,
  ) {
    _throwIfInvalid(options.validationErrors(capability: capability));
    return <String, dynamic>{
      ?imageCountField: options.count,
      if (_has(options.aspectRatio) && imageAspectRatioField != null)
        imageAspectRatioField!: options.aspectRatio!.trim(),
      if (_has(options.resolution) && imageResolutionField != null)
        imageResolutionField!: options.resolution!.trim(),
      if (_has(options.size) && imageSizeField != null)
        imageSizeField!: options.size!.trim(),
      if (_has(options.quality) && imageQualityField != null)
        imageQualityField!: options.quality!.trim(),
    };
  }

  Map<String, dynamic> serializeVideoGeneration(
    VideoGenerationOptions options,
  ) {
    _throwIfInvalid(options.validationErrors(capability: capability));
    return <String, dynamic>{
      if (options.duration != null && videoDurationField != null)
        videoDurationField!: options.duration,
      if (_has(options.aspectRatio) && videoAspectRatioField != null)
        videoAspectRatioField!: options.aspectRatio!.trim(),
      if (_has(options.resolution) && videoResolutionField != null)
        videoResolutionField!: options.resolution!.trim(),
    };
  }

  void _throwIfInvalid(List<String> errors) {
    if (errors.isNotEmpty) throw ArgumentError(errors.join('；'));
  }

  static bool _has(String? value) => value != null && value.trim().isNotEmpty;
}

/// Resolve a centralized, credential-free media request profile. Runtime
/// pages call this registry instead of accumulating provider/model string
/// branches beside UI code. A persisted explicit profile id can be added to
/// the channel model later without changing any request sheet.
MediaRequestProviderProfile resolveImageRequestProfile({
  required String modelName,
  required String protocol,
  String baseUrl = '',
}) {
  final model = modelName.trim().toLowerCase();
  final provider = protocol.trim().toLowerCase();
  final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
  if (model.contains('grok-imagine-image') ||
      provider.contains('xai') ||
      host == 'api.x.ai' ||
      host.endsWith('.x.ai')) {
    return MediaRequestProviderProfile.xAiGrokImage;
  }
  if (model.startsWith('gpt-image') ||
      model.startsWith('dall-e') ||
      provider.contains('openai_images')) {
    return MediaRequestProviderProfile.openAiImageGeneration;
  }
  return MediaRequestProviderProfile.openAiCompatibleImage;
}

MediaRequestProviderProfile resolveVideoRequestProfile({
  required String modelName,
  required String protocol,
  String baseUrl = '',
}) {
  final model = modelName.trim().toLowerCase();
  final provider = protocol.trim().toLowerCase();
  final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
  if (model.contains('grok-imagine-video') ||
      model.contains('grok-video') ||
      provider.contains('xai') ||
      host == 'api.x.ai' ||
      host.endsWith('.x.ai')) {
    return MediaRequestProviderProfile.xAiGrokVideo;
  }
  if (model == 'sora' ||
      model.startsWith('sora-') ||
      provider.contains('sora')) {
    return MediaRequestProviderProfile.openAiSoraVideo;
  }
  return MediaRequestProviderProfile.openAiCompatibleVideo;
}

MediaRequestProviderProfile imageRequestProfileById(String? id) {
  return switch (id?.trim().toLowerCase()) {
    'openai_images' => MediaRequestProviderProfile.openAiImageGeneration,
    'xai_grok_images' => MediaRequestProviderProfile.xAiGrokImage,
    'openai_compatible_images' =>
      MediaRequestProviderProfile.openAiCompatibleImage,
    _ => MediaRequestProviderProfile.openAiCompatibleImage,
  };
}
