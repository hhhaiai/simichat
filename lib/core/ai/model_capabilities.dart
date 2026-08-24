import 'dart:collection';

/// 能力的三态结论。`unknown` 不是 `supported`：调用方只能使用低风险的
/// 兼容路径，或等待用户在渠道设置中明确覆盖。
enum CapabilityState { supported, unsupported, unknown }

extension CapabilityStateX on CapabilityState {
  bool get isSupported => this == CapabilityState.supported;
  bool get isUnsupported => this == CapabilityState.unsupported;
  bool get isUnknown => this == CapabilityState.unknown;
}

/// 渠道把本地文件送到上游的实际协议。文件理解能力和传输方式分开表达：模型
/// 可能理解文件，但当前渠道仍未实现任何安全可用的传输协议。
enum FileTransport {
  multipart,
  base64DataUrl,
  messageContentFile,
  remoteFileId,
  unsupported,
}

/// 能力的可靠来源；合并时优先级按枚举定义：后端声明 > 已验证内置 profile >
/// 用户覆盖 > 保守默认值。
enum ModelCapabilitiesSource {
  conservativeDefault,
  userOverride,
  builtInProfile,
  provider,
}

/// 单个模型的产品级能力描述。
///
/// 该对象不包含 API Key、Base URL 或本地文件路径。空列表只表示该项目没有
/// 可用声明，不能被 UI 解释为“尝试发给上游”；是否可用由对应三态字段决定。
class ModelCapabilities {
  const ModelCapabilities({
    this.modelId = '',
    this.providerId = '',
    this.contextWindowTokens,
    this.maxOutputTokens,
    this.maxRequestBytes,
    this.textInputSupport = CapabilityState.unknown,
    this.fileInputSupport = CapabilityState.unknown,
    this.supportedInputMimeTypes = const <String>[],
    this.supportedFileTransports = const <FileTransport>[],
    this.maxInputFiles,
    this.maxInputFileBytes,
    this.visionSupport = CapabilityState.unknown,
    this.maxReferenceImages = 0,
    this.imageGenerationSupport = CapabilityState.unknown,
    this.supportedImageCounts = const <int>[],
    this.supportedAspectRatios = const <String>[],
    this.supportedImageResolutions = const <String>[],
    this.supportedImageSizes = const <String>[],
    this.supportedImageQualities = const <String>[],
    this.speechSynthesisSupport = CapabilityState.unknown,
    this.supportedVoices = const <String>[],
    this.supportedSpeechSpeeds = const <double>[],
    this.supportedAudioOutputFormats = const <String>[],
    this.voiceDesignSupport = CapabilityState.unknown,
    this.voiceCloneSupport = CapabilityState.unknown,
    this.supportedReferenceAudioMimeTypes = const <String>[],
    this.maxReferenceAudioBytes,
    this.maxReferenceAudioDurationSeconds,
    this.speechRecognitionSupport = CapabilityState.unknown,
    this.supportedRecognitionLanguages = const <String>[],
    this.videoGenerationSupport = CapabilityState.unknown,
    this.supportsFirstFrame = CapabilityState.unknown,
    this.supportsReferenceAudio = CapabilityState.unknown,
    this.supportedVideoDurations = const <int>[],
    this.supportedVideoAspectRatios = const <String>[],
    this.supportedVideoResolutions = const <String>[],
  });

  final String modelId;
  final String providerId;
  final int? contextWindowTokens;
  final int? maxOutputTokens;
  final int? maxRequestBytes;

  final CapabilityState textInputSupport;
  final CapabilityState fileInputSupport;
  final List<String> supportedInputMimeTypes;
  final List<FileTransport> supportedFileTransports;
  final int? maxInputFiles;
  final int? maxInputFileBytes;

  final CapabilityState visionSupport;
  final int maxReferenceImages;

  final CapabilityState imageGenerationSupport;
  final List<int> supportedImageCounts;
  final List<String> supportedAspectRatios;

  /// 输出清晰度 / 规格档位，例如 1K、2K、4K。
  final List<String> supportedImageResolutions;

  /// 明确像素尺寸，例如 1024x1024、1536x1024。
  final List<String> supportedImageSizes;
  final List<String> supportedImageQualities;

