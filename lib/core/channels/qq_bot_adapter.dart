import 'dart:convert';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import 'channel_adapter.dart';
import 'webhook_channel_adapter.dart';

class QqBotException implements Exception {
  final String message;
  const QqBotException(this.message);

  @override
  String toString() => message;
}

/// QQ 开放平台 Bot（C2C 单聊）适配器。
///
/// - 校验：`GET /app/v1/me`；
/// - 发送：`POST /app/v1/users/{openid}/messages`；
/// - 接收：本地 webhook 收件箱解析 `C2C_MESSAGE_CREATE` 事件。
class QqBotAdapter extends WebhookChannelAdapter {
  QqBotAdapter({required this.accessToken, String? apiBaseUrl})
    : _apiBaseUrl = apiBaseUrl;

  static const kDefaultApiBaseUrl = 'https://bot.q.qq.com';

  final String accessToken;
  final String? _apiBaseUrl;

  String get _restBase {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  @override
  String get channelName => 'qq';

  @override
  Future<bool> testConnection() async {
    if (accessToken.trim().isEmpty) {
      throw const QqBotException('QQ Bot Token 未配置');
    }
    final dio = createDio();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_restBase/app/v1/me',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          responseType: ResponseType.json,
        ),
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      throw QqBotException(formatDioError(e));
    }
  }

  @override
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
  }) async {
    if (accessToken.trim().isEmpty) {
      throw const QqBotException('QQ Bot Token 未配置');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const QqBotException('回复内容不能为空');
    }
    final dio = createDio();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_restBase/app/v1/users/$toUserId/messages',
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
        ),
        data: {
          'content': [
            {'type': 'text', 'data': trimmed},
          ],
          'msg_type': 0,
        },
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      throw QqBotException(formatDioError(e));
    }
  }

  /// QQ 事件：`C2C_MESSAGE_CREATE`，`content` 为富文本数组。
  @override
  List<ChannelInboundMessage> parseWebhookBody(String body) {
    final messages = <ChannelInboundMessage>[];
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final t = decoded['t'];
      if (t != 'C2C_MESSAGE_CREATE') return messages;
      final d = decoded['d'];
      if (d is! Map) return messages;
      final content = d['content'];
      if (content is! List) return messages;
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map && part['type'] == 'text') {
          buffer.write(part['data']?.toString() ?? '');
        }
      }
      final text = buffer.toString().trim();
      final openid = d['openid']?.toString();
      if (text.isEmpty || openid == null) return messages;
      messages.add(
        ChannelInboundMessage(
          id: d['msgId']?.toString() ?? '${messages.length}',
          fromUserId: openid,
          text: text,
          at: DateTime.now(),
        ),
      );
    } catch (_) {}
    return messages;
  }
}
