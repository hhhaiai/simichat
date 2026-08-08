import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/extensions/mobile_extension_agent.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_installer.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_manifest.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_service.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile extension package install and App Native MCP smoke', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('simichat-ext-smoke-');
    final installer = MobileExtensionInstaller(storageDirectory: root);
    addTearDown(() async {
      installer.dispose();
      if (await root.exists()) await root.delete(recursive: true);
    });
    final service = MobileExtensionService(installer);

    final skillPackage = _package(
      id: 'device-skill-smoke',
      type: MobileExtensionType.skill,
      runtime: MobileExtensionRuntime.dart,
      entry: 'SKILL.md',
      files: {'SKILL.md': '设备扩展 Skill：只输出可验证事实。'},
    );
    final skill = await service.installBytes(skillPackage.toBytes());
    expect(skill.skill?.sha256Verified, isTrue);
    await service.setEnabled('device-skill-smoke', true);
    final enabledSkill = skill.skill!.copyWith(isEnabled: true);

    final agentPackage = _package(
      id: 'device-agent-smoke',
      type: MobileExtensionType.agent,
      runtime: MobileExtensionRuntime.declarative,
      entry: 'agent.json',
      files: {
        'agent.json': jsonEncode({
          'name': '设备 Agent',
          'prompt': 'system.md',
          'skills': ['device-skill-smoke'],
          'mcpServers': ['device-app-native'],
        }),
        'system.md': '你是设备上的本地 Agent。',
      },
    );
    final agent = await service.installBytes(agentPackage.toBytes());
    final plan = const MobileAgentRuntime().buildPlan(
      agent: agent.agent!,
      availableSkills: [enabledSkill],
      availableMcpServerIds: const ['device-app-native'],
    );
    expect(plan.model, 'gemma4');
    expect(plan.systemPrompt, contains('本地 Agent'));

    final mcpPackage = _package(
      id: 'device-mcp-smoke',
      type: MobileExtensionType.mcp,
      runtime: MobileExtensionRuntime.dart,
      entry: 'server.json',
      mcpTransport: 'app_native',
      mcpServerId: 'simichat-local',
      files: {'server.json': '{"handler":"simichat-local"}'},
    );
    final mcp = await service.installBytes(mcpPackage.toBytes());
    expect(mcp.mcp?.isAppNative, isTrue);
    final client = McpClient(
      name: 'device-app-native',
      transport: AppNativeMcpTransport(serverId: mcp.mcp!.serverId!),
    );
    addTearDown(client.dispose);
    await client.initialize();
    expect(
      client.tools.map((tool) => tool.name),
      contains('simichat.runtime_info'),
    );
    final result = await client.callTool('simichat.runtime_info', const {});
    expect(result.isError, isFalse);

    await service.uninstall('device-agent-smoke');
    expect(
      (await service.installed()).map((record) => record.manifest.id),
      containsAll(['device-skill-smoke', 'device-mcp-smoke']),
    );
    // ignore: avoid_print
    print('SIMICHAT_MOBILE_EXTENSIONS_APP_NATIVE_READY');
    expect(tester.takeException(), isNull);
  });
}

MobileExtensionPackage _package({
  required String id,
  required MobileExtensionType type,
  required MobileExtensionRuntime runtime,
  required String entry,
  required Map<String, String> files,
  String? mcpTransport,
  String? mcpServerId,
}) {
  final bytesByName = <String, List<int>>{
    for (final file in files.entries) file.key: utf8.encode(file.value),
  };
  final entryBytes = bytesByName[entry]!;
  return MobileExtensionPackage(
    manifest: MobileExtensionManifest(
      id: id,
      version: '1.0.0',
      type: type,
      entry: entry,
      sha256: sha256.convert(entryBytes).toString(),
      sizeBytes: entryBytes.length,
      runtime: runtime,
      mcpTransport: mcpTransport,
      mcpServerId: mcpServerId,
    ),
    files: bytesByName,
  );
}