  final CapabilityState speechSynthesisSupport;
  final List<String> supportedVoices;
  final List<double> supportedSpeechSpeeds;
  final List<String> supportedAudioOutputFormats;

  final CapabilityState voiceDesignSupport;
  final CapabilityState voiceCloneSupport;
  final List<String> supportedReferenceAudioMimeTypes;
  final int? maxReferenceAudioBytes;
  final int? maxReferenceAudioDurationSeconds;

  final CapabilityState speechRecognitionSupport;
  final List<String> supportedRecognitionLanguages;

  final CapabilityState videoGenerationSupport;
  final CapabilityState supportsFirstFrame;
  final CapabilityState supportsReferenceAudio;
  final List<int> supportedVideoDurations;
  final List<String> supportedVideoAspectRatios;
  final List<String> supportedVideoResolutions;

  /// 文件输入只有模型明确支持、当前渠道至少注册一种真正可用的传输协议、
  /// 并且 MIME / 数量 / 大小都在能力范围内时才可走附件路径。
  bool canUseFileInput({
    required String mimeType,
    required int fileCount,
    required int fileBytes,
  }) {
    if (!fileInputSupport.isSupported ||
        !supportedFileTransports.any(
          (transport) => transport != FileTransport.unsupported,
        )) {
      return false;
    }
    if (maxInputFiles != null && fileCount > maxInputFiles!) return false;
    if (maxInputFileBytes != null && fileBytes > maxInputFileBytes!) {
      return false;
    }
    return _contains(supportedInputMimeTypes, mimeType);
  }

  /// 返回最适合的渠道文件传输方式；未知 / unsupported 一律不返回猜测值。
  FileTransport? preferredFileTransport() {
    if (!fileInputSupport.isSupported) return null;
    for (final transport in const <FileTransport>[
      FileTransport.remoteFileId,
      FileTransport.messageContentFile,
      FileTransport.multipart,
      FileTransport.base64DataUrl,
    ]) {
      if (supportedFileTransports.contains(transport)) return transport;
    }
    return null;
  }

  bool supportsInputMimeType(String mimeType) =>
      _contains(supportedInputMimeTypes, mimeType);

