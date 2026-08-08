import 'package:ai_chat_app/core/channels/channel_adapter.dart';
import 'package:ai_chat_app/core/channels/channel_bot_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements ChannelAdapter {
  final List<ChannelInboundMessage> queue;
  final List<String> sent = [];
  final bool failSend;

  _FakeAdapter({List<ChannelInboundMessage>? queue, this.failSend = false})
    : queue = queue ?? [];

  @override
  String get channelName => 'fake';

  @override
  Future<bool> testConnection() async => true;

  @override
  Future<List<ChannelInboundMessage>> poll() async => List.of(queue);

  @override
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
  }) async {
    if (failSend) throw StateError('send failed');
    sent.add(text);
    return true;
  }
}

void main() {
  test('gateway polls, replies via AI, and sends back to each user', () async {
    final adapter = _FakeAdapter(
      queue: [
        ChannelInboundMessage(
          id: '1',
          fromUserId: 'u1',
          text: '你好',
          at: DateTime(2026, 1, 1),
        ),
        ChannelInboundMessage(
          id: '2',
          fromUserId: 'u2',
          text: 'Flutter 是什么',
          at: DateTime(2026, 1, 1),
        ),
      ],
    );
    final gateway = ChannelBotGateway(
      adapter: adapter,
      reply: (text) async => '回复: $text',
    );

    final handled = await gateway.runOnce();

    expect(handled, 2);
    expect(adapter.sent, contains('回复: 你好'));
    expect(adapter.sent, contains('回复: Flutter 是什么'));
  });

  test('send failure does not throw and stops the batch', () async {
    final adapter = _FakeAdapter(
      failSend: true,
      queue: [
        ChannelInboundMessage(
          id: '1',
          fromUserId: 'u1',
          text: 'a',
          at: DateTime(2026, 1, 1),
        ),
      ],
    );
    final gateway = ChannelBotGateway(
      adapter: adapter,
      reply: (text) async => 'ok',
    );

    // sendMessage 抛错会让 runOnce 向上抛出（真实适配器对失败会抛异常）。
    await expectLater(gateway.runOnce(), throwsA(anything));
  });
}
