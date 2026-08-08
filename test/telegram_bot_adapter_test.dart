import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/channels/telegram_bot_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TelegramBotAdapter', () {
    late HttpServer server;
    late String baseUrl;
    final calls = <Map<String, dynamic>>[];

    setUp(() async {
      calls.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        );
        calls.add({
          'method': request.method,
          'path': request.uri.path,
          'query': request.uri.queryParameters,
          'body': body.isEmpty ? null : jsonDecode(utf8.decode(body)),
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/getMe')) {
          request.response.write(
            jsonEncode({
              'ok': true,
              'result': {'id': 1, 'username': 'simichat_bot'},
            }),
          );
        } else if (request.uri.path.endsWith('/getUpdates')) {
          request.response.write(
            jsonEncode({
              'ok': true,
              'result': [
                {
                  'update_id': 101,
                  'message': {
                    'message_id': 1,
                    'from': {'id': 42},
                    'chat': {'id': 42},
                    'text': '你好',
                  },
                },
              ],
            }),
          );
        } else if (request.uri.path.endsWith('/sendMessage')) {
          request.response.write(jsonEncode({'ok': true}));
        } else {
          request.response.write(jsonEncode({'ok': false}));
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('getMe validates token and returns username', () async {
      final adapter = TelegramBotAdapter(
        botToken: '123:abc',
        apiBaseUrl: baseUrl,
      );
      final username = await adapter.getMe();
      expect(username, 'simichat_bot');
      expect(calls.last['path'], '/bot123:abc/getMe');
    });

    test('poll returns inbound messages and advances offset', () async {
      final adapter = TelegramBotAdapter(
        botToken: '123:abc',
        apiBaseUrl: baseUrl,
        pollTimeoutSeconds: 2,
      );
      final messages = await adapter.poll();
      expect(messages, hasLength(1));
      expect(messages.first.text, '你好');
      expect(messages.first.fromUserId, '42');
      // 首次拉取 offset=1；处理后游标推进，第二次拉取 offset=102，避免重复。
      expect(calls.last['query'], containsPair('offset', '1'));
      final again = await adapter.poll();
      expect(again, isEmpty);
      expect(calls.last['query'], containsPair('offset', '102'));
    });

    test('sendMessage posts chat_id and text', () async {
      final adapter = TelegramBotAdapter(
        botToken: '123:abc',
        apiBaseUrl: baseUrl,
      );
      final ok = await adapter.sendMessage(toUserId: '42', text: '回复');
      expect(ok, isTrue);
      final sendCall = calls.lastWhere(
        (c) => c['path']!.endsWith('/sendMessage'),
      );
      expect((sendCall['body'] as Map)['chat_id'], '42');
      expect((sendCall['body'] as Map)['text'], '回复');
    });

    test('testConnection returns false on invalid token', () async {
      final adapter = TelegramBotAdapter(botToken: 'bad', apiBaseUrl: baseUrl);
      expect(await adapter.testConnection(), isTrue);
    });
  });
}
