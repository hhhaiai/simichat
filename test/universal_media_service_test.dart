import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ai_chat_app/core/ai/universal_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UniversalMediaService', () {
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() => server.close(force: true));

    test(
      'parses b64_json video result and uses configurable endpoint',
      () async {
        final seen = Completer<String>();
        unawaited(
          server.forEach((request) async {
            final body = await utf8.decodeStream(request);
            seen.complete(body);
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'data': [
                    {
                      'b64_json': base64Encode([1, 2, 3, 4]),
                    },
                  ],
                }),
              );
            await request.response.close();
          }),
        );

        final asset =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'media-test-key',
            ).generateVideo(
              model: 'video-test',
              endpoint: '/v1/video/custom',
              prompt: '一只猫在海边奔跑',
            );

        expect(asset.bytes, [1, 2, 3, 4]);
        expect(asset.mimeType, 'video/mp4');
        expect(asset.extension, 'mp4');
        expect(seen.future, completion(contains('一只猫在海边奔跑')));
      },
    );

    test(
      'does not duplicate /v1 when a media base has a custom prefix',
      () async {
        final paths = <String>[];
        server.listen((request) async {
          paths.add(request.uri.path);
          await request.drain();
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'data': [
                  {
                    'b64_json': base64Encode([0x10, 0x11]),
                  },
                ],
              }),
            );
          await request.response.close();
        });

        final service = UniversalMediaService(
          baseUrl: '$baseUrl/v2',
          apiKey: 'media-test-key',
        );
        await service.generateImage(prompt: 'origin-root image');
        await service.generateVideo(
          model: 'video-test',
          endpoint: 'videos/custom',
          prompt: 'prefix-relative video',
        );

        expect(paths, ['/v1/images/generations', '/v2/videos/custom']);
      },
    );

    test('accepts direct binary music response', () async {
      server.listen((request) async {
        request.response
          ..headers.contentType = ContentType('audio', 'mpeg')
          ..add([9, 8, 7]);
        await request.response.close();
      });

      final asset = await UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'music-key',
      ).generateMusic(model: 'music-test', prompt: '轻快的爵士钢琴');

      expect(asset.bytes, [9, 8, 7]);
      expect(asset.mimeType, 'audio/mpeg');
      expect(asset.extension, 'mp3');
    });

    test(
      'keeps explicit media MIME binary even when bytes start like JSON',
      () async {
        server.listen((request) async {
          request.response
            ..headers.contentType = ContentType('image', 'png')
            ..add([0x7b, 0x01, 0x02, 0x03]);
          await request.response.close();
        });

        final asset = await UniversalMediaService(
          baseUrl: baseUrl,
          apiKey: 'image-key',
        ).generateImage(prompt: 'binary image');

        expect(asset.bytes, [0x7b, 0x01, 0x02, 0x03]);
        expect(asset.mimeType, 'image/png');
        expect(asset.extension, 'png');
      },
    );

    test('maps an opus output format to audio/opus and .opus', () async {
      server.listen((request) async {
        await request.drain();
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'status': 'completed',
              'output_format': 'opus',
              'b64_json': base64Encode([1, 2, 3]),
            }),
          );
        await request.response.close();
      });

      final asset = await UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'music-key',
      ).generateMusic(model: 'music-test', prompt: 'an opus tone');

      expect(asset.mimeType, 'audio/opus');
      expect(asset.extension, 'opus');
    });

    test(
      'uses a requested output format when media response omits its MIME',
      () async {
        server.listen((request) async {
          await request.drain();
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'status': 'completed',
                'b64_json': base64Encode([4, 5, 6]),
              }),
            );
          await request.response.close();
        });

        final asset =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'music-key',
            ).generateMusic(
              model: 'music-test',
              prompt: 'requested opus format',
              extra: const <String, dynamic>{'output_format': 'opus'},
            );

        expect(asset.mimeType, 'audio/opus');
        expect(asset.extension, 'opus');
      },
    );

    test(
      'uses a requested output format for generic binary responses',
      () async {
        server.listen((request) async {
          await request.drain();
          request.response
            ..headers.contentType = ContentType.binary
            ..add([7, 8, 9]);
          await request.response.close();
        });

        final asset =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'music-key',
            ).generateMusic(
              model: 'music-test',
              prompt: 'binary opus format',
              extra: const <String, dynamic>{'output_format': 'opus'},
            );

        expect(asset.mimeType, 'audio/opus');
        expect(asset.extension, 'opus');
      },
    );

    test(
      'does not add image-only response_format to configurable music fields',
      () async {
        final bodySeen = Completer<Map<String, dynamic>>();
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          bodySeen.complete(jsonDecode(body) as Map<String, dynamic>);
          request.response
            ..statusCode = 202
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({'task_id': 'music-fields-1', 'status': 'queued'}),
            );
          await request.response.close();
        });

        final result =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'music-key',
            ).submitMusic(
              model: 'music-test',
              prompt: 'lofi loop',
              extra: const <String, dynamic>{
                'duration_seconds': 12,
                'output_format': 'opus',
              },
            );

        final body = await bodySeen.future;
        expect(result.job.status, UniversalMediaJobStatus.pending);
        expect(body['duration_seconds'], 12);
        expect(body['output_format'], 'opus');
        expect(body.containsKey('response_format'), isFalse);
      },
    );

    test(
      'uses explicit OpenAI image edit fields and omits response_format for gpt-image',
      () async {
        final temp = await Directory.systemTemp.createTemp('universal-media-');
        addTearDown(() => temp.delete(recursive: true));
        final image = File('${temp.path}/input.png')
          ..writeAsBytesSync([1, 2, 3]);
        final bodySeen = Completer<String>();
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          bodySeen.complete(body);
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'data': [
                  {
                    'b64_json': base64Encode([0x89, 0x50, 0x4e, 0x47]),
                    'output_format': 'png',
                  },
                ],
              }),
            );
          await request.response.close();
        });

        final result =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'image-key',
            ).generateImageEdit(
              model: 'gpt-image-1',
              prompt: 'make it a sketch',
              referenceImagePath: image.path,
              extra: const <String, dynamic>{'output_format': 'png'},
            );

        final body = await bodySeen.future;
        expect(result.mimeType, 'image/png');
        expect(body, contains('name="output_format"'));
        expect(body, isNot(contains('name="response_format"')));
      },
    );

    test(
      'polls a configured async music task and derives the downloaded extension',
      () async {
        final paths = <String>[];
        server.listen((request) async {
          paths.add(request.uri.path);
          if (request.method == 'POST') {
            await request.drain();
            request.response
              ..statusCode = 202
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({'task_id': 'music-task-1', 'state': 'queued'}),
              );
          } else if (request.uri.path == '/jobs/music-task-1/status') {
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({'task_id': 'music-task-1', 'state': 'completed'}),
              );
          } else if (request.uri.path == '/jobs/music-task-1/download') {
            request.response
              ..headers.contentType = ContentType('audio', 'webm')
              ..add([0x1a, 0x45, 0xdf, 0xa3, 1, 2]);
          } else {
            request.response.statusCode = 404;
          }
          await request.response.close();
        });

        final asset =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'music-key',
            ).generateMusic(
              model: 'custom-music',
              prompt: 'ambient rain',
              extra: const <String, dynamic>{'duration_seconds': 30},
              taskOptions: const UniversalMediaTaskOptions(
                protocol: UniversalMediaProtocol.configuredAsync,
                requestFormat: UniversalMediaRequestFormat.json,
                pollUrlTemplate: '/jobs/{id}/status',
                contentUrlTemplate: '/jobs/{id}/download',
                cancelUrlTemplate: '/jobs/{id}',
              ),
              pollingOptions: const UniversalMediaPollingOptions(
                maxAttempts: 1,
                deadline: Duration(seconds: 2),
                initialBackoff: Duration.zero,
              ),
            );

        expect(asset.bytes, [0x1a, 0x45, 0xdf, 0xa3, 1, 2]);
        expect(asset.mimeType, 'audio/webm');
        expect(asset.extension, 'webm');
        expect(paths, [
          '/v1/audio/music',
          '/jobs/music-task-1/status',
          '/jobs/music-task-1/download',
        ]);
      },
    );

    test(
      'uses the configured content URL extension when download MIME is generic',
      () async {
        final paths = <String>[];
        server.listen((request) async {
          paths.add(request.uri.path);
          if (request.method == 'POST') {
            await request.drain();
            request.response
              ..statusCode = 202
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'task_id': 'generic-mime-1'}));
          } else if (request.uri.path == '/tasks/generic-mime-1/status') {
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'task_id': 'generic-mime-1',
                  'status': 'completed',
                }),
              );
          } else if (request.uri.path == '/tasks/generic-mime-1/output.webm') {
            request.response
              ..headers.contentType = ContentType.binary
              ..add([1, 2, 3]);
          } else {
            request.response.statusCode = 404;
          }
          await request.response.close();
        });

        final asset =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'music-key',
            ).generateMusic(
              model: 'music-test',
              prompt: 'generic MIME output',
              taskOptions: const UniversalMediaTaskOptions(
                protocol: UniversalMediaProtocol.configuredAsync,
                pollUrlTemplate: '/tasks/{id}/status',
                contentUrlTemplate: '/tasks/{id}/output.webm',
              ),
              pollingOptions: const UniversalMediaPollingOptions(
                maxAttempts: 1,
                deadline: Duration(seconds: 2),
                initialBackoff: Duration.zero,
              ),
            );

        expect(asset.bytes, [1, 2, 3]);
        expect(asset.mimeType, 'audio/webm');
        expect(asset.extension, 'webm');
        expect(paths, [
          '/v1/audio/music',
          '/tasks/generic-mime-1/status',
          '/tasks/generic-mime-1/output.webm',
        ]);
      },
    );

    test(
      'forced JSON reference uploads a data URL instead of a local path',
      () async {
        final temp = await Directory.systemTemp.createTemp('universal-media-');
        addTearDown(() => temp.delete(recursive: true));
        final image = File('${temp.path}/reference.png')
          ..writeAsBytesSync([1, 2, 3]);
        final bodySeen = Completer<Map<String, dynamic>>();
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          bodySeen.complete(jsonDecode(body) as Map<String, dynamic>);
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'status': 'completed',
                'b64_json': base64Encode([4, 5, 6]),
              }),
            );
          await request.response.close();
        });

        await UniversalMediaService(
          baseUrl: baseUrl,
          apiKey: 'json-reference-key',
        ).submitVideo(
          model: 'custom-video',
          prompt: 'animate the reference',
          referenceImagePath: image.path,
          extra: const <String, dynamic>{'source_image': '/should-not-be-sent'},
          taskOptions: const UniversalMediaTaskOptions(
            protocol: UniversalMediaProtocol.configuredAsync,
            requestFormat: UniversalMediaRequestFormat.json,
            referenceField: 'source_image',
          ),
        );

        final body = await bodySeen.future;
        expect(body['source_image'], startsWith('data:image/png;base64,'));
        expect(body['source_image'], isNot(image.path));
      },
    );

    test('reference image uses multipart without leaking api key', () async {
      final temp = await Directory.systemTemp.createTemp('universal-media-');
      addTearDown(() => temp.delete(recursive: true));
      final image = File('${temp.path}/reference.png')
        ..writeAsBytesSync([1, 2, 3]);
      final seen = Completer<String>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          seen.complete(body);
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'output': [
                  'data:video/mp4;base64,${base64Encode([4, 5, 6])}',
                ],
              }),
            );
          await request.response.close();
        }),
      );

      final asset =
          await UniversalMediaService(
            baseUrl: baseUrl,
            apiKey: 'secret-media-key',
          ).generateVideo(
            model: 'video-test',
            prompt: '让参考图中的车缓慢移动',
            referenceImagePath: image.path,
          );

      expect(asset.bytes, [4, 5, 6]);
      final body = await seen.future;
      expect(body, contains('name="image"'));
      expect(body, contains('reference.png'));
      expect(body, isNot(contains('secret-media-key')));
    });

    test('rejects a missing api key before network request', () async {
      final service = UniversalMediaService(baseUrl: baseUrl, apiKey: ' ');
      await expectLater(
        service.generateMusic(model: 'music-test', prompt: 'test'),
        throwsA(
          isA<UniversalMediaException>().having(
            (error) => error.message,
            'message',
            contains('API Key'),
          ),
        ),
      );
    });

    test(
      'returns pending job for 202 and polls OpenAI video shape to completion',
      () async {
        var pollCount = 0;
        final seenMethods = <String>[];
        server.listen((request) async {
          seenMethods.add(request.method);
          if (request.method == 'POST') {
            await request.drain();
            request.response
              ..statusCode = 202
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'id': 'video_123',
                  'object': 'video',
                  'status': 'queued',
                }),
              );
          } else if (request.uri.path == '/v1/videos/video_123') {
            pollCount++;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(
                pollCount == 1
                    ? {'id': 'video_123', 'status': 'in_progress'}
                    : {
                        'id': 'video_123',
                        'status': 'completed',
                        'video': {'url': '$baseUrl/content.mp4'},
                      },
              ),
            );
          } else if (request.uri.path == '/content.mp4') {
            request.response
              ..headers.contentType = ContentType('video', 'webm')
              ..add([0x1a, 0x45, 0xdf, 0xa3, 1, 2]);
          }
          await request.response.close();
        });

        final service = UniversalMediaService(
          baseUrl: baseUrl,
          apiKey: 'video-key',
        );
        final submitted = await service.submitVideo(
          model: 'sora-test',
          endpoint: '/v1/videos',
          endpointStyle: UniversalMediaEndpointStyle.openAiVideo,
          prompt: 'a slow camera move',
        );

        expect(submitted.job.status, UniversalMediaJobStatus.pending);
        expect(submitted.job.jobId, 'video_123');
        expect(
          submitted.job.pollUrl.toString(),
          '$baseUrl/v1/videos/video_123',
        );

        final completed = await service.waitForJob(
          submitted.job,
          pollingOptions: const UniversalMediaPollingOptions(
            maxAttempts: 3,
            deadline: Duration(seconds: 2),
            initialBackoff: Duration.zero,
          ),
        );
        expect(completed.job.status, UniversalMediaJobStatus.completed);
        expect(completed.asset?.bytes, [0x1a, 0x45, 0xdf, 0xa3, 1, 2]);
        expect(completed.asset?.mimeType, 'video/webm');
        expect(completed.asset?.extension, 'webm');
        expect(pollCount, 2);
        expect(seenMethods, ['POST', 'GET', 'GET', 'GET']);
      },
    );

    test('parses xAI request_id and constructs its poll URL', () {
      final submitUri = Uri.parse('https://api.x.ai/v1/videos/generations');
      final parsed = UniversalMediaResponseParser.parse(
        kind: UniversalMediaKind.video,
        statusCode: 202,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode({'request_id': 'req_456'})),
        submitUri: submitUri,
      );

      expect(parsed.status, UniversalMediaJobStatus.pending);
      expect(parsed.requestId, 'req_456');
      expect(parsed.identifier, 'req_456');
      expect(parsed.pollUrl, Uri.parse('https://api.x.ai/v1/videos/req_456'));
      expect(
        UniversalMediaEndpointBuilder.xAiRequestIdPollUrl(
          submitUri: submitUri,
          requestId: 'req_456',
        ),
        Uri.parse('https://api.x.ai/v1/videos/req_456'),
      );
      expect(parsed.cancelUrl, isNull);
    });

    test('downloads xAI file_output public_url after a done poll', () async {
      final methods = <String>[];
      server.listen((request) async {
        methods.add(request.method);
        if (request.method == 'POST') {
          await request.drain();
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'request_id': 'xai_public_1'}));
        } else if (request.method == 'GET' &&
            request.uri.path == '/v1/videos/xai_public_1') {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'status': 'done',
                'video': {
                  'file_output': {'public_url': '$baseUrl/generated.mp4'},
                },
              }),
            );
        } else if (request.method == 'GET' &&
            request.uri.path == '/generated.mp4') {
          request.response
            ..headers.contentType = ContentType('video', 'mp4')
            ..add([0, 0, 0, 1]);
        }
        await request.response.close();
      });

      final service = UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'xai-key',
      );
      final submitted = await service.submitVideo(
        model: 'grok-imagine-video',
        prompt: 'a paper boat crossing a puddle',
      );
      final completed = await service.waitForJob(
        submitted.job,
        pollingOptions: const UniversalMediaPollingOptions(
          maxAttempts: 1,
          deadline: Duration(seconds: 2),
          initialBackoff: Duration.zero,
        ),
      );
      expect(completed.job.status, UniversalMediaJobStatus.completed);
      expect(completed.asset?.bytes, [0, 0, 0, 1]);
      expect(completed.asset?.mimeType, 'video/mp4');
      expect(methods, ['POST', 'GET', 'GET']);
    });

    test(
      'xAI request_id cancellation is local when no cancel URL is supplied',
      () async {
        final methods = <String>[];
        server.listen((request) async {
          methods.add(request.method);
          if (request.method == 'POST') {
            await request.drain();
            request.response
              ..statusCode = 202
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'request_id': 'xai_cancel_1'}));
          } else if (request.method == 'DELETE') {
            request.response.statusCode = 500;
          }
          await request.response.close();
        });

        final service = UniversalMediaService(
          baseUrl: baseUrl,
          apiKey: 'xai-key',
        );
        final submitted = await service.submitVideo(
          model: 'grok-imagine-video',
          prompt: 'cancel without a provider endpoint',
        );
        expect(submitted.job.cancelUrl, isNull);

        final cancelled = await service.cancelJob(submitted.job);
        expect(cancelled.job.status, UniversalMediaJobStatus.cancelled);
        expect(methods, ['POST']);
      },
    );

    test('downloads the authenticated OpenAI video content endpoint', () async {
      final seenAuthorization = <String>[];
      server.listen((request) async {
        seenAuthorization.add(request.headers.value('authorization') ?? '');
        if (request.method == 'POST') {
          await request.drain();
          request.response
            ..statusCode = 202
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': 'video_content', 'status': 'queued'}));
        } else if (request.uri.path == '/v1/videos/video_content') {
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': 'video_content', 'status': 'completed'}));
        } else if (request.uri.path == '/v1/videos/video_content/content') {
          request.response
            ..headers.contentType = ContentType('video', 'mp4')
            ..add([0, 0, 0, 1]);
        }
        await request.response.close();
      });

      final service = UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'openai-video-key',
      );
      final result = await service.generateVideo(
        model: 'sora-test',
        endpoint: '/v1/videos',
        endpointStyle: UniversalMediaEndpointStyle.openAiVideo,
        prompt: 'official content endpoint',
        pollingOptions: const UniversalMediaPollingOptions(
          maxAttempts: 2,
          deadline: Duration(seconds: 2),
          initialBackoff: Duration.zero,
        ),
      );

      expect(result.bytes, [0, 0, 0, 1]);
      expect(result.mimeType, 'video/mp4');
      expect(seenAuthorization, [
        'Bearer openai-video-key',
        'Bearer openai-video-key',
        'Bearer openai-video-key',
      ]);
      expect(
        UniversalMediaEndpointBuilder.openAiVideoContentUrl(
          submitUri: Uri.parse('$baseUrl/v1/videos'),
          videoId: 'video_content',
        ).toString(),
        '$baseUrl/v1/videos/video_content/content',
      );
    });

    test(
      'does not forward the provider key to a cross-origin media URL',
      () async {
        final external = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => external.close(force: true));
        final externalAuthorization = <String>[];
        external.listen((request) async {
          externalAuthorization.add(
            request.headers.value('authorization') ?? '',
          );
          request.response
            ..headers.contentType = ContentType('image', 'png')
            ..add([0x89, 0x50, 0x4e, 0x47]);
          await request.response.close();
        });

        server.listen((request) async {
          await request.drain();
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'data': [
                  {'url': 'http://127.0.0.1:${external.port}/signed.png'},
                ],
              }),
            );
          await request.response.close();
        });

        final result = await UniversalMediaService(
          baseUrl: baseUrl,
          apiKey: 'must-not-leak',
        ).generateImage(prompt: 'cross origin signed image');

        expect(result.bytes, [0x89, 0x50, 0x4e, 0x47]);
        expect(externalAuthorization, ['']);
      },
    );

    test(
      'returns failed status without treating provider failure as missing media',
      () async {
        server.listen((request) async {
          await request.drain();
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'job_id': 'music_failed',
                'status': 'failed',
                'error': {'message': 'moderation rejected'},
              }),
            );
          await request.response.close();
        });

        final result = await UniversalMediaService(
          baseUrl: baseUrl,
          apiKey: 'music-key',
        ).submitMusic(model: 'music-test', prompt: 'a song');

        expect(result.job.status, UniversalMediaJobStatus.failed);
        expect(result.job.jobId, 'music_failed');
        expect(result.job.error, 'moderation rejected');
        expect(result.asset, isNull);
      },
    );

    test(
      'maps a server expired poll to expired without another request',
      () async {
        var pollCount = 0;
        server.listen((request) async {
          if (request.method == 'POST') {
            await request.drain();
            request.response
              ..statusCode = 202
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'job_id': 'expired_1', 'status': 'pending'}));
          } else {
            pollCount++;
            request.response
              ..statusCode = 410
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'expired', 'message': 'too late'}));
          }
          await request.response.close();
        });

        final service = UniversalMediaService(
          baseUrl: baseUrl,
          apiKey: 'video-key',
        );
        final submitted = await service.submitVideo(
          model: 'video-test',
          prompt: 'expire me',
        );
        final result = await service.waitForJob(
          submitted.job,
          pollingOptions: const UniversalMediaPollingOptions(
            maxAttempts: 4,
            deadline: Duration(seconds: 2),
            initialBackoff: Duration.zero,
          ),
        );

        expect(result.job.status, UniversalMediaJobStatus.expired);
        expect(result.job.error, 'too late');
        expect(pollCount, 1);
      },
    );

    test('cancel sends DELETE and never returns an asset', () async {
      final methods = <String>[];
      server.listen((request) async {
        methods.add(request.method);
        if (request.method == 'POST') {
          await request.drain();
          request.response
            ..statusCode = 202
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': 'cancel_1', 'status': 'queued'}));
        } else {
          request.response.statusCode = 204;
        }
        await request.response.close();
      });

      final service = UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'video-key',
      );
      final submitted = await service.submitVideo(
        model: 'video-test',
        endpoint: '/v1/videos',
        endpointStyle: UniversalMediaEndpointStyle.openAiVideo,
        prompt: 'cancel me',
      );
      final cancelled = await service.cancelJob(submitted.job);

      expect(cancelled.job.status, UniversalMediaJobStatus.cancelled);
      expect(cancelled.asset, isNull);
      expect(methods, ['POST', 'DELETE']);
    });

    test('enforces max attempts and does not poll forever', () async {
      var pollCount = 0;
      server.listen((request) async {
        if (request.method == 'POST') {
          await request.drain();
          request.response
            ..statusCode = 202
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': 'never_done', 'status': 'pending'}));
        } else {
          pollCount++;
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': 'never_done', 'status': 'pending'}));
        }
        await request.response.close();
      });

      final service = UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'video-key',
      );
      final submitted = await service.submitVideo(
        model: 'video-test',
        prompt: 'keep waiting',
      );
      final result = await service.waitForJob(
        submitted.job,
        pollingOptions: const UniversalMediaPollingOptions(
          maxAttempts: 2,
          deadline: Duration(seconds: 2),
          initialBackoff: Duration.zero,
        ),
      );

      expect(result.job.status, UniversalMediaJobStatus.expired);
      expect(result.job.error, '媒体任务轮询次数已达上限');
      expect(result.job.attempts, 2);
      expect(pollCount, 2);
    });

    test(
      'expires on deadline even when a poll response arrives late',
      () async {
        final adapter = _LatePendingAdapter(
          delay: const Duration(milliseconds: 40),
        );
        final service = UniversalMediaService(
          baseUrl: 'https://media.test',
          apiKey: 'deadline-key',
          adapter: adapter,
        );
        final submitted = await service.submitVideo(
          model: 'video-test',
          prompt: 'deadline test',
        );

        final result = await service.waitForJob(
          submitted.job,
          pollingOptions: const UniversalMediaPollingOptions(
            maxAttempts: 5,
            deadline: Duration(milliseconds: 5),
            initialBackoff: Duration.zero,
          ),
        );

        expect(result.job.status, UniversalMediaJobStatus.expired);
        expect(result.job.error, '媒体任务轮询超时');
        expect(adapter.pollCalls, 1);
        expect(result.asset, isNull);
      },
    );

    test(
      'propagates CancelToken through poll and suppresses half-success result',
      () async {
        final cancelToken = CancelToken();
        final updates = <UniversalMediaJobStatus>[];
        server.listen((request) async {
          if (request.method == 'POST') {
            await request.drain();
            request.response
              ..statusCode = 202
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'id': 'slow_1', 'status': 'pending'}));
          } else {
            await Future<void>.delayed(const Duration(seconds: 1));
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'id': 'slow_1',
                  'status': 'completed',
                  'data': [
                    {
                      'b64_json': base64Encode([7, 7, 7]),
                    },
                  ],
                }),
              );
          }
          await request.response.close();
        });

        final service = UniversalMediaService(
          baseUrl: baseUrl,
          apiKey: 'video-key',
          onJobUpdate: (job) => updates.add(job.status),
        );
        final submitted = await service.submitVideo(
          model: 'video-test',
          prompt: 'cancel during poll',
          cancelToken: cancelToken,
        );
        final pending = service.waitForJob(
          submitted.job,
          cancelToken: cancelToken,
          pollingOptions: const UniversalMediaPollingOptions(
            maxAttempts: 3,
            deadline: Duration(seconds: 5),
            initialBackoff: Duration.zero,
          ),
        );
        Future<void>.delayed(
          const Duration(milliseconds: 30),
          cancelToken.cancel,
        );

        await expectLater(
          pending,
          throwsA(isA<UniversalMediaCancelledException>()),
        );
        expect(updates, contains(UniversalMediaJobStatus.pending));
        expect(updates, contains(UniversalMediaJobStatus.cancelled));
      },
    );

    test('parses image URL and music data URI response shapes', () async {
      server.listen((request) async {
        if (request.method == 'POST' && request.uri.path.contains('images')) {
          await request.drain();
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'data': [
                  {'url': '$baseUrl/image.jpg'},
                ],
              }),
            );
        } else if (request.method == 'POST') {
          await request.drain();
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'output': [
                  'data:audio/ogg;base64,${base64Encode([1, 2, 3])}',
                ],
              }),
            );
        } else {
          request.response
            ..headers.contentType = ContentType('image', 'jpeg')
            ..add([0xff, 0xd8, 0xff, 0xd9]);
        }
        await request.response.close();
      });

      final service = UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'multi-key',
      );
      final image = await service.generateImage(prompt: 'a red flower');
      final music = await service.generateMusic(
        model: 'music-test',
        prompt: 'an ambient loop',
      );

      expect(image.mimeType, 'image/jpeg');
      expect(image.extension, 'jpg');
      expect(music.mimeType, 'audio/ogg');
      expect(music.extension, 'ogg');
    });

    test(
      'uses the OpenAI video multipart field and keeps generic image uploads compatible',
      () async {
        final temp = await Directory.systemTemp.createTemp('universal-media-');
        addTearDown(() => temp.delete(recursive: true));
        final image = File('${temp.path}/reference.png')
          ..writeAsBytesSync([1, 2, 3]);
        final seen = Completer<String>();
        String? contentType;
        server.listen((request) async {
          contentType = request.headers.value('content-type');
          final body = await utf8.decodeStream(request);
          seen.complete(body);
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': 'openai-video-1', 'status': 'queued'}));
          await request.response.close();
        });

        final result =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'openai-video-key',
            ).submitVideo(
              model: 'sora-2',
              endpoint: '/v1/videos',
              prompt: 'a paper boat',
              referenceImagePath: image.path,
            );

        final body = await seen.future;
        expect(result.job.status, UniversalMediaJobStatus.pending);
        expect(contentType, startsWith('multipart/form-data;'));
        expect(body, contains('name="model"'));
        expect(body, contains('name="prompt"'));
        expect(body, contains('name="input_reference"'));
        expect(body, isNot(contains('name="image"')));
        expect(body, isNot(contains('response_format')));
      },
    );

    test(
      'encodes a local xAI image-to-video reference as a data URL',
      () async {
        final temp = await Directory.systemTemp.createTemp('universal-media-');
        addTearDown(() => temp.delete(recursive: true));
        final image = File('${temp.path}/reference.jpg')
          ..writeAsBytesSync([0xff, 0xd8, 0xff]);
        final seen = Completer<Map<String, dynamic>>();
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          seen.complete(jsonDecode(body) as Map<String, dynamic>);
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'request_id': 'xai-image-video-1'}));
          await request.response.close();
        });

        final result =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'xai-video-key',
            ).submitVideo(
              model: 'grok-imagine-video',
              endpoint: '/v1/videos/generations',
              endpointStyle: UniversalMediaEndpointStyle.xAiRequestId,
              prompt: 'animate this still',
              referenceImagePath: image.path,
            );

        final body = await seen.future;
        final imageField = body['image'] as Map<String, dynamic>;
        expect(result.job.status, UniversalMediaJobStatus.pending);
        expect(imageField['url'], startsWith('data:image/jpeg;base64,'));
        expect(body['response_format'], isNull);
      },
    );

    test(
      'image edit uses the unified job path and the standard edits endpoint',
      () async {
        final temp = await Directory.systemTemp.createTemp('universal-media-');
        addTearDown(() => temp.delete(recursive: true));
        final image = File('${temp.path}/input.png')
          ..writeAsBytesSync([4, 5, 6]);
        final paths = <String>[];
        server.listen((request) async {
          paths.add(request.uri.path);
          await request.drain();
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'data': [
                  {
                    'b64_json': base64Encode([0x89, 0x50, 0x4e, 0x47]),
                    'output_format': 'png',
                  },
                ],
              }),
            );
          await request.response.close();
        });

        final result =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'image-edit-key',
            ).generateImageEdit(
              model: 'gpt-image-1',
              prompt: 'turn it into a sketch',
              referenceImagePath: image.path,
            );

        expect(paths, ['/v1/images/edits']);
        expect(result.bytes, [0x89, 0x50, 0x4e, 0x47]);
        expect(result.mimeType, 'image/png');
      },
    );

    test(
      'polls xAI video edits at /videos/request_id and reads file_output',
      () async {
        var pollCount = 0;
        server.listen((request) async {
          if (request.method == 'POST') {
            await request.drain();
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'request_id': 'xai-edit-1'}));
          } else if (request.uri.path == '/v1/videos/xai-edit-1') {
            pollCount++;
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'status': 'done',
                  'video': {
                    'file_output': {'public_url': '$baseUrl/generated.mp4'},
                  },
                  'progress': 100,
                }),
              );
          } else if (request.uri.path == '/generated.mp4') {
            request.response
              ..headers.contentType = ContentType('video', 'mp4')
              ..add([0, 0, 0, 1]);
          } else {
            request.response.statusCode = 404;
          }
          await request.response.close();
        });

        final result =
            await UniversalMediaService(
              baseUrl: baseUrl,
              apiKey: 'xai-video-key',
            ).generateVideo(
              model: 'grok-imagine-video',
              endpoint: '/v1/videos/edits',
              prompt: 'add snow',
              pollingOptions: const UniversalMediaPollingOptions(
                maxAttempts: 1,
                deadline: Duration(seconds: 1),
                initialBackoff: Duration.zero,
              ),
            );

        expect(result.bytes, [0, 0, 0, 1]);
        expect(result.mimeType, 'video/mp4');
        expect(pollCount, 1);
      },
    );

    test('does not accept media from an HTTP error envelope', () async {
      server.listen((request) async {
        await request.drain();
        request.response
          ..statusCode = 500
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'status': 'completed',
              'data': [
                {
                  'b64_json': base64Encode([1, 2, 3]),
                },
              ],
              'error': {'message': 'upstream failed'},
            }),
          );
        await request.response.close();
      });

      final result = await UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'error-key',
      ).submitImage(prompt: 'should fail');

      expect(result.job.status, UniversalMediaJobStatus.failed);
      expect(result.job.error, 'upstream failed');
      expect(result.asset, isNull);
    });

    test(
      'does not mark a job cancelled when the server rejects DELETE',
      () async {
        server.listen((request) async {
          if (request.method == 'POST') {
            await request.drain();
            request.response
              ..statusCode = 202
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({'id': 'cancel-rejected', 'status': 'queued'}),
              );
          } else {
            request.response
              ..statusCode = 500
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'error': {'message': 'cannot cancel'},
                }),
              );
          }
          await request.response.close();
        });

        final service = UniversalMediaService(
          baseUrl: baseUrl,
          apiKey: 'cancel-key',
        );
        final submitted = await service.submitVideo(
          model: 'sora-2',
          endpoint: '/v1/videos',
          prompt: 'keep running',
        );

        await expectLater(
          service.cancelJob(submitted.job),
          throwsA(
            isA<UniversalMediaException>().having(
              (error) => error.message,
              'message',
              allOf(contains('取消失败'), contains('cannot cancel')),
            ),
          ),
        );
      },
    );

    test('supports relative media URLs and non-base64 data URLs', () async {
      server.listen((request) async {
        if (request.method == 'POST') {
          await request.drain();
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'data': {'url': '/assets/cover.jpg'},
              }),
            );
        } else {
          request.response
            ..headers.contentType = ContentType('image', 'jpeg')
            ..add([0xff, 0xd8, 0xff, 0xd9]);
        }
        await request.response.close();
      });

      final result = await UniversalMediaService(
        baseUrl: '$baseUrl/api/v3',
        apiKey: 'relative-url-key',
      ).generateImage(prompt: 'relative URL');

      expect(result.bytes, [0xff, 0xd8, 0xff, 0xd9]);
      expect(result.mimeType, 'image/jpeg');

      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final data = body.contains('base64 field')
            ? <String, dynamic>{
                'data': {
                  'base64':
                      'data:image/png;base64,${base64Encode([0x89, 0x50, 0x4e, 0x47])}',
                },
              }
            : <String, dynamic>{
                'output': {'data': 'data:image/svg+xml,%3Csvg%2F%3E'},
              };
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(data));
        await request.response.close();
      });

      final dataUrl = await UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'data-url-key',
      ).generateImage(prompt: 'plain data URL');
      expect(dataUrl.mimeType, 'image/svg+xml');
      expect(dataUrl.extension, 'svg');
      expect(utf8.decode(dataUrl.bytes), '<svg/>');

      final base64DataUrl = await UniversalMediaService(
        baseUrl: baseUrl,
        apiKey: 'data-url-key',
      ).generateImage(prompt: 'base64 field');
      expect(base64DataUrl.bytes, [0x89, 0x50, 0x4e, 0x47]);
      expect(base64DataUrl.mimeType, 'image/png');
    });

    test('uses an HTTP Location header as the async poll URL', () {
      final parsed = UniversalMediaResponseParser.parse(
        kind: UniversalMediaKind.video,
        statusCode: 202,
        headers: const {
          'content-type': 'application/json',
          'location': '/v1/videos/location-job',
        },
        body: const <int>[],
        submitUri: Uri.parse('https://media.test/v1/videos'),
      );

      expect(parsed.status, UniversalMediaJobStatus.pending);
      expect(
        parsed.pollUrl,
        Uri.parse('https://media.test/v1/videos/location-job'),
      );
    });

    test('does not treat a 3xx JSON envelope as a successful media result', () {
      final parsed = UniversalMediaResponseParser.parse(
        kind: UniversalMediaKind.image,
        statusCode: 302,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(
          jsonEncode({
            'status': 'completed',
            'data': [
              {
                'b64Json': base64Encode([1, 2, 3]),
              },
            ],
          }),
        ),
        submitUri: Uri.parse('https://media.test/v1/images/generations'),
      );

      expect(parsed.status, UniversalMediaJobStatus.failed);
      expect(parsed.media?.isBase64, isTrue);
    });

    test(
      'caller cancellation wins over a non-cooperative poll adapter',
      () async {
        final cancelToken = CancelToken();
        final service = UniversalMediaService(
          baseUrl: 'https://media.test',
          apiKey: 'cancel-key',
          adapter: _NeverCompletesMediaAdapter(),
        );
        final submitted = await service.submitVideo(
          model: 'video-test',
          prompt: 'cancel a stuck adapter',
        );
        final stopwatch = Stopwatch()..start();
        final waiting = service.waitForJob(
          submitted.job,
          cancelToken: cancelToken,
          pollingOptions: const UniversalMediaPollingOptions(
            maxAttempts: 2,
            deadline: Duration(seconds: 1),
            initialBackoff: Duration.zero,
          ),
        );
        Future<void>.delayed(
          const Duration(milliseconds: 20),
          cancelToken.cancel,
        );

        await expectLater(
          waiting,
          throwsA(isA<UniversalMediaCancelledException>()),
        );
        stopwatch.stop();
        expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
      },
    );

    test(
      'returns an expired job when a custom poll adapter exceeds the deadline',
      () async {
        final service = UniversalMediaService(
          baseUrl: 'https://media.test',
          apiKey: 'deadline-key',
          adapter: _NeverCompletesMediaAdapter(),
        );
        final submitted = await service.submitVideo(
          model: 'video-test',
          prompt: 'deadline test',
        );
        final stopwatch = Stopwatch()..start();
        final result = await service.waitForJob(
          submitted.job,
          pollingOptions: const UniversalMediaPollingOptions(
            maxAttempts: 2,
            deadline: Duration(milliseconds: 15),
            initialBackoff: Duration.zero,
          ),
        );
        stopwatch.stop();

        expect(result.job.status, UniversalMediaJobStatus.expired);
        expect(result.job.error, '媒体任务轮询超时');
        expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
      },
    );
  });
}

