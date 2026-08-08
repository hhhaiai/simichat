import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import 'channel_adapter.dart';

class TelegramBotException implements Exception {
  final String message;
  const TelegramBotException(this.message);

  @override
  String toString() => message;
}

/// Telegram Bot API 适配器。
///
/// 通过 Bot Token 与 `api.telegram.org/bot<TOKEN>/...` 交互：
/// - `getMe`：校验 Token；
/// - `getUpdates`：长轮询拉取新消息（内部维护 offset，天然去重）；
/// - `sendMessage`：回复用户。
class TelegramBotAdapter implements ChannelAdapter {
  TelegramBotAdapter({
    required this.botToken,
    String? apiBaseUrl,
    this.pollTimeoutSeconds = 25,
  }) : _apiBaseUrl = apiBaseUrl;

  /// 可注入的 API 根地址（测试用）；默认官方地址。
  static const kDefaultApiBaseUrl = 'https://api.telegram.org';

  final String botToken;
  final int pollTimeoutSeconds;
  final String? _apiBaseUrl;

  int _lastUpdateId = 0;

  String get _endpoint {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}/bot$botToken';
  }

  @override
  String get channelName => 'telegram';

  @override
  Future<bool> testConnection() async {
    final me = await getMe();
    return me != null;
  }

  /// 校验 Token，返回 bot 用户名或 null。
  Future<String?> getMe() async {
    if (botToken.trim().isEmpty) {
      throw const TelegramBotException('Telegram Bot Token 未配置');
    }
    final dio = createDio();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_endpoint/getMe',
        options: Options(responseType: ResponseType.json),
      );
      final ok = response.data?['ok'] == true;
      if (!ok) {
        final desc = response.data?['description'];
        throw TelegramBotException(
          'Bot Token 无效${desc != null ? '：$desc' : ''}',
        );
      }
      final user = response.data?['result'];
      if (user is Map) return user['username'] as String?;
      return null;
    } on DioException catch (e) {
      throw TelegramBotException(formatDioError(e));
    }
  }

  @override
  Future<List<ChannelInboundMessage>> poll() async {
    if (botToken.trim().isEmpty) {
      throw const TelegramBotException('Telegram Bot Token 未配置');
    }
    final dio = createDio();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_endpoint/getUpdates',
        queryParameters: {
          'offset': _lastUpdateId + 1,
          'timeout': pollTimeoutSeconds,
          'allowed_updates': '["message"]',
        },
        options: Options(
          responseType: ResponseType.json,
          // 长轮询允许比默认更长的接收超时。
          receiveTimeout: Duration(seconds: pollTimeoutSeconds + 10),
        ),
      );
      final result = response.data?['result'];
      if (result is! List) return const [];

      final messages = <ChannelInboundMessage>[];
      for (final update in result) {
        if (update is! Map) continue;
        final updateId = update['update_id'];
        // 只处理新消息：offset 语义要求跳过已处理过的 update_id。
        if (updateId is! int || updateId <= _lastUpdateId) continue;
        _lastUpdateId = updateId;
        final message = update['message'];
        if (message is! Map) continue;
        final text = message['text'];
        if (text is! String || text.trim().isEmpty) continue;
        final from = message['from'];
        final chat = message['chat'];
        final userId = from is Map
            ? '${from['id']}'
            : chat is Map
            ? '${chat['id']}'
            : null;
        if (userId == null) continue;
        messages.add(
          ChannelInboundMessage(
            id: '${update['update_id']}',
            fromUserId: userId,
            text: text,
            at: DateTime.now(),
          ),
        );
      }
      return messages;
    } on DioException catch (e) {
      throw TelegramBotException(formatDioError(e));
    }
  }

  @override
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
  }) async {
    if (botToken.trim().isEmpty) {
      throw const TelegramBotException('Telegram Bot Token 未配置');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const TelegramBotException('回复内容不能为空');
    }
    final dio = createDio();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_endpoint/sendMessage',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          responseType: ResponseType.json,
        ),
        data: jsonEncode({
          'chat_id': toUserId,
          'text': trimmed,
          'disable_web_page_preview': true,
        }),
      );
      return response.data?['ok'] == true;
    } on DioException catch (e) {
      throw TelegramBotException(formatDioError(e));
    }
  }
}
