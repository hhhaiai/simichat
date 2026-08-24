import 'media_model_capability.dart';

/// 媒体任务本地校验的公共约束。错误由任务面板以字段级提示展示；服务层也会
/// 在真正请求前重复校验，避免 UI 漏掉字段时发送无效请求。
abstract interface class MediaRequestOptions {
  String get model;

  List<String> validationErrors({required MediaModelCapability capability});
}

List<String> _normalizedPaths(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final path = value.trim();
    if (path.isNotEmpty && seen.add(path)) result.add(path);
  }
  return List<String>.unmodifiable(result);
}

String? _optional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

void _validateModel(String model, List<String> errors) {
  if (model.trim().isEmpty) errors.add('请选择模型');
}

void _validateInput(
  String input,
  List<String> errors, {
  String label = '输入内容',
}) {
  if (input.trim().isEmpty) errors.add('请输入$label');
}

void _validateFormat(
  String? value,
  MediaModelCapability capability,
  List<String> errors,
) {
  if (value != null && !capability.supportsOutputFormat(value)) {
    errors.add('当前模型不支持输出格式 $value');
  }
}

/// 图片生成的本次请求。`referenceImages` 是完整有序集合，服务层不得取第一张
/// 代替其它图片。
class ImageGenerationOptions implements MediaRequestOptions {
  const ImageGenerationOptions({
    required this.model,
    required this.prompt,
    this.count = 1,
    List<String> referenceImages = const <String>[],
    this.aspectRatio,
    this.resolution,
    this.size,
    this.quality,
  }) : _referenceImages = referenceImages;

  @override
  final String model;
  final String prompt;
  final int count;
  final List<String> _referenceImages;
  final String? aspectRatio;

  /// 输出清晰度 / 规格档位，例如 1K、2K、4K。
  final String? resolution;

  /// 最终图像的像素尺寸，例如 1024x1024、1536x1024。
  final String? size;
  final String? quality;

  List<String> get referenceImages => _normalizedPaths(_referenceImages);

  @override
  List<String> validationErrors({required MediaModelCapability capability}) {
    final errors = <String>[];
    _validateModel(model, errors);
    _validateInput(prompt, errors, label: '图片描述');
    if (!capability.supportsOutputCount(count)) {
      errors.add('当前模型不支持生成数量 $count');
    }
    if (referenceImages.length > capability.maxReferenceImages) {
      errors.add('当前模型最多支持 ${capability.maxReferenceImages} 张参考图');
    }
    final ratio = _optional(aspectRatio);
    if (ratio != null && !capability.supportsAspectRatio(ratio)) {
      errors.add('当前模型不支持图片比例 $ratio');
    }
    final selectedResolution = _optional(resolution);
    if (selectedResolution != null &&
        !capability.supportsResolution(selectedResolution)) {
      errors.add('当前模型不支持图片清晰度 $selectedResolution');
    }
    final selectedSize = _optional(size);
    if (selectedSize != null && !capability.supportsSize(selectedSize)) {
      errors.add('当前模型不支持图片像素尺寸 $selectedSize');
    }
    final selectedQuality = _optional(quality);
    if (selectedQuality != null &&
        !capability.supportsQuality(selectedQuality)) {
      errors.add('当前模型不支持图片质量 $selectedQuality');
    }
    return List<String>.unmodifiable(errors);
  }
}

class SpeechSynthesisOptions implements MediaRequestOptions {
  const SpeechSynthesisOptions({
    required this.model,
    required this.input,
    required this.voice,
    this.speed = 1.0,
    this.responseFormat,
  });

  @override
  final String model;
  final String input;
  final String voice;
  final double speed;
  final String? responseFormat;

  @override
  List<String> validationErrors({required MediaModelCapability capability}) {
    final errors = <String>[];
    _validateModel(model, errors);
    _validateInput(input, errors);
    if (voice.trim().isEmpty) errors.add('请选择音色');
    if (speed <= 0) errors.add('语速必须大于 0');
    _validateFormat(_optional(responseFormat), capability, errors);
    return List<String>.unmodifiable(errors);
  }
}

class VoiceDesignOptions implements MediaRequestOptions {
  const VoiceDesignOptions({
    required this.model,
    required this.input,
    required this.style,
    this.speed = 1.0,
    this.responseFormat,
  });

