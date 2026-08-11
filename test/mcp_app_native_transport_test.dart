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

  test('McpManager persists an enabled toggle without reconnecting', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final manager = McpManager(db.mcpDao);
    addTearDown(manager.dispose);
    await manager.ready;

    const config = McpServerConfig(
      id: 'toggle-mcp',
      name: 'Toggle MCP',
      transport: kMcpTransportAppNative,
      isEnabled: false,
    );
    await manager.addServer(config);
    await manager.connectServer(config);
    expect(manager.isConnected(config.id), isTrue);

    await manager.setServerEnabled(config.id, false);
    expect(manager.state.single.isEnabled, isFalse);
    expect((await db.mcpDao.getAllServers()).single.isEnabled, isFalse);
    expect(manager.isConnected(config.id), isTrue);

    await manager.setServerEnabled(config.id, true);
    expect(manager.state.single.isEnabled, isTrue);
    expect((await db.mcpDao.getAllServers()).single.isEnabled, isTrue);
  });

  test('McpManager connects audited stdio adapter on mobile', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final manager = McpManager(db.mcpDao, mobilePlatform: true);
    addTearDown(manager.dispose);
    await manager.ready;

    const config = McpServerConfig(
      id: 'mobile-stdio-time',
      name: '移动端时间 stdio',
      transport: kMcpTransportStdio,
      command: 'npx',
      args: ['--yes', '@modelcontextprotocol/server-time@latest'],
    );

    await manager.connectServer(config);

    expect(manager.isConnected(config.id), isTrue);
    expect(mobileStdioDescription(config), '移动端 stdio · 内置 Runtime');
    final result = await manager.callTool(config.id, 'simichat.now', {});
    expect(result.isError, isFalse);
  });

  test('mobile node extension keeps stdio semantics in its server row', () {
    const config = McpServerConfig(
      id: 'mobile-extension-stdio',
      name: '移动扩展 stdio',
      transport: kMcpTransportStdio,
      marketplaceId: 'mobile-extension:weather-mobile',
      headers: {
        kMobileExtensionRootConfigKey: '/app/extensions/weather-mobile',
        kMobileExtensionEntryConfigKey: 'index.mjs',
        kMobileExtensionProtocolConfigKey: 'stdio-compat-v1',
        kMobileExtensionSha256ConfigKey:
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      },
    );

    expect(hasMobileExtensionRegistrationMetadata(config), isTrue);
    expect(mobileExtensionIdForMcpConfig(config), 'weather-mobile');
    expect(mobileStdioDescription(config), '移动端 stdio · Node Runtime');
  });

  test(
    'McpManager gives an actionable error for unknown mobile stdio',
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
            contains('移动端 stdio 需要随 App 分发的移动 Runtime'),
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
    'McpManager startup does not block on an unknown enabled mobile stdio row',
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

      expect(manager.state.single.isEnabled, isFalse);
      expect(
        manager.connectionErrorFor('legacy-mobile-stdio'),
        contains('移动端 stdio 需要随 App 分发的移动 Runtime'),
      );
      expect(manager.isConnected('legacy-mobile-stdio'), isFalse);
    },
  );

  test('McpManager migrates a stale PC container row off mobile', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.mcpDao.insertServer(
      id: 'legacy-pc-container',
      name: '旧版 PC 容器',
      transport: kMcpTransportSse,
      url: 'http://127.0.0.1:37651/mcp/sse/simichat-node',
      marketplaceId: kContainerMcpServerId,
      isEnabled: true,
    );

    final manager = McpManager(db.mcpDao, mobilePlatform: true);
    addTearDown(manager.dispose);
    await manager.ready;

    expect(manager.state.single.isEnabled, isFalse);
    expect(manager.isConnected('legacy-pc-container'), isFalse);
    expect(
      manager.connectionErrorFor('legacy-pc-container'),
      contains('仅支持 PC'),
    );
    expect((await db.mcpDao.getAllServers()).single.isEnabled, isFalse);
  });

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
