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
        .trim();
    const maxLength = 160;
    return sanitized.length <= maxLength
        ? sanitized
        : '${sanitized.substring(0, maxLength)}…';
  }
}
