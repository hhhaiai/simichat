import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/image_generation_task.dart';

/// 图片生成任务的内存注册表：占位消息 id → 任务。仅用于当前进程内的
/// 进度 / 失败 / 取消展示与重试，不持久化（冷启动后占位消息按普通
/// 文本渲染，不会误显示 spinner）。
final imageGenerationTasksProvider =
    StateNotifierProvider<ImageGenerationTasksNotifier,
        Map<String, ImageGenerationTask>>((ref) {
      return ImageGenerationTasksNotifier();
    });

class ImageGenerationTasksNotifier
    extends StateNotifier<Map<String, ImageGenerationTask>> {
  ImageGenerationTasksNotifier() : super(const {});

  /// 每任务一个 CancelToken，取消后立即失效。
  final Map<String, CancelToken> _cancelTokens = {};

  CancelToken start(ImageGenerationTask task) {
    final cancelToken = CancelToken();
    _cancelTokens[task.messageId] = cancelToken;
    state = {...state, task.messageId: task};
    return cancelToken;
  }

  void markFailed(String messageId, String error) {
    final task = state[messageId];
    if (task == null) return;
    task.status = ImageGenerationTaskStatus.failed;
    task.error = error;
    state = {...state, messageId: task};
    _cancelTokens.remove(messageId);
  }

  void markCancelled(String messageId) {
    final task = state[messageId];
    if (task == null) return;
    task.status = ImageGenerationTaskStatus.cancelled;
    state = {...state, messageId: task};
    _cancelTokens.remove(messageId);
  }

  void finish(String messageId) {
    if (!state.containsKey(messageId)) return;
    final updated = Map<String, ImageGenerationTask>.from(state)
      ..remove(messageId);
    state = updated;
    _cancelTokens.remove(messageId);
  }

  /// 取消该会话所有运行中的任务（stop 按钮入口）。
  Future<void> cancelForSession(String sessionId) async {
    final running = state.values
        .where(
          (task) =>
              task.sessionId == sessionId &&
              task.status == ImageGenerationTaskStatus.running,
        )
        .toList();
    for (final task in running) {
      final token = _cancelTokens[task.messageId];
      if (token != null && !token.isCancelled) {
        token.cancel();
      }
      markCancelled(task.messageId);
    }
  }
}
