import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/channels/feishu_bot_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeishuBotAdapter', () {
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        if (request.uri.path ==
            '/open-apis/auth/v3/tenant_access_token/internal') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({'code': 0, 'tenant_access_token': 'feishu-token'}),
            );
        } else if (request.uri.path == '/open-apis/im/v1/messages') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'code': 0,
                'data': {'message_id': 'm1'},
              }),
            );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('testConnection obtains tenant access token', () async {
      final adapter = FeishuBotAdapter(
        appId: 'cli_app',
        appSecret: 'secret',
        apiBaseUrl: baseUrl,
      );
      expect(await adapter.testConnection(), isTrue);
    });

    test('sendMessage posts text with bearer token', () async {
      final adapter = FeishuBotAdapter(
        appId: 'cli_app',
        appSecret: 'secret',
        apiBaseUrl: baseUrl,
      );
      final ok = await adapter.sendMessage(toUserId: 'ou_123', text: '回复');
      expect(ok, isTrue);
    });

    test('webhook inbox ingests text events and poll drains them', () async {
      final adapter = FeishuBotAdapter(
        appId: 'cli_app',
        appSecret: 'secret',
        apiBaseUrl: baseUrl,
      );
      addTearDown(adapter.stopWebhook);
      final webhookBase = await adapter.startWebhook();

      // 模拟飞书事件回调。
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('$webhookBase/feishu/webhook'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'event': {
            'message': {
              'message_id': 'om_1',
              'message_type': 'text',
              'chat_id': 'oc_123',
              'content': jsonEncode({'text': '你好飞书'}),
            },
          },
        }),
      );
      final response = await request.close();
      await response.drain<void>();
      client.close();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final messages = await adapter.poll();
      expect(messages, hasLength(1));
      expect(messages.first.text, '你好飞书');
      expect(messages.first.fromUserId, 'oc_123');
    });
  });
}
