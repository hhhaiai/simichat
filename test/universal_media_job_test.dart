import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_chat_app/core/ai/universal_media_service.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/universal_media_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('media provider profiles expose explicit public wire contracts', () {
    final sora = findUniversalMediaProviderProfile(
      kUniversalMediaProfileOpenAiSora,
      kind: UniversalMediaKind.video,
    )!;
    expect(sora.taskOptions.protocol, UniversalMediaProtocol.openAiVideo);
    expect(sora.taskOptions.referenceField, 'input_reference');
    expect(sora.endpoint, '/v1/videos');
    expect(sora.wireSummary, contains('protocol=openAiVideo'));

    final xai = findUniversalMediaProviderProfile(
      kUniversalMediaProfileXaiGrokVideo,
      kind: UniversalMediaKind.video,
    )!;
    expect(xai.taskOptions.protocol, UniversalMediaProtocol.xAiVideo);
    expect(xai.taskOptions.requestFormat, UniversalMediaRequestFormat.json);
    expect(xai.taskOptions.referenceField, isNull);
    expect(xai.description, contains('request_id'));

    final customMusic = findUniversalMediaProviderProfile(
      kUniversalMediaProfileMusicCustomAsync,
      kind: UniversalMediaKind.music,
    )!;
    expect(
      customMusic.taskOptions.protocol,
      UniversalMediaProtocol.configuredAsync,
    );
    expect(
      customMusic.taskOptions.pollUrlTemplate,
      '/v1/audio/music/tasks/{id}',
    );
    expect(customMusic.taskOptions.contentUrlTemplate, contains('{id}'));
    expect(customMusic.taskOptions.cancelUrlTemplate, contains('{id}'));
  });

  test(
    'legacy model and endpoint keys migrate to a profile without a key',
    () async {
      SharedPreferences.setMockInitialValues({
        kUniversalMediaVideoModelStorageKey: 'sora-2',
        kUniversalMediaVideoEndpointStorageKey: '/v1/videos/generations',
        kUniversalMediaMusicModelStorageKey: 'legacy-music',
        kUniversalMediaMusicEndpointStorageKey: '/v1/audio/music',
      });

      final notifier = UniversalMediaConfigNotifier();
      addTearDown(notifier.dispose);
      await notifier.ready;

      expect(notifier.state.videoModel, 'sora-2');
      expect(notifier.state.videoEndpoint, '/v1/videos/generations');
      expect(notifier.state.videoProfileId, kUniversalMediaProfileOpenAiSora);
      expect(
        notifier.state.videoTaskOptions.protocol,
        UniversalMediaProtocol.openAiVideo,
      );
      expect(
        notifier.state.musicProfileId,
        kUniversalMediaProfileMusicOpenAiCompatible,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kUniversalMediaVideoProfileStorageKey),
        kUniversalMediaProfileOpenAiSora,
      );
      expect(
        prefs.getString(kUniversalMediaMusicProfileStorageKey),
        kUniversalMediaProfileMusicOpenAiCompatible,
      );
      expect(prefs.getString(kUniversalMediaVideoModelStorageKey), 'sora-2');
      expect(
        prefs.getString(kUniversalMediaVideoEndpointStorageKey),
        '/v1/videos/generations',
      );
      expect(
        prefs.getKeys().where((key) => key.toLowerCase().contains('apikey')),
        isEmpty,
      );
    },
  );

  test(
    'saving a profile writes old route keys and readable task options',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = UniversalMediaConfigNotifier();
      addTearDown(notifier.dispose);
      await notifier.ready;

      await notifier.save(
        videoModel: 'grok-imagine-video',
        videoEndpoint: '/v1/videos/generations',
        musicModel: 'music-model',
        musicEndpoint: '/v1/audio/music/tasks',
        videoProfileId: kUniversalMediaProfileXaiGrokVideo,
        musicProfileId: kUniversalMediaProfileMusicCustomAsync,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kUniversalMediaVideoModelStorageKey),
        'grok-imagine-video',
      );
      expect(
        prefs.getString(kUniversalMediaMusicEndpointStorageKey),
        '/v1/audio/music/tasks',
      );
      expect(
        prefs.getString(kUniversalMediaVideoProfileStorageKey),
        kUniversalMediaProfileXaiGrokVideo,
      );
      final videoOptions =
          jsonDecode(
                prefs.getString(kUniversalMediaVideoTaskOptionsStorageKey)!,
              )
              as Map<String, dynamic>;
      final musicOptions =
          jsonDecode(
                prefs.getString(kUniversalMediaMusicTaskOptionsStorageKey)!,
              )
              as Map<String, dynamic>;
      expect(videoOptions['protocol'], UniversalMediaProtocol.xAiVideo.name);
      expect(
        videoOptions['request_format'],
        UniversalMediaRequestFormat.json.name,
      );
      expect(
        musicOptions['protocol'],
        UniversalMediaProtocol.configuredAsync.name,
      );
      expect(musicOptions['poll_url_template'], contains('{id}'));
      expect(notifier.state.videoProfileId, kUniversalMediaProfileXaiGrokVideo);
      expect(
        notifier.state.musicTaskOptions.protocol,
        UniversalMediaProtocol.configuredAsync,
      );
    },
  );

  test('media config exposes explicit async task routing options', () {
    const options = UniversalMediaTaskOptions(
      protocol: UniversalMediaProtocol.configuredAsync,
      requestFormat: UniversalMediaRequestFormat.multipart,
      referenceField: 'source_file',
      pollUrlTemplate: '/tasks/{id}/status',
      contentUrlTemplate: '/tasks/{id}/content',
      cancelUrlTemplate: '/tasks/{id}',
    );
    const config = UniversalMediaConfig(
      videoModel: 'video-custom',
      videoEndpoint: '/v1/video/tasks',
      musicModel: 'music-custom',
      musicEndpoint: '/v1/music/tasks',
      videoTaskOptions: options,
    );

    expect(
      config.videoTaskOptions.protocol,
      UniversalMediaProtocol.configuredAsync,
    );
    expect(
      config.videoTaskOptions.requestFormat,
      UniversalMediaRequestFormat.multipart,
    );
    expect(config.videoTaskOptions.referenceField, 'source_file');
    expect(config.videoTaskOptions.pollUrlTemplate, '/tasks/{id}/status');
    expect(config.videoTaskOptions.contentUrlTemplate, '/tasks/{id}/content');
    expect(config.videoTaskOptions.cancelUrlTemplate, '/tasks/{id}');
  });

  test(
    'media config persists task routing options without losing old fields',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = UniversalMediaConfigNotifier();
      await first.ready;
      final options = const UniversalMediaTaskOptions(
        protocol: UniversalMediaProtocol.configuredAsync,
        requestFormat: UniversalMediaRequestFormat.json,
        pollUrlTemplate: '/jobs/{id}/status',
        contentUrlTemplate: '/jobs/{id}/download',
      );

      await first.save(
        videoModel: 'video-model',
        videoEndpoint: '/v1/videos/tasks',
        musicModel: 'music-model',
        musicEndpoint: '/v1/audio/tasks',
        videoTaskOptions: options,
      );

      final second = UniversalMediaConfigNotifier();
      await second.ready;
      expect(second.state.videoModel, 'video-model');
      expect(second.state.videoEndpoint, '/v1/videos/tasks');
      expect(
        second.state.videoTaskOptions.protocol,
        UniversalMediaProtocol.configuredAsync,
      );
      expect(
        second.state.videoTaskOptions.pollUrlTemplate,
        '/jobs/{id}/status',
      );
      expect(second.state.musicModel, 'music-model');
      expect(second.state.musicEndpoint, '/v1/audio/tasks');
      expect(
        second.state.musicTaskOptions.protocol,
        UniversalMediaProtocol.auto,
      );
    },
  );

  test('provider exposes pending/completed/failed/cancelled states', () {
    final notifier = UniversalMediaJobNotifier();
    final pending = UniversalMediaJob(
      id: 'job-1',
      jobId: 'provider-job-1',
      kind: UniversalMediaKind.video,
      status: UniversalMediaJobStatus.pending,
      pollUrl: Uri.parse('https://media.test/v1/videos/provider-job-1'),
      cancelUrl: Uri.parse('https://media.test/v1/videos/provider-job-1'),
    );

    notifier.upsert(pending);
    expect(notifier.pendingJobs.map((job) => job.id), ['job-1']);

    final asset = UniversalMediaAsset(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'video/mp4',
      extension: 'mp4',
    );
    notifier.markCompleted(pending, asset);
    expect(notifier.completedJobs.single.asset, same(asset));
    expect(notifier.pendingJobs, isEmpty);

    notifier.markFailed(notifier.find('job-1')!, error: 'provider failed');
    expect(notifier.failedJobs.single.error, 'provider failed');
    notifier.markCancelled(notifier.find('job-1')!);
    expect(
      notifier.cancelledJobs.single.status,
      UniversalMediaJobStatus.cancelled,
    );
    expect(notifier.failedJobs, isEmpty);
  });

  test('recovery snapshots contain routing fields but not media bytes', () {
    final notifier = UniversalMediaJobNotifier();
    final job = UniversalMediaJob(
      id: 'xai-local',
      requestId: 'req-1',
      kind: UniversalMediaKind.video,
      status: UniversalMediaJobStatus.pending,
      pollUrl: Uri.parse('https://api.x.ai/v1/videos/req-1'),
      endpointStyle: UniversalMediaEndpointStyle.xAiRequestId,
      asset: UniversalMediaAsset(
        bytes: Uint8List.fromList([9, 8, 7]),
        mimeType: 'video/mp4',
        extension: 'mp4',
      ),
    );
    notifier.upsert(job);

    final snapshot = notifier.recoverySnapshots.single;
    expect(snapshot['request_id'], 'req-1');
    expect(snapshot['poll_url'], 'https://api.x.ai/v1/videos/req-1');
    expect(snapshot.containsKey('bytes'), isFalse);

    final restored = UniversalMediaJob.fromRecoveryJson(snapshot);
    expect(restored.requestId, 'req-1');
    expect(restored.status, UniversalMediaJobStatus.pending);
    expect(restored.asset, isNull);

    final fresh = UniversalMediaJobNotifier();
    fresh.restoreRecovery([
      snapshot,
      <String, dynamic>{'bad': true},
    ]);
    expect(fresh.pendingJobs.single.id, 'xai-local');
  });

  test('recovery accepts provider aliases and preserves terminal state', () {
    final restored = UniversalMediaJob.fromRecoveryJson({
      'id': 'legacy-audio-job',
      'kind': 'audio',
      'status': 'done',
      'jobId': 'provider-job',
      'requestId': 'request-1',
      'pollUrl': 'HTTPS://media.test/v1/videos/request-1',
      'cancelUrl': 'https://media.test/v1/videos/request-1',
      'contentUrl': 'https://cdn.test/output.mp4',
      'createdAt': '2026-08-18T00:00:00Z',
      'updatedAt': '2026-08-18T00:00:01Z',
      'pollAttempts': '4',
      'endpointStyle': 'xai_request_id',
      'metadata': <String, dynamic>{'provider_status': 'done'},
    });

    expect(restored.kind, UniversalMediaKind.music);
    expect(restored.status, UniversalMediaJobStatus.completed);
    expect(restored.jobId, 'provider-job');
    expect(restored.requestId, 'request-1');
    expect(
      restored.pollUrl,
      Uri.parse('HTTPS://media.test/v1/videos/request-1'),
    );
    expect(restored.attempts, 4);
    expect(restored.endpointStyle, UniversalMediaEndpointStyle.xAiRequestId);
  });

  test('recovery accepts operation, polling, output, and error aliases', () {
    final restored = UniversalMediaJob.fromRecoveryJson({
      'operationId': 42,
      'type': 'audio',
      'phase': 'processing',
      'generationId': 9001,
      'pollingUrl': 'https://media.test/v1/audio/42',
      'deleteEndpoint': 'https://media.test/v1/audio/42',
      'outputUrl': 'https://cdn.test/audio/42.mp3',
      'pollCount': '2',
      'error': {'message': 'waiting for provider'},
    });

    expect(restored.id, '42');
    expect(restored.kind, UniversalMediaKind.music);
    expect(restored.status, UniversalMediaJobStatus.pending);
    expect(restored.jobId, '9001');
    expect(restored.pollUrl, Uri.parse('https://media.test/v1/audio/42'));
    expect(restored.cancelUrl, Uri.parse('https://media.test/v1/audio/42'));
    expect(restored.contentUrl, Uri.parse('https://cdn.test/audio/42.mp3'));
    expect(restored.attempts, 2);
    expect(restored.error, 'waiting for provider');
  });

  test('recovery errors are sanitized and nullable fields can be cleared', () {
    final asset = UniversalMediaAsset(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'video/mp4',
      extension: 'mp4',
    );
    final job = UniversalMediaJob(
      id: 'sanitize-job',
      kind: UniversalMediaKind.video,
      status: UniversalMediaJobStatus.failed,
      pollUrl: Uri.parse('https://media.test/jobs/sanitize'),
      error:
          'Bearer raw-secret token=raw sk-live-secret https://media.test/poll?token=url-secret /private/voice.mp4',
      asset: asset,
    );

    expect(job.error, contains('Bearer ***'));
    expect(job.error, contains('token=***'));
    expect(job.error, contains('sk-***'));
    expect(job.error, contains('[链接]'));
    expect(job.error, contains('[本机路径]'));
    expect(job.error, isNot(contains('raw-secret')));
    expect(job.error, isNot(contains('url-secret')));
    expect(job.toRecoveryJson()['error'], job.error);

    final restored = UniversalMediaJob.fromRecoveryJson({
      ...job.toRecoveryJson(),
      'error':
          'Bearer restored-secret https://media.test/restore /home/sanbo/out.mp4',
    });
    expect(restored.error, contains('Bearer ***'));
    expect(restored.error, contains('[链接]'));
    expect(restored.error, contains('[本机路径]'));
    expect(restored.error, isNot(contains('restored-secret')));

    final cleared = job.copyWith(error: null, asset: null, pollUrl: null);
    expect(cleared.error, isNull);
    expect(cleared.asset, isNull);
    expect(cleared.pollUrl, isNull);
  });

  test(
    'xAI operation URLs keep query parameters and use the shared videos path',
    () {
      final submit = Uri.parse(
        'https://api.x.ai/api/v2/videos/extensions?tenant=simichat',
      );

      expect(
        UniversalMediaEndpointBuilder.xAiRequestIdPollUrl(
          submitUri: submit,
          requestId: 'request-2',
        ),
        Uri.parse('https://api.x.ai/api/v2/videos/request-2?tenant=simichat'),
      );
      expect(
        UniversalMediaEndpointBuilder.openAiVideoContentUrl(
          submitUri: submit,
          videoId: 'video-2',
        ),
        Uri.parse(
          'https://api.x.ai/api/v2/videos/video-2/content?tenant=simichat',
        ),
      );
    },
  );

  test('provider submit wrapper tracks a completed custom response', () async {
    final notifier = UniversalMediaJobNotifier();
    final service = UniversalMediaService(
      baseUrl: 'https://media.test',
      apiKey: 'key',
      adapter: _StaticMediaAdapter(
        UniversalMediaHttpResponse(
          statusCode: 200,
          requestUri: Uri.parse('https://media.test/v1/audio/music'),
          headers: const {'content-type': 'application/json'},
          bytes: utf8.encode(
            jsonEncode({
              'data': [
                {
                  'b64_json': base64Encode([4, 5]),
                },
              ],
            }),
          ),
        ),
      ),
    );

    final result = await notifier.submit(
      service: service,
      kind: UniversalMediaKind.music,
      model: 'music-test',
      prompt: 'short tone',
    );

    expect(result.job.status, UniversalMediaJobStatus.completed);
    expect(notifier.completedJobs.single.id, result.job.id);
    expect(notifier.completedJobs.single.asset?.bytes, [4, 5]);
  });

  test('provider run forwards configurable request fields to submit', () async {
    final adapter = _RunExtraMediaAdapter();
    final notifier = UniversalMediaJobNotifier();
    final result = await notifier.run(
      operationId: 'run-extra-fields',
      service: UniversalMediaService(
        baseUrl: 'https://media.test',
        apiKey: 'key',
        adapter: adapter,
        pollingOptions: const UniversalMediaPollingOptions(
          maxAttempts: 1,
          deadline: Duration(seconds: 1),
          initialBackoff: Duration.zero,
        ),
      ),
      kind: UniversalMediaKind.music,
      model: 'music-test',
      prompt: 'custom fields',
      extra: const <String, dynamic>{
        'duration_seconds': 18,
        'output_format': 'opus',
      },
    );

    expect(result.job.status, UniversalMediaJobStatus.completed);
    expect(adapter.extra, {'duration_seconds': 18, 'output_format': 'opus'});
  });

  test(
    'run stops before polling when the database claim loses a race',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.mediaJobDao.upsertJob(
        id: 'claim-race-job',
        kind: 'music',
        status: 'running',
        leaseId: 'other-worker',
        createdAt: now,
        updatedAt: now,
        pollUrl: 'https://media.test/v1/audio/claim-race-job',
      );

      final adapter = _PendingMediaAdapter();
      final notifier = UniversalMediaJobNotifier(mediaJobDao: db.mediaJobDao);
      await notifier.ready;
      final service = UniversalMediaService(
        baseUrl: 'https://media.test',
        apiKey: 'test-key',
        adapter: adapter,
        pollingOptions: const UniversalMediaPollingOptions(
          maxAttempts: 2,
          deadline: Duration(seconds: 1),
          initialBackoff: Duration.zero,
          maxBackoff: Duration.zero,
        ),
      );

      await expectLater(
        notifier.run(
          operationId: 'claim-race-job',
          service: service,
          kind: UniversalMediaKind.music,
          model: 'music-test',
          prompt: 'claim race',
        ),
        throwsA(isA<UniversalMediaClaimException>()),
      );
      expect(adapter.pollCalls, 0);
      final row = await db.mediaJobDao.getJob('claim-race-job');
      expect(row!.status, 'running');
      expect(row.leaseId, 'other-worker');
      expect(
        notifier.find('claim-race-job')?.status,
        UniversalMediaJobStatus.pending,
      );
    },
  );

  test('waitFor heartbeats the lease during a long poll', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final jobId = 'heartbeat-provider-job';
    final pollUrl = 'https://media.test/v1/videos/$jobId';
    await db.mediaJobDao.upsertJob(
      id: jobId,
      kind: 'video',
      status: 'pending',
      pollUrl: pollUrl,
    );
    final adapter = _HeartbeatMediaAdapter(pollUrl: Uri.parse(pollUrl));
    final notifier = UniversalMediaJobNotifier(
      mediaJobDao: db.mediaJobDao,
      leaseHeartbeatInterval: const Duration(milliseconds: 10),
    );
    await notifier.ready;
    final job = UniversalMediaJob(
      id: jobId,
      kind: UniversalMediaKind.video,
      status: UniversalMediaJobStatus.pending,
      pollUrl: Uri.parse(pollUrl),
    );
    final wait = notifier.waitFor(
      service: UniversalMediaService(
        baseUrl: 'https://media.test',
        apiKey: 'test-key',
        adapter: adapter,
      ),
      job: job,
      pollingOptions: const UniversalMediaPollingOptions(
        maxAttempts: 3,
        deadline: Duration(seconds: 1),
        initialBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      ),
    );
    await adapter.firstPollStarted.future;
    final claimedAt = (await db.mediaJobDao.getJob(jobId))!.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final renewed = await db.mediaJobDao.getJob(jobId);
    expect(renewed!.leaseId, isNotNull);
    expect(renewed.updatedAt, greaterThan(claimedAt));
    adapter.releaseFirstPoll();

    final result = await wait;
    expect(result.job.status, UniversalMediaJobStatus.completed);
    final completedResponse = await db.mediaJobDao.getJob(jobId);
    expect(completedResponse!.leaseId, isNotNull);
  });
}

