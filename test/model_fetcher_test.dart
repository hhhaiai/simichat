import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/ai/model_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelFetcher capability discovery', () {
    test('paginates Gemini and filters non-generation models', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seenPageTokens = <String?>[];
      unawaited(
        server.forEach((request) async {
          expect(request.uri.path, '/v1beta/models');
          seenPageTokens.add(request.uri.queryParameters['pageToken']);
          final isSecondPage =
              request.uri.queryParameters['pageToken'] == 'next';
          final body = isSecondPage
              ? {
                  'models': [
                    {
                      'name': 'models/gemini-next',
                      'supportedGenerationMethods': ['generateContent'],
                    },
                  ],
                }
              : {
                  'models': [
                    {
                      'name': 'models/gemini-chat',
                      'supportedGenerationMethods': [
                        'generateContent',
                        'streamGenerateContent',
                      ],
                    },
                    {
                      'name': 'models/text-embedding-004',
                      'supportedGenerationMethods': ['embedContent'],
                    },
                    {'name': 'models/missing-methods'},
                    {
                      'name': 'models/gemini-tts',
                      'supportedGenerationMethods': ['generateContent'],
                    },
                  ],
                  'nextPageToken': 'next',
                };
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(body));
          await request.response.close();
        }),
      );

      final models = await ModelFetcher.fetchGeminiModelInfos(
        baseUrl: 'http://${server.address.host}:${server.port}',
        apiKey: 'gemini-key',
        pageSize: 2,
      );

      expect(seenPageTokens, [null, 'next']);
      expect(models.map((model) => model.id), [
        'gemini-chat',
        'gemini-next',
        'gemini-tts',
      ]);
      expect(models.every((model) => model.id != 'text-embedding-004'), isTrue);
      final tts = models.firstWhere((model) => model.id == 'gemini-tts');
      expect(tts.capability, ModelCapability.chat);
      expect(tts.supports(ModelCapability.audio), isFalse);
      expect(tts.supports(ModelCapability.vision), isFalse);
    });

    test(
      'reads Ollama /api/show capabilities and stays conservative',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) async {
            if (request.method == 'GET' && request.uri.path == '/api/tags') {
              request.response
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'models': [
                      {'name': 'vision-model'},
                      {'name': 'video-model'},
                      {'name': 'unknown-video-name'},
                    ],
                  }),
                );
            } else if (request.method == 'POST' &&
                request.uri.path == '/api/show') {
              final body = jsonDecode(await utf8.decodeStream(request)) as Map;
              final name = body['name']?.toString();
              final capabilities = switch (name) {
                'vision-model' => ['completion', 'vision'],
                'video-model' => ['completion', 'video'],
                _ => ['completion'],
              };
              request.response
                ..headers.contentType = ContentType.json
                ..write(jsonEncode({'capabilities': capabilities}));
            }
            await request.response.close();
          }),
        );

        final models = await ModelFetcher.fetchOllamaModelInfos(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        final vision = models.firstWhere((model) => model.id == 'vision-model');
        final video = models.firstWhere((model) => model.id == 'video-model');
        final unknown = models.firstWhere(
          (model) => model.id == 'unknown-video-name',
        );

        expect(vision.capabilities, contains(ModelCapability.vision));
        expect(video.supports(ModelCapability.video), isTrue);
        expect(
          unknown.supports(ModelCapability.video),
          isFalse,
          reason: '模型名不能替代 /api/show 能力证据',
        );
        expect(unknown.supports(ModelCapability.music), isFalse);
      },
    );

    test(
      'uses a configured OpenAI-compatible prefix for model fetch',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) async {
            expect(request.uri.path, '/v2/models');
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'data': [
                    {
                      'id': 'explicit-video-model',
                      'capabilities': ['chat', 'video'],
                    },
                  ],
                }),
              );
            await request.response.close();
          }),
        );

        final models = await ModelFetcher.fetchOpenAIModelInfos(
          baseUrl: 'http://${server.address.host}:${server.port}/v2',
          apiKey: 'openai-key',
        );

        expect(models.single.id, 'explicit-video-model');
        expect(models.single.supports(ModelCapability.video), isTrue);
      },
    );

    test(
      'keeps Ollama name-only media models at conservative chat fallback',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) async {
            if (request.method == 'GET' && request.uri.path == '/api/tags') {
              request.response
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'models': [
                      {'name': 'llava'},
                      {'name': 'musicgen'},
                      {'name': 'grok-voice'},
                    ],
                  }),
                );
            } else {
              request.response.statusCode = HttpStatus.notFound;
            }
            await request.response.close();
          }),
        );

        final models = await ModelFetcher.fetchOllamaModelInfos(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );

        expect(models.map((model) => model.id), [
          'grok-voice',
          'llava',
          'musicgen',
        ]);
        expect(
          models.every((model) => model.capability == ModelCapability.chat),
          isTrue,
        );
        expect(
          models.every((model) => !model.supports(ModelCapability.audio)),
          isTrue,
        );
        expect(
          models.every((model) => !model.supports(ModelCapability.video)),
          isTrue,
        );
        expect(
          models.every((model) => !model.supports(ModelCapability.music)),
          isTrue,
        );
      },
    );

    test(
      'ignores malformed OpenAI model rows and infers xAI media names',
      () {
        final models = ModelFetcher.parseOpenAIModels({
          'data': [
            null,
            {'id': ' grok-imagine-video '},
            {'id': 'grok-imagine-video'},
            {'id': ' '},
            {'id': 42},
            {
              'id': 'explicit-video',
              'capabilities': ['chat', 'video'],
            },
          ],
        });

        expect(models.map((model) => model.id), [
          'explicit-video',
          'grok-imagine-video',
        ]);
        final xai = models.firstWhere(
          (model) => model.id == 'grok-imagine-video',
        );
        // 名称命中 grok-imagine-video 前缀表 → 目录能力为 video。
        expect(xai.capability, ModelCapability.video);
        expect(xai.supports(ModelCapability.video), isTrue);
        expect(
          models
              .firstWhere((model) => model.id == 'explicit-video')
              .supports(ModelCapability.video),
          isTrue,
        );
      },
    );

    test('sanitizes credential-shaped model discovery errors', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      const secret = 'super-secret-model-fetch-key';
      unawaited(
        server.forEach((request) async {
          request.response
            ..statusCode = 418
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'error': {'message': 'Bearer $secret token=$secret'},
              }),
            );
          await request.response.close();
        }),
      );

      await expectLater(
        ModelFetcher.fetchOpenAIModelInfos(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: secret,
        ),
        throwsA(
          predicate(
            (error) =>
                !error.toString().contains(secret) &&
                error.toString().contains('Bearer ***'),
          ),
        ),
      );
    });

    test(
      'normalizes protocol aliases for conservative Claude discovery',
      () async {
        final models = await ModelFetcher.fetchModelInfos(
          protocol: '  CLAUDE  ',
          baseUrl: 'https://api.anthropic.com',
          apiKey: 'claude-key',
        );

        expect(models, isNotEmpty);
        expect(
          models.every((model) => model.capability == ModelCapability.vision),
          isTrue,
        );
        expect(
          models.every((model) => model.supports(ModelCapability.vision)),
          isTrue,
        );
        expect(
          models.every((model) => !model.supports(ModelCapability.video)),
          isTrue,
        );
        expect(
          models.every((model) => !model.supports(ModelCapability.music)),
          isTrue,
        );
      },
    );
  });
}
