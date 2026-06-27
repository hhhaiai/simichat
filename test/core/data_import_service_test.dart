import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat_app/core/archive/data_export_service.dart';
import 'package:ai_chat_app/core/archive/data_import_service.dart';
import 'package:ai_chat_app/core/archive/local_database_snapshot.dart';
import 'package:ai_chat_app/core/archive/structured_data_backup.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DataImportService', () {
    late Directory sourceDir;
    late Directory targetDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sourceDir = await Directory.systemTemp.createTemp('simichat_import_src_');
      targetDir = await Directory.systemTemp.createTemp('simichat_import_dst_');
    });

    tearDown(() async {
      for (final dir in [sourceDir, targetDir]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    test('previews and imports SimiChat export without overwriting', () async {
      await File(
        '${sourceDir.path}/conversations/s1.md',
      ).create(recursive: true).then((file) => file.writeAsString('# 会话\n正文'));
      await File(
        '${sourceDir.path}/audio_transcripts/a1.md',
      ).create(recursive: true).then((file) => file.writeAsString('# 转写\n文本'));
      await File(
        '${sourceDir.path}/audio_files/m1/a1.m4a',
      ).create(recursive: true).then((file) => file.writeAsBytes([1, 2, 3, 4]));

      final export = await DataExportService(
        rootDirectory: sourceDir,
        now: () => DateTime.utc(2026, 6, 27, 1, 2, 3),
      ).exportLocalData();

      final service = DataImportService(rootDirectory: targetDir);
      final preview = await service.previewExport(export.file);
      expect(preview.exportFormat, 'simichat.data_export.v1');
      expect(preview.importableFileCount, 3);
      expect(preview.existingFileCount, 0);
      expect(preview.unsupportedEntryCount, 0);
      expect(preview.includeAudioFiles, isTrue);

      final result = await service.importExport(export.file);
      expect(result.importedFiles, 3);
      expect(result.skippedExistingFiles, 0);
      expect(result.skippedUnsupportedFiles, 0);
      expect(
        await File('${targetDir.path}/conversations/s1.md').readAsString(),
        contains('正文'),
      );
      expect(
        await File('${targetDir.path}/audio_transcripts/a1.md').readAsString(),
        contains('文本'),
      );
      expect(
        await File('${targetDir.path}/audio_files/m1/a1.m4a').readAsBytes(),
        [1, 2, 3, 4],
      );

      await File(
        '${targetDir.path}/conversations/s1.md',
      ).writeAsString('保留现有文件');
      final secondPreview = await service.previewExport(export.file);
      expect(secondPreview.existingFileCount, 3);
      final second = await service.importExport(export.file);
      expect(second.importedFiles, 0);
      expect(second.skippedExistingFiles, 3);
      expect(
        await File('${targetDir.path}/conversations/s1.md').readAsString(),
        '保留现有文件',
      );
    });

    test('previews and imports exported attachment files', () async {
      final bytes = [5, 4, 3, 2];
      final archive = await _writeCustomExport(
        sourceDir,
        'attachments.tar.gz',
        entries: {'attachments/m1/a1-image.png': bytes},
        checksums: {
          'attachments/m1/a1-image.png': sha256.convert(bytes).toString(),
        },
      );

      final service = DataImportService(rootDirectory: targetDir);
      final preview = await service.previewExport(archive);
      expect(preview.importableFileCount, 1);
      expect(preview.unsupportedEntryCount, 0);
      expect(
        preview.importableEntries.single.path,
        'attachments/m1/a1-image.png',
      );

      final result = await service.importExport(archive);
      expect(result.importedFiles, 1);
      expect(
        await File(
          '${targetDir.path}/attachments/m1/a1-image.png',
        ).readAsBytes(),
        bytes,
      );
    });

    test(
      'restores local database snapshot and relinks attachment paths',
      () async {
        final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
        var sourceDbClosed = false;
        addTearDown(() async {
          if (!sourceDbClosed) await sourceDb.close();
        });

        await sourceDb.sessionDao.createSession(id: 's1');
        await sourceDb.sessionDao.updateTitle('s1', '可恢复会话');
        await sourceDb.messageDao.insertMessage(
          id: 'm1',
          sessionId: 's1',
          role: 'user',
          content: '恢复这条消息',
        );
        final image = await File(
          '${sourceDir.path}/picked.png',
        ).writeAsBytes([8, 6, 4], flush: true);
        await sourceDb.attachmentDao.insertAttachment(
          id: 'a1',
          messageId: 'm1',
          fileType: 'image',
          localPath: image.path,
          fileName: 'picked.png',
          fileSize: 3,
        );

        final export = await DataExportService(
          rootDirectory: sourceDir,
          now: () => DateTime.utc(2026, 6, 27),
          listAttachments: () async {
            final rows = await sourceDb.attachmentDao.getAllAttachments();
            return rows
                .map(
                  (row) => ExportableAttachment(
                    id: row.id,
                    messageId: row.messageId,
                    fileType: row.fileType,
                    localPath: row.localPath,
                    fileName: row.fileName,
                    fileSize: row.fileSize,
                  ),
                )
                .toList(growable: false);
          },
          exportLocalDatabase: ({required includeAudioFiles}) {
            return LocalDatabaseSnapshotService(
              database: sourceDb,
              rootDirectory: sourceDir,
              now: () => DateTime.utc(2026, 6, 27),
            ).exportSnapshot(includeAudioFiles: includeAudioFiles);
          },
        ).exportLocalData();
        await sourceDb.close();
        sourceDbClosed = true;

        final targetDb = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(targetDb.close);

        final service = DataImportService(
          rootDirectory: targetDir,
          localDatabaseSnapshotService: LocalDatabaseSnapshotService(
            database: targetDb,
            rootDirectory: targetDir,
          ),
        );

        final preview = await service.previewExport(export.file);
        expect(preview.importableFileCount, 1);
        expect(preview.hasStructuredData, isTrue);
        expect(preview.structuredKeyCount, 3);

        final result = await service.importExport(export.file);
        expect(result.importedFiles, 1);
        expect(result.restoredStructuredKeys, 3);
        final session = await targetDb.sessionDao.getSession('s1');
        expect(session?.title, '可恢复会话');
        final messages = await targetDb.messageDao.getMessagesBySession('s1');
        expect(messages.single.content, '恢复这条消息');
        final attachments = await targetDb.attachmentDao
            .getAttachmentsByMessage('m1');
        expect(attachments.single.fileName, 'picked.png');
        expect(
          attachments.single.localPath,
          endsWith('attachments/m1/a1-picked.png'),
        );
        expect(await File(attachments.single.localPath).readAsBytes(), [
          8,
          6,
          4,
        ]);

        final second = await service.importExport(export.file);
        expect(second.importedFiles, 0);
        expect(second.skippedExistingFiles, 1);
        expect(second.restoredStructuredKeys, 0);
        expect(second.skippedExistingStructuredKeys, 3);
      },
    );

    test(
      'restores non-secret configuration records with safe disabled secrets',
      () async {
        final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
        var sourceDbClosed = false;
        addTearDown(() async {
          if (!sourceDbClosed) await sourceDb.close();
        });
        const now = 1760000000000;
        await sourceDb
            .into(sourceDb.folders)
            .insert(
              FoldersCompanion.insert(
                id: 'f1',
                userId: const Value('local'),
                name: '工作资料',
                aiSummary: const Value('长期项目资料'),
                lastSummarizedAt: const Value(now + 1),
                createdAt: now,
                updatedAt: now + 2,
              ),
            );
        await sourceDb.sessionDao.createSession(id: 's1', folderId: 'f1');
        await sourceDb.sessionDao.updateTitle('s1', '带文件夹会话');
        await sourceDb
            .into(sourceDb.prompts)
            .insert(
              PromptsCompanion.insert(
                id: 'p1',
                name: '复盘助手',
                content: '请输出复盘',
                category: const Value('review'),
                isDefault: const Value(true),
                createdAt: now,
                updatedAt: now + 3,
              ),
            );
        await sourceDb
            .into(sourceDb.skills)
            .insert(
              SkillsCompanion.insert(
                id: 'skill1',
                name: '任务抽取',
                description: const Value('抽取任务'),
                instructions: '只输出行动项',
                sourceUrl: const Value('https://skills.example.test/tasks'),
                sourceSha256: const Value('hash123'),
                sha256Verified: const Value(true),
                online: const Value(true),
                isEnabled: const Value(true),
                createdAt: now,
              ),
            );
        await sourceDb
            .into(sourceDb.mcpServers)
            .insert(
              McpServersCompanion.insert(
                id: 'mcp1',
                name: 'MCP 工具',
                transport: 'sse',
                command: const Value('node server.js'),
                args: const Value('["--token","mcp-secret-never-restore"]'),
                url: const Value(
                  'https://mcp.example.test/sse?access_token=mcp-secret-never-restore',
                ),
                headers: const Value(
                  '{"Authorization":"Bearer mcp-secret-never-restore"}',
                ),
                isEnabled: const Value(true),
                source: const Value('marketplace'),
                marketplaceId: const Value('market-1'),
                createdAt: now,
              ),
            );
        await sourceDb
            .into(sourceDb.modelChannels)
            .insert(
              ModelChannelsCompanion.insert(
                id: 'channel1',
                name: 'OpenAI 兼容',
                baseUrl: 'https://api.example.test/v1',
                apiKeyEncrypted: 'encrypted-model-secret-never-restore',
                protocol: 'openai_chat',
                isEnabled: const Value(true),
                isDefault: const Value(true),
                createdAt: now,
              ),
            );
        await sourceDb
            .into(sourceDb.channelModels)
            .insert(
              ChannelModelsCompanion.insert(
                id: 'model1',
                channelId: 'channel1',
                modelName: 'gpt-4o-mini',
                capability: const Value('vision'),
                isDefault: const Value(true),
              ),
            );

        final export = await DataExportService(
          rootDirectory: sourceDir,
          now: () => DateTime.utc(2026, 6, 27),
          exportLocalDatabase: ({required includeAudioFiles}) {
            return LocalDatabaseSnapshotService(
              database: sourceDb,
              rootDirectory: sourceDir,
              now: () => DateTime.utc(2026, 6, 27),
            ).exportSnapshot(includeAudioFiles: includeAudioFiles);
          },
        ).exportLocalData();
        await sourceDb.close();
        sourceDbClosed = true;

        final targetDb = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(targetDb.close);
        final service = DataImportService(
          rootDirectory: targetDir,
          localDatabaseSnapshotService: LocalDatabaseSnapshotService(
            database: targetDb,
            rootDirectory: targetDir,
          ),
        );

        final preview = await service.previewExport(export.file);
        expect(preview.importableFileCount, 0);
        expect(preview.hasStructuredData, isTrue);
        expect(preview.structuredKeyCount, 7);

        final result = await service.importExport(export.file);
        expect(result.importedFiles, 0);
        expect(result.restoredStructuredKeys, 7);
        expect(result.skippedUnsupportedStructuredKeys, 0);

        final folder = await targetDb.folderDao.getFolder('f1');
        expect(folder?.name, '工作资料');
        final session = await targetDb.sessionDao.getSession('s1');
        expect(session?.folderId, 'f1');
        final prompt = await targetDb.promptDao.getPrompt('p1');
        expect(prompt?.content, '请输出复盘');
        final skill = await targetDb.skillDao.getSkill('skill1');
        expect(skill?.instructions, '只输出行动项');

        final mcp = await targetDb.mcpDao.getServer('mcp1');
        expect(mcp?.command, 'node server.js');
        expect(mcp?.args, isNull);
        expect(mcp?.url, isNull);
        expect(mcp?.headers, isNull);
        expect(mcp?.isEnabled, isFalse);

        final channels = await targetDb.channelDao.getAllChannels();
        expect(channels.single.apiKeyEncrypted, '');
        expect(channels.single.baseUrl, 'https://api.example.test/v1');
        expect(channels.single.isEnabled, isFalse);
        expect(channels.single.isDefault, isFalse);
        final models = await targetDb.channelDao.getModelsByChannel('channel1');
        expect(models.single.modelName, 'gpt-4o-mini');
        expect(models.single.capability, 'vision');

        final second = await service.importExport(export.file);
        expect(second.restoredStructuredKeys, 0);
        expect(second.skippedExistingStructuredKeys, 7);
      },
    );

    test('rejects checksum mismatch before writing', () async {
      final archive = await _writeCustomExport(
        sourceDir,
        'bad-checksum.tar.gz',
        entries: {'conversations/s1.md': utf8.encode('# 会话')},
        checksums: {'conversations/s1.md': '0' * 64},
      );

      await expectLater(
        DataImportService(rootDirectory: targetDir).previewExport(archive),
        throwsA(isA<DataImportException>()),
      );
      expect(
        await File('${targetDir.path}/conversations/s1.md').exists(),
        false,
      );
    });

    test('rejects path traversal entries', () async {
      final bytes = utf8.encode('evil');
      final archive = await _writeCustomExport(
        sourceDir,
        'simichat-export-evil.tar.gz',
        entries: {'../evil.md': bytes},
        checksums: {'../evil.md': sha256.convert(bytes).toString()},
      );

      await expectLater(
        DataImportService(rootDirectory: targetDir).previewExport(archive),
        throwsA(isA<DataImportException>()),
      );
      expect(await File('${targetDir.path}/../evil.md').exists(), false);
    });

    test('rejects archives without manifest', () async {
      final archive = File('${sourceDir.path}/simichat-export-empty.tar.gz');
      await archive.writeAsBytes(gzip.encode(_tarBytes({})), flush: true);

      await expectLater(
        DataImportService(rootDirectory: targetDir).previewExport(archive),
        throwsA(isA<DataImportException>()),
      );
    });

    test('previews and restores structured preferences safely', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('key_point_memory_v1', '保留旧记忆');

      final structuredBytes = utf8.encode(
        jsonEncode({
          'format': kStructuredDataFormat,
          'values': {
            'key_point_memory_v1': {'type': 'string', 'value': '新记忆'},
            'font_scale': {'type': 'double', 'value': 1.25},
            'semantic_search_enabled': {'type': 'bool', 'value': false},
            'openai_api_key': {
              'type': 'string',
              'value': 'fake-key-should-never-restore',
            },
          },
        }),
      );
      final archive = await _writeCustomExport(
        sourceDir,
        'structured.tar.gz',
        entries: {kStructuredDataArchivePath: structuredBytes},
        checksums: {
          kStructuredDataArchivePath: sha256
              .convert(structuredBytes)
              .toString(),
        },
      );

      final service = DataImportService(rootDirectory: targetDir);
      final preview = await service.previewExport(archive);
      expect(preview.importableFileCount, 0);
      expect(preview.hasStructuredData, isTrue);
      expect(preview.existingStructuredData, isTrue);
      expect(preview.structuredKeyCount, 3);
      expect(preview.unsupportedStructuredKeyCount, 1);

      final result = await service.importExport(archive);
      expect(result.importedFiles, 0);
      expect(result.restoredStructuredKeys, 2);
      expect(result.skippedExistingStructuredKeys, 1);
      expect(result.skippedUnsupportedStructuredKeys, 1);
      expect(prefs.getString('key_point_memory_v1'), '保留旧记忆');
      expect(prefs.getDouble('font_scale'), 1.25);
      expect(prefs.getBool('semantic_search_enabled'), isFalse);
      expect(prefs.containsKey('openai_api_key'), isFalse);

      final overwrite = await service.importExport(
        archive,
        overwriteExisting: true,
      );
      expect(overwrite.restoredStructuredKeys, 3);
      expect(overwrite.skippedExistingStructuredKeys, 0);
      expect(prefs.getString('key_point_memory_v1'), '新记忆');
    });

    test('rejects invalid structured preference snapshot', () async {
      final structuredBytes = utf8.encode(
        jsonEncode({'format': 'bad.format', 'values': {}}),
      );
      final archive = await _writeCustomExport(
        sourceDir,
        'bad-structured.tar.gz',
        entries: {kStructuredDataArchivePath: structuredBytes},
        checksums: {
          kStructuredDataArchivePath: sha256
              .convert(structuredBytes)
              .toString(),
        },
      );

      await expectLater(
        DataImportService(rootDirectory: targetDir).previewExport(archive),
        throwsA(isA<DataImportException>()),
      );
      await expectLater(
        DataImportService(rootDirectory: targetDir).importExport(archive),
        throwsA(isA<DataImportException>()),
      );
    });
  });
}