class _StaticMediaAdapter implements UniversalMediaAdapter {
  _StaticMediaAdapter(this.response);

  final UniversalMediaHttpResponse response;

  @override
  Future<UniversalMediaHttpResponse> submit(
    UniversalMediaSubmitRequest request,
  ) async => response;

  @override
  Future<UniversalMediaHttpResponse> poll(
    UniversalMediaPollRequest request,
  ) async => response;

  @override
  Future<UniversalMediaHttpResponse> cancel(
    UniversalMediaCancelRequest request,
  ) async => response;
}

class _RunExtraMediaAdapter implements UniversalMediaAdapter {
  Map<String, dynamic>? extra;

  @override
  Future<UniversalMediaHttpResponse> submit(
    UniversalMediaSubmitRequest request,
  ) async {
    extra = Map<String, dynamic>.from(request.extra);
    return UniversalMediaHttpResponse(
      statusCode: 202,
      requestUri: Uri.parse('https://media.test/v1/audio/music'),
      headers: const {'content-type': 'application/json'},
      bytes: utf8.encode(
        jsonEncode({'task_id': 'run-extra-provider-job', 'status': 'queued'}),
      ),
    );
  }

  @override
  Future<UniversalMediaHttpResponse> poll(
    UniversalMediaPollRequest request,
  ) async {
    return UniversalMediaHttpResponse(
      statusCode: 200,
      requestUri: request.job.pollUrl ?? Uri.parse('https://media.test'),
      headers: const {'content-type': 'application/json'},
      bytes: utf8.encode(
        jsonEncode({
          'task_id': 'run-extra-provider-job',
          'status': 'completed',
          'b64_json': base64Encode([7, 8, 9]),
        }),
      ),
    );
  }

