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

  test(
    'McpManager rejects stdio on mobile before starting a process',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final manager = McpManager(db.mcpDao, mobilePlatform: true);
      addTearDown(manager.dispose);
      await manager.ready;

      const config = McpServerConfig(
        id: 'mobile-stdio',
        name: '移动端 stdio',
        transport: kMcpTransportStdio,
        command: 'this-command-must-not-be-started',
      );

      await expectLater(
        manager.connectServer(config),
        throwsA(
          isA<McpUnsupportedTransportException>().having(
            (error) => error.message,
            'message',
            contains('移动端不支持 stdio'),
          ),
        ),
      );
      expect(manager.isConnected(config.id), isFalse);
    },
  );

  test('McpManager safely loads malformed optional JSON fields', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.mcpDao.insertServer(
      id: 'malformed-json',
      name: '损坏配置',
      transport: kMcpTransportAppNative,
      args: '{not-json',
      headers: '["not-an-object"]',
      isEnabled: false,
    );

    final manager = McpManager(db.mcpDao, mobilePlatform: true);
    addTearDown(manager.dispose);
    await manager.ready;

    expect(manager.state.single.args, isNull);
    expect(manager.state.single.headers, isNull);
  });

  test(
    'McpManager startup does not block on a legacy enabled mobile stdio row',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.mcpDao.insertServer(
        id: 'legacy-mobile-stdio',
        name: '旧版 stdio',
        transport: kMcpTransportStdio,
        command: 'this-command-must-not-be-started',
        isEnabled: true,
      );

      final manager = McpManager(db.mcpDao, mobilePlatform: true);
      addTearDown(manager.dispose);
      await manager.ready;

      expect(manager.state.single.isEnabled, isTrue);
      expect(
        manager.connectionErrorFor('legacy-mobile-stdio'),
        contains('移动端不支持 stdio'),
      );
      expect(manager.isConnected('legacy-mobile-stdio'), isFalse);
    },
  );

  test(
    'McpClient dispose is idempotent after app-native initialization',
    () async {
      final client = McpClient(
        name: 'dispose-test',
        transport: AppNativeMcpTransport(),
      );
      await client.initialize();

      await client.dispose();
      await client.dispose();
      expect(client.isInitialized, isFalse);
    },
  );
}
