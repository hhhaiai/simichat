import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/archive/data_export_service.dart';
import 'package:ai_chat_app/core/archive/local_database_snapshot.dart';
import 'package:ai_chat_app/core/archive/structured_data_backup.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DataExportService', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('simichat_export_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('exports local markdown and media archives as tar.gz', () async {
      await File(
        '${tempDir.path}/conversations/s1.md',
      ).create(recursive: true).then((file) => file.writeAsString('# 会话\n正文'));
      await File(
        '${tempDir.path}/audio_transcripts/a1.md',
      ).create(recursive: true).then((file) => file.writeAsString('# 转写\n文本'));
      await File(
        '${tempDir.path}/audio_files/m1/a1.m4a',
      ).create(recursive: true).then((file) => file.writeAsBytes([1, 2, 3, 4]));
      await File(
        '${tempDir.path}/exports/old.tar.gz',
      ).create(recursive: true).then((file) => file.writeAsString('old'));

      final result = await DataExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27, 1, 2, 3),
      ).exportLocalData();

      expect(
        result.file.path,
        endsWith('simichat-export-20260627-010203.tar.gz'),
      );
      expect(result.manifest.fileCount, 3);
      expect(result.manifest.includeAudioFiles, isTrue);
      expect(result.compressedBytes, greaterThan(0));

      final entries = _readTarGzEntries(result.file);
      expect(entries.keys, contains('manifest.json'));
      expect(entries.keys, contains('conversations/s1.md'));
      expect(entries.keys, contains('audio_transcripts/a1.md'));
      expect(entries.keys, contains('audio_files/m1/a1.m4a'));
      expect(entries.keys, isNot(contains('exports/old.tar.gz')));
      expect(utf8.decode(entries['conversations/s1.md']!), contains('正文'));

      final manifest = jsonDecode(utf8.decode(entries['manifest.json']!));
      expect(manifest['export_format'], 'simichat.data_export.v1');
      expect(manifest['privacy']['contains_api_keys'], isFalse);
      expect(jsonEncode(manifest), isNot(contains(tempDir.path)));
    });

    test('can exclude original audio files from export', () async {
      await File(
        '${tempDir.path}/conversations/s1.md',
      ).create(recursive: true).then((file) => file.writeAsString('# 会话'));
      await File(
        '${tempDir.path}/audio_files/m1/a1.m4a',
      ).create(recursive: true).then((file) => file.writeAsBytes([1, 2, 3, 4]));

      final result = await DataExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27),
      ).exportLocalData(includeAudioFiles: false);

      final entries = _readTarGzEntries(result.file);
      expect(entries.keys, contains('conversations/s1.md'));
      expect(entries.keys, isNot(contains('audio_files/m1/a1.m4a')));
      final manifest = jsonDecode(utf8.decode(entries['manifest.json']!));
      expect(manifest['include_audio_files'], isFalse);
    });

    test(
      'exports audio transcript status without leaking failure details',
      () async {
        await AudioTranscriptArchive(rootDirectory: tempDir).writeFailure(
          messageId: 'message:fail',
          attachmentId: 'attachment:fail',
          fileName: 'voice.m4a',
          fileSize: 2048,
          error:
              'STT failed sk-secret-token at /Users/sanbo/audio/voice.m4a https://example.com/stt?token=raw',
          createdAt: DateTime.utc(2026, 6, 27, 1, 2, 3),
        );

        final result = await DataExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27, 1, 3, 4),
        ).exportLocalData(includeStructuredData: false);

        final entries = _readTarGzEntries(result.file);
        final transcript = utf8.decode(
          entries['audio_transcripts/message_fail/attachment_fail.md']!,
        );
        expect(transcript, contains('- status: `failed`'));
        expect(transcript, contains('[已隐藏密钥]'));
        expect(transcript, contains('[已隐藏路径]'));
        expect(transcript, contains('[已隐藏链接]'));
        expect(transcript, isNot(contains('sk-secret-token')));
        expect(transcript, isNot(contains('/Users/sanbo')));
        expect(transcript, isNot(contains('token=raw')));
      },
    );

    test(
      'exports whitelisted structured preferences without secrets',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('key_point_memory_v1', '[{"id":"m1"}]');
        await prefs.setString('user_profile_v1', '{"summary":"本地画像"}');
        await prefs.setDouble('font_scale', 1.2);
        await prefs.setBool('semantic_search_enabled', false);
        await prefs.setString('openai_api_key', 'fake-key-should-never-export');

        final result = await DataExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27),
        ).exportLocalData();

        final entries = _readTarGzEntries(result.file);
        expect(entries.keys, contains(kStructuredDataArchivePath));
        final structured = jsonDecode(
          utf8.decode(entries[kStructuredDataArchivePath]!),
        );
        expect(structured['format'], kStructuredDataFormat);
        expect(structured['privacy']['contains_model_api_keys'], isFalse);
        expect(
          structured['values'],
          containsPair('key_point_memory_v1', isA<Map>()),
        );
        expect(
          structured['values'],
          containsPair('user_profile_v1', isA<Map>()),
        );
        expect(structured['values'], containsPair('font_scale', isA<Map>()));
        expect(
          structured['values'],
          containsPair('semantic_search_enabled', isA<Map>()),
        );
        expect(structured['values'], isNot(contains('openai_api_key')));
        expect(
          jsonEncode(structured),
          isNot(contains('fake-key-should-never-export')),
        );

        final manifest = jsonDecode(utf8.decode(entries['manifest.json']!));
        final manifestText = jsonEncode(manifest);
        expect(manifestText, contains(kStructuredDataArchivePath));
        expect(manifestText, isNot(contains('fake-key-should-never-export')));
      },
    );

    test(
      'exports non-audio attachment files with sanitized archive paths',
      () async {
        final sourceDir = await Directory.systemTemp.createTemp(
          'simichat_attachment_src_',
        );
        addTearDown(() async {
          if (await sourceDir.exists()) {
            await sourceDir.delete(recursive: true);
          }
        });
        final image = await File(
          '${sourceDir.path}/picked image.png',
        ).writeAsBytes([9, 8, 7], flush: true);
        final missing = File('${sourceDir.path}/missing-secret.pdf');

        final result = await DataExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27),
          listAttachments: () async => [
            ExportableAttachment(
              id: 'attachment/../one',
              messageId: 'message/../one',
              fileType: 'image',
              localPath: image.path,
              fileName: '../secret card.png',
              fileSize: 3,
            ),
            ExportableAttachment(
              id: 'audio-one',
              messageId: 'message-one',
              fileType: 'audio',
              localPath: image.path,
              fileName: 'voice.m4a',
              fileSize: 3,
            ),
            ExportableAttachment(
              id: 'missing-one',
              messageId: 'message-one',
              fileType: 'document',
              localPath: missing.path,
              fileName: 'missing-secret.pdf',
              fileSize: 10,
            ),
          ],
        ).exportLocalData();

        final entries = _readTarGzEntries(result.file);
        const attachmentPath =
            'attachments/message_one/attachment_one-secret_card.png';
        expect(entries.keys, contains(attachmentPath));
        expect(entries[attachmentPath], [9, 8, 7]);
        expect(
          entries.keys.where((path) => path.startsWith('attachments/')),
          hasLength(1),
        );

        final manifest = jsonDecode(utf8.decode(entries['manifest.json']!));
        final manifestText = jsonEncode(manifest);
        expect(manifestText, contains(attachmentPath));
        expect(manifestText, isNot(contains(sourceDir.path)));
        expect(manifestText, isNot(contains(missing.path)));
        expect(manifestText, isNot(contains('secret card')));
        expect(manifestText, isNot(contains('voice.m4a')));
      },
    );

    test(
      'exports local database snapshot without absolute attachment paths',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.sessionDao.createSession(id: 's1');
        await db.sessionDao.updateTitle('s1', '迁移会话');
        await db.messageDao.insertMessage(
          id: 'm1',
          sessionId: 's1',
          role: 'user',
          content: '带附件的本地消息',
        );
        final sourceDir = await Directory.systemTemp.createTemp(
          'simichat_snapshot_attachment_',
        );
        addTearDown(() async {
          if (await sourceDir.exists()) {
            await sourceDir.delete(recursive: true);
          }
        });
        final image = await File(
          '${sourceDir.path}/photo.png',
        ).writeAsBytes([1, 3, 5], flush: true);
        await db.attachmentDao.insertAttachment(
          id: 'a1',
          messageId: 'm1',
          fileType: 'image',
          localPath: image.path,
          fileName: 'photo.png',
          fileSize: 3,
        );

        final result = await DataExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27),
          listAttachments: () async {
            final rows = await db.attachmentDao.getAllAttachments();
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
              database: db,
              rootDirectory: tempDir,
              now: () => DateTime.utc(2026, 6, 27),
            ).exportSnapshot(includeAudioFiles: includeAudioFiles);
          },
        ).exportLocalData();

        final entries = _readTarGzEntries(result.file);
        expect(entries.keys, contains(kLocalDatabaseArchivePath));
        expect(entries.keys, contains('attachments/m1/a1-photo.png'));

        final snapshot = jsonDecode(
          utf8.decode(entries[kLocalDatabaseArchivePath]!),
        );
        expect(snapshot['format'], kLocalDatabaseSnapshotFormat);
        expect(snapshot['sessions'], hasLength(1));
        expect(snapshot['messages'], hasLength(1));
        expect(snapshot['attachments'], hasLength(1));
        expect(
          snapshot['attachments'][0]['archive_path'],
          'attachments/m1/a1-photo.png',
        );
        final snapshotText = jsonEncode(snapshot);
        expect(snapshotText, isNot(contains(sourceDir.path)));
        expect(snapshotText, isNot(contains(image.path)));
      },
    );

    test(
      'exports non-secret configuration tables without keys or MCP headers',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        const now = 1760000000000;
        await db
            .into(db.folders)
            .insert(
              FoldersCompanion.insert(
                id: 'f1',
                userId: const Value('local'),
                name: '工作',
                aiSummary: const Value('项目资料'),
                lastSummarizedAt: const Value(now + 1),
                createdAt: now,
                updatedAt: now + 2,
              ),
            );
        await db
            .into(db.prompts)
            .insert(
              PromptsCompanion.insert(
                id: 'p1',
                name: '总结助手',
                content: '请帮我总结重点',
                category: const Value('work'),
                isDefault: const Value(true),
                createdAt: now,
                updatedAt: now + 3,
              ),
            );
        await db
            .into(db.skills)
            .insert(
              SkillsCompanion.insert(
                id: 'skill1',
                name: '日程整理',
                description: const Value('整理每日待办'),
                instructions: '提取任务和截止时间',
                sourceUrl: const Value('https://skills.example.test/schedule'),
                sourceSha256: const Value('abc123'),
                sha256Verified: const Value(true),
                online: const Value(true),
                isEnabled: const Value(true),
                createdAt: now,
              ),
            );
        await db
            .into(db.mcpServers)
            .insert(
              McpServersCompanion.insert(
                id: 'mcp1',
                name: 'MCP 工具',
                transport: 'sse',
                command: const Value('node server.js'),
                args: const Value('["--token","mcp-secret-never-export"]'),
                url: const Value(
                  'https://mcp.example.test/sse?access_token=mcp-secret-never-export',
                ),
                headers: const Value(
                  '{"Authorization":"Bearer mcp-secret-never-export"}',
                ),
                isEnabled: const Value(true),
                source: const Value('marketplace'),
                marketplaceId: const Value('market-1'),
                createdAt: now,
              ),
            );
        await db
            .into(db.modelChannels)
            .insert(
              ModelChannelsCompanion.insert(
                id: 'channel1',
                name: 'OpenAI 兼容',
                baseUrl: 'https://api.example.test/v1',
                apiKeyEncrypted: 'encrypted-model-secret-never-export',
                protocol: 'openai_chat',
                isEnabled: const Value(true),
                isDefault: const Value(true),
                createdAt: now,
              ),
            );
        await db
            .into(db.channelModels)
            .insert(
              ChannelModelsCompanion.insert(
                id: 'model1',
                channelId: 'channel1',
                modelName: 'gpt-4o-mini',
                capability: const Value('vision'),
                isDefault: const Value(true),
              ),
            );

        final result = await DataExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27),
          exportLocalDatabase: ({required includeAudioFiles}) {
            return LocalDatabaseSnapshotService(
              database: db,
              rootDirectory: tempDir,
              now: () => DateTime.utc(2026, 6, 27),
            ).exportSnapshot(includeAudioFiles: includeAudioFiles);
          },
        ).exportLocalData();

        final entries = _readTarGzEntries(result.file);
        final snapshot = jsonDecode(
          utf8.decode(entries[kLocalDatabaseArchivePath]!),
        );
        expect(snapshot['folders'], hasLength(1));
        expect(snapshot['prompts'], hasLength(1));
        expect(snapshot['skills'], hasLength(1));
        expect(snapshot['mcp_servers'], hasLength(1));
        expect(snapshot['model_channels'], hasLength(1));
        expect(snapshot['channel_models'], hasLength(1));

        final mcp = (snapshot['mcp_servers'] as List).single as Map;
        expect(mcp.containsKey('headers'), isFalse);
        expect(mcp['headers_exported'], isFalse);
        expect(mcp['command'], 'node server.js');
        expect(mcp['args'], isNull);
        expect(mcp['url'], isNull);

        final channel = (snapshot['model_channels'] as List).single as Map;
        expect(channel.containsKey('api_key_encrypted'), isFalse);
        expect(channel['api_key_exported'], isFalse);
        expect(channel['base_url'], 'https://api.example.test/v1');

        final snapshotText = jsonEncode(snapshot);
        expect(
          snapshotText,
          isNot(contains('encrypted-model-secret-never-export')),
        );
        expect(snapshotText, isNot(contains('mcp-secret-never-export')));
        expect(snapshotText, isNot(contains('Authorization')));
        expect(snapshotText, isNot(contains(tempDir.path)));
      },
    );

    test('exports and restores dreaming jobs and reports', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      const now = 1760000000000;
      await db.dreamingDao.createJob(
        id: 'dreaming-job-export',
        dayKey: '2026-07-07',
        scheduledFor: now,
        trigger: 'foreground_due',
        messageLimit: 5000,
        createdAt: now - 100,
      );
      await db.dreamingDao.markJobCompleted(
        'dreaming-job-export',
        finishedAt: now + 100,
      );
      await db.dreamingDao.upsertReport(
        id: 'dreaming-report-export',
        dayKey: '2026-07-07',
        jobId: 'dreaming-job-export',
        generatedAt: now + 50,
        markdown: '# Dreaming 日报 2026-07-07',
        digestJson: '{"dayKey":"2026-07-07","hasContent":true}',
        sessionCount: 2,
        originalMessageCount: 12,
        totalOriginalMessageCount: 12,
        memoryCandidateCount: 4,
        createdAt: now + 50,
      );

      final bytes = await LocalDatabaseSnapshotService(
        database: db,
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 7, 7),
      ).exportSnapshot();

      expect(bytes, isNotNull);
      final snapshot = jsonDecode(utf8.decode(bytes!));
      expect(snapshot['dreaming_jobs'], hasLength(1));
      expect(snapshot['dreaming_reports'], hasLength(1));
      expect(
        snapshot['dreaming_reports'][0]['markdown'],
        '# Dreaming 日报 2026-07-07',
      );

      await db.close();
      final restoredDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(restoredDb.close);
      await LocalDatabaseSnapshotService(
        database: restoredDb,
        rootDirectory: tempDir,
      ).restoreSnapshot(bytes);

      final restoredJob = await restoredDb.dreamingDao.getJob(
        'dreaming-job-export',
      );
      final restoredReport = await restoredDb.dreamingDao.getReportByDay(
        '2026-07-07',
      );
      expect(restoredJob, isNotNull);
      expect(restoredJob!.status, 'completed');
      expect(restoredReport, isNotNull);
      expect(restoredReport!.jobId, 'dreaming-job-export');
      expect(restoredReport.memoryCandidateCount, 4);
    });

    test(
      'exports dreaming failed job errors without leaking secrets or paths',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        const now = 1760000000000;
        await db.dreamingDao.createJob(
          id: 'dreaming-job-failed-export',
          dayKey: '2026-07-08',
          scheduledFor: now,
          trigger: 'foreground_due',
          createdAt: now - 100,
        );
        await db.dreamingDao.markJobFailed(
          'dreaming-job-failed-export',
          error:
              'Dreaming failed Bearer raw-bearer-token sk-secret-token at /Users/sanbo/private/dreaming.log https://example.test/run?token=raw&api_key=raw-key token=loose api_key=loose-key',
          finishedAt: now + 100,
        );

        final bytes = await LocalDatabaseSnapshotService(
          database: db,
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 7, 8),
        ).exportSnapshot();

        expect(bytes, isNotNull);
        final snapshot = jsonDecode(utf8.decode(bytes!));
        final job = (snapshot['dreaming_jobs'] as List).single as Map;
        expect(job['status'], 'failed');
        expect(job['error'], contains('Bearer ***'));
        expect(job['error'], contains('sk-***'));
        expect(job['error'], contains('[本机路径]'));
        expect(job['error'], contains('[链接]'));
        expect(job['error'], contains('token=***'));
        expect(job['error'], contains('api_key=***'));

        final snapshotText = jsonEncode(snapshot);
        expect(snapshotText, isNot(contains('raw-bearer-token')));
        expect(snapshotText, isNot(contains('sk-secret-token')));
        expect(snapshotText, isNot(contains('/Users/sanbo')));
        expect(snapshotText, isNot(contains('https://example.test')));
        expect(snapshotText, isNot(contains('token=raw')));
        expect(snapshotText, isNot(contains('token=loose')));
        expect(snapshotText, isNot(contains('api_key=raw-key')));
        expect(snapshotText, isNot(contains('api_key=loose-key')));
      },
    );

    test(
      'restores dreaming failed job errors as sanitized diagnostics',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        const now = 1760000000000;
        final snapshot = <String, Object?>{
          'format': kLocalDatabaseSnapshotFormat,
          'dreaming_jobs': [
            {
              'id': 'dreaming-job-imported-failed',
              'day_key': '2026-07-09',
              'scheduled_for': now,
              'status': 'failed',
              'trigger': 'foreground_due',
              'message_limit': 5000,
              'started_at': now + 1,
              'finished_at': now + 2,
              'error':
                  'Imported failure Bearer raw-bearer-token sk-secret-token at /Users/sanbo/private/dreaming.log https://example.test/run?token=raw&api_key=raw-key token=loose api_key=loose-key',
              'created_at': now,
              'updated_at': now + 3,
            },
          ],
        };

        await LocalDatabaseSnapshotService(
          database: db,
          rootDirectory: tempDir,
        ).restoreSnapshot(utf8.encode(jsonEncode(snapshot)));

        final restored = await db.dreamingDao.getJob(
          'dreaming-job-imported-failed',
        );
        expect(restored, isNotNull);
        expect(restored!.error, contains('Bearer ***'));
        expect(restored.error, contains('sk-***'));
        expect(restored.error, contains('[本机路径]'));
        expect(restored.error, contains('[链接]'));
        expect(restored.error, contains('token=***'));
        expect(restored.error, contains('api_key=***'));
        expect(restored.error, isNot(contains('raw-bearer-token')));
        expect(restored.error, isNot(contains('sk-secret-token')));
        expect(restored.error, isNot(contains('/Users/sanbo')));
        expect(restored.error, isNot(contains('https://example.test')));
        expect(restored.error, isNot(contains('token=raw')));
        expect(restored.error, isNot(contains('token=loose')));
        expect(restored.error, isNot(contains('api_key=raw-key')));
        expect(restored.error, isNot(contains('api_key=loose-key')));
      },
    );
  });
}

Map<String, List<int>> _readTarGzEntries(File file) {
  final tarBytes = gzip.decode(file.readAsBytesSync());
  final entries = <String, List<int>>{};
  var offset = 0;
  while (offset + 512 <= tarBytes.length) {
    final header = tarBytes.sublist(offset, offset + 512);
    if (header.every((byte) => byte == 0)) break;
    final name = _readString(header, 0, 100);
    final prefix = _readString(header, 345, 155);
    final fullName = prefix.isEmpty ? name : '$prefix/$name';
    final sizeText = _readString(header, 124, 12).trim();
    final size = int.parse(sizeText, radix: 8);
    offset += 512;
    entries[fullName] = tarBytes.sublist(offset, offset + size);
    offset += size;
    final padding = (512 - (size % 512)) % 512;
    offset += padding;
  }
  return entries;
}

String _readString(List<int> bytes, int offset, int length) {
  final slice = bytes.sublist(offset, offset + length);
  final end = slice.indexOf(0);
  return ascii.decode(end == -1 ? slice : slice.sublist(0, end));
}
