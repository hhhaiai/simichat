import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/extensions/mobile_extension_agent.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_installer.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_manifest.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_registry.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_service.dart';
import 'package:ai_chat_app/core/skills/skill.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late MobileExtensionInstaller installer;

  setUp(() {
    root = Directory.systemTemp.createTempSync('simichat-mobile-extensions-');
    installer = MobileExtensionInstaller(storageDirectory: root);
  });

  tearDown(() async {
    installer.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('installs a Skill atomically and restores it from registry', () async {
    final package = _package(
      type: MobileExtensionType.skill,
      runtime: MobileExtensionRuntime.dart,
      entry: 'SKILL.md',
      name: '本地摘要',
      description: '摘要技能',
      files: {'SKILL.md': '# 摘要\n只输出事实。'},
    );

    final result = await installer.installBytes(package.toBytes());

    expect(result.record.status, MobileExtensionStatus.installed);
    expect(result.record.enabled, isFalse);
    expect(Directory(result.record.installPath).existsSync(), isTrue);
    expect(
      File('${result.record.installPath}/SKILL.md').readAsStringSync(),
      contains('只输出事实'),
    );
    expect(
      (await installer.installed()).single.manifest.id,
      package.manifest.id,
    );

    final enabled = await installer.enable(package.manifest.id);
    expect(enabled?.status, MobileExtensionStatus.enabled);
    expect(enabled?.enabled, isTrue);

    await installer.uninstall(package.manifest.id);
    expect(await installer.installed(), isEmpty);
  });

  test(
    'installs a declarative Agent and keeps gemma4 as local default',
    () async {
      final package = _package(
        type: MobileExtensionType.agent,
        runtime: MobileExtensionRuntime.declarative,
        entry: 'agent.json',
        files: {
          'agent.json': jsonEncode({
            'name': '本地研究员',
            'skills': ['skill-summary'],
            'mcpServers': ['simichat-local'],
            'prompt': 'prompts/system.md',
          }),
          'prompts/system.md': '你是一个只使用本地能力的研究员。',
        },
      );

      final installed = await MobileExtensionService(
        installer,
      ).installBytes(package.toBytes());
      final definition = installed.agent!;
      expect(definition.model, 'gemma4');
      expect(definition.systemPrompt, contains('本地能力'));

      final plan = const MobileAgentRuntime().buildPlan(
        agent: definition,
        availableSkills: [SkillFixture.skill],
        availableMcpServerIds: ['simichat-local'],
      );
      expect(plan.model, 'gemma4');
      expect(plan.systemPrompt, contains('摘要'));
      expect(plan.mcpServerIds, ['simichat-local']);
    },
  );

  test('app-native MCP package is installable without an executable', () async {
    final package = _package(
      type: MobileExtensionType.mcp,
      runtime: MobileExtensionRuntime.dart,
      entry: 'server.json',
      name: 'SimiChat 本地 MCP',
      mcpTransport: 'app_native',
      mcpServerId: 'simichat-local',
      files: {'server.json': '{"handler":"simichat-local"}'},
    );

    final result = await MobileExtensionService(
      installer,
    ).installBytes(package.toBytes());
    expect(result.mcp!.isAppNative, isTrue);
    expect(result.mcp!.serverId, 'simichat-local');
    expect(result.mcp!.isNodeMobile, isFalse);
  });

  test(
    'rejects traversal, hash mismatch and preserves a quarantine artifact',
    () async {
      final raw = utf8.encode(
        jsonEncode({
          'packageFormat': 1,
          'manifest': {
            'id': 'safe-package',
            'version': '1.0.0',
            'type': 'skill',
            'entry': '../SKILL.md',
            'sha256': List.filled(64, '0').join(),
            'sizeBytes': 1,
            'runtime': 'dart',
            'permissions': [],
          },
          'files': {
            '../SKILL.md': base64.encode([1]),
          },
        }),
      );

      await expectLater(
        installer.installBytes(raw),
        throwsA(
          isA<MobileExtensionInstallException>().having(
            (error) => error.quarantinePath,
            'quarantinePath',
            isNotNull,
          ),
        ),
      );
      expect(Directory('${root.path}/quarantine').listSync(), isNotEmpty);

      final valid = _package(
        type: MobileExtensionType.skill,
        runtime: MobileExtensionRuntime.dart,
        entry: 'SKILL.md',
        files: {'SKILL.md': 'valid'},
      );
      await expectLater(
        installer.installBytes(
          valid.toBytes(),
          expectedPackageSha256: List.filled(64, '0').join(),
        ),
        throwsA(isA<MobileExtensionInstallException>()),
      );
    },
  );

  test(
    'corrupted registry is quarantined and does not block startup',
    () async {
      final registry = MobileExtensionRegistry(root: root);
      await root.create(recursive: true);
      await registry.file.writeAsString('{not-json');

      expect(await registry.load(), isEmpty);
      expect(File('${registry.file.path}.corrupt').existsSync(), isTrue);
    },
  );
}

MobileExtensionPackage _package({
  required MobileExtensionType type,
  required MobileExtensionRuntime runtime,
  required String entry,
  required Map<String, String> files,
  String? name,
  String? description,
  String? mcpTransport,
  String? mcpServerId,
}) {
  final encodedFiles = <String, List<int>>{
    for (final item in files.entries) item.key: utf8.encode(item.value),
  };
  final entryBytes = encodedFiles[entry]!;
  return MobileExtensionPackage(
    manifest: MobileExtensionManifest(
      id: '${type.name}-test-package',
      version: '1.0.0',
      type: type,
      entry: entry,
      sha256: sha256.convert(entryBytes).toString(),
      sizeBytes: entryBytes.length,
      runtime: runtime,
      name: name,
      description: description,
      mcpTransport: mcpTransport,
      mcpServerId: mcpServerId,
    ),
    files: encodedFiles,
  );
}

class SkillFixture {
  static const skill = Skill(
    id: 'skill-summary',
    name: '摘要',
    description: '摘要',
    instructions: '摘要技能说明',
    createdAt: 0,
  );
}
