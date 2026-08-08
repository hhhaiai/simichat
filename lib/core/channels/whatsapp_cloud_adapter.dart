import 'dart:convert';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import 'channel_adapter.dart';
import 'webhook_channel_adapter.dart';

class WhatsAppCloudException implements Exception {
  final String message;
  const WhatsAppCloudException(this.message);

  @override
  String toString() => message;
}

/// WhatsApp Business Cloud API 适配器。
///
/// - 校验：`GET /{phone_number_id}`；
/// - 发送：`POST /{phone_number_id}/messages`（Bearer Token）；
/// - 接收：本地 webhook 收件箱解析 WhatsApp 事件回调。
class WhatsAppCloudAdapter extends WebhookChannelAdapter {
  WhatsAppCloudAdapter({
    required this.accessToken,
    required this.phoneNumberId,
    String? apiBaseUrl,
  }) : _apiBaseUrl = apiBaseUrl;

  static const kDefaultApiBaseUrl = 'https://graph.facebook.com/v21.0';

  final String accessToken;
  final String phoneNumberId;
  final String? _apiBaseUrl;

  String get _restBase {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  @override
  String get channelName => 'whatsapp';

  @override
  Future<bool> testConnection() async {
    if (accessToken.trim().isEmpty || phoneNumberId.trim().isEmpty) {
      throw const WhatsAppCloudException(
        'WhatsApp Token / Phone Number ID 未配置',
      );
    }
    final dio = createDio();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_restBase/$phoneNumberId',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          responseType: ResponseType.json,
        ),
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      throw WhatsAppCloudException(formatDioError(e));
    }
  }

  @override
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
  }) async {
    if (accessToken.trim().isEmpty || phoneNumberId.trim().isEmpty) {
      throw const WhatsAppCloudException(
        'WhatsApp Token / Phone Number ID 未配置',
      );
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const WhatsAppCloudException('回复内容不能为空');
    }
    final dio = createDio();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_restBase/$phoneNumberId/messages',
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
        ),
        data: {
          'messaging_product': 'whatsapp',
          'to': toUserId,
          'type': 'text',
          'text': {'body': trimmed},
        },
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      throw WhatsAppCloudException(formatDioError(e));
    }
  }

  @override
  List<ChannelInboundMessage> parseWebhookBody(String body) {
    final messages = <ChannelInboundMessage>[];
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final entries = decoded['entry'];
      if (entries is! List) return messages;
      for (final entry in entries) {
        if (entry is! Map) continue;
        final changes = entry['changes'];
        if (changes is! List) continue;
        for (final change in changes) {
          if (change is! Map) continue;
          final value = change['value'];
          if (value is! Map) continue;
          final valueMessages = value['messages'];
          if (valueMessages is! List) continue;
          for (final m in valueMessages) {
            if (m is! Map) continue;
            final from = m['from']?.toString();
            final text = m['text'];
            final bodyText = text is Map ? text['body']?.toString() : null;
            if (from == null || bodyText == null || bodyText.trim().isEmpty) {
              continue;
            }
            messages.add(
              ChannelInboundMessage(
                id: m['id']?.toString() ?? '${messages.length}',
                fromUserId: from,
                text: bodyText.trim(),
                at: DateTime.now(),
              ),
            );
          }
        }
      }
    } catch (_) {}
    return messages;
  }
}