  @override
  Future<UniversalMediaHttpResponse> cancel(
    UniversalMediaCancelRequest request,
  ) async {
    return UniversalMediaHttpResponse(
      statusCode: 204,
      requestUri: request.job.pollUrl ?? Uri.parse('https://media.test'),
      bytes: const <int>[],
    );
  }
}

class _PendingMediaAdapter implements UniversalMediaAdapter {
  int pollCalls = 0;

  UniversalMediaHttpResponse get _pending => UniversalMediaHttpResponse(
    statusCode: 202,
    requestUri: Uri.parse('https://media.test/v1/audio/music'),
    headers: const {'content-type': 'application/json'},
    bytes: utf8.encode(
      jsonEncode({
        'id': 'claim-race-provider-job',
        'status': 'pending',
        'poll_url': 'https://media.test/v1/audio/claim-race-provider-job',
      }),
    ),
  );

  @override
  Future<UniversalMediaHttpResponse> submit(
    UniversalMediaSubmitRequest request,
  ) async => _pending;

  @override
  Future<UniversalMediaHttpResponse> poll(
    UniversalMediaPollRequest request,
  ) async {
    pollCalls++;
    return _pending;
  }

  @override
  Future<UniversalMediaHttpResponse> cancel(
    UniversalMediaCancelRequest request,
  ) async => _pending;
}

