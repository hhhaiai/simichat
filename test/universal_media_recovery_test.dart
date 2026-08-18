import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat_app/core/ai/universal_media_service.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart' as database;
import 'package:ai_chat_app/core/database/dao/channel_dao.dart';
import 'package:ai_chat_app/core/database/dao/media_job_dao.dart'
    as media_database;
import 'package:ai_chat_app/shared/providers/universal_media_provider.dart';
import 'package:ai_chat_app/shared/providers/universal_media_recovery_provider.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UniversalMediaRecoveryCoordinator', () {
    test(
      'awaits notifier.ready, starts once, claims and delivers a pending job',
      () async {
        final db = database.AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final root = await Directory.systemTemp.createTemp(
          'simichat_universal_media_recovery_start_',
        );
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        await _seedValidRouting(db);
        await _insertRecoverableJob(db, id: 'recovery-start-job');

        final notifier = UniversalMediaJobNotifier(mediaJobDao: db.mediaJobDao);
        final adapter = _CompletingMediaAdapter();
        final harness = _ServiceFactoryHarness(adapter);
        final coordinator = UniversalMediaRecoveryCoordinator(
          appDatabase: db,
          notifier: notifier,
          serviceFactory: harness.create,
        );

        final first = coordinator.start(
          delivery: _localDelivery(
            database: db,
            notifier: notifier,
            rootDirectory: root,
          ),
        );
        // start() must not inspect the recoverable list before the notifier's
        // SQLite restore boundary has completed. The second call must reuse
        // this exact Future rather than creating another worker.
        expect(harness.factoryCalls, 0);
        expect(adapter.pollCalls, 0);
        final second = coordinator.start(
          delivery: ({required row, required result, required leaseId}) async {
            fail('a second start must not invoke a second delivery callback');
          },
        );
        expect(identical(first, second), isTrue);
        expect(coordinator.isStarted, isTrue);

        await notifier.ready;
        await first;

        expect(harness.factoryCalls, 1);
        expect(harness.apiKeys, ['test-api-key']);
        expect(adapter.pollCalls, 1);
        final row = await db.mediaJobDao.getJob('recovery-start-job');
        expect(row, isNotNull);
        expect(row!.status, media_database.mediaJobCompletedStatus);
        expect(
          row.deliveryPhase,
          media_database.mediaJobDeliveryCompletedPhase,
        );
        expect(row.leaseId, isNull);
        expect(row.deliveryUserMessageId, 'recovery-start-job-user');
        expect(row.deliveryAssistantMessageId, 'recovery-start-job-assistant');
        expect(row.deliveryAttachmentId, 'recovery-start-job-attachment');
        expect(
          await db.messageDao.getMessagesBySession('recovery-session'),
          hasLength(2),
        );
        expect(await db.attachmentDao.getAllAttachments(), hasLength(1));
      },
    );

    test(
      'two coordinators racing on the same SQLite row produce one claim and one delivery',
      () async {
        final db = database.AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final root = await Directory.systemTemp.createTemp(
          'simichat_universal_media_recovery_race_',
        );
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        await _seedValidRouting(db);
        await _insertRecoverableJob(db, id: 'recovery-race-job');

        final notifierA = UniversalMediaJobNotifier(
          mediaJobDao: db.mediaJobDao,
        );
        final notifierB = UniversalMediaJobNotifier(
          mediaJobDao: db.mediaJobDao,
        );
        final adapter = _CompletingMediaAdapter();
        final harness = _ServiceFactoryHarness(adapter);
        final coordinatorA = UniversalMediaRecoveryCoordinator(
          appDatabase: db,
          notifier: notifierA,
          serviceFactory: harness.create,
        );
        final coordinatorB = UniversalMediaRecoveryCoordinator(
          appDatabase: db,
          notifier: notifierB,
          serviceFactory: harness.create,
        );

        await Future.wait([
          coordinatorA.start(
            delivery: _localDelivery(
              database: db,
              notifier: notifierA,
              rootDirectory: root,
            ),
          ),
          coordinatorB.start(
            delivery: _localDelivery(
              database: db,
              notifier: notifierB,
              rootDirectory: root,
            ),
          ),
        ]);

        expect(harness.factoryCalls, 1);
        expect(adapter.pollCalls, 1);
        final row = await db.mediaJobDao.getJob('recovery-race-job');
        expect(row!.status, media_database.mediaJobCompletedStatus);
        expect(
          row.deliveryPhase,
          media_database.mediaJobDeliveryCompletedPhase,
        );
        expect(row.deliveryUserMessageId, 'recovery-race-job-user');
        expect(row.deliveryAssistantMessageId, 'recovery-race-job-assistant');
        expect(row.deliveryAttachmentId, 'recovery-race-job-attachment');
        expect(
          await db.messageDao.getMessagesBySession('recovery-session'),
          hasLength(2),
        );
        expect(await db.attachmentDao.getAllAttachments(), hasLength(1));
      },
    );

    test(
      'missing channel, invalid key, and expired deadline converge explicitly',
      () async {
        final db = database.AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await _seedValidRouting(db);
        await db.channelDao.createChannel(
          id: 'bad-key-channel',
          name: 'Bad key channel',
          baseUrl: 'https://media.test',
          apiKeyEncrypted: 'not-an-encrypted-key',
          protocol: 'openai_chat',
        );
        await db.channelDao.addModel(
          id: 'bad-key-model',
          channelId: 'bad-key-channel',
          modelName: 'music-test',
        );

        final now = DateTime.now().millisecondsSinceEpoch;
        await _insertRecoverableJob(
          db,
          id: 'missing-channel-job',
          channelModelId: 'missing-channel-model',
          deadline: now + 60000,
        );
        await _insertRecoverableJob(
          db,
          id: 'bad-key-job',
          channelModelId: 'bad-key-model',
          deadline: now + 60000,
        );
        await _insertRecoverableJob(db, id: 'expired-job', deadline: now - 1);

        final notifier = UniversalMediaJobNotifier(mediaJobDao: db.mediaJobDao);
        final adapter = _CompletingMediaAdapter();
        final harness = _ServiceFactoryHarness(adapter);
        var deliveryCalls = 0;
        final coordinator = UniversalMediaRecoveryCoordinator(
          appDatabase: db,
          notifier: notifier,
          serviceFactory: harness.create,
        );
        await coordinator.start(
          delivery: ({required row, required result, required leaseId}) async {
            deliveryCalls++;
          },
        );

        final missing = await db.mediaJobDao.getJob('missing-channel-job');
        final badKey = await db.mediaJobDao.getJob('bad-key-job');
        final expired = await db.mediaJobDao.getJob('expired-job');
        expect(missing!.status, media_database.mediaJobFailedStatus);
        expect(missing.error, contains('渠道模型不存在'));
        expect(missing.leaseId, isNull);
        expect(badKey!.status, media_database.mediaJobFailedStatus);
        expect(badKey.error, contains('API Key 缺失或无法解密'));
        expect(badKey.leaseId, isNull);
        expect(expired!.status, media_database.mediaJobExpiredStatus);
        expect(expired.error, contains('已过期'));
        expect(expired.leaseId, isNull);
        expect(harness.factoryCalls, 0);
        expect(adapter.pollCalls, 0);
        expect(deliveryCalls, 0);
        expect(await db.mediaJobDao.listRecoverableJobs(), isEmpty);
      },
    );

    test(
      'a factory exception fails one job without blocking later recovery',
      () async {
        final db = database.AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await _seedValidRouting(db);
        await _insertRecoverableJob(db, id: 'factory-fails-job');
        await _insertRecoverableJob(db, id: 'factory-recovers-job');

        final notifier = UniversalMediaJobNotifier(mediaJobDao: db.mediaJobDao);
        final adapter = _CompletingMediaAdapter();
        final harness = _ServiceFactoryHarness(adapter);
        final coordinator = UniversalMediaRecoveryCoordinator(
          appDatabase: db,
          notifier: notifier,
          serviceFactory: (row, model, apiKey) {
            if (row.id == 'factory-fails-job') {
              throw StateError(
                'factory Bearer raw-factory-secret https://media.test/factory /Users/sanbo/factory.log',
              );
            }
            return harness.create(row, model, apiKey);
          },
        );

        await coordinator.start(
          delivery: ({required row, required result, required leaseId}) async {
            final asset = result.asset!;
            await deliverRecoveredUniversalMediaJob(
              database: db,
              notifier: notifier,
              row: row,
              result: result,
              leaseId: leaseId,
              rootDirectory: await Directory.systemTemp.createTemp(
                'simichat_universal_media_recovery_factory_',
              ),
            );
            expect(asset.bytes, isNotEmpty);
          },
        );

        final failed = await db.mediaJobDao.getJob('factory-fails-job');
        final recovered = await db.mediaJobDao.getJob('factory-recovers-job');
        expect(failed!.status, media_database.mediaJobFailedStatus);
        expect(failed.error, contains('Bearer ***'));
        expect(failed.error, contains('[链接]'));
        expect(failed.error, contains('[本机路径]'));
        expect(failed.error, isNot(contains('raw-factory-secret')));
        expect(recovered!.status, media_database.mediaJobCompletedStatus);
        expect(adapter.pollCalls, 1);
      },
    );

    test(
      'repeated recovery and delivery reuse the same message and attachment IDs',
      () async {
        final db = database.AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final root = await Directory.systemTemp.createTemp(
          'simichat_universal_media_recovery_idempotent_',
        );
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        await _seedValidRouting(db);
        const jobId = 'recovery-idempotent-job';
        await _insertRecoverableJob(db, id: jobId);

        final adapter = _CompletingMediaAdapter();
        final harness = _ServiceFactoryHarness(adapter);
        final notifierA = UniversalMediaJobNotifier(
          mediaJobDao: db.mediaJobDao,
        );
        final coordinatorA = UniversalMediaRecoveryCoordinator(
          appDatabase: db,
          notifier: notifierA,
          serviceFactory: harness.create,
        );
        await coordinatorA.start(
          delivery: _localDelivery(
            database: db,
            notifier: notifierA,
            rootDirectory: root,
          ),
        );

        final completed = await db.mediaJobDao.getJob(jobId);
        expect(completed!.status, media_database.mediaJobCompletedStatus);
        expect(
          completed.deliveryPhase,
          media_database.mediaJobDeliveryCompletedPhase,
        );
        final stableIds = <String?>[
          completed.deliveryUserMessageId,
          completed.deliveryAssistantMessageId,
          completed.deliveryAttachmentId,
        ];

        // A new process/notifier sees no recoverable work. This is a recovery
        // check, not a real cloud E2E: the adapter below is deterministic fake
        // transport and the assertions are local SQLite/file effects.
        final notifierB = UniversalMediaJobNotifier(
          mediaJobDao: db.mediaJobDao,
        );
        final coordinatorB = UniversalMediaRecoveryCoordinator(
          appDatabase: db,
          notifier: notifierB,
          serviceFactory: harness.create,
        );
        await coordinatorB.start(
          delivery: _localDelivery(
            database: db,
            notifier: notifierB,
            rootDirectory: root,
          ),
        );
        expect(harness.factoryCalls, 1);
        expect(adapter.pollCalls, 1);

        final asset = UniversalMediaAsset(
          bytes: Uint8List.fromList([9, 8, 7]),
          mimeType: 'audio/mpeg',
          extension: 'mp3',
        );
        final duplicateResult = UniversalMediaJobResult(
          job: UniversalMediaJob(
            id: jobId,
            kind: UniversalMediaKind.music,
            status: UniversalMediaJobStatus.completed,
            asset: asset,
          ),
          asset: asset,
        );
        await deliverRecoveredUniversalMediaJob(
          database: db,
          notifier: notifierB,
          row: completed,
          result: duplicateResult,
          leaseId: 'duplicate-delivery-lease',
          rootDirectory: root,
        );
        await deliverRecoveredUniversalMediaJob(
          database: db,
          notifier: notifierB,
          row: completed,
          result: duplicateResult,
          leaseId: 'duplicate-delivery-lease-2',
          rootDirectory: root,
        );

        final after = await db.mediaJobDao.getJob(jobId);
        final messages = await db.messageDao.getMessagesBySession(
          'recovery-session',
        );
        final attachments = await db.attachmentDao.getAllAttachments();
        expect(after!.status, media_database.mediaJobCompletedStatus);
        expect(
          after.deliveryPhase,
          media_database.mediaJobDeliveryCompletedPhase,
        );
        expect(<String?>[
          after.deliveryUserMessageId,
          after.deliveryAssistantMessageId,
          after.deliveryAttachmentId,
        ], stableIds);
        expect(messages, hasLength(2));
        expect(
          messages.map((message) => message.id),
          containsAll(<String>[stableIds[0]!, stableIds[1]!]),
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.id, stableIds[2]);
      },
    );
  });
}