class _LatePendingAdapter implements UniversalMediaAdapter {
  _LatePendingAdapter({required this.delay});

  final Duration delay;
  int pollCalls = 0;

  UniversalMediaHttpResponse _pending(String id) {
    return UniversalMediaHttpResponse(
      statusCode: 202,
      requestUri: Uri.parse('https://media.test/v1/videos/$id'),
      headers: const {'content-type': 'application/json'},
      bytes: utf8.encode(jsonEncode({'id': id, 'status': 'pending'})),
    );
  }

  @override
  Future<UniversalMediaHttpResponse> submit(
    UniversalMediaSubmitRequest request,
  ) async => _pending('deadline_job');

  @override
  Future<UniversalMediaHttpResponse> poll(
    UniversalMediaPollRequest request,
  ) async {
    pollCalls++;
    await Future<void>.delayed(delay);
    return _pending(request.job.providerId);
  }

  @override
  Future<UniversalMediaHttpResponse> cancel(
    UniversalMediaCancelRequest request,
  ) async => UniversalMediaHttpResponse(
    statusCode: 204,
    requestUri: request.job.pollUrl!,
    bytes: const <int>[],
  );
}

class _NeverCompletesMediaAdapter implements UniversalMediaAdapter {
  @override
  Future<UniversalMediaHttpResponse> submit(
    UniversalMediaSubmitRequest request,
  ) async => UniversalMediaHttpResponse(
    statusCode: 202,
    requestUri: Uri.parse('https://media.test/v1/videos/deadline-job'),
    headers: const {'content-type': 'application/json'},
    bytes: utf8.encode(jsonEncode({'id': 'deadline-job', 'status': 'pending'})),
  );

  @override
  Future<UniversalMediaHttpResponse> poll(UniversalMediaPollRequest request) =>
      Completer<UniversalMediaHttpResponse>().future;

  @override
  Future<UniversalMediaHttpResponse> cancel(
    UniversalMediaCancelRequest request,
  ) async => UniversalMediaHttpResponse(
    statusCode: 204,
    requestUri: request.job.pollUrl ?? request.baseUri,
    bytes: const <int>[],
  );
}
