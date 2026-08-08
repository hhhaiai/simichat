/// 外部社交通道抽象（飞书 / Telegram / Discord 等）。
///
/// 各平台实现负责：连通性测试、拉取新消息、发送回复。
/// 消息统一为 [ChannelInboundMessage]，与本地消息模型解耦。
library;

/// 从社交通道收到的一条消息。
class ChannelInboundMessage {
  final String id;
  final String fromUserId;
  final String text;
  final DateTime at;

  const ChannelInboundMessage({
    required this.id,
    required this.fromUserId,
    required this.text,
    required this.at,
  });
}

/// 社交通道适配器接口。
abstract interface class ChannelAdapter {
  /// 通道名（如 telegram）。
  String get channelName;

  /// 校验凭据是否有效（如调用 getMe）。
  Future<bool> testConnection();

  /// 拉取自上次拉取以来的新消息（内部维护游标，幂等）。
  Future<List<ChannelInboundMessage>> poll();

  /// 向指定用户发送回复。
  Future<bool> sendMessage({required String toUserId, required String text});
}