  ModelCapabilities copyWith({
    String? modelId,
    String? providerId,
    int? contextWindowTokens,
    int? maxOutputTokens,
    int? maxRequestBytes,
    CapabilityState? textInputSupport,
    CapabilityState? fileInputSupport,
    List<String>? supportedInputMimeTypes,
    List<FileTransport>? supportedFileTransports,
    int? maxInputFiles,
    int? maxInputFileBytes,
    CapabilityState? visionSupport,
    int? maxReferenceImages,
    CapabilityState? imageGenerationSupport,
    List<int>? supportedImageCounts,
    List<String>? supportedAspectRatios,
    List<String>? supportedImageResolutions,
    List<String>? supportedImageSizes,
    List<String>? supportedImageQualities,
    CapabilityState? speechSynthesisSupport,
    List<String>? supportedVoices,
    List<double>? supportedSpeechSpeeds,
    List<String>? supportedAudioOutputFormats,
    CapabilityState? voiceDesignSupport,
    CapabilityState? voiceCloneSupport,
    List<String>? supportedReferenceAudioMimeTypes,
    int? maxReferenceAudioBytes,
    int? maxReferenceAudioDurationSeconds,
    CapabilityState? speechRecognitionSupport,
    List<String>? supportedRecognitionLanguages,
    CapabilityState? videoGenerationSupport,
    CapabilityState? supportsFirstFrame,
    CapabilityState? supportsReferenceAudio,
    List<int>? supportedVideoDurations,
    List<String>? supportedVideoAspectRatios,
    List<String>? supportedVideoResolutions,
  }) {
    return ModelCapabilities(
      modelId: modelId ?? this.modelId,
      providerId: providerId ?? this.providerId,
      contextWindowTokens: contextWindowTokens ?? this.contextWindowTokens,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      maxRequestBytes: maxRequestBytes ?? this.maxRequestBytes,
      textInputSupport: textInputSupport ?? this.textInputSupport,
      fileInputSupport: fileInputSupport ?? this.fileInputSupport,
      supportedInputMimeTypes:
          supportedInputMimeTypes ?? this.supportedInputMimeTypes,
      supportedFileTransports:
          supportedFileTransports ?? this.supportedFileTransports,
      maxInputFiles: maxInputFiles ?? this.maxInputFiles,
      maxInputFileBytes: maxInputFileBytes ?? this.maxInputFileBytes,
      visionSupport: visionSupport ?? this.visionSupport,
      maxReferenceImages: maxReferenceImages ?? this.maxReferenceImages,
      imageGenerationSupport:
          imageGenerationSupport ?? this.imageGenerationSupport,
      supportedImageCounts: supportedImageCounts ?? this.supportedImageCounts,
      supportedAspectRatios:
          supportedAspectRatios ?? this.supportedAspectRatios,
      supportedImageResolutions:
          supportedImageResolutions ?? this.supportedImageResolutions,
      supportedImageSizes: supportedImageSizes ?? this.supportedImageSizes,
      supportedImageQualities:
          supportedImageQualities ?? this.supportedImageQualities,
      speechSynthesisSupport:
          speechSynthesisSupport ?? this.speechSynthesisSupport,
      supportedVoices: supportedVoices ?? this.supportedVoices,
      supportedSpeechSpeeds:
          supportedSpeechSpeeds ?? this.supportedSpeechSpeeds,
      supportedAudioOutputFormats:
          supportedAudioOutputFormats ?? this.supportedAudioOutputFormats,
      voiceDesignSupport: voiceDesignSupport ?? this.voiceDesignSupport,
      voiceCloneSupport: voiceCloneSupport ?? this.voiceCloneSupport,
      supportedReferenceAudioMimeTypes:
          supportedReferenceAudioMimeTypes ??
          this.supportedReferenceAudioMimeTypes,
      maxReferenceAudioBytes:
          maxReferenceAudioBytes ?? this.maxReferenceAudioBytes,
      maxReferenceAudioDurationSeconds:
          maxReferenceAudioDurationSeconds ??
          this.maxReferenceAudioDurationSeconds,
      speechRecognitionSupport:
          speechRecognitionSupport ?? this.speechRecognitionSupport,
      supportedRecognitionLanguages:
          supportedRecognitionLanguages ?? this.supportedRecognitionLanguages,
      videoGenerationSupport:
          videoGenerationSupport ?? this.videoGenerationSupport,
      supportsFirstFrame: supportsFirstFrame ?? this.supportsFirstFrame,
      supportsReferenceAudio:
          supportsReferenceAudio ?? this.supportsReferenceAudio,
      supportedVideoDurations:
          supportedVideoDurations ?? this.supportedVideoDurations,
      supportedVideoAspectRatios:
          supportedVideoAspectRatios ?? this.supportedVideoAspectRatios,
      supportedVideoResolutions:
          supportedVideoResolutions ?? this.supportedVideoResolutions,
    );
  }

  static bool _contains(List<String> values, String value) => values.any(
    (candidate) => candidate.trim().toLowerCase() == value.trim().toLowerCase(),
  );
}

/// 按可信来源合并模型能力。列表只在高优先级来源提供非空声明时替换；三态
/// 字段仅在高优先级来源不是 unknown 时替换，避免空 profile 擦掉验证结果。
class ModelCapabilitiesRegistry {
  const ModelCapabilitiesRegistry();

  ModelCapabilities resolve({
    ModelCapabilities? provider,
    ModelCapabilities? builtInProfile,
    ModelCapabilities? userOverride,
    ModelCapabilities conservativeDefault = const ModelCapabilities(),
  }) {
    var resolved = conservativeDefault;
    for (final candidate in <ModelCapabilities?>[
      userOverride,
      builtInProfile,
      provider,
    ]) {
      if (candidate == null) continue;
      resolved = _merge(resolved, candidate);
    }
    return resolved;
  }

