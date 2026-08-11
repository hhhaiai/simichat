import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/mcp/bundled_node_runtime.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mobile stdio transport runs the runtime-server JSONL session',
    () async {
      final portProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = portProbe.port;
      await portProbe.close();

      final workspace = await Directory.systemTemp.createTemp(
        'simichat-mobile-stdio-',
      );
      final process = await Process.start(
        'node',
        ['tools/mcp_runtime/container/runtime-server.mjs'],
        workingDirectory: Directory.current.path,
        environment: <String, String>{
          ...Platform.environment,
          'MCP_RUNTIME_HOST': '127.0.0.1',
          'MCP_RUNTIME_PORT': '$port',
          'MCP_RUNTIME_WORKSPACE_ROOT': workspace.path,
          'MCP_RUNTIME_EXTENSION_ROOT': workspace.parent.path,
          'SIMICHAT_NODE_RUNTIME_KIND': 'android-embedded',
          'SIMICHAT_NODE_APP_MANAGED': 'true',
        },
        runInShell: false,
      );
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());

    McpClient? client;
    addTearDown(() async {
      await client?.dispose();
      if (process.kill(ProcessSignal.sigterm)) {
        await process.exitCode;
      }
        await workspace.delete(recursive: true);
      });

      await _waitForHealth('http://127.0.0.1:$port/health');
      client = McpClient(
        name: 'mobile-stdio-protocol-test',
        transport: MobileStdioTransport(
          command: 'npx',
          args: const ['--yes', '@modelcontextprotocol/server-time@latest'],
          baseUrl: 'http://127.0.0.1:$port',
          ensureRuntime: false,
        ),
      );

      await client.initialize();
      expect(client.tools.map((tool) => tool.name), contains('simichat.now'));
      final result = await client.callTool('simichat.runtime_info', const {});
      expect(result.isError, isFalse);
      final payload =
          jsonDecode(result.content.single.text!) as Map<String, dynamic>;
      expect(payload['transport'], 'stdio');
      expect(payload['wireProtocol'], 'jsonl');
      expect(payload['command'], 'npx');
      expect(payload['args'], [
        '--yes',
        '@modelcontextprotocol/server-time@latest',
      ]);
    },
  );

  test(
    'unknown mobile stdio command fails before a session is created',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        if (request.method == 'POST' &&
            request.uri.path == '/runtime/stdio/start') {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({'error': '移动 Runtime 未打包该 stdio command/args'}),
            );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      await expectLater(
        BundledNodeRuntime.startStdioSession(
          command: 'not-a-mobile-command',
          baseUrl: 'http://127.0.0.1:${server.port}',
          ensureRuntime: false,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('移动 Runtime 未打包'),
          ),
        ),
      );
    },
  );
}

Future<void> _waitForHealth(String url) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      if (response.statusCode == HttpStatus.ok) {
        await response.drain<void>();
        client.close(force: true);
        return;
      }
      lastError = 'HTTP ${response.statusCode}';
    } on Object catch (error) {
      lastError = error;
    } finally {
      client.close(force: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('runtime health failed: $lastError');
}
