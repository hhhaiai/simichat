import 'dart:convert';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import 'channel_adapter.dart';
import 'webhook_channel_adapter.dart';

class SlackBotException implements Exception {
  final String message;
  const SlackBotException(this.message);

  @override
  String toString() => message;
}

/// Slack Bot 适配器（Web API + Events API webhook）。
///
/// - 校验：`POST /auth.test`；
/// - 发送：`POST /chat.postMessage`；
/// - 接收：本地 webhook 收件箱解析 Slack Events API 的 `message` 事件。
class SlackBotAdapter extends WebhookChannelAdapter {
  SlackBotAdapter({required this.botToken, String? apiBaseUrl})
    : _apiBaseUrl = apiBaseUrl;

  static const kDefaultApiBaseUrl = 'https://slack.com/api';

  final String botToken;
  final String? _apiBaseUrl;

  String get _restBase {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  @override
  String get channelName => 'slack';

  @override
  Future<bool> testConnection() async {
    if (botToken.trim().isEmpty) {
      throw const SlackBotException('Slack Bot Token 未配置');
    }
    final dio = createDio();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_restBase/auth.test',
        options: Options(
          headers: {'Authorization': 'Bearer $botToken'},
          responseType: ResponseType.json,
        ),
      );
      return response.data?['ok'] == true;
    } on DioException catch (e) {
      throw SlackBotException(formatDioError(e));
    }
  }

  @override
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
  }) async {
    if (botToken.trim().isEmpty) {
      throw const SlackBotException('Slack Bot Token 未配置');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const SlackBotException('回复内容不能为空');
    }
    final dio = createDio();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_restBase/chat.postMessage',
        options: Options(
          headers: {
            'Authorization': 'Bearer $botToken',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
        ),
        data: {'channel': toUserId, 'text': trimmed},
      );
      return response.data?['ok'] == true;
    } on DioException catch (e) {
      throw SlackBotException(formatDioError(e));
    }
  }

  @override
  List<ChannelInboundMessage> parseWebhookBody(String body) {
    final messages = <ChannelInboundMessage>[];
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final event = decoded['event'];
      if (event is! Map) return messages;
      if (event['type'] != 'message') return messages;
      if (event['bot_id'] != null) return messages;
      final text = event['text']?.toString();
      final channel = event['channel']?.toString();
      final user = event['user']?.toString();
      if (text == null || text.trim().isEmpty || channel == null) {
        return messages;
      }
      messages.add(
        ChannelInboundMessage(
          id: event['ts']?.toString() ?? '${messages.length}',
          fromUserId: user ?? channel,
          text: text.trim(),
          at: DateTime.now(),
        ),
      );
    } catch (_) {}
    return messages;
  }
}
