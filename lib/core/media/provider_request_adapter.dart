import '../ai/model_capabilities.dart';
import 'media_provider_profile.dart';
import 'media_request_options.dart';

/// 一份尚未被网络层编码的 provider 请求。它没有 API Key、Base URL 或本机
/// 路径序列化行为；adapter 仅表达哪一个经验证的字段和附件角色应该被传输层
/// 编码，避免 Widget 或业务层拼接厂商 JSON。
class ProviderRequest {
  ProviderRequest({
    required Map<String, dynamic> fields,
    List<ProviderAttachmentRequest> attachments =
        const <ProviderAttachmentRequest>[],
  }) : fields = Map<String, dynamic>.unmodifiable(fields),
       attachments = List<ProviderAttachmentRequest>.unmodifiable(attachments);

  final Map<String, dynamic> fields;
  final List<ProviderAttachmentRequest> attachments;
}

enum ProviderAttachmentRole {
  referenceImage,
  firstFrameImage,
  referenceAudio,
  inputAudio,
}

class ProviderAttachmentRequest {
  const ProviderAttachmentRequest({
    required this.role,
    required this.field,
    required this.paths,
  });

  final ProviderAttachmentRole role;
  final String field;
  final List<String> paths;
}

abstract interface class ProviderRequestAdapter<T extends MediaRequestOptions> {
  List<String> validate(T options, ModelCapabilities capabilities);

  ProviderRequest build(T options, ModelCapabilities capabilities);
}

class ImageGenerationRequestAdapter
    implements ProviderRequestAdapter<ImageGenerationOptions> {
  const ImageGenerationRequestAdapter(this.profile);

  final MediaRequestProviderProfile profile;

  @override
  List<String> validate(
    ImageGenerationOptions options,
    ModelCapabilities capabilities,
  ) {
    final errors = <String>[
      ...options.validationErrors(capability: profile.capability),
    ];
    if (capabilities.imageGenerationSupport.isUnsupported) {
      errors.add('当前模型不支持图片生成');
    }
    if (capabilities.imageGenerationSupport.isUnknown &&
        (options.referenceImages.isNotEmpty ||
            options.aspectRatio?.trim().isNotEmpty == true ||
            options.resolution?.trim().isNotEmpty == true ||
            options.size?.trim().isNotEmpty == true ||
            options.quality?.trim().isNotEmpty == true ||
            options.count > 1)) {
      errors.add('当前图片模型的高级能力未知，请切换到已验证模型或在渠道设置中声明能力');
    }
    return List<String>.unmodifiable(errors);
  }

  @override
  ProviderRequest build(
    ImageGenerationOptions options,
    ModelCapabilities capabilities,
  ) {
    _throwIfInvalid(validate(options, capabilities));
    return ProviderRequest(
      fields: <String, dynamic>{
        'model': options.model.trim(),
        'prompt': options.prompt.trim(),
        ...profile.serializeImageGeneration(options),
      },
      attachments: options.referenceImages.isEmpty
          ? const <ProviderAttachmentRequest>[]
          : <ProviderAttachmentRequest>[
              ProviderAttachmentRequest(
                role: ProviderAttachmentRole.referenceImage,
                field: profile.referenceImagesField ?? 'image',
                paths: options.referenceImages,
              ),
            ],
    );
  }
}

class SpeechSynthesisRequestAdapter
    implements ProviderRequestAdapter<SpeechSynthesisOptions> {
  const SpeechSynthesisRequestAdapter(this.profile);

  final MediaRequestProviderProfile profile;

  @override
  List<String> validate(
    SpeechSynthesisOptions options,
    ModelCapabilities capabilities,
  ) {
    final errors = <String>[
      ...options.validationErrors(capability: profile.capability),
    ];
    if (capabilities.speechSynthesisSupport.isUnsupported) {
      errors.add('当前模型不支持语音合成');
    }
    return List<String>.unmodifiable(errors);
  }

  @override
  ProviderRequest build(
    SpeechSynthesisOptions options,
    ModelCapabilities capabilities,
  ) {
    _throwIfInvalid(validate(options, capabilities));
    return ProviderRequest(
      fields: <String, dynamic>{
        'model': options.model.trim(),
        ...profile.serializeSpeechSynthesis(options),
      },
    );
  }
}

class VoiceDesignRequestAdapter
    implements ProviderRequestAdapter<VoiceDesignOptions> {
  const VoiceDesignRequestAdapter(this.profile);

  final MediaRequestProviderProfile profile;

  @override
  List<String> validate(
    VoiceDesignOptions options,
    ModelCapabilities capabilities,
  ) {
    final errors = <String>[
      ...options.validationErrors(capability: profile.capability),
    ];
    if (capabilities.voiceDesignSupport.isUnsupported) {
      errors.add('当前模型不支持声音设计');
    }
    return List<String>.unmodifiable(errors);
  }

  @override
  ProviderRequest build(
    VoiceDesignOptions options,
    ModelCapabilities capabilities,
  ) {
    _throwIfInvalid(validate(options, capabilities));
    return ProviderRequest(
      fields: <String, dynamic>{
        'model': options.model.trim(),
        ...profile.serializeVoiceDesign(options),
      },
    );
  }
}

