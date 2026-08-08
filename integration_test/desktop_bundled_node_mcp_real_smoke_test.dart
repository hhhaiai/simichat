import 'dart:convert';

import 'package:ai_chat_app/core/mcp/bundled_node_runtime.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
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
    expect(info['runtime'], 'simichat-node-embedded');
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
}
