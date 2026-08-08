import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'channel_adapter.dart';

/// 基于「REST 发送 + 本地 webhook 收件箱接收」的社交通道基类。
///
/// 飞书 / WhatsApp / Slack / 微信公众号 / QQ 等平台多使用事件订阅而非轮询：
/// 本类在本机起一个 `HttpServer` 作为 webhook 回调端点，外部平台通过公网隧道
/// 把事件回调 POST 到 `{address}{webhookPath}`，[poll] 只排空收件箱。
/// 子类实现 [testConnection] / [sendMessage] / [parseWebhookBody]。
abstract class WebhookChannelAdapter implements ChannelAdapter {
  HttpServer? _webhookServer;
  StreamSubscription<HttpRequest>? _subscription;
  final _inbox = <ChannelInboundMessage>[];

  /// 本机 webhook 回调路径（默认 `/webhook`）。
  String get webhookPath => '/webhook';

  /// 启动本机收件箱，返回回调地址（不含路径）。
  Future<String> startWebhook({int port = 0}) async {
    if (_webhookServer != null) return _webhookBase;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _webhookServer = server;
    _subscription = server.listen((request) async {
      if (request.uri.path == webhookPath && request.method == 'POST') {
        try {
          final body = await request.fold<List<int>>(
            [],
            (acc, chunk) => acc..addAll(chunk),
          );
          _inbox.addAll(parseWebhookBody(utf8.decode(body)));
        } catch (_) {}
        request.response.statusCode = 200;
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    return _webhookBase;
  }

  String get _webhookBase => 'http://127.0.0.1:${_webhookServer!.port}';

  /// 解析平台事件回调 body，返回入站消息。
  List<ChannelInboundMessage> parseWebhookBody(String body);

  Future<void> stopWebhook() async {
    await _subscription?.cancel();
    _subscription = null;
    await _webhookServer?.close(force: true);
    _webhookServer = null;
  }

  @override
  Future<List<ChannelInboundMessage>> poll() async {
    final messages = List<ChannelInboundMessage>.from(_inbox);
    _inbox.clear();
    return messages;
  }
}