  ModelCapabilities _merge(ModelCapabilities base, ModelCapabilities high) {
    CapabilityState choose(CapabilityState lower, CapabilityState upper) =>
        upper.isUnknown ? lower : upper;
    List<T> list<T>(List<T> lower, List<T> upper) =>
        upper.isEmpty ? lower : List<T>.unmodifiable(upper);
    return ModelCapabilities(
      modelId: high.modelId.trim().isEmpty ? base.modelId : high.modelId,
      providerId: high.providerId.trim().isEmpty
          ? base.providerId
          : high.providerId,
      contextWindowTokens: high.contextWindowTokens ?? base.contextWindowTokens,
      maxOutputTokens: high.maxOutputTokens ?? base.maxOutputTokens,
      maxRequestBytes: high.maxRequestBytes ?? base.maxRequestBytes,
      textInputSupport: choose(base.textInputSupport, high.textInputSupport),
      fileInputSupport: choose(base.fileInputSupport, high.fileInputSupport),
      supportedInputMimeTypes: list(
        base.supportedInputMimeTypes,
        high.supportedInputMimeTypes,
      ),
      supportedFileTransports: list(
        base.supportedFileTransports,
        high.supportedFileTransports,
      ),
      maxInputFiles: high.maxInputFiles ?? base.maxInputFiles,
      maxInputFileBytes: high.maxInputFileBytes ?? base.maxInputFileBytes,
      visionSupport: choose(base.visionSupport, high.visionSupport),
      maxReferenceImages: high.maxReferenceImages > 0
          ? high.maxReferenceImages
          : base.maxReferenceImages,
      imageGenerationSupport: choose(
        base.imageGenerationSupport,
        high.imageGenerationSupport,
      ),
      supportedImageCounts: list(
        base.supportedImageCounts,
        high.supportedImageCounts,
      ),
      supportedAspectRatios: list(
        base.supportedAspectRatios,
        high.supportedAspectRatios,
      ),
      supportedImageResolutions: list(
        base.supportedImageResolutions,
        high.supportedImageResolutions,
      ),
      supportedImageSizes: list(
        base.supportedImageSizes,
        high.supportedImageSizes,
      ),
      supportedImageQualities: list(
        base.supportedImageQualities,
        high.supportedImageQualities,
      ),
      speechSynthesisSupport: choose(
        base.speechSynthesisSupport,
        high.speechSynthesisSupport,
      ),
      supportedVoices: list(base.supportedVoices, high.supportedVoices),
      supportedSpeechSpeeds: list(
        base.supportedSpeechSpeeds,
        high.supportedSpeechSpeeds,
      ),
      supportedAudioOutputFormats: list(
        base.supportedAudioOutputFormats,
        high.supportedAudioOutputFormats,
      ),
      voiceDesignSupport: choose(
        base.voiceDesignSupport,
        high.voiceDesignSupport,
      ),
      voiceCloneSupport: choose(base.voiceCloneSupport, high.voiceCloneSupport),
      supportedReferenceAudioMimeTypes: list(
        base.supportedReferenceAudioMimeTypes,
        high.supportedReferenceAudioMimeTypes,
      ),
      maxReferenceAudioBytes:
          high.maxReferenceAudioBytes ?? base.maxReferenceAudioBytes,
      maxReferenceAudioDurationSeconds:
          high.maxReferenceAudioDurationSeconds ??
          base.maxReferenceAudioDurationSeconds,
      speechRecognitionSupport: choose(
        base.speechRecognitionSupport,
        high.speechRecognitionSupport,
      ),
      supportedRecognitionLanguages: list(
        base.supportedRecognitionLanguages,
        high.supportedRecognitionLanguages,
      ),
      videoGenerationSupport: choose(
        base.videoGenerationSupport,
        high.videoGenerationSupport,
      ),
      supportsFirstFrame: choose(
        base.supportsFirstFrame,
        high.supportsFirstFrame,
      ),
      supportsReferenceAudio: choose(
        base.supportsReferenceAudio,
        high.supportsReferenceAudio,
      ),
      supportedVideoDurations: list(
        base.supportedVideoDurations,
        high.supportedVideoDurations,
      ),
      supportedVideoAspectRatios: list(
        base.supportedVideoAspectRatios,
        high.supportedVideoAspectRatios,
      ),
      supportedVideoResolutions: list(
        base.supportedVideoResolutions,
        high.supportedVideoResolutions,
      ),
    );
  }
}

/// 只读视图帮助 UI 不把内部可变列表泄漏给 selector。
extension ModelCapabilitiesReadOnlyX on ModelCapabilities {
  UnmodifiableListView<FileTransport> get fileTransports =>
      UnmodifiableListView<FileTransport>(supportedFileTransports);
}
