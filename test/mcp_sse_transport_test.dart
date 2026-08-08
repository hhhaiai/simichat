import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'SseTransport resolves relative MCP message endpoint against server URL',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final postPaths = <String>[];
      HttpResponse? sseResponse;

      final subscription = server.listen((request) async {
        if (request.method == 'GET' && request.uri.path == '/mcp/sse/test') {
          sseResponse = request.response
            ..bufferOutput = false
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType(
              'text',
              'event-stream',
              charset: 'utf-8',
            )
            ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
          sseResponse!
            ..write(': connected\n\n')
            ..write('event: endpoint\n')
            ..write('data: /mcp/messages/session-1\n\n');
          await sseResponse!.flush();
          return;
        }

        if (request.method == 'POST' &&
            request.uri.path == '/mcp/messages/session-1') {
          postPaths.add(request.uri.path);
          final body = await utf8.decoder.bind(request).join();
          final message = jsonDecode(body) as Map<String, dynamic>;
          final id = message['id'];
          if (id != null) {
            final method = message['method'] as String?;
            final result = switch (method) {
              'initialize' => <String, dynamic>{
                'protocolVersion': '2024-11-05',
                'capabilities': {'tools': {}, 'resources': {}},
                'serverInfo': {'name': 'relative-sse-test', 'version': '1.0.0'},
              },
              'tools/list' => <String, dynamic>{'tools': []},
              'resources/list' => <String, dynamic>{'resources': []},
              _ => <String, dynamic>{},
            };
            sseResponse!
              ..write('event: message\n')
              ..write(
                'data: ${jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result})}\n\n',
              );
            await sseResponse!.flush();
          }
          request.response
            ..statusCode = HttpStatus.accepted
            ..headers.contentType = ContentType.json
            ..write('{"accepted":true}');
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final client = McpClient(
        name: 'relative-sse-test',
        transport: SseTransport(
          url: 'http://127.0.0.1:${server.port}/mcp/sse/test',
        ),
      );
      addTearDown(client.dispose);

      await client.initialize();

      expect(client.isInitialized, isTrue);
      expect(postPaths, contains('/mcp/messages/session-1'));
    },
  );

  test(
    'SseTransport rejects non-success status and clears the client',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write('not authorized');
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final transport = SseTransport(
        url: 'http://127.0.0.1:${server.port}/mcp/sse/test',
        connectTimeout: const Duration(seconds: 1),
        endpointTimeout: const Duration(seconds: 1),
      );
      addTearDown(transport.disconnect);

      await expectLater(
        transport.connect((_) {}),
        throwsA(
          isA<McpSseException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 401'),
          ),
        ),
      );
      await expectLater(
        transport.send({'jsonrpc': '2.0', 'id': 1}),
        throwsA(isA<McpSseException>()),
      );
    },
  );

  test(
    'SseTransport cleans up when endpoint does not arrive in time',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          )
          ..bufferOutput = false;
        request.response.write(': connected\n\n');
        await request.response.flush();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final transport = SseTransport(
        url: 'http://127.0.0.1:${server.port}/mcp/sse/test',
        connectTimeout: const Duration(seconds: 1),
        endpointTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(transport.disconnect);

      await expectLater(
        transport.connect((_) {}),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        transport.send({'jsonrpc': '2.0', 'id': 1}),
        throwsA(isA<McpSseException>()),
      );
    },
  );
}
