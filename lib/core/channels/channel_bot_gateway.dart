import 'channel_adapter.dart';

/// 由 AI 生成回复的回调：入参为用户消息文本，返回回复文本。
typedef ChannelReplyFunction = Future<String> Function(String text);

/// 社交通道机器人网关：拉取新消息 → AI 应答 → 回发。
///
/// 单次 [runOnce] 处理一批消息；长轮询由调用方周期性驱动
/// （移动端受生命周期约束，通常由前台 / 后台定时器触发）。
class ChannelBotGateway {
  ChannelBotGateway({required this.adapter, required this.reply});

  final ChannelAdapter adapter;
  final ChannelReplyFunction reply;

  bool _handling = false;

  /// 处理一批新消息，返回处理条数。
  Future<int> runOnce() async {
    final messages = await adapter.poll();
    var handled = 0;
    for (final message in messages) {
      if (_handling) break;
      _handling = true;
      try {
        final replyText = await reply(message.text);
        await adapter.sendMessage(
          toUserId: message.fromUserId,
          text: replyText,
        );
        handled++;
      } finally {
        _handling = false;
      }
    }
    return handled;
  }
}
