import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import 'channel_adapter.dart';

class DiscordBotException implements Exception {
  final String message;
  const DiscordBotException(this.message);

  @override
  String toString() => message;
}

/// Discord Bot 适配器。
///
/// - 接收：Gateway WebSocket（v10），IDENTIFY 后订阅 `MESSAGE_CREATE`；
/// - 发送：REST `POST /channels/{id}/messages`；
/// - 校验：REST `GET /users/@me`。
///
/// `fromUserId` 使用消息的 `channel_id`，以便回复回到同一会话。
class DiscordBotAdapter implements ChannelAdapter {
  DiscordBotAdapter({
    required this.botToken,
    String? apiBaseUrl,
    String? gatewayUrl,
  }) : _apiBaseUrl = apiBaseUrl,
       _gatewayUrl = gatewayUrl;

  static const kDefaultApiBaseUrl = 'https://discord.com/api/v10';
  static const kDefaultGatewayUrl =
      'wss://gateway.discord.gg/?v=10&encoding=json';

  final String botToken;
  final String? _apiBaseUrl;
  final String? _gatewayUrl;

  WebSocket? _socket;
  final _inbox = <ChannelInboundMessage>[];
  bool _identified = false;
  Timer? _heartbeatTimer;

  String get _restBase {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  String get _gateway => _gatewayUrl ?? kDefaultGatewayUrl;

  @override
  String get channelName => 'discord';

  @override
  Future<bool> testConnection() async {
    final me = await getMe();
    return me != null;
  }

  /// 校验 Token，返回 bot 用户名或 null。
  Future<String?> getMe() async {
    if (botToken.trim().isEmpty) {
      throw const DiscordBotException('Discord Bot Token 未配置');
    }
    final dio = createDio();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_restBase/users/@me',
        options: Options(
          headers: {'Authorization': 'Bot $botToken'},
          responseType: ResponseType.json,
        ),
      );
      final user = response.data;
      if (user == null) return null;
      return user['username'] as String?;
    } on DioException catch (e) {
      throw DiscordBotException(formatDioError(e));
    }
  }

  /// 确保 Gateway 连接已建立（幂等）。
  Future<void> ensureConnected() async {
    if (_socket != null && _identified) return;
    if (botToken.trim().isEmpty) {
      throw const DiscordBotException('Discord Bot Token 未配置');
    }
    await _connectGateway();
  }

  Future<void> _connectGateway() async {
    await _disconnectGateway();
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(_gateway);
    } catch (e) {
      throw DiscordBotException('无法连接 Discord Gateway：$e');
    }
    _socket = socket;
    _identified = false;

    final subscription = socket.listen(
      (raw) => _onGatewayEvent(socket, raw),
      onError: (_) {},
      onDone: () => _disconnectGateway(),
      cancelOnError: true,
    );
    // 连接建立后发送 IDENTIFY（OP 2）。
    socket.add(
      jsonEncode({
        'op': 2,
        'd': {
          'token': botToken,
          'intents': 1 << 9, // GUILD_MESSAGES（接收私聊需要 512？私聊用 DM_CHANNELS）
          'properties': {
            'os': 'unknown',
            'browser': 'simichat',
            'device': 'simichat',
          },
        },
      }),
    );
    // 等待 HELLO 后开始收发；记录 subscription 防泄漏。
    _subscriptions.add(subscription);
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  void _onGatewayEvent(WebSocket socket, dynamic raw) {
    final Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final op = payload['op'];
    switch (op) {
      case 10: // HELLO
        final interval = payload['d']?['heartbeat_interval'];
        if (interval is int && interval > 0) {
          _heartbeatTimer?.cancel();
          _heartbeatTimer = Timer.periodic(
            Duration(milliseconds: interval),
            (_) => socket.add(jsonEncode({'op': 1, 'd': null})),
          );
        }
        break;
      case 11: // HEARTBEAT_ACK
        break;
      case 0: // DISPATCH
        final t = payload['t'];
        if (t == 'READY') {
          _identified = true;
        } else if (t == 'MESSAGE_CREATE') {
          final d = payload['d'];
          if (d is Map) {
            final author = d['author'];
            final isBot = author is Map && author['bot'] == true;
            if (!isBot) {
              final content = d['content'];
              final channelId = d['channel_id'];
              if (content is String &&
                  content.trim().isNotEmpty &&
                  channelId is String) {
                _inbox.add(
                  ChannelInboundMessage(
                    id: '${d['id']}',
                    fromUserId: channelId,
                    text: content,
                    at: DateTime.now(),
                  ),
                );
              }
            }
          }
        }
        break;
    }
  }

  @override
  Future<List<ChannelInboundMessage>> poll() async {
    await ensureConnected();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final messages = List<ChannelInboundMessage>.from(_inbox);
    _inbox.clear();
    return messages;
  }

  @override
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
  }) async {
    if (botToken.trim().isEmpty) {
      throw const DiscordBotException('Discord Bot Token 未配置');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const DiscordBotException('回复内容不能为空');
    }
    final dio = createDio();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_restBase/channels/$toUserId/messages',
        options: Options(
          headers: {
            'Authorization': 'Bot $botToken',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
        ),
        data: jsonEncode({'content': trimmed}),
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      throw DiscordBotException(formatDioError(e));
    }
  }

  Future<void> _disconnectGateway() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _socket = null;
    _identified = false;
  }

  Future<void> dispose() => _disconnectGateway();
}