  @override
  final String model;
  final String input;
  final String style;
  final double speed;
  final String? responseFormat;

  @override
  List<String> validationErrors({required MediaModelCapability capability}) {
    final errors = <String>[];
    _validateModel(model, errors);
    _validateInput(input, errors);
    if (style.trim().isEmpty) errors.add('请输入声音风格');
    if (speed <= 0) errors.add('语速必须大于 0');
    _validateFormat(_optional(responseFormat), capability, errors);
    return List<String>.unmodifiable(errors);
  }
}

class VoiceCloneOptions implements MediaRequestOptions {
  const VoiceCloneOptions({
    required this.model,
    required this.input,
    required this.referenceAudio,
    this.speed = 1.0,
    this.responseFormat,
  });

  @override
  final String model;
  final String input;
  final String referenceAudio;
  final double speed;
  final String? responseFormat;

  @override
  List<String> validationErrors({required MediaModelCapability capability}) {
    final errors = <String>[];
    _validateModel(model, errors);
    _validateInput(input, errors);
    if (referenceAudio.trim().isEmpty) errors.add('请选择参考音频');
    if (!capability.supportsReferenceAudio) {
      errors.add('当前模型不支持参考音频');
    }
    if (speed <= 0) errors.add('语速必须大于 0');
    _validateFormat(_optional(responseFormat), capability, errors);
    return List<String>.unmodifiable(errors);
  }
}

enum SpeechRecognitionLanguage {
  auto,
  chinese,
  english;

  String? get wireLanguage => switch (this) {
    SpeechRecognitionLanguage.auto => null,
    SpeechRecognitionLanguage.chinese => 'zh',
    SpeechRecognitionLanguage.english => 'en',
  };
}

class SpeechRecognitionOptions implements MediaRequestOptions {
  const SpeechRecognitionOptions({
    required this.model,
    required this.audioFile,
    this.language = SpeechRecognitionLanguage.auto,
  });

  @override
  final String model;
  final String audioFile;
  final SpeechRecognitionLanguage language;

  @override
  List<String> validationErrors({required MediaModelCapability capability}) {
    final errors = <String>[];
    _validateModel(model, errors);
    if (audioFile.trim().isEmpty) errors.add('请选择音频文件');
    return List<String>.unmodifiable(errors);
  }
}

/// 视频生成的本次请求。首帧、普通参考图和参考音频有独立字段，禁止相互
/// 借用或把本地路径作为普通 JSON 字段上传。
class VideoGenerationOptions implements MediaRequestOptions {
  const VideoGenerationOptions({
    required this.model,
    required this.prompt,
    this.firstFrameImage,
    List<String> referenceImages = const <String>[],
    this.referenceAudio,
    this.duration,
    this.aspectRatio,
    this.resolution,
  }) : _referenceImages = referenceImages;

  @override
  final String model;
  final String prompt;
  final String? firstFrameImage;
  final List<String> _referenceImages;
  final String? referenceAudio;
  final int? duration;
  final String? aspectRatio;
  final String? resolution;

  List<String> get referenceImages => _normalizedPaths(_referenceImages);

  @override
  List<String> validationErrors({required MediaModelCapability capability}) {
    final errors = <String>[];
    _validateModel(model, errors);
    _validateInput(prompt, errors, label: '视频描述');
    if (_optional(firstFrameImage) != null && !capability.supportsFirstFrame) {
      errors.add('当前模型不支持首帧图');
    }
    if (referenceImages.length > capability.maxReferenceImages) {
      errors.add('当前模型最多支持 ${capability.maxReferenceImages} 张参考图');
    }
    if (_optional(referenceAudio) != null &&
        !capability.supportsReferenceAudio) {
      errors.add('当前模型不支持参考音频');
    }
    if (duration != null && !capability.supportsDuration(duration)) {
      errors.add('当前模型不支持时长 $duration 秒');
    }
    final ratio = _optional(aspectRatio);
    if (ratio != null && !capability.supportsAspectRatio(ratio)) {
      errors.add('当前模型不支持视频比例 $ratio');
    }
    final size = _optional(resolution);
    if (size != null && !capability.supportsResolution(size)) {
      errors.add('当前模型不支持视频分辨率 $size');
    }
    return List<String>.unmodifiable(errors);
  }
}
