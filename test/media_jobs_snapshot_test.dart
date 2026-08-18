import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/archive/data_export_service.dart';
import 'package:ai_chat_app/core/archive/data_import_service.dart';
import 'package:ai_chat_app/core/archive/local_database_snapshot.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('media_jobs structured snapshot', () {
    late Directory sourceDir;
    late AppDatabase sourceDb;
    var sourceDbClosed = false;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sourceDir = await Directory.systemTemp.createTemp(
        'simichat_media_snapshot_src_',
      );
      sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      sourceDbClosed = false;
    });

    tearDown(() async {
      if (!sourceDbClosed) await sourceDb.close();
      if (await sourceDir.exists()) {
        await sourceDir.delete(recursive: true);
      }
    });

    test(
      'exports pending running and terminal metadata without secrets or media bytes',
      () async {
        await sourceDb.sessionDao.createSession(id: 'media-session');
        final mediaFile = await File(
          '${sourceDir.path}/generated/result.bin',
        ).create(recursive: true);
        await mediaFile.writeAsString('MEDIA-BINARY-NEVER-IN-SNAPSHOT');

        await _insertMediaJob(
          sourceDb,
          id: 'media-pending',
          sessionId: 'media-session',
          kind: 'image',
          status: 'pending',
          endpoint: '/v1/images/generations?api_key=raw-key',
          requestUrl: 'https://media.example.test/submit?token=raw-token',
          prompt:
              'Bearer raw-prompt-secret api_key=raw-key /Users/sanbo/prompt.txt',
          createdAt: 100,
          updatedAt: 110,
        );
        await _insertMediaJob(
          sourceDb,
          id: 'media-running',
          sessionId: 'media-session',
          kind: 'video',
          status: 'running',
          provider: 'media.example.test',
          model: 'video-model',
          endpoint: '/v1/videos/generations',
          progress: 45,
          phase: 'polling',
          requestUrl: 'https://media.example.test/submit',
          pollUrl: 'https://media.example.test/jobs/provider-job',
          providerJobId: 'provider-job',
          attempts: 2,
          createdAt: 200,
          updatedAt: 210,
          deadline: 999,
        );
        await _insertMediaJob(
          sourceDb,
          id: 'media-completed',
          sessionId: 'media-session',
          kind: 'music',
          status: 'completed',
          provider: 'media.example.test',
          model: 'music-model',
          endpoint: '/v1/music/generations',
          progress: 100,
          phase: 'completed',
          contentUrl: 'https://media.example.test/content/result',
          assetPath: 'generated/result.bin',
          assetMime: 'audio/mpeg',
          assetExtension: 'mp3',
          prompt: '生成一段安全的背景音乐',
          endpointStyle: 'json',
          createdAt: 300,
          updatedAt: 310,
        );
        await _insertMediaJob(
          sourceDb,
          id: 'media-failed',
          kind: 'video',
          status: 'failed',
          error:
              'failed Bearer raw-error-secret sk-error-secret at /Users/sanbo/job.log https://media.example.test/poll?token=raw token=loose',
          createdAt: 400,
          updatedAt: 410,
        );

        final bytes = await LocalDatabaseSnapshotService(
          database: sourceDb,
          rootDirectory: sourceDir,
          now: () => DateTime.utc(2026, 8, 18),
        ).exportSnapshot();

        expect(bytes, isNotNull);
        final snapshot = jsonDecode(utf8.decode(bytes!)) as Map;
        final jobs = (snapshot['media_jobs'] as List).cast<Map>();
        expect(jobs, hasLength(4));
        final byId = <String, Map>{
          for (final job in jobs) job['id'] as String: job,
        };
        expect(byId['media-pending']!['status'], 'pending');
        expect(byId['media-running']!['status'], 'running');
        expect(byId['media-running']!['progress'], 45);
        expect(
          byId['media-running']!['poll_url'],
          contains('/jobs/provider-job'),
        );
        expect(byId['media-completed']!['status'], 'completed');
        expect(byId['media-completed']!['asset_path'], 'generated/result.bin');
        expect(byId['media-completed']!['asset_mime'], 'audio/mpeg');
        expect(byId['media-failed']!['status'], 'failed');

        final pending = byId['media-pending']!;
        expect(pending['endpoint'], isNull);
        expect(pending['request_url'], isNull);
        expect(pending['prompt'], contains('Bearer ***'));
        expect(pending['prompt'], contains('[本机路径]'));
        expect(pending['prompt'], isNot(contains('raw-prompt-secret')));

        final failed = byId['media-failed']!;
        expect(failed['error'], contains('Bearer ***'));
        expect(failed['error'], contains('sk-***'));
        expect(failed['error'], contains('[本机路径]'));
        expect(failed['error'], contains('[链接]'));
        expect(failed['error'], contains('token=***'));

        final privacy = snapshot['privacy'] as Map;
        expect(privacy['contains_media_job_secrets'], isFalse);
        expect(privacy['contains_media_binaries'], isFalse);
        final snapshotText = jsonEncode(snapshot);
        expect(snapshotText, isNot(contains('raw-key')));
        expect(snapshotText, isNot(contains('raw-token')));
        expect(snapshotText, isNot(contains('raw-error-secret')));
        expect(snapshotText, isNot(contains('MEDIA-BINARY-NEVER-IN-SNAPSHOT')));
        expect(snapshotText, isNot(contains(sourceDir.path)));
      },
    );

    test(
      'carries media jobs through archive preview and import with conflict skipping',
      () async {
        await sourceDb.sessionDao.createSession(id: 'media-session');
        await _insertMediaJob(
          sourceDb,
          id: 'media-pending',
          sessionId: 'media-session',
          kind: 'image',
          status: 'pending',
          phase: 'queued',
          createdAt: 100,
          updatedAt: 110,
        );
        await _insertMediaJob(
          sourceDb,
          id: 'media-running',
          sessionId: 'media-session',
          kind: 'video',
          status: 'running',
          progress: 45,
          phase: 'polling',
          createdAt: 200,
          updatedAt: 210,
        );
        await _insertMediaJob(
          sourceDb,
          id: 'media-completed',
          sessionId: 'media-session',
          kind: 'music',
          status: 'completed',
          assetPath: 'generated/result.mp3',
          assetMime: 'audio/mpeg',
          assetExtension: 'mp3',
          createdAt: 300,
          updatedAt: 310,
        );

        final export = await DataExportService(
          rootDirectory: sourceDir,
          now: () => DateTime.utc(2026, 8, 18),
          exportLocalDatabase: ({required includeAudioFiles}) {
            return LocalDatabaseSnapshotService(
              database: sourceDb,
              rootDirectory: sourceDir,
              now: () => DateTime.utc(2026, 8, 18),
            ).exportSnapshot(includeAudioFiles: includeAudioFiles);
          },
        ).exportLocalData();
        await sourceDb.close();
        sourceDbClosed = true;

        final targetDir = await Directory.systemTemp.createTemp(
          'simichat_media_snapshot_dst_',
        );
        addTearDown(() async {
          if (await targetDir.exists()) {
            await targetDir.delete(recursive: true);
          }
        });
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
        expect(preview.hasStructuredData, isTrue);
        expect(preview.structuredKeyCount, 4);
        expect(preview.existingStructuredData, isFalse);

        final result = await service.importExport(export.file);
        expect(result.importedFiles, 0);
        expect(result.restoredStructuredKeys, 4);
        expect(result.skippedUnsupportedStructuredKeys, 0);
        expect(
          (await targetDb.mediaJobDao.listRecoverableJobs()).map((e) => e.id),
          containsAll(<String>['media-pending', 'media-running']),
        );
        final completed = await targetDb.mediaJobDao.getJob('media-completed');
        expect(completed?.status, 'completed');
        expect(completed?.assetPath, '${targetDir.path}/generated/result.mp3');
        expect(
          await File('${targetDir.path}/generated/result.mp3').exists(),
          isFalse,
        );

        final secondPreview = await service.previewExport(export.file);
        expect(secondPreview.structuredKeyCount, 4);
        expect(secondPreview.existingStructuredData, isTrue);
        expect(secondPreview.importableEntries.single.isStructuredData, isTrue);
        final second = await service.importExport(export.file);
        expect(second.restoredStructuredKeys, 0);
        expect(second.skippedExistingStructuredKeys, 4);
      },
    );

    test(
      'round-trips schema 11 media delivery fields without secrets or absolute paths',
      () async {
        await sourceDb.sessionDao.createSession(id: 'media-session');
        final sourcePath = p.join(
          sourceDir.path,
          'attachments',
          'reference.png',
        );
        await _insertMediaJob(
          sourceDb,
          id: 'media-schema-11',
          sessionId: 'media-session',
          kind: 'video',
          status: 'running',
          phase: 'polling',
          assetPath: 'generated/result.mp4',
          assetMime: 'video/mp4',
          assetExtension: 'mp4',
          deadline: 1234567890,
          channelModelId: 'channel-model-11',
          deliveryUserMessageId: 'media-schema-11-user',
          deliveryAssistantMessageId: 'media-schema-11-assistant',
          deliveryAttachmentId: 'media-schema-11-attachment',
          deliverySourceAttachmentId: 'media-schema-11-source',
          deliveryPhase: 'file_written',
          deliveryUserContent: '生成一段旅行视频',
          deliveryAssistantContent:
              '已完成 Bearer delivery-secret /Users/sanbo/result.mp4 token=raw',
          deliveryFileType: 'video',
          deliverySourcePath: sourcePath,
          deliverySourceFileName: 'reference.png',
          deliverySourceFileType: 'image',
          createdAt: 100,
          updatedAt: 110,
        );

        final bytes = await LocalDatabaseSnapshotService(
          database: sourceDb,
          rootDirectory: sourceDir,
        ).exportSnapshot();
        expect(bytes, isNotNull);
        final snapshot = jsonDecode(utf8.decode(bytes!)) as Map;
        final exported = (snapshot['media_jobs'] as List).single as Map;
        expect(exported['channel_model_id'], 'channel-model-11');
        expect(exported['delivery_user_message_id'], 'media-schema-11-user');
        expect(
          exported['delivery_assistant_message_id'],
          'media-schema-11-assistant',
        );
        expect(
          exported['delivery_attachment_id'],
          'media-schema-11-attachment',
        );
        expect(
          exported['delivery_source_attachment_id'],
          'media-schema-11-source',
        );
        expect(exported['delivery_phase'], 'file_written');
        expect(exported['delivery_user_content'], '生成一段旅行视频');
        expect(exported['delivery_assistant_content'], contains('Bearer ***'));
        expect(exported['delivery_assistant_content'], contains('[本机路径]'));
        expect(exported['delivery_assistant_content'], contains('token=***'));
        expect(exported['delivery_file_type'], 'video');
        expect(exported['delivery_source_path'], 'attachments/reference.png');
        expect(exported['delivery_source_file_name'], 'reference.png');
        expect(exported['delivery_source_file_type'], 'image');

        final snapshotText = jsonEncode(snapshot);
        expect(snapshotText, isNot(contains('delivery-secret')));
        expect(snapshotText, isNot(contains('/Users/sanbo/result.mp4')));
        expect(snapshotText, isNot(contains(sourceDir.path)));

        await sourceDb.close();
        sourceDbClosed = true;

        final targetDir = await Directory.systemTemp.createTemp(
          'simichat_media_snapshot_schema11_dst_',
        );
        addTearDown(() async {
          if (await targetDir.exists()) {
            await targetDir.delete(recursive: true);
          }
        });
        final targetDb = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(targetDb.close);
        final restore = await LocalDatabaseSnapshotService(
          database: targetDb,
          rootDirectory: targetDir,
        ).restoreSnapshot(bytes);

        expect(restore.restoredMediaJobs, 1);
        final restored = await targetDb.mediaJobDao.getJob('media-schema-11');
        expect(restored, isNotNull);
        expect(restored!.sessionId, 'media-session');
        expect(restored.channelModelId, 'channel-model-11');
        expect(restored.deliveryUserMessageId, 'media-schema-11-user');
        expect(
          restored.deliveryAssistantMessageId,
          'media-schema-11-assistant',
        );
        expect(restored.deliveryAttachmentId, 'media-schema-11-attachment');
        expect(restored.deliverySourceAttachmentId, 'media-schema-11-source');
        expect(restored.deliveryPhase, 'file_written');
        expect(restored.deliveryUserContent, '生成一段旅行视频');
        expect(restored.deliveryAssistantContent, contains('Bearer ***'));
        expect(restored.deliveryAssistantContent, contains('[本机路径]'));
        expect(restored.deliveryAssistantContent, contains('token=***'));
        expect(restored.deliveryFileType, 'video');
        expect(
          restored.deliverySourcePath,
          p.join(targetDir.path, 'attachments', 'reference.png'),
        );
        expect(restored.deliverySourceFileName, 'reference.png');
        expect(restored.deliverySourceFileType, 'image');
        expect(
          restored.assetPath,
          p.join(targetDir.path, 'generated', 'result.mp4'),
        );
      },
    );

    test(
      'imports old media job rows with missing fields and skips unsafe rows',
      () async {
        await sourceDb.close();
        sourceDbClosed = true;
        final targetDir = await Directory.systemTemp.createTemp(
          'simichat_media_snapshot_legacy_',
        );
        addTearDown(() async {
          if (await targetDir.exists()) {
            await targetDir.delete(recursive: true);
          }
        });
        final targetDb = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(targetDb.close);
        final snapshot = <String, Object?>{
          'format': kLocalDatabaseSnapshotFormat,
          'media_jobs': [
            <String, Object?>{'id': 'legacy-running', 'status': 'running'},
            <String, Object?>{
              'id': 'legacy-failed',
              'kind': 'video',
              'status': 'failed',
              'request_url': 'https://media.example.test/job?token=raw-token',
              'prompt':
                  'Bearer import-secret sk-import-secret /Users/sanbo/input.png https://media.example.test/prompt?api_key=raw-key token=raw',
              'error':
                  'failed Bearer import-error sk-import-error at /Users/sanbo/error.log https://media.example.test/error?token=raw',
            },
            <String, Object?>{
              'id': 'unsafe-asset-path',
              'kind': 'music',
              'status': 'completed',
              'asset_path': '../../escape.mp3',
            },
            <String, Object?>{
              'id': 'unsafe-delivery-source-path',
              'kind': 'video',
              'status': 'running',
              'delivery_source_path': '../../escape.png',
            },
            <String, Object?>{
              'id': 'bad-progress-type',
              'kind': 'image',
              'status': 'pending',
              'progress': '90',
            },
          ],
        };
        final bytes = utf8.encode(jsonEncode(snapshot));
        final service = LocalDatabaseSnapshotService(
          database: targetDb,
          rootDirectory: targetDir,
        );

        final preview = await service.previewSnapshot(bytes);
        expect(preview.mediaJobCount, 2);
        expect(preview.invalidMediaJobCount, 3);
        final restore = await service.restoreSnapshot(bytes);
        expect(restore.restoredMediaJobs, 2);
        expect(restore.skippedInvalidMediaJobs, 3);

        final legacy = await targetDb.mediaJobDao.getJob('legacy-running');
        expect(legacy, isNotNull);
        expect(legacy!.kind, 'image');
        expect(legacy.status, 'running');
        expect(legacy.endpointStyle, 'auto');
        expect(legacy.attempts, 0);
        expect(legacy.assetPath, isNull);

        final failed = await targetDb.mediaJobDao.getJob('legacy-failed');
        expect(failed, isNotNull);
        expect(failed!.requestUrl, isNull);
        expect(failed.prompt, contains('Bearer ***'));
        expect(failed.prompt, contains('sk-***'));
        expect(failed.prompt, contains('[本机路径]'));
        expect(failed.prompt, contains('[链接]'));
        expect(failed.prompt, contains('token=***'));
        expect(failed.error, contains('Bearer ***'));
        expect(failed.error, contains('sk-***'));
        expect(failed.error, contains('[本机路径]'));
        expect(failed.error, contains('[链接]'));
        expect(await targetDb.mediaJobDao.getJob('unsafe-asset-path'), isNull);
        expect(
          await targetDb.mediaJobDao.getJob('unsafe-delivery-source-path'),
          isNull,
        );
        expect(await targetDb.mediaJobDao.getJob('bad-progress-type'), isNull);
        expect(
          await File('${targetDir.parent.path}/escape.mp3').exists(),
          isFalse,
        );
      },
    );
  });
}

