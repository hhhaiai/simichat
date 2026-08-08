import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/marketplace/marketplace_models.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app-native MCP transport runs without external command', () async {
    final client = McpClient(
      name: 'SimiChat Local',
      transport: AppNativeMcpTransport(),
    );
    addTearDown(client.dispose);

    await client.initialize();

    expect(client.isInitialized, isTrue);
    expect(
      client.tools.map((tool) => tool.name),
      containsAll(['simichat.now', 'simichat.runtime_info']),
    );

    final result = await client.callTool('simichat.runtime_info', {});
    expect(result.isError, isFalse);
    expect(result.content, hasLength(1));

    final payload =
        jsonDecode(result.content.single.text!) as Map<String, dynamic>;
    expect(payload['transport'], kMcpTransportAppNative);
    expect(payload['externalProcess'], isFalse);
    expect(payload['requiresNode'], isFalse);
    expect(payload['requiresNpx'], isFalse);
    expect(payload['mobileReady'], isTrue);
    expect(payload['desktopReady'], isTrue);
  });

  test('app-native MCP time tool supports timezone conversion', () async {
    final client = McpClient(
      name: 'SimiChat Local',
      transport: AppNativeMcpTransport(),
    );
    addTearDown(client.dispose);

    await client.initialize();
    final result = await client.callTool('simichat.now', {
      'timezoneOffsetMinutes': 480,
    });

    expect(result.isError, isFalse);
    final payload =
        jsonDecode(result.content.single.text!) as Map<String, dynamic>;
    expect(payload['runtime'], kMcpTransportAppNative);
    expect(payload['timezoneOffsetMinutes'], 480);
    expect(payload['timezoneName'], 'UTC+08:00');
    expect(DateTime.parse(payload['iso8601'] as String), isA<DateTime>());
  });

  test('marketplace exposes a mobile-ready built-in MCP server first', () {
    expect(builtinMcpServers.first.id, kAppNativeMcpServerId);
    expect(builtinMcpServers.first.transport, kMcpTransportAppNative);
    expect(builtinMcpServers.first.command, isNull);
    expect(builtinMcpServers.first.args, isEmpty);
    expect(builtinMcpServers.first.description, contains('不依赖 Node'));
  });

  test('McpManager connects app-native server without stdio command', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final manager = McpManager(db.mcpDao);
    addTearDown(manager.dispose);
    await manager.ready;

    const config = McpServerConfig(
      id: 'local-mcp',
      name: 'SimiChat 内建工具',
      transport: kMcpTransportAppNative,
      source: 'marketplace',
      marketplaceId: kAppNativeMcpServerId,
    );

    await manager.addServer(config);
    await manager.connectServer(config);

    expect(manager.isConnected(config.id), isTrue);
    expect(manager.connectionErrorFor(config.id), isNull);
    expect(
      manager.getAllTools().map((entry) => entry.tool.name),
      contains('simichat.runtime_info'),
    );

    final result = await manager.callTool(
      config.id,
      'simichat.runtime_info',
      {},
    );
    final payload =
        jsonDecode(result.content.single.text!) as Map<String, dynamic>;
    expect(payload['serverId'], kAppNativeMcpServerId);
    expect(payload['externalProcess'], isFalse);
  });
}
