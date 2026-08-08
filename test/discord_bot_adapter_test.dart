import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/channels/discord_bot_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiscordBotAdapter', () {
    late HttpServer restServer;
    late String restBase;

    setUp(() async {
      restServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      restBase = 'http://127.0.0.1:${restServer.port}/api/v10';
      restServer.listen((request) async {
        if (request.uri.path == '/api/v10/users/@me') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': '1', 'username': 'simichat_bot'}));
        } else if (request.uri.path.startsWith('/api/v10/channels/') &&
            request.method == 'POST') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': 'msg-ok'}));
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await restServer.close(force: true);
    });

    test('getMe returns bot username via REST', () async {
      final adapter = DiscordBotAdapter(
        botToken: 'token',
        apiBaseUrl: restBase,
      );
      final username = await adapter.getMe();
      expect(username, 'simichat_bot');
    });

    test('sendMessage posts to channel', () async {
      final adapter = DiscordBotAdapter(
        botToken: 'token',
        apiBaseUrl: restBase,
      );
      final ok = await adapter.sendMessage(toUserId: 'ch123', text: '回复');
      expect(ok, isTrue);
    });

    test('poll receives MESSAGE_CREATE from gateway', () async {
      // 启动一个本地 WebSocket 网关。
      final wsServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wsServer.close(force: true));
      final gatewayUrl = 'ws://127.0.0.1:${wsServer.port}';
      wsServer.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        // HELLO
        socket.add(
          jsonEncode({
            'op': 10,
            'd': {'heartbeat_interval': 5000},
          }),
        );
        // 等待 IDENTIFY
        await socket.first.timeout(
          const Duration(seconds: 3),
          onTimeout: () => '',
        );
        socket.add(jsonEncode({'op': 0, 't': 'READY', 'd': {}}));
        socket.add(
          jsonEncode({
            'op': 0,
            't': 'MESSAGE_CREATE',
            'd': {
              'id': 'm1',
              'channel_id': 'ch123',
              'author': {'id': 'u1', 'bot': false},
              'content': '你好 Discord',
            },
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await socket.close();
      });

      final adapter = DiscordBotAdapter(
        botToken: 'token',
        apiBaseUrl: restBase,
        gatewayUrl: gatewayUrl,
      );
      addTearDown(adapter.dispose);

      final messages = await adapter.poll();
      expect(messages, hasLength(1));
      expect(messages.first.text, '你好 Discord');
      expect(messages.first.fromUserId, 'ch123');
    });
  });
}