class _HeartbeatMediaAdapter implements UniversalMediaAdapter {
  _HeartbeatMediaAdapter({required this.pollUrl});

  final Uri pollUrl;
  final Completer<void> firstPollStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();
  int pollCalls = 0;

  UniversalMediaHttpResponse _response({required bool completed}) {
    final body = completed
        ? <String, dynamic>{
            'id': 'heartbeat-provider-job',
            'status': 'completed',
            'data': [
              {
                'b64_json': base64Encode([1, 2, 3, 4]),
              },
            ],
          }
        : <String, dynamic>{
            'id': 'heartbeat-provider-job',
            'status': 'pending',
            'poll_url': pollUrl.toString(),
          };
    return UniversalMediaHttpResponse(
      statusCode: completed ? 200 : 202,
      requestUri: pollUrl,
      headers: const {'content-type': 'application/json'},
      bytes: utf8.encode(jsonEncode(body)),
    );
  }

  void releaseFirstPoll() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<UniversalMediaHttpResponse> submit(
    UniversalMediaSubmitRequest request,
  ) async => _response(completed: false);

  @override
  Future<UniversalMediaHttpResponse> poll(
    UniversalMediaPollRequest request,
  ) async {
    pollCalls++;
    if (pollCalls == 1) {
      firstPollStarted.complete();
      await _release.future;
      return _response(completed: false);
    }
    return _response(completed: true);
  }

  @override
  Future<UniversalMediaHttpResponse> cancel(
    UniversalMediaCancelRequest request,
  ) async => _response(completed: false);
}