Future<File> _writeCustomExport(
  Directory dir,
  String fileName, {
  required Map<String, List<int>> entries,
  required Map<String, String> checksums,
}) async {
  final manifest = {
    'export_format': 'simichat.data_export.v1',
    'created_at': DateTime.utc(2026, 6, 27).toIso8601String(),
    'file_count': entries.length,
    'uncompressed_bytes': entries.values.fold<int>(
      0,
      (sum, e) => sum + e.length,
    ),
    'include_audio_files': true,
    'privacy': {'local_only': true, 'contains_api_keys': false},
    'entries': checksums.entries
        .map(
          (entry) => {
            'path': entry.key,
            'size': entries[entry.key]?.length ?? 0,
            'sha256': entry.value,
          },
        )
        .toList(),
  };
  final allEntries = <String, List<int>>{
    'manifest.json': utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    ),
    ...entries,
  };
  final archive = File('${dir.path}/$fileName');
  await archive.writeAsBytes(gzip.encode(_tarBytes(allEntries)), flush: true);
  return archive;
}

List<int> _tarBytes(Map<String, List<int>> entries) {
  final builder = BytesBuilder(copy: false);
  for (final entry in entries.entries) {
    final header = Uint8List(512);
    _writeAscii(header, 0, 100, entry.key);
    _writeOctal(header, 100, 8, 0x1a4);
    _writeOctal(header, 108, 8, 0);
    _writeOctal(header, 116, 8, 0);
    _writeOctal(header, 124, 12, entry.value.length);
    _writeOctal(header, 136, 12, 0);
    for (var i = 148; i < 156; i++) {
      header[i] = 0x20;
    }
    header[156] = 0x30;
    _writeAscii(header, 257, 6, 'ustar');
    _writeAscii(header, 263, 2, '00');
    final checksum = header.fold<int>(0, (sum, byte) => sum + byte);
    _writeChecksum(header, checksum);
    builder.add(header);
    builder.add(entry.value);
    final padding = (512 - (entry.value.length % 512)) % 512;
    if (padding > 0) builder.add(Uint8List(padding));
  }
  builder.add(Uint8List(1024));
  return builder.takeBytes();
}

void _writeAscii(Uint8List header, int offset, int length, String value) {
  final bytes = ascii.encode(value);
  header.setRange(offset, offset + bytes.length, bytes);
}

void _writeOctal(Uint8List header, int offset, int length, int value) {
  final octal = value.toRadixString(8).padLeft(length - 1, '0');
  final bytes = ascii.encode(octal);
  header.setRange(offset, offset + bytes.length, bytes);
  header[offset + length - 1] = 0;
}

void _writeChecksum(Uint8List header, int checksum) {
  final octal = checksum.toRadixString(8).padLeft(6, '0');
  final bytes = ascii.encode(octal);
  header.setRange(148, 148 + bytes.length, bytes);
  header[154] = 0;
  header[155] = 0x20;
}
