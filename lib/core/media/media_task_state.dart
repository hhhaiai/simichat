/// 多模态任务与 Artifact 面向用户的统一生命周期。
///
/// 该状态不复用远端厂商的原始 state；适配层负责把 provider 的 queued /
/// processing 等状态映射到这个稳定集合，避免 UI 依赖某一个接口的枚举。
enum MediaTaskState {
  draft,
  validating,
  preparing,
  uploading,
  queued,
  running,
  succeeded,
  failed,
  cancelled,
}

extension MediaTaskStateX on MediaTaskState {
  bool get isTerminal => switch (this) {
    MediaTaskState.succeeded ||
    MediaTaskState.failed ||
    MediaTaskState.cancelled => true,
    _ => false,
  };

  String get label => switch (this) {
    MediaTaskState.draft => '草稿',
    MediaTaskState.validating => '正在检查参数',
    MediaTaskState.preparing => '正在准备内容',
    MediaTaskState.uploading => '正在上传素材',
    MediaTaskState.queued => '正在排队',
    MediaTaskState.running => '正在生成',
    MediaTaskState.succeeded => '已完成',
    MediaTaskState.failed => '失败',
    MediaTaskState.cancelled => '已取消',
  };
}