Future<void> _insertMediaJob(
  AppDatabase database, {
  required String id,
  required String kind,
  required String status,
  String? sessionId,
  String? provider,
  String? model,
  String? endpoint,
  int? progress,
  String? phase,
  String? requestUrl,
  String? providerJobId,
  String? requestId,
  String? pollUrl,
  String? cancelUrl,
  String? contentUrl,
  String? assetPath,
  String? assetMime,
  String? assetExtension,
  String? prompt,
  String? error,
  int attempts = 0,
  required int createdAt,
  required int updatedAt,
  int? deadline,
  String? endpointStyle,
  String? channelModelId,
  String? deliveryUserMessageId,
  String? deliveryAssistantMessageId,
  String? deliveryAttachmentId,
  String? deliverySourceAttachmentId,
  String? deliveryPhase,
  String? deliveryUserContent,
  String? deliveryAssistantContent,
  String? deliveryFileType,
  String? deliverySourcePath,
  String? deliverySourceFileName,
  String? deliverySourceFileType,
}) async {
  await database
      .into(database.mediaJobs)
      .insert(
        MediaJobsCompanion.insert(
          id: id,
          sessionId: Value(sessionId),
          kind: kind,
          provider: Value(provider),
          model: Value(model),
          endpoint: Value(endpoint),
          status: status,
          progress: Value(progress),
          phase: Value(phase),
          requestUrl: Value(requestUrl),
          providerJobId: Value(providerJobId),
          requestId: Value(requestId),
          pollUrl: Value(pollUrl),
          cancelUrl: Value(cancelUrl),
          contentUrl: Value(contentUrl),
          assetPath: Value(assetPath),
          assetMime: Value(assetMime),
          assetExtension: Value(assetExtension),
          prompt: Value(prompt),
          error: Value(error),
          attempts: Value(attempts),
          createdAt: createdAt,
          updatedAt: updatedAt,
          deadline: Value(deadline),
          endpointStyle: Value(endpointStyle),
          channelModelId: Value(channelModelId),
          deliveryUserMessageId: Value(deliveryUserMessageId),
          deliveryAssistantMessageId: Value(deliveryAssistantMessageId),
          deliveryAttachmentId: Value(deliveryAttachmentId),
          deliverySourceAttachmentId: Value(deliverySourceAttachmentId),
          deliveryPhase: Value(deliveryPhase),
          deliveryUserContent: Value(deliveryUserContent),
          deliveryAssistantContent: Value(deliveryAssistantContent),
          deliveryFileType: Value(deliveryFileType),
          deliverySourcePath: Value(deliverySourcePath),
          deliverySourceFileName: Value(deliverySourceFileName),
          deliverySourceFileType: Value(deliverySourceFileType),
        ),
      );
}
