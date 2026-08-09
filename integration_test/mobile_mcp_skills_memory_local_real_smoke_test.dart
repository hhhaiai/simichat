import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_installer.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_manifest.dart';
import 'package:ai_chat_app/core/extensions/mobile_extension_service.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/search/local_full_text_search.dart';
import 'package:ai_chat_app/shared/providers/key_point_memory_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _memoryStorageKey = 'simichat_mobile_local_memory_smoke_v1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MCP Skills and memory persist on-device without external services',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'simichat-local-core-smoke-',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_memoryStorageKey);

      MobileExtensionInstaller? installer;
      AppDatabase? database;
      McpClient? mcpClient;
      try {
        // MCP: the transport and tools live in the App process. No socket,
        // host executable, remote endpoint, Node, npm, npx or Python is used.
        mcpClient = McpClient(
          name: 'device-local-app-native',
          transport: AppNativeMcpTransport(serverId: kAppNativeMcpServerId),
        );
        await mcpClient.initialize();
        expect(
          mcpClient.tools.map((tool) => tool.name),
          containsAll(['simichat.runtime_info', 'simichat.now']),
        );
        final runtimeResult = await mcpClient.callTool(
          'simichat.runtime_info',
          const <String, dynamic>{},
        );
        expect(runtimeResult.isError, isFalse);
        final runtime =
            jsonDecode(runtimeResult.content.single.text!)
                as Map<String, dynamic>;
        expect(runtime['dependencyMode'], 'in_app');
        expect(runtime['externalProcess'], isFalse);
        expect(runtime['requiresNode'], isFalse);
        expect(runtime['requiresNpx'], isFalse);
        expect(runtime['requiresPython'], isFalse);
        expect(runtime['mobileReady'], isTrue);

        // Skills: install verified package bytes directly into an app-private
        // directory, enable it, then recreate the installer and reload the
        // persisted registry. No HTTP request or marketplace is involved.
        final extensionRoot = Directory(p.join(root.path, 'extensions'));
        installer = MobileExtensionInstaller(storageDirectory: extensionRoot);
        var extensionService = MobileExtensionService(installer);
        final skillPackage = _localSkillPackage();
        final packageBytes = skillPackage.toBytes();
        final installed = await extensionService.installBytes(
          packageBytes,
          expectedPackageSha256: sha256.convert(packageBytes).toString(),
        );
        expect(installed.skill?.sha256Verified, isTrue);
        final enabled = await extensionService.setEnabled(
          'device-local-skill',
          true,
        );
        expect(enabled?.enabled, isTrue);
        final skillFile = File(
          p.join(installed.install.record.installPath, 'SKILL.md'),
        );
        expect(await skillFile.readAsString(), contains('只使用设备本地能力'));

        installer.dispose();
        installer = MobileExtensionInstaller(storageDirectory: extensionRoot);
        extensionService = MobileExtensionService(installer);
        final reloadedExtensions = await extensionService.installed();
        expect(reloadedExtensions, hasLength(1));
        expect(reloadedExtensions.single.manifest.id, 'device-local-skill');
        expect(reloadedExtensions.single.enabled, isTrue);

        // Memory database: use an actual SQLite file in the device sandbox,
        // close it, reopen it, then verify FTS and semantic/local retrieval.
        final databaseFile = File(p.join(root.path, 'memory.sqlite'));
        database = await _openDatabase(databaseFile);
        await database.sessionDao.createSession(id: 'device-local-session');
        await database.sessionDao.updateTitle(
          'device-local-session',
          '设备本地记忆验收',
        );
        await database.messageDao.insertMessage(
          id: 'device-local-message',
          sessionId: 'device-local-session',
          role: 'user',
          content: '设备 SQLite 持久化搜索链路已经建立。',
        );
        final ftsHealth = await database.messageDao.prewarmMessageFtsIndex();
        final semanticHealth = await database.messageDao
            .prewarmMessageSemanticIndex();
        expect(ftsHealth.isHealthy, isTrue);
        expect(semanticHealth.isHealthy, isTrue);
        await database.close();
        database = null;

        database = await _openDatabase(databaseFile);
        final persistedMessages = await database.messageDao
            .getMessagesBySession('device-local-session');
        expect(persistedMessages.single.id, 'device-local-message');
        final persistedSearch = await LocalFullTextSearchService(
          sessionDao: database.sessionDao,
          messageDao: database.messageDao,
        ).search('SQLite 持久化');
        expect(
          persistedSearch.map((result) => result.sessionId),
          contains('device-local-session'),
        );

        // Key Point memory: use the production notifier with an isolated real
        // SharedPreferences key, reload a second notifier, and retrieve it.
        final extracted = const KeyPointExtractor().extractFromUserMessage(
          sessionId: 'device-local-session',
          sourceMessageId: 'device-local-message',
          content: '请记住以后优先使用设备本地能力完成移动端工作。',
          now: DateTime.utc(2026, 8, 9),
        );
        expect(extracted, isNotEmpty);
        final memory = KeyPointMemoryNotifier(storageKey: _memoryStorageKey);
        await memory.ready;
        await memory.rememberAll(extracted);
        expect(prefs.getString(_memoryStorageKey), isNotEmpty);
        await prefs.reload();

        final reloadedMemory = KeyPointMemoryNotifier(
          storageKey: _memoryStorageKey,
        );
        await reloadedMemory.ready;
        final relevant = await reloadedMemory.searchRelevant(
          '优先设备本地能力',
          sessionId: 'device-local-session',
        );
        expect(relevant, isNotEmpty);
        expect(relevant.first.content, contains('设备本地能力'));

        final memorySearch = await LocalFullTextSearchService(
          sessionDao: database.sessionDao,
          messageDao: database.messageDao,
          memoryItems: reloadedMemory.state,
        ).search('优先设备本地能力');
        expect(
          memorySearch.map((result) => result.sessionId),
          contains('device-local-session'),
        );

        // ignore: avoid_print
        print('SIMICHAT_MCP_SKILLS_MEMORY_LOCAL_DEVICE_READY');
        expect(tester.takeException(), isNull);
      } finally {
        await mcpClient?.dispose();
        installer?.dispose();
        await database?.close();
        await prefs.remove(_memoryStorageKey);
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );
}

Future<AppDatabase> _openDatabase(File file) async {
  await file.parent.create(recursive: true);
  final executor = NativeDatabase.createInBackground(
    file,
    setup: (database) {
      database.execute('PRAGMA foreign_keys = ON');
    },
  );
  return AppDatabase.forTesting(executor);
}

MobileExtensionPackage _localSkillPackage() {
  const content = '''# Device Local Skill

只使用设备本地能力，不连接第三方服务。
''';
  final entryBytes = utf8.encode(content);
  return MobileExtensionPackage(
    manifest: MobileExtensionManifest(
      id: 'device-local-skill',
      version: '1.0.0',
      type: MobileExtensionType.skill,
      entry: 'SKILL.md',
      sha256: sha256.convert(entryBytes).toString(),
      sizeBytes: entryBytes.length,
      runtime: MobileExtensionRuntime.dart,
    ),
    files: {'SKILL.md': entryBytes},
  );
}
