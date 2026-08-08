import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import 'channel_adapter.dart';

class FeishuBotException implements Exception {
  final String message;
  const FeishuBotException(this.message);

  @override
  String toString() => message;
}

/// 飞书（Lark）Bot 适配器。
///
/// - 校验 / 取 token：`POST /open-apis/auth/v3/tenant_access_token/internal`；
/// - 发送：`POST /open-apis/im/v1/messages`（text 消息）；
/// - 接收：飞书使用事件订阅而非轮询，因此适配器在本机起一个 webhook 收件箱
///   （[startWebhook]），用户把飞书应用的事件回调 URL 指向该地址的公网隧道，
///   [poll] 只排空收件箱。
class FeishuBotAdapter implements ChannelAdapter {
  FeishuBotAdapter({
    required this.appId,
    required this.appSecret,
    String? apiBaseUrl,
  }) : _apiBaseUrl = apiBaseUrl;

  static const kDefaultApiBaseUrl = 'https://open.feishu.cn';

  final String appId;
  final String appSecret;
  final String? _apiBaseUrl;

  HttpServer? _webhookServer;
  final _inbox = <ChannelInboundMessage>[];
  StreamSubscription<HttpRequest>? _subscription;

  String get _restBase {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  @override
  String get channelName => 'feishu';

  Future<String> _getTenantToken() async {
    if (appId.trim().isEmpty || appSecret.trim().isEmpty) {
      throw const FeishuBotException('飞书 App ID / App Secret 未配置');
    }
    final dio = createDio();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_restBase/open-apis/auth/v3/tenant_access_token/internal',
        options: Options(responseType: ResponseType.json),
        data: {'app_id': appId.trim(), 'app_secret': appSecret.trim()},
      );
      final code = response.data?['code'];
      if (code != 0) {
        final msg = response.data?['msg'];
        throw FeishuBotException('飞书鉴权失败${msg != null ? '：$msg' : ''}');
      }
      final token = response.data?['tenant_access_token'];
      if (token is! String || token.isEmpty) {
        throw const FeishuBotException('飞书未返回 tenant_access_token');
      }
      return token;
    } on DioException catch (e) {
      throw FeishuBotException(formatDioError(e));
    }
  }

  @override
  Future<bool> testConnection() async {
    await _getTenantToken();
    return true;
  }

  @override
  Future<List<ChannelInboundMessage>> poll() async {
    final messages = List<ChannelInboundMessage>.from(_inbox);
    _inbox.clear();
    return messages;
  }

  @override
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
  }) async {
    final token = await _getTenantToken();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const FeishuBotException('回复内容不能为空');
    }
    final dio = createDio();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_restBase/open-apis/im/v1/messages',
        queryParameters: {'receive_id_type': 'open_id'},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
        ),
        data: {
          'receive_id': toUserId,
          'msg_type': 'text',
          'content': jsonEncode({'text': trimmed}),
        },
      );
      return response.data?['code'] == 0;
    } on DioException catch (e) {
      throw FeishuBotException(formatDioError(e));
    }
  }

  /// 在本机启动 webhook 收件箱，返回回调地址（不含路径）。
  /// 用户在飞书开放平台把事件回调 URL 配置为 `<该地址>/feishu/webhook` 的公网隧道。
  Future<String> startWebhook({int port = 0}) async {
    if (_webhookServer != null) return _webhookBase;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _webhookServer = server;
    _subscription = server.listen((request) async {
      if (request.uri.path == '/feishu/webhook' && request.method == 'POST') {
        try {
          final body = await request.fold<List<int>>(
            [],
            (acc, chunk) => acc..addAll(chunk),
          );
          _ingestEvent(jsonDecode(utf8.decode(body)));
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

  /// 解析飞书事件订阅 payload：`event.message` 文本消息。
  void _ingestEvent(Map<String, dynamic> payload) {
    final event = payload['event'];
    if (event is! Map) return;
    final message = event['message'];
    if (message is! Map) return;
    final messageType = message['message_type'];
    if (messageType != 'text') return;
    final content = message['content'];
    if (content is! String) return;
    String? text;
    try {
      text = jsonDecode(content)['text'] as String?;
    } catch (_) {}
    if (text == null || text.trim().isEmpty) return;
    final chatId = message['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty) return;
    _inbox.add(
      ChannelInboundMessage(
        id: message['message_id']?.toString() ?? '${_inbox.length}',
        fromUserId: chatId,
        text: text.trim(),
        at: DateTime.now(),
      ),
    );
  }

  Future<void> stopWebhook() async {
    await _subscription?.cancel();
    _subscription = null;
    await _webhookServer?.close(force: true);
    _webhookServer = null;
  }
}
