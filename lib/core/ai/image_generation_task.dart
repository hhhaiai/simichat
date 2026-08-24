/// 图片生成任务的运行状态（内存态，不持久化）。
enum ImageGenerationTaskStatus { running, failed, cancelled }

/// 一次图片生成 / 图片编辑的任务视图：以占位消息为载体，在聊天流里
/// 展示生成进度；失败后保留参数供重试。CancelToken 由 provider 持有，
/// 视图模型保持无 dio 依赖。
class ImageGenerationTask {
  final String messageId;
  final String sessionId;
  final String prompt;
  final String? referenceImagePath;
  final String? referenceImageName;
  final String modelName;
  final String channelId;
  final String? routeModelId;

  /// The credential-free request profile selected for this task. Persisting
  /// the profile id keeps a cold-start retry on the same provider contract
  /// instead of re-inferring advanced fields from a possibly changed global
  /// model selection.
  final String providerProfileId;

  /// 完整任务快照。旧版 [referenceImagePath] 仍保留用于兼容已创建任务，
  /// 新版任务重试必须使用这个有序集合，不能把多参考图压缩成第一张。
  final List<String> referenceImagePaths;
  final List<String> referenceImageNames;
  final int count;
  final String? aspectRatio;
  final String? resolution;
  final String? size;
  final String? quality;
  final bool typedOptions;
  ImageGenerationTaskStatus status;
  String? error;

  ImageGenerationTask({
    required this.messageId,
    required this.sessionId,
    required this.prompt,
    this.referenceImagePath,
    this.referenceImageName,
    required this.modelName,
    required this.channelId,
    this.routeModelId,
    this.providerProfileId = 'openai_images',
    this.referenceImagePaths = const <String>[],
    this.referenceImageNames = const <String>[],
    this.count = 1,
    this.aspectRatio,
    this.resolution,
    this.size,
    this.quality,
    this.typedOptions = false,
    this.status = ImageGenerationTaskStatus.running,
    this.error,
  });

  bool get isRunning => status == ImageGenerationTaskStatus.running;
  bool get isFailed => status == ImageGenerationTaskStatus.failed;
  bool get isCancelled => status == ImageGenerationTaskStatus.cancelled;

  /// 失败原因的精简展示（复用测试器同款清洗，避免 API Key 泄漏）。
  String get compactError {
    final raw = error?.trim() ?? '';
    if (raw.isEmpty) return '未知错误';
    final sanitized = raw
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'), 'Bearer ***')
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{6,}'), 'sk-***')
        .replaceAll(
          RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false),
          '[链接]',
        )
        .replaceAll(
          RegExp(
            r'''(?:[A-Za-z]:[\\/]|/)(?:Users|home|private|var|data)[^\s<>"']*''',
            caseSensitive: false,
          ),
          '[本机路径]',
        )
        .trim();
    const maxLength = 160;
    return sanitized.length <= maxLength
        ? sanitized
        : '${sanitized.substring(0, maxLength)}…';
  }
}
