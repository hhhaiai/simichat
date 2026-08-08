import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import 'channel_adapter.dart';
import 'webhook_channel_adapter.dart';

class WechatMpException implements Exception {
  final String message;
  const WechatMpException(this.message);

  @override
  String toString() => message;
}

/// 微信公众号（服务号）适配器。
///
/// - 校验 / 取 token：`GET /cgi-bin/token?grant_type=client_credential&appid=...&secret=...`；
/// - 发送：`POST /cgi-bin/message/custom/send`（客服消息）；
/// - 接收：公众号消息回调为 XML，本地 webhook 收件箱解析后回复。
class WechatMpAdapter extends WebhookChannelAdapter {
  WechatMpAdapter({
    required this.appId,
    required this.appSecret,
    String? apiBaseUrl,
  }) : _apiBaseUrl = apiBaseUrl;

  static const kDefaultApiBaseUrl = 'https://api.weixin.qq.com';

  final String appId;
  final String appSecret;
  final String? _apiBaseUrl;

  String get _restBase {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  @override
  String get channelName => 'wechat-mp';

  Future<String> _getAccessToken() async {
    if (appId.trim().isEmpty || appSecret.trim().isEmpty) {
      throw const WechatMpException('微信公众号 AppID / AppSecret 未配置');
    }
    final dio = createDio();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_restBase/cgi-bin/token',
        queryParameters: {
          'grant_type': 'client_credential',
          'appid': appId.trim(),
          'secret': appSecret.trim(),
        },
        options: Options(responseType: ResponseType.json),
      );
      final errcode = response.data?['errcode'];
      if (errcode != null && errcode != 0) {
        throw WechatMpException(
          '微信鉴权失败：${response.data?['errmsg'] ?? errcode}',
        );
      }
      final token = response.data?['access_token'];
      if (token is! String || token.isEmpty) {
        throw const WechatMpException('微信未返回 access_token');
      }
      return token;
    } on DioException catch (e) {
      throw WechatMpException(formatDioError(e));
    }
  }

  @override
  Future<bool> testConnection() async {
    await _getAccessToken();
    return true;
  }

  @override
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
  }) async {
    final token = await _getAccessToken();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const WechatMpException('回复内容不能为空');
    }
    final dio = createDio();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_restBase/cgi-bin/message/custom/send',
        queryParameters: {'access_token': token},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          responseType: ResponseType.json,
        ),
        data: {
          'touser': toUserId,
          'msgtype': 'text',
          'text': {'content': trimmed},
        },
      );
      return response.data?['errcode'] == 0;
    } on DioException catch (e) {
      throw WechatMpException(formatDioError(e));
    }
  }

  /// 公众号消息回调 XML：`<Content>` 文本、`<FromUserName>` 用户 openid。
  @override
  List<ChannelInboundMessage> parseWebhookBody(String body) {
    final messages = <ChannelInboundMessage>[];
    final from = _xmlField(body, 'FromUserName');
    final msgType = _xmlField(body, 'MsgType');
    final content = _xmlField(body, 'Content');
    final msgId = _xmlField(body, 'MsgId');
    if (from != null &&
        msgType == 'text' &&
        content != null &&
        content.isNotEmpty) {
      messages.add(
        ChannelInboundMessage(
          id: msgId ?? '${messages.length}',
          fromUserId: from,
          text: content.trim(),
          at: DateTime.now(),
        ),
      );
    }
    return messages;
  }

  String? _xmlField(String xml, String name) {
    final match = RegExp(
      '<$name>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</$name>',
      dotAll: true,
    ).firstMatch(xml);
    return match?.group(1);
  }
}