class VoiceCloneRequestAdapter
    implements ProviderRequestAdapter<VoiceCloneOptions> {
  const VoiceCloneRequestAdapter(this.profile);

  final MediaRequestProviderProfile profile;

  @override
  List<String> validate(
    VoiceCloneOptions options,
    ModelCapabilities capabilities,
  ) {
    final errors = <String>[
      ...options.validationErrors(capability: profile.capability),
    ];
    if (capabilities.voiceCloneSupport.isUnsupported) {
      errors.add('当前模型不支持声音克隆');
    }
    if (!capabilities.supportsReferenceAudio.isSupported) {
      errors.add('当前模型未声明可用的参考音频能力');
    }
    return List<String>.unmodifiable(errors);
  }

  @override
  ProviderRequest build(
    VoiceCloneOptions options,
    ModelCapabilities capabilities,
  ) {
    _throwIfInvalid(validate(options, capabilities));
    return ProviderRequest(
      fields: <String, dynamic>{
        'model': options.model.trim(),
        ...profile.serializeVoiceClone(options),
      },
      attachments: <ProviderAttachmentRequest>[
        ProviderAttachmentRequest(
          role: ProviderAttachmentRole.referenceAudio,
          field: profile.referenceAudioField ?? 'voice',
          paths: <String>[options.referenceAudio.trim()],
        ),
      ],
    );
  }
}

class SpeechRecognitionRequestAdapter
    implements ProviderRequestAdapter<SpeechRecognitionOptions> {
  const SpeechRecognitionRequestAdapter(this.profile);

  final MediaRequestProviderProfile profile;

  @override
  List<String> validate(
    SpeechRecognitionOptions options,
    ModelCapabilities capabilities,
  ) {
    final errors = <String>[
      ...options.validationErrors(capability: profile.capability),
    ];
    if (capabilities.speechRecognitionSupport.isUnsupported) {
      errors.add('当前模型不支持语音识别');
    }
    return List<String>.unmodifiable(errors);
  }

  @override
  ProviderRequest build(
    SpeechRecognitionOptions options,
    ModelCapabilities capabilities,
  ) {
    _throwIfInvalid(validate(options, capabilities));
    return ProviderRequest(
      fields: <String, dynamic>{
        'model': options.model.trim(),
        ...profile.serializeSpeechRecognition(options),
      },
      attachments: <ProviderAttachmentRequest>[
        ProviderAttachmentRequest(
          role: ProviderAttachmentRole.inputAudio,
          field: 'file',
          paths: <String>[options.audioFile.trim()],
        ),
      ],
    );
  }
}

class VideoGenerationRequestAdapter
    implements ProviderRequestAdapter<VideoGenerationOptions> {
  const VideoGenerationRequestAdapter(this.profile);

  final MediaRequestProviderProfile profile;

  @override
  List<String> validate(
    VideoGenerationOptions options,
    ModelCapabilities capabilities,
  ) {
    final errors = <String>[
      ...options.validationErrors(capability: profile.capability),
    ];
    if (capabilities.videoGenerationSupport.isUnsupported) {
      errors.add('当前模型不支持视频生成');
    }
    if (capabilities.videoGenerationSupport.isUnknown &&
        (options.firstFrameImage?.trim().isNotEmpty == true ||
            options.referenceImages.isNotEmpty ||
            options.referenceAudio?.trim().isNotEmpty == true ||
            options.duration != null ||
            options.aspectRatio?.trim().isNotEmpty == true ||
            options.resolution?.trim().isNotEmpty == true)) {
      errors.add('当前视频模型的高级能力未知，请切换到已验证模型或在渠道设置中声明能力');
    }
    return List<String>.unmodifiable(errors);
  }

  @override
  ProviderRequest build(
    VideoGenerationOptions options,
    ModelCapabilities capabilities,
  ) {
    _throwIfInvalid(validate(options, capabilities));
    final attachments = <ProviderAttachmentRequest>[];
    if (options.firstFrameImage?.trim().isNotEmpty == true) {
      attachments.add(
        ProviderAttachmentRequest(
          role: ProviderAttachmentRole.firstFrameImage,
          field: profile.firstFrameField!,
          paths: <String>[options.firstFrameImage!.trim()],
        ),
      );
    }
    if (options.referenceImages.isNotEmpty) {
      attachments.add(
        ProviderAttachmentRequest(
          role: ProviderAttachmentRole.referenceImage,
          field: profile.referenceImagesField!,
          paths: options.referenceImages,
        ),
      );
    }
    if (options.referenceAudio?.trim().isNotEmpty == true) {
      attachments.add(
        ProviderAttachmentRequest(
          role: ProviderAttachmentRole.referenceAudio,
          field: profile.referenceAudioField!,
          paths: <String>[options.referenceAudio!.trim()],
        ),
      );
    }
    return ProviderRequest(
      fields: <String, dynamic>{
        'model': options.model.trim(),
        'prompt': options.prompt.trim(),
        ...profile.serializeVideoGeneration(options),
      },
      attachments: attachments,
    );
  }
}

void _throwIfInvalid(List<String> errors) {
  if (errors.isNotEmpty) throw ArgumentError(errors.join('；'));
}
