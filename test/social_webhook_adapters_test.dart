import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/channels/qq_bot_adapter.dart';
import 'package:ai_chat_app/core/channels/slack_bot_adapter.dart';
import 'package:ai_chat_app/core/channels/wechat_mp_adapter.dart';
import 'package:ai_chat_app/core/channels/whatsapp_cloud_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// 起一个 mock REST 服务器 + 返回 [serverUrl]。
Future<String> _serveRest(
  HttpServer server,
  Map<String, dynamic> Function(HttpRequest) respond,
) async {
  server.listen((request) async {
    final resp = respond(request);
    request.response
      ..statusCode = (resp['status'] as int?) ?? 200
      ..headers.contentType = ContentType.json;
    final payload = resp['payload'];
    if (payload != null) request.response.write(jsonEncode(payload));
    await request.response.close();
  });
  return 'http://127.0.0.1:${server.port}';
}

Future<void> _postWebhook(String base, Map<String, dynamic> payload) async {
  final client = HttpClient();
  final request = await client.postUrl(Uri.parse('$base/webhook'));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(payload));
  final response = await request.close();
  await response.drain<void>();
  client.close();
}

void main() {
  group('WhatsAppCloudAdapter', () {
    test('sends message via Business Cloud API and parses webhook', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final base = await _serveRest(server, (request) {
        if (request.uri.path.endsWith('/messages')) {
          return {
            'payload': {
              'messages': [
                {'id': 'wamid'},
              ],
            },
          };
        }
        return {
          'payload': {'id': '1'},
        };
      });

      final adapter = WhatsAppCloudAdapter(
        accessToken: 'wa-token',
        phoneNumberId: '12345',
        apiBaseUrl: '$base/v21.0',
      );
      addTearDown(adapter.stopWebhook);

      expect(await adapter.testConnection(), isTrue);
      expect(await adapter.sendMessage(toUserId: '1555', text: 'hi'), isTrue);

      final webhookBase = await adapter.startWebhook();
      await _postWebhook(webhookBase, {
        'entry': [
          {
            'changes': [
              {
                'value': {
                  'messages': [
                    {
                      'id': 'm1',
                      'from': '1555',
                      'text': {'body': 'hello'},
                    },
                  ],
                },
              },
            ],
          },
        ],
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final messages = await adapter.poll();
      expect(messages, hasLength(1));
      expect(messages.first.text, 'hello');
      expect(messages.first.fromUserId, '1555');
    });
  });

  group('SlackBotAdapter', () {
    test('sends message and parses events api webhook', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final base = await _serveRest(server, (request) {
        return {
          'payload': {'ok': true},
        };
      });

      final adapter = SlackBotAdapter(botToken: 'xoxb-test', apiBaseUrl: base);
      addTearDown(adapter.stopWebhook);

      expect(await adapter.testConnection(), isTrue);
      expect(await adapter.sendMessage(toUserId: 'C123', text: '回复'), isTrue);

      final webhookBase = await adapter.startWebhook();
      await _postWebhook(webhookBase, {
        'event': {
          'type': 'message',
          'ts': '1',
          'user': 'U1',
          'channel': 'C123',
          'text': '你好',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final messages = await adapter.poll();
      expect(messages, hasLength(1));
      expect(messages.first.text, '你好');
      expect(messages.first.fromUserId, 'U1');
    });

    test('ignores bot messages', () async {
      final adapter = SlackBotAdapter(
        botToken: 'x',
        apiBaseUrl: 'http://127.0.0.1:1',
      );
      final parsed = adapter.parseWebhookBody(
        jsonEncode({
          'event': {'type': 'message', 'bot_id': 'B1', 'text': 'from bot'},
        }),
      );
      expect(parsed, isEmpty);
    });
  });

  group('WechatMpAdapter', () {
    test('gets token, sends custom message, parses xml webhook', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final base = await _serveRest(server, (request) {
        if (request.uri.path == '/cgi-bin/token') {
          return {
            'payload': {'access_token': 'wx-token'},
          };
        }
        return {
          'payload': {'errcode': 0},
        };
      });

      final adapter = WechatMpAdapter(
        appId: 'wx-app',
        appSecret: 'wx-secret',
        apiBaseUrl: base,
      );
      addTearDown(adapter.stopWebhook);

      expect(await adapter.testConnection(), isTrue);
      expect(
        await adapter.sendMessage(toUserId: 'openid-1', text: '回复'),
        isTrue,
      );

      final webhookBase = await adapter.startWebhook();
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$webhookBase/webhook'));
      request.headers.contentType = ContentType.text;
      request.write(
        '<xml><ToUserName><![CDATA[gh_1]]></ToUserName>'
        '<FromUserName><![CDATA[openid-1]]></FromUserName>'
        '<MsgType><![CDATA[text]]></MsgType>'
        '<Content><![CDATA[你好微信]]></Content>'
        '<MsgId>123</MsgId></xml>',
      );
      final response = await request.close();
      await response.drain<void>();
      client.close();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final messages = await adapter.poll();
      expect(messages, hasLength(1));
      expect(messages.first.text, '你好微信');
      expect(messages.first.fromUserId, 'openid-1');
    });
  });

  group('QqBotAdapter', () {
    test('sends C2C message and parses C2C_MESSAGE_CREATE', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final base = await _serveRest(server, (request) {
        return {
          'payload': {'code': 0},
        };
      });

      final adapter = QqBotAdapter(accessToken: 'qq-token', apiBaseUrl: base);
      addTearDown(adapter.stopWebhook);

      expect(await adapter.testConnection(), isTrue);
      expect(
        await adapter.sendMessage(toUserId: 'openid-9', text: '回复'),
        isTrue,
      );

      final webhookBase = await adapter.startWebhook();
      await _postWebhook(webhookBase, {
        'op': 0,
        't': 'C2C_MESSAGE_CREATE',
        'd': {
          'msgId': 'msg-1',
          'openid': 'openid-9',
          'content': [
            {'type': 'text', 'data': '你好 QQ'},
          ],
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final messages = await adapter.poll();
      expect(messages, hasLength(1));
      expect(messages.first.text, '你好 QQ');
      expect(messages.first.fromUserId, 'openid-9');
    });
  });
}