Future<void> _seedValidRouting(database.AppDatabase db) async {
  await db.channelDao.createChannel(
    id: 'media-channel',
    name: 'Fake media channel',
    baseUrl: 'https://media.test',
    apiKeyEncrypted: KeyEncryptor.encrypt('test-api-key'),
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'media-model',
    channelId: 'media-channel',
    modelName: 'music-test',
  );
  await db.sessionDao.createSession(
    id: 'recovery-session',
    defaultChannelModelId: 'media-model',
  );
}

Future<void> _insertRecoverableJob(
  database.AppDatabase db, {
  required String id,
  String channelModelId = 'media-model',
  int? deadline,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final ids = UniversalMediaDeliveryIds.forOperationId(id);
  await db.mediaJobDao.upsertJob(
    id: id,
    sessionId: 'recovery-session',
    kind: 'music',
    status: media_database.mediaJobPendingStatus,
    provider: 'fake-provider',
    model: 'music-test',
    endpoint: '/v1/audio/music',
    phase: 'pending',
    providerJobId: 'provider-$id',
    pollUrl: 'https://media.test/v1/audio/$id',
    prompt: 'deterministic recovery prompt',
    createdAt: now,
    updatedAt: now,
    deadline: deadline ?? now + 60000,
    endpointStyle: UniversalMediaEndpointStyle.auto.name,
    channelModelId: channelModelId,
    deliveryUserMessageId: ids.userMessageId,
    deliveryAssistantMessageId: ids.assistantMessageId,
    deliveryAttachmentId: ids.attachmentId,
    deliverySourceAttachmentId: ids.sourceAttachmentId,
    deliveryPhase: media_database.mediaJobDeliveryPlannedPhase,
    deliveryUserContent: '生成音乐：deterministic recovery prompt',
    deliveryAssistantContent: '已生成音乐',
    deliveryFileType: 'audio',
  );
}

UniversalMediaRecoveryDelivery _localDelivery({
  required database.AppDatabase database,
  required UniversalMediaJobNotifier notifier,
  required Directory rootDirectory,
}) {
  return ({required row, required result, required leaseId}) {
    return deliverRecoveredUniversalMediaJob(
      database: database,
      notifier: notifier,
      row: row,
      result: result,
      leaseId: leaseId,
      rootDirectory: rootDirectory,
    );
  };
}

class _ServiceFactoryHarness {
  _ServiceFactoryHarness(this.adapter);

  final _CompletingMediaAdapter adapter;
  int factoryCalls = 0;
  final List<String> apiKeys = <String>[];

  UniversalMediaService create(
    database.MediaJob row,
    ChannelModelWithChannel model,
    String apiKey,
  ) {
    factoryCalls++;
    apiKeys.add(apiKey);
    return UniversalMediaService(
      baseUrl: model.channel.baseUrl,
      apiKey: apiKey,
      adapter: adapter,
      pollingOptions: const UniversalMediaPollingOptions(
        maxAttempts: 2,
        deadline: Duration(seconds: 1),
        initialBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      ),
    );
  }
}

class _CompletingMediaAdapter implements UniversalMediaAdapter {
  int submitCalls = 0;
  int pollCalls = 0;
  int cancelCalls = 0;
  final List<String> apiKeys = <String>[];

  UniversalMediaHttpResponse _completed(Uri requestUri) {
    return UniversalMediaHttpResponse(
      statusCode: 200,
      requestUri: requestUri,
      headers: const {'content-type': 'application/json'},
      bytes: utf8.encode(
        jsonEncode({
          'id': 'fake-provider-job',
          'status': 'completed',
          'data': [
            {
              'b64_json': base64Encode([1, 2, 3, 4]),
            },
          ],
        }),
      ),
    );
  }

  @override
  Future<UniversalMediaHttpResponse> submit(
    UniversalMediaSubmitRequest request,
  ) async {
    submitCalls++;
    apiKeys.add(request.apiKey);
    return _completed(request.baseUri);
  }

  @override
  Future<UniversalMediaHttpResponse> poll(
    UniversalMediaPollRequest request,
  ) async {
    pollCalls++;
    apiKeys.add(request.apiKey);
    return _completed(request.job.pollUrl ?? request.baseUri);
  }

  @override
  Future<UniversalMediaHttpResponse> cancel(
    UniversalMediaCancelRequest request,
  ) async {
    cancelCalls++;
    apiKeys.add(request.apiKey);
    return UniversalMediaHttpResponse(
      statusCode: 204,
      requestUri: request.job.pollUrl ?? request.baseUri,
      bytes: const <int>[],
    );
  }
}
