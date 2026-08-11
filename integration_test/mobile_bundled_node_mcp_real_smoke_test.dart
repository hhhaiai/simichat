import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/mcp/bundled_node_runtime.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('embedded mobile Node MCP runs without host runtime', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.mcpDao.insertServer(
      id: 'real-mobile-bundled-node-mcp',
      name: 'SimiChat 内置 Node Runtime',
      transport: kMcpTransportSse,
      url: kBundledNodeRuntimeSseUrl,
      isEnabled: true,
      source: 'marketplace',
      marketplaceId: kBundledNodeMcpServerId,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiChatApp)),
      listen: false,
    );
    final manager = container.read(mcpManagerProvider.notifier);
    await manager.ready;
    await tester.pumpAndSettle();

    final runtimeStatus = await BundledNodeRuntime.status();
    expect(runtimeStatus['running'], isTrue);
    expect(runtimeStatus['state'], 'running');
    expect(runtimeStatus['nativeState'], 2);
    expect(runtimeStatus['healthUrl'], kBundledNodeRuntimeHealthUrl);

    expect(manager.isConnected('real-mobile-bundled-node-mcp'), isTrue);
    expect(manager.connectionErrorFor('real-mobile-bundled-node-mcp'), isNull);
    expect(
      manager.getAllTools().map((entry) => entry.tool.name),
      containsAll([
        'simichat.node_runtime_info',
        'simichat.echo',
        'simichat.fs_list',
      ]),
    );

    final infoResult = await manager.callTool(
      'real-mobile-bundled-node-mcp',
      'simichat.node_runtime_info',
      const <String, dynamic>{},
    );
    expect(infoResult.isError, isFalse);
    final info =
        jsonDecode(infoResult.content.single.text!) as Map<String, dynamic>;
    expect(info['runtime'], 'simichat-node-embedded');
    expect(info['dependencyMode'], 'bundled_nodejs_mobile');
    expect(info['externalProcess'], isFalse);
    expect(info['appManaged'], isTrue);
    expect(info['requiresHostNode'], isFalse);
    expect(info['requiresHostNpx'], isFalse);
    expect(info['requiresDocker'], isFalse);
    expect(info['platform'], Platform.isAndroid ? 'android' : 'ios');

    final echoResult = await manager.callTool(
      'real-mobile-bundled-node-mcp',
      'simichat.echo',
      const {'text': 'android bundled node'},
    );
    expect(echoResult.isError, isFalse);
    expect(echoResult.content.single.text, contains('android bundled node'));

    // ignore: avoid_print
    print(
      'SIMICHAT_${Platform.operatingSystem.toUpperCase()}_BUNDLED_NODE_MCP_READY',
    );
    expect(tester.takeException(), isNull);
  });
}
