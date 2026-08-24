import 'dart:io';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/database/dao/media_job_dao.dart';
import 'package:ai_chat_app/shared/providers/universal_media_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_chat_app/core/ai/universal_media_service.dart';

void main() {
  group('media job database', () {
    test('fresh database registers media jobs and chunked-content tasks', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, 14);
      expect(await db.mediaJobDao.listPendingJobs(), isEmpty);
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'media_jobs'",
          )
          .get();
      expect(tables, hasLength(1));
      final columns = await db
          .customSelect('PRAGMA table_info(media_jobs)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        contains('lease_id'),
      );
      final chunkedTables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'chunked_content_tasks'",
          )
          .get();
      expect(chunkedTables, hasLength(1));
      final chunkedColumns = await db
          .customSelect('PRAGMA table_info(chunked_content_tasks)')
          .get();
      expect(
        chunkedColumns.map((row) => row.read<String>('name')),
        containsAll(<String>[
          'session_id',
          'source_attachment_id',
          'request_snapshot',
          'chunk_results',
          'lease_id',
        ]),
      );
    });

    test('schema 8 file migrates without losing existing tables', () async {
      final directory = await Directory.systemTemp.createTemp(
        'simichat-media-',
      );
      final file = File('${directory.path}/db.sqlite');
      try {
        final oldDatabase = AppDatabase.forTesting(NativeDatabase(file));
        await oldDatabase.customStatement('DROP TABLE media_jobs');
        await oldDatabase.customStatement('DROP TABLE chunked_content_tasks');
        // 用当前 schema 建库后回退版本号，必须同时移除 v8 之后才引入的列，
        // 否则重开时迁移会重复添加已存在的列（duplicate column）。
        await oldDatabase.customStatement(
          'ALTER TABLE channel_models DROP COLUMN capabilities',
        );
        await oldDatabase.customStatement(
          'ALTER TABLE sessions DROP COLUMN is_pinned',
        );
        await oldDatabase.customStatement('PRAGMA user_version = 8');
        await oldDatabase.close();

        final migrated = AppDatabase.forTesting(NativeDatabase(file));
        addTearDown(migrated.close);
        expect(await migrated.mediaJobDao.listPendingJobs(), isEmpty);
        final existing = await migrated
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sessions'",
            )
            .get();
        expect(existing, hasLength(1));
        final chunked = await migrated
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'chunked_content_tasks'",
            )
            .get();
        expect(chunked, hasLength(1));
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('upsert redacts secrets and rejects non-app-owned paths', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.mediaJobDao.upsertJob(
        id: 'media-safe-1',
        sessionId: 'session-1',
        kind: 'video',
        provider: 'media.test',
        model: 'video-model',
        endpoint: '/v1/videos/generations?api_key=raw',
        status: 'pending',
        requestUrl: 'https://media.test/v1/videos/generations?token=raw',
        prompt: 'Bearer raw-secret api_key=raw /Users/sanbo/private.txt',
        assetPath: '/tmp/not-app-owned.mp4',
        createdAt: 100,
        updatedAt: 100,
      );

      final row = await db.mediaJobDao.getJob('media-safe-1');
      expect(row, isNotNull);
      expect(row!.prompt, isNot(contains('raw-secret')));
      expect(row.prompt, isNot(contains('/Users/sanbo')));
      expect(row.endpoint, '/v1/videos/generations');
      expect(row.requestUrl, 'https://media.test/v1/videos/generations');
      expect(row.assetPath, isNull);
    });

    test(
      'preserves recovery URL queries but strips request URL queries',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);

        await db.mediaJobDao.upsertJob(
          id: 'media-signed-url-1',
          kind: 'video',
          status: 'pending',
          requestUrl: 'https://media.test/v1/videos?token=request-secret',
          pollUrl: 'https://media.test/jobs/provider-1?tenant=simichat',
          cancelUrl: 'https://media.test/jobs/provider-1?tenant=simichat',
          contentUrl:
              'https://cdn.test/generated/provider-1.mp4?tenant=simichat&sig=signed',
        );

        final row = await db.mediaJobDao.getJob('media-signed-url-1');
        expect(row, isNotNull);
        expect(row!.requestUrl, 'https://media.test/v1/videos');
        expect(
          row.pollUrl,
          'https://media.test/jobs/provider-1?tenant=simichat',
        );
        expect(
          row.cancelUrl,
          'https://media.test/jobs/provider-1?tenant=simichat',
        );
        expect(
          row.contentUrl,
          'https://cdn.test/generated/provider-1.mp4?tenant=simichat&sig=signed',
        );
      },
    );

    test(
      'sanitizes persisted media errors including URLs and local paths',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);

        await db.mediaJobDao.upsertJob(
          id: 'media-error-safe-1',
          kind: 'music',
          status: 'failed',
          error:
              'Bearer raw-secret token=raw https://media.test/fail?api_key=url-secret /var/mobile/audio.mp3',
        );

        final row = await db.mediaJobDao.getJob('media-error-safe-1');
        expect(row, isNotNull);
        expect(row!.error, contains('Bearer ***'));
        expect(row.error, contains('token=***'));
        expect(row.error, contains('[链接]'));
        expect(row.error, contains('[本机路径]'));
        expect(row.error, isNot(contains('raw-secret')));
        expect(row.error, isNot(contains('url-secret')));
        expect(row.error, isNot(contains('/var/mobile/audio.mp3')));
      },
    );

    test('claim is single-winner and terminal states are immutable', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.mediaJobDao.upsertJob(
        id: 'media-race-1',
        kind: 'music',
        status: 'pending',
        createdAt: 1000,
        updatedAt: 1000,
      );

      final claimed = await Future.wait([
        db.mediaJobDao.claimJob(
          'media-race-1',
          claimedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
        db.mediaJobDao.claimJob(
          'media-race-1',
          claimedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
      ]);
      expect(claimed.whereType<MediaJob>(), hasLength(1));
      expect((await db.mediaJobDao.getJob('media-race-1'))!.status, 'running');
      final leaseId = claimed.whereType<MediaJob>().single.leaseId;
      expect(leaseId, isNotNull);

      await db.mediaJobDao.completeJob(
        'media-race-1',
        assetPath: 'generated/music.mp3',
        assetMime: 'audio/mpeg',
        assetExtension: 'mp3',
        leaseId: leaseId,
      );
      await db.mediaJobDao.updateStatus('media-race-1', 'pending');
      await db.mediaJobDao.failJob('media-race-1', error: 'late failure');
      final terminal = await db.mediaJobDao.getJob('media-race-1');
      expect(terminal!.status, 'completed');
      expect(terminal.assetPath, 'generated/music.mp3');
      expect(await db.mediaJobDao.retryJob('media-race-1'), isNotNull);
    });

    test(
      'terminal states are monotonic for atomic upsert and terminal races',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.mediaJobDao.upsertJob(
          id: 'media-terminal-race',
          kind: 'video',
          status: 'pending',
          createdAt: 1000,
          updatedAt: 1000,
        );

        await db.mediaJobDao.upsertJob(
          id: 'media-terminal-race',
          kind: 'video',
          status: 'completed',
          assetPath: 'generated/video.mp4',
          assetMime: 'video/mp4',
          assetExtension: 'mp4',
          createdAt: 1000,
          updatedAt: 2000,
        );
        await db.mediaJobDao.upsertJob(
          id: 'media-terminal-race',
          kind: 'video',
          status: 'failed',
          error: 'late failure',
          createdAt: 1000,
          updatedAt: 3000,
        );
        var row = await db.mediaJobDao.getJob('media-terminal-race');
        expect(row!.status, 'completed');
        expect(row.assetPath, 'generated/video.mp4');

        await db.mediaJobDao.upsertJob(
          id: 'media-terminal-race',
          kind: 'video',
          status: 'completed',
          assetPath: 'generated/video-v2.mp4',
          createdAt: 1000,
          updatedAt: 4000,
        );
        row = await db.mediaJobDao.getJob('media-terminal-race');
        expect(row!.status, 'completed');
        expect(row.assetPath, 'generated/video-v2.mp4');

        await db.mediaJobDao.deleteJob('media-terminal-race');
        await db.mediaJobDao.upsertJob(
          id: 'media-terminal-race',
          kind: 'video',
          status: 'pending',
          createdAt: 5000,
          updatedAt: 5000,
        );
        final claimed = await db.mediaJobDao.claimJob(
          'media-terminal-race',
          claimedAt: DateTime.fromMillisecondsSinceEpoch(6000),
          leaseId: 'race-owner',
        );
        expect(claimed!.leaseId, 'race-owner');
        final results = await Future.wait([
          db.mediaJobDao.failJob(
            'media-terminal-race',
            error: 'first terminal',
            leaseId: 'race-owner',
          ),
          db.mediaJobDao.expireJob(
            'media-terminal-race',
            error: 'late terminal',
            leaseId: 'race-owner',
          ),
        ]);
        expect(results, hasLength(2));
        row = await db.mediaJobDao.getJob('media-terminal-race');
        expect(row!.status, anyOf(mediaJobFailedStatus, mediaJobExpiredStatus));
        // Whichever atomic UPDATE won is immutable against the other terminal
        // transition; the second call returns the authoritative winner.
        final lateCompleted = await db.mediaJobDao.completeJob(
          'media-terminal-race',
          assetPath: 'generated/late.mp4',
          leaseId: 'race-owner',
        );
        expect(lateCompleted!.status, row.status);
        expect(
          (await db.mediaJobDao.getJob('media-terminal-race'))!.status,
          row.status,
        );
      },
    );

    test(
      'heartbeat keeps the current lease from being reclaimed early',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.mediaJobDao.upsertJob(
          id: 'media-heartbeat-1',
          kind: 'music',
          status: 'pending',
          createdAt: 1000,
          updatedAt: 1000,
        );

        final owner = await db.mediaJobDao.claimJob(
          'media-heartbeat-1',
          claimedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          staleAfter: const Duration(seconds: 1),
          leaseId: 'worker-a',
        );
        expect(owner!.leaseId, 'worker-a');
        final renewed = await db.mediaJobDao.heartbeatJob(
          'media-heartbeat-1',
          'worker-a',
          heartbeatAt: DateTime.fromMillisecondsSinceEpoch(2500),
        );
        expect(renewed!.updatedAt, 2500);
        expect(
          await db.mediaJobDao.claimJob(
            'media-heartbeat-1',
            claimedAt: DateTime.fromMillisecondsSinceEpoch(3000),
            staleAfter: const Duration(seconds: 1),
            leaseId: 'worker-b',
          ),
          isNull,
        );
      },
    );

    test(
      'expired lease can be taken over, but old worker cannot heartbeat or finish',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.mediaJobDao.upsertJob(
          id: 'media-lease-takeover',
          kind: 'image',
          status: 'pending',
          createdAt: 1000,
          updatedAt: 1000,
        );
        final first = await db.mediaJobDao.claimJob(
          'media-lease-takeover',
          claimedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          staleAfter: const Duration(seconds: 1),
          leaseId: 'worker-old',
        );
        expect(first!.leaseId, 'worker-old');
        final second = await db.mediaJobDao.claimJob(
          'media-lease-takeover',
          claimedAt: DateTime.fromMillisecondsSinceEpoch(4001),
          staleAfter: const Duration(seconds: 1),
          leaseId: 'worker-new',
        );
        expect(second!.leaseId, 'worker-new');

        expect(
          await db.mediaJobDao.heartbeatJob(
            'media-lease-takeover',
            'worker-old',
            heartbeatAt: DateTime.fromMillisecondsSinceEpoch(4100),
          ),
          isNull,
        );
        final oldFinish = await db.mediaJobDao.completeJob(
          'media-lease-takeover',
          assetPath: 'generated/old.png',
          leaseId: 'worker-old',
        );
        expect(oldFinish!.status, mediaJobRunningStatus);
        expect(oldFinish.leaseId, 'worker-new');

        final newFinish = await db.mediaJobDao.failJob(
          'media-lease-takeover',
          error: 'new worker failure',
          leaseId: 'worker-new',
        );
        expect(newFinish!.status, mediaJobFailedStatus);
        expect(
          (await db.mediaJobDao.getJob('media-lease-takeover'))!.assetPath,
          isNull,
        );
      },
    );

    test('list by session and delete are scoped to media jobs', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      for (final entry in [
        ('session-a-job', 'session-a'),
        ('session-b-job', 'session-b'),
      ]) {
        await db.mediaJobDao.upsertJob(
          id: entry.$1,
          sessionId: entry.$2,
          kind: 'image',
          status: 'pending',
        );
      }
      expect(
        (await db.mediaJobDao.listJobsBySession('session-a')).map((e) => e.id),
        ['session-a-job'],
      );
      await db.mediaJobDao.deleteJob('session-a-job');
      expect(await db.mediaJobDao.getJob('session-a-job'), isNull);
      expect(await db.mediaJobDao.getJob('session-b-job'), isNotNull);
    });
  });

  group('universal media provider recovery', () {
    test(
      'ready restores pending/running jobs and expires overdue jobs',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final now = DateTime.now();
        await db.mediaJobDao.upsertJob(
          id: 'media-restart-pending',
          sessionId: 'session-restart',
          kind: 'video',
          provider: 'media.test',
          model: 'video-model',
          endpoint: '/v1/videos/generations',
          status: 'running',
          pollUrl: 'https://media.test/v1/videos/provider-1',
          providerJobId: 'provider-1',
          prompt: 'recover this task',
          deadline: now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
        );
        await db.mediaJobDao.upsertJob(
          id: 'media-restart-expired',
          kind: 'music',
          status: 'pending',
          deadline: now
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        );

        final first = UniversalMediaJobNotifier(mediaJobDao: db.mediaJobDao);
        await first.ready;
        expect(
          first.find('media-restart-pending')?.status,
          UniversalMediaJobStatus.pending,
        );
        expect(
          first.find('media-restart-pending')?.metadata['media_session_id'],
          'session-restart',
        );
        expect(
          first.find('media-restart-expired')?.status,
          UniversalMediaJobStatus.expired,
        );
        expect(
          (await db.mediaJobDao.getJob('media-restart-expired'))!.status,
          'expired',
        );

        final restarted = UniversalMediaJobNotifier(
          mediaJobDao: db.mediaJobDao,
        );
        await restarted.ready;
        expect(restarted.pendingJobs.map((job) => job.id), [
          'media-restart-pending',
        ]);
      },
    );

    test(
      'provider upsert, retry and cancel persist state without API keys',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final notifier = UniversalMediaJobNotifier(mediaJobDao: db.mediaJobDao);
        await notifier.ready;
        final job = UniversalMediaJob(
          id: 'media-provider-1',
          kind: UniversalMediaKind.video,
          status: UniversalMediaJobStatus.pending,
          pollUrl: Uri.parse('https://media.test/v1/videos/provider-1'),
        );

        await notifier.upsert(
          job,
          sessionId: 'session-provider',
          provider: 'media.test',
          model: 'video-model',
          endpoint: '/v1/videos/generations',
          prompt: 'Bearer raw-secret',
          deadline: DateTime.now().add(const Duration(minutes: 5)),
        );
        final row = await db.mediaJobDao.getJob(job.id);
        expect(row!.sessionId, 'session-provider');
        expect(row.model, 'video-model');
        expect(row.prompt, isNot(contains('raw-secret')));

        await db.mediaJobDao.failJob(job.id, error: 'temporary');
        final retried = await notifier.retry(job.id);
        expect(retried?.status, UniversalMediaJobStatus.pending);
        final cancelled = await notifier.cancelPersisted(job.id);
        expect(cancelled?.status, UniversalMediaJobStatus.cancelled);
        expect((await db.mediaJobDao.getJob(job.id))!.status, 'cancelled');
      },
    );
  });
}
