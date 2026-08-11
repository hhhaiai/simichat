import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/mcp/bundled_node_runtime.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop bundled Node MCP runs without Docker or host Node', (
    tester,
  ) async {
    final runtime = await BundledNodeRuntime.start();
    addTearDown(() async {
      await BundledNodeRuntime.stop();
    });
    expect(runtime['running'], isTrue);
    expect(runtime['state'], 'running');
    expect(runtime['healthVerified'], isTrue);
    expect(runtime['restartCount'], isA<int>());
    expect(runtime['runtime'], 'simichat-node-desktop-bundled');
    expect(runtime['dependencyMode'], 'bundled_node');
    expect(runtime['requiresHostNode'], isFalse);
    expect(runtime['requiresHostNpx'], isFalse);
    expect(runtime['requiresDocker'], isFalse);

    final client = McpClient(
      name: 'desktop bundled node real smoke',
      transport: SseTransport(url: kBundledNodeRuntimeSseUrl),
    );
    addTearDown(client.dispose);
    await client.initialize();

    final result = await client.callTool(
      'simichat.node_runtime_info',
      const <String, dynamic>{},
    );
    expect(result.isError, isFalse);
    final info =
        jsonDecode(result.content.single.text!) as Map<String, dynamic>;
    expect(info['runtime'], 'simichat-node-desktop-bundled');
    expect(info['dependencyMode'], 'bundled_node');
    expect(info['externalProcess'], isTrue);
    expect(info['appManaged'], isTrue);
    expect(info['requiresHostNode'], isFalse);
    expect(info['requiresHostNpx'], isFalse);
    expect(info['requiresDocker'], isFalse);

    // ignore: avoid_print
    print('SIMICHAT_DESKTOP_BUNDLED_NODE_MCP_READY');
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop audited npx profile uses bundled JSONL runtime', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final manager = McpManager(db.mcpDao, mobilePlatform: false);
    addTearDown(manager.dispose);
    await manager.ready;

    const config = McpServerConfig(
      id: 'desktop-audited-stdio',
      name: 'Desktop bundled time profile',
      transport: kMcpTransportStdio,
      command: 'npx',
      args: ['--yes', '@modelcontextprotocol/server-time@latest'],
      isEnabled: true,
    );
    await manager.addServer(config);
    await manager.connectServer(config);
    expect(manager.isConnected(config.id), isTrue);
    final result = await manager.callTool(
      config.id,
      'simichat.now',
      const <String, dynamic>{},
    );
    expect(result.isError, isFalse);
    // ignore: avoid_print
    print('SIMICHAT_DESKTOP_AUDITED_STDIO_MCP_READY');
    expect(tester.takeException(), isNull);
  });
}
