import 'dart:collection';

/// 一个媒体模型已声明的、无凭据的能力边界。
///
/// 空列表表示该参数未声明可用；它不是“向上游尝试发送”的许可。这样自定义
/// 模型仍可安全显示为可选模型，但不会因猜测字段破坏请求兼容性。
class MediaModelCapability {
  const MediaModelCapability({
    this.supportedAspectRatios = const <String>[],
    this.supportedResolutions = const <String>[],
    this.supportedSizes = const <String>[],
    this.supportedQualities = const <String>[],
    this.supportedOutputFormats = const <String>[],
    this.supportedDurations = const <int>[],
    this.maxReferenceImages = 0,
    this.supportsFirstFrame = false,
    this.supportsReferenceAudio = false,
    this.supportsMultipleOutputs = false,
    this.minOutputs = 1,
    this.maxOutputs = 1,
  }) : assert(maxReferenceImages >= 0),
       assert(minOutputs >= 1),
       assert(maxOutputs >= minOutputs);

  /// 无能力声明的兼容模型：仅允许 model、prompt / input 等核心字段。
  static const undeclared = MediaModelCapability();

  final List<String> supportedAspectRatios;

  /// 输出清晰度 / 规格档位，例如 1K、2K、4K。
  final List<String> supportedResolutions;

  /// 明确的像素尺寸，例如 1024x1024、1536x1024。
  final List<String> supportedSizes;
  final List<String> supportedQualities;
  final List<String> supportedOutputFormats;
  final List<int> supportedDurations;
  final int maxReferenceImages;
  final bool supportsFirstFrame;
  final bool supportsReferenceAudio;
  final bool supportsMultipleOutputs;
  final int minOutputs;
  final int maxOutputs;

  bool supportsAspectRatio(String? value) =>
      _contains(supportedAspectRatios, value);

  bool supportsResolution(String? value) =>
      _contains(supportedResolutions, value);

  bool supportsSize(String? value) => _contains(supportedSizes, value);

  bool supportsQuality(String? value) => _contains(supportedQualities, value);

  bool supportsOutputFormat(String? value) =>
      _contains(supportedOutputFormats, value);

  bool supportsDuration(int? value) =>
      value == null || supportedDurations.contains(value);

  bool supportsOutputCount(int value) =>
      value >= minOutputs &&
      value <= maxOutputs &&
      (value == 1 || supportsMultipleOutputs);

  UnmodifiableListView<String> get aspectRatios =>
      UnmodifiableListView<String>(supportedAspectRatios);

  UnmodifiableListView<String> get resolutions =>
      UnmodifiableListView<String>(supportedResolutions);

  UnmodifiableListView<String> get sizes =>
      UnmodifiableListView<String>(supportedSizes);

  UnmodifiableListView<String> get qualities =>
      UnmodifiableListView<String>(supportedQualities);

  UnmodifiableListView<String> get outputFormats =>
      UnmodifiableListView<String>(supportedOutputFormats);

  UnmodifiableListView<int> get durations =>
      UnmodifiableListView<int>(supportedDurations);

  static bool _contains(List<String> values, String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return true;
    return values.any(
      (candidate) => candidate.trim().toLowerCase() == normalized.toLowerCase(),
    );
  }
}
