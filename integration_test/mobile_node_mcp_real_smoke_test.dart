import 'dart:convert';

import 'package:ai_chat_app/core/extensions/mobile_extension_installer.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_manifest.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_service.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/mcp/bundled_node_runtime.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/core/mcp/mobile_npx_resolver.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pure JS node-mobile MCP runs on the device', (tester) async {
    final installer = MobileExtensionInstaller();
    addTearDown(installer.dispose);
    final service = MobileExtensionService(installer);
    const id = 'device-node-mobile-smoke';
    final package = _package();
    final installed = await service.installBytes(package.toBytes());
    addTearDown(() => service.uninstall(id));

    final descriptor = installed.mcp!;
    expect(descriptor.isNodeMobile, isTrue);
    expect(descriptor.protocol, 'mobile-mcp-v1');

    final runtime = await BundledNodeRuntime.start();
    expect(runtime['running'], isTrue);
    final registration = await BundledNodeRuntime.registerExtension(
      id: descriptor.id,
      root: descriptor.installPath,
      entry: descriptor.entry,
      protocol: descriptor.protocol!,
      sha256: descriptor.sha256,
      permissions: descriptor.permissions,
    );
    expect(registration['loaded'], isTrue);

    final client = McpClient(
      name: 'device-node-mobile-smoke',
      transport: SseTransport(
        url: BundledNodeRuntime.extensionSseUrl(descriptor.id),
      ),
    );
    addTearDown(() async {
      await client.dispose();
      await BundledNodeRuntime.unregisterExtension(id);
    });
    await client.initialize();
    expect(client.tools.map((tool) => tool.name), contains('smoke.echo'));
    final result = await client.callTool('smoke.echo', {'text': 'device'});
    expect(result.isError, isFalse);
    expect(result.content.single.text, contains('device'));
    // ignore: avoid_print
    print('SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY');
    expect(tester.takeException(), isNull);
  });

  testWidgets('stdio-compat-v1 MCP runs without a stdio process', (
    tester,
  ) async {
    final installer = MobileExtensionInstaller();
    addTearDown(installer.dispose);
    final service = MobileExtensionService(installer);
    const id = 'device-stdio-compat-smoke';
    final installed = await service.installBytes(
      _package(id: id, protocol: 'stdio-compat-v1').toBytes(),
    );
    addTearDown(() => service.uninstall(id));

    final descriptor = installed.mcp!;
    expect(descriptor.isNodeMobile, isTrue);
    expect(descriptor.protocol, 'stdio-compat-v1');

    final runtime = await BundledNodeRuntime.start();
    expect(runtime['running'], isTrue);
    final registration = await BundledNodeRuntime.registerExtension(
      id: descriptor.id,
      root: descriptor.installPath,
      entry: descriptor.entry,
      protocol: descriptor.protocol!,
      sha256: descriptor.sha256,
      permissions: descriptor.permissions,
    );
    expect(registration['protocol'], 'stdio-compat-v1');

    final client = McpClient(
      name: id,
      transport: SseTransport(
        url: BundledNodeRuntime.extensionSseUrl(descriptor.id),
      ),
    );
    addTearDown(() async {
      await client.dispose();
      await BundledNodeRuntime.unregisterExtension(id);
    });
    await client.initialize();
    expect(client.tools.map((tool) => tool.name), contains('smoke.echo'));
    final result = await client.callTool('smoke.echo', {
      'text': 'stdio-compat',
    });
    expect(result.isError, isFalse);
    expect(result.content.single.text, contains('stdio-compat'));
    // ignore: avoid_print
    print('SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY');
    expect(tester.takeException(), isNull);
  });

  testWidgets('stdio config binds to the mobile Node Runtime bridge', (
    tester,
  ) async {
    final installer = MobileExtensionInstaller();
    addTearDown(installer.dispose);
    final service = MobileExtensionService(installer);
    const id = 'device-stdio-config-smoke';
    final installed = await service.installBytes(
      _package(id: id, protocol: 'stdio-compat-v1').toBytes(),
    );
    addTearDown(() => service.uninstall(id));

    final descriptor = installed.mcp!;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final manager = McpManager(db.mcpDao, mobilePlatform: true);
    addTearDown(manager.dispose);
    await manager.ready;

    final config = McpServerConfig(
      id: 'mobile-extension-$id',
      name: 'stdio config bridge',
      transport: kMcpTransportStdio,
      isEnabled: true,
      source: 'mobile_extension',
      marketplaceId: '$kMobileExtensionMarketplacePrefix$id',
      headers: {
        kMobileExtensionRootConfigKey: descriptor.installPath,
        kMobileExtensionEntryConfigKey: descriptor.entry,
        kMobileExtensionProtocolConfigKey: descriptor.protocol!,
        kMobileExtensionSha256ConfigKey: descriptor.sha256,
        kMobileExtensionPermissionsConfigKey: descriptor.permissions.join(','),
      },
    );
    await manager.addServer(config);
    await manager.connectServer(config);
    expect(manager.isConnected(config.id), isTrue);
    expect(mobileStdioDescription(config), '移动端 stdio · Node Runtime');

    final result = await manager.callTool(config.id, 'smoke.echo', {
      'text': 'stdio-config',
    });
    expect(result.isError, isFalse);
    expect(result.content.single.text, contains('stdio-config'));
    // ignore: avoid_print
    print('SIMICHAT_STDIO_CONFIG_MCP_DEVICE_READY');
    await BundledNodeRuntime.unregisterExtension(id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile stdio uses JSONL stdin and stdout with command args', (
    tester,
  ) async {
    const command = 'npx';
    const args = <String>['--yes', '@modelcontextprotocol/server-time@latest'];
    final client = McpClient(
      name: 'mobile-stdio-jsonl-smoke',
      transport: MobileStdioTransport(command: command, args: args),
    );
    addTearDown(client.dispose);

    await client.initialize();
    expect(client.isInitialized, isTrue);
    expect(client.tools.map((tool) => tool.name), contains('simichat.now'));
    final result = await client.callTool('simichat.runtime_info', const {});
    expect(result.isError, isFalse);
    expect(result.content.single.text, contains('"transport": "stdio"'));
    expect(result.content.single.text, contains('server-time@latest'));
    // ignore: avoid_print
    print('SIMICHAT_MOBILE_STDIO_PROTOCOL_DEVICE_READY');
    expect(tester.takeException(), isNull);
  });

  testWidgets('audited npx config resolves through the app-owned manager', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final manager = McpManager(db.mcpDao, mobilePlatform: true);
    addTearDown(manager.dispose);
    await manager.ready;

    const config = McpServerConfig(
      id: 'audited-npx-config-smoke',
      name: 'Audited npx config',
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
    print('SIMICHAT_AUDITED_NPX_MANAGER_DEVICE_READY');
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy npx MCP resolves to the mobile in-process adapter', (
    tester,
  ) async {
    final resolution = MobileNpxResolver.resolve(
      command: 'npx',
      args: const ['--yes', '@modelcontextprotocol/server-time@latest'],
    );
    expect(resolution?.profile, 'time');
    final client = McpClient(
      name: 'mobile-npx-time-smoke',
      transport: AppNativeMcpTransport(
        serverId: 'mobile-npx:${resolution!.packageName}',
        profile: resolution.profile,
      ),
    );
    addTearDown(client.dispose);
    await client.initialize();
    expect(client.tools.map((tool) => tool.name), contains('simichat.now'));
    final result = await client.callTool('simichat.now', const {});
    expect(result.isError, isFalse);
    // ignore: avoid_print
    print('SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY');
    expect(tester.takeException(), isNull);
  });
}

MobileExtensionPackage _package({
  String id = 'device-node-mobile-smoke',
  String protocol = 'mobile-mcp-v1',
}) {
  const source = '''
export default {
  async initialize(context) {
    return {
      protocolVersion: context.protocolVersion,
      capabilities: { tools: {} },
      serverInfo: { name: 'device-node-mobile-smoke', version: '1.0.0' }
    };
  },
  async listTools() {
    return {
      tools: [{
        name: 'smoke.echo',
        description: 'Pure JavaScript device smoke tool',
        inputSchema: { type: 'object', properties: { text: { type: 'string' } } }
      }]
    };
  },
  async callTool(name, args) {
    if (name !== 'smoke.echo') throw new Error('unknown tool');
    return { content: [{ type: 'text', text: String(args.text || '') }], isError: false };
  }
};
''';
  final bytes = utf8.encode(source);
  return MobileExtensionPackage(
    manifest: MobileExtensionManifest(
      id: id,
      version: '1.0.0',
      type: MobileExtensionType.mcp,
      entry: 'index.mjs',
      sha256: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
      runtime: MobileExtensionRuntime.nodeMobile,
      protocol: protocol,
      permissions: const [],
    ),
    files: {'index.mjs': bytes},
  );
}
