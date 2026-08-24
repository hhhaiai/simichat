import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/image_generation_service.dart';
import 'package:ai_chat_app/core/media/media_provider_profile.dart';
import 'package:ai_chat_app/core/media/media_request_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageGenerationService', () {
    late HttpServer server;
    late String baseUrl;
    final requests = <HttpRequest>[];
    Map<String, dynamic>? lastRequestBody;

    setUp(() async {
      requests.clear();
      lastRequestBody = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    void serveImageEndpoint({
      required Map<String, dynamic> Function(HttpRequest) responder,
    }) {
      server.listen((request) async {
        requests.add(request);
        final bodyBytes = await request.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        );
        if (bodyBytes.isNotEmpty) {
          lastRequestBody =
              jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
        }
        final body = responder(request);
        request.response
          ..statusCode = (body['status'] as int?) ?? 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body['payload'] ?? {}));
        await request.response.close();
      });
    }

    test('returns image bytes from b64_json response', () async {
      const pngBytes = [1, 2, 3, 4, 5];
      serveImageEndpoint(
        responder: (_) => {
          'payload': {
            'created': 1234,
            'data': [
              {'b64_json': base64Encode(pngBytes)},
            ],
          },
        },
      );

      final service = ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: 'sk-test',
        model: 'dall-e-3',
      );
      final image = await service.generate('一只在月球上的猫');

      expect(image.bytes, [1, 2, 3, 4, 5]);
      expect(requests.single.uri.path, '/v1/images/generations');
      expect(requests.single.headers.value('Authorization'), 'Bearer sk-test');

      expect(lastRequestBody?['model'], 'dall-e-3');
      expect(lastRequestBody?['prompt'], '一只在月球上的猫');
      expect(lastRequestBody?['response_format'], 'b64_json');
    });

    test(
      'typed image options preserve model and per-request fields on the wire',
      () async {
        serveImageEndpoint(
          responder: (_) => {
            'payload': {
              'data': [
                {
                  'b64_json': base64Encode([9, 8, 7]),
                },
              ],
            },
          },
        );

        final image =
            await ImageGenerationService(
              baseUrl: baseUrl,
              apiKey: 'sk-test',
              model: 'gpt-image-2',
            ).generateWithOptions(
              const ImageGenerationOptions(
                model: 'gpt-image-2',
                prompt: '森林小屋',
                count: 4,
                aspectRatio: '16:9',
                resolution: '2K',
                size: '1536x1024',
                quality: 'high',
              ),
              profile: MediaRequestProviderProfile.openAiImageGeneration,
            );

        expect(image.single.bytes, [9, 8, 7]);
        expect(lastRequestBody?['model'], 'gpt-image-2');
        expect(lastRequestBody?['n'], 4);
        expect(lastRequestBody?['aspect_ratio'], '16:9');
        expect(lastRequestBody?['resolution'], '2K');
        expect(lastRequestBody?['size'], '1536x1024');
        expect(lastRequestBody?['quality'], 'high');
      },
    );

    test('typed automatic image options omit advanced wire fields', () async {
      serveImageEndpoint(
        responder: (_) => {
          'payload': {
            'data': [
              {
                'b64_json': base64Encode([5, 4, 3]),
              },
            ],
          },
        },
      );

      await ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: 'sk-test',
        model: 'gpt-image-2',
      ).generateWithOptions(
        const ImageGenerationOptions(model: 'gpt-image-2', prompt: '使用服务端默认参数'),
        profile: MediaRequestProviderProfile.openAiImageGeneration,
      );

      expect(lastRequestBody, isNot(contains('aspect_ratio')));
      expect(lastRequestBody, isNot(contains('resolution')));
      expect(lastRequestBody, isNot(contains('size')));
      expect(lastRequestBody, isNot(contains('quality')));
      expect(lastRequestBody?['n'], 1);
    });

    test(
      'Grok typed image parameters keep provider-specific wire names',
      () async {
        serveImageEndpoint(
          responder: (_) => {
            'payload': {
              'data': [
                {
                  'b64_json': base64Encode([4, 2, 4, 2]),
                },
              ],
            },
          },
        );

        await ImageGenerationService(
          baseUrl: baseUrl,
          apiKey: 'sk-test',
          model: 'grok-imagine-image-lite',
        ).generateWithOptions(
          const ImageGenerationOptions(
            model: 'grok-imagine-image-lite',
            prompt: 'wide studio',
            count: 2,
            aspectRatio: '16:9',
            resolution: '2K',
            quality: 'high',
          ),
          profile: MediaRequestProviderProfile.xAiGrokImage,
        );

        expect(lastRequestBody?['model'], 'grok-imagine-image-lite');
        expect(lastRequestBody?['n'], 2);
        expect(lastRequestBody?['aspect_ratio'], '16:9');
        expect(lastRequestBody?['resolution'], '2K');
        expect(lastRequestBody?['quality'], 'high');
        expect(lastRequestBody, isNot(contains('size')));
        expect(lastRequestBody?['response_format'], 'url');
      },
    );

    test(
      'resolves image generation through a configured /api/v3 prefix',
      () async {
        serveImageEndpoint(
          responder: (request) {
            expect(request.uri.path, '/api/v3/images/generations');
            return {
              'payload': {
                'data': [
                  {
                    'b64_json': base64Encode([6, 7, 8]),
                  },
                ],
              },
            };
          },
        );

        final image = await ImageGenerationService(
          baseUrl: '$baseUrl/api/v3',
          apiKey: 'sk-test',
          model: 'dall-e-3',
        ).generate('prefix image');

        expect(image.bytes, [6, 7, 8]);
      },
    );

    test('rejects missing api key before calling upstream', () async {
      final service = ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: '  ',
        model: 'dall-e-3',
      );
      await expectLater(
        service.generate('prompt'),
        throwsA(
          isA<ImageGenerationException>().having(
            (e) => e.message,
            'message',
            contains('API Key'),
          ),
        ),
      );
    });

    test('rejects empty prompt before calling upstream', () async {
      final service = ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: 'sk-test',
        model: 'dall-e-3',
      );
      await expectLater(
        service.generate('   '),
        throwsA(
          isA<ImageGenerationException>().having(
            (e) => e.message,
            'message',
            contains('图片描述'),
          ),
        ),
      );
    });

    test('throws friendly error on 401', () async {
      serveImageEndpoint(
        responder: (_) => {
          'status': 401,
          'payload': {
            'error': {'message': 'invalid api key'},
          },
        },
      );
      final service = ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: 'sk-bad',
        model: 'dall-e-3',
      );
      await expectLater(
        service.generate('prompt'),
        throwsA(
          isA<ImageGenerationException>().having(
            (e) => e.message,
            'message',
            contains('API Key'),
          ),
        ),
      );
    });

    test('reports an unsupported generation endpoint on 404', () async {
      serveImageEndpoint(
        responder: (_) => {
          'status': 404,
          'payload': {
            'error': {'message': 'not found'},
          },
        },
      );
      final service = ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: 'sk-test',
        model: 'dall-e-3',
      );

      await expectLater(
        service.generate('prompt'),
        throwsA(
          isA<ImageGenerationException>().having(
            (error) => error.message,
            'message',
            contains('当前渠道不支持图片生成接口'),
          ),
        ),
      );
    });

    test('downloads remote url when b64_json absent', () async {
      // 第一个请求返回 url，第二个请求返回图片字节。
      server.listen((request) async {
        requests.add(request);
        if (request.uri.path == '/v1/images/generations') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'created': 1,
                'data': [
                  {'url': '$baseUrl/raw-image.png'},
                ],
              }),
            );
        } else {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.binary
            ..add([9, 8, 7]);
        }
        await request.response.close();
      });

      final service = ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: 'sk-test',
        model: 'dall-e-3',
      );
      final image = await service.generate('prompt');
      expect(image.bytes, [9, 8, 7]);
    });

    test(
      'preserves image MIME and extension from an OpenAI-compatible response',
      () async {
        serveImageEndpoint(
          responder: (_) => {
            'payload': {
              'data': [
                {
                  'b64_json': base64Encode([0xff, 0xd8, 0xff, 0xd9]),
                  'output_format': 'jpeg',
                },
              ],
            },
          },
        );

        final image = await ImageGenerationService(
          baseUrl: baseUrl,
          apiKey: 'sk-test',
          model: 'dall-e-3',
        ).generate('jpeg image');

        expect(image.mimeType, 'image/jpeg');
        expect(image.extension, 'jpg');
      },
    );

    test(
      'uses gpt-image output_format without legacy response_format',
      () async {
        serveImageEndpoint(
          responder: (_) => {
            'payload': {
              'data': [
                {
                  'b64_json': base64Encode([1, 2, 3]),
                },
              ],
            },
          },
        );

        final image =
            await ImageGenerationService(
              baseUrl: baseUrl,
              apiKey: 'sk-test',
              model: 'gpt-image-1',
            ).generate(
              'gpt image',
              extra: const <String, dynamic>{'output_format': 'webp'},
            );

        expect(lastRequestBody?['output_format'], 'webp');
        expect(lastRequestBody?.containsKey('response_format'), isFalse);
        expect(image.bytes, [1, 2, 3]);
        expect(image.mimeType, 'image/webp');
        expect(image.extension, 'webp');
      },
    );

    test('accepts a data URL returned in the image url field', () async {
      const webpBytes = [
        0x52,
        0x49,
        0x46,
        0x46,
        0x00,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ];
      serveImageEndpoint(
        responder: (_) => {
          'payload': {
            'data': [
              {'url': 'data:image/webp;base64,${base64Encode(webpBytes)}'},
            ],
          },
        },
      );

      final image = await ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: 'sk-test',
        model: 'gpt-image-1',
      ).generate('webp image');

      expect(image.bytes, webpBytes);
      expect(image.mimeType, 'image/webp');
      expect(image.extension, 'webp');
    });

    test('uses the downloaded image MIME instead of assuming PNG', () async {
      const webpBytes = [
        0x52,
        0x49,
        0x46,
        0x46,
        0x00,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ];
      server.listen((request) async {
        if (request.uri.path == '/v1/images/generations') {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'data': [
                  {'url': '$baseUrl/generated.webp'},
                ],
              }),
            );
        } else {
          request.response
            ..headers.contentType = ContentType('image', 'webp')
            ..add(webpBytes);
        }
        await request.response.close();
      });

      final image = await ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: 'sk-test',
        model: 'dall-e-3',
      ).generate('remote webp');

      expect(image.mimeType, 'image/webp');
      expect(image.extension, 'webp');
    });

    test(
      'uses the remote image extension when the download MIME is generic',
      () async {
        server.listen((request) async {
          if (request.uri.path == '/v1/images/generations') {
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'data': [
                    {'url': '$baseUrl/generated.webp'},
                  ],
                }),
              );
          } else {
            request.response
              ..headers.contentType = ContentType.binary
              ..add([1, 2, 3]);
          }
          await request.response.close();
        });

        final image = await ImageGenerationService(
          baseUrl: baseUrl,
          apiKey: 'sk-test',
          model: 'dall-e-3',
        ).generate('generic MIME webp');

        expect(image.bytes, [1, 2, 3]);
        expect(image.mimeType, 'image/webp');
        expect(image.extension, 'webp');
      },
    );

    test('rejects non-http base url', () {
      expect(
        () => normalizeImageGenerationBaseUrl('file:///tmp/x'),
        throwsA(isA<ImageGenerationException>()),
      );
      expect(
        normalizeImageGenerationBaseUrl('https://api.dwchainless.com/v1'),
        'https://api.dwchainless.com',
      );
    });

    test('rejects malformed response payload', () async {
      serveImageEndpoint(
        responder: (_) => {
          'payload': {'created': 1, 'data': <Object>[]},
        },
      );
      final service = ImageGenerationService(
        baseUrl: baseUrl,
        apiKey: 'sk-test',
        model: 'dall-e-3',
      );
      await expectLater(
        service.generate('prompt'),
        throwsA(isA<ImageGenerationException>()),
      );
    });

    test('edit posts multipart /v1/images/edits and returns bytes', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = Completer<String>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          expect(request.method, 'POST');
          expect(request.uri.path, '/v1/images/edits');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer image-test-key',
          );
          expect(body, contains('name="model"'));
          expect(body, contains('gpt-image-2'));
          expect(body, contains('name="prompt"'));
          expect(body, contains('改成赛博朋克夜景'));
          expect(body, contains('name="image"'));
          expect(body, contains('filename="input.png"'));
          expect(body, contains('name="size"'));
          expect(body, contains('1024x1024'));
          seen.complete(body);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {
                  'b64_json': base64Encode([0x89, 0x50, 0x4E, 0x47]),
                },
              ],
            }),
          );
          await request.response.close();
        }),
      );

      final tempDir = await Directory.systemTemp.createTemp('image-edit-');
      addTearDown(() => tempDir.delete(recursive: true));
      final image = File('${tempDir.path}/input.png');
      await image.writeAsBytes([0, 1, 2, 3]);

      final service = ImageGenerationService(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'image-test-key',
        model: 'gpt-image-2',
      );
      final result = await service.edit(
        imagePath: image.path,
        prompt: '改成赛博朋克夜景',
      );
      expect(result.bytes, [0x89, 0x50, 0x4E, 0x47]);
      expect(await seen.future, isNot(contains('image-test-key')));
    });

    test(
      'generate with a reference image reuses the multipart edit endpoint',
      () async {
        final referenceServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => referenceServer.close(force: true));
        final seen = Completer<String>();
        unawaited(
          referenceServer.forEach((request) async {
            final body = await utf8.decodeStream(request);
            expect(request.uri.path, '/v1/images/edits');
            expect(body, contains('name="image"'));
            expect(body, contains('filename="reference.png"'));
            expect(body, contains('name="prompt"'));
            expect(body, contains('参考图变成水彩'));
            expect(body, isNot(contains('reference-server-secret')));
            seen.complete(body);
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'data': [
                  {
                    'b64_json': base64Encode([5, 6, 7]),
                  },
                ],
              }),
            );
            await request.response.close();
          }),
        );

        final tempDir = await Directory.systemTemp.createTemp(
          'image-reference-generation-',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final image = File('${tempDir.path}/reference.png')
          ..writeAsBytesSync([0, 1, 2]);
        final service = ImageGenerationService(
          baseUrl:
              'http://${referenceServer.address.host}:${referenceServer.port}/v1',
          apiKey: 'reference-server-secret',
          model: 'gpt-image-2',
        );

        final result = await service.generate(
          '参考图变成水彩',
          referenceImagePath: image.path,
        );

        expect(result.bytes, [5, 6, 7]);
        expect(await seen.future, isNotEmpty);
      },
    );

    test(
      'keeps requested count and every reference image at the multipart boundary',
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
                      'b64_json': base64Encode([1, 2, 3]),
                    },
                    {
                      'b64_json': base64Encode([4, 5, 6]),
                    },
                  ],
                }),
              );
            await request.response.close();
          }),
        );
        final tempDir = await Directory.systemTemp.createTemp('image-many-');
        addTearDown(() => tempDir.delete(recursive: true));
        final first = File('${tempDir.path}/first.png')
          ..writeAsBytesSync([1, 2]);
        final second = File('${tempDir.path}/second.png')
          ..writeAsBytesSync([3, 4]);

        final results =
            await ImageGenerationService(
              baseUrl: baseUrl,
              apiKey: 'image-test-key',
              model: 'gpt-image-2',
            ).generateAll(
              'two references',
              count: 2,
              referenceImagePaths: [first.path, second.path],
            );

        final body = await seen.future;
        expect(results.map((image) => image.bytes), [
          [1, 2, 3],
          [4, 5, 6],
        ]);
        expect(body, contains('name="n"'));
        expect(body, contains('\r\n2\r\n'));
        expect(body, contains('filename="first.png"'));
        expect(body, contains('filename="second.png"'));
      },
    );

    test('edit rejects missing or empty reference image', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final service = ImageGenerationService(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'image-test-key',
        model: 'gpt-image-2',
      );
      await expectLater(
        service.edit(imagePath: '/nonexistent/input.png', prompt: '编辑一下'),
        throwsA(isA<ImageGenerationException>()),
      );
    });

    test('reports an unsupported edit endpoint on 405', () async {
      final editServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => editServer.close(force: true));
      unawaited(
        editServer.forEach((request) async {
          await request.drain<void>();
          request.response
            ..statusCode = 405
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'error': 'method not allowed'}));
          await request.response.close();
        }),
      );
      final tempDir = await Directory.systemTemp.createTemp(
        'image-edit-unsupported-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final image = File('${tempDir.path}/input.png');
      await image.writeAsBytes([0, 1, 2, 3]);
      final service = ImageGenerationService(
        baseUrl: 'http://${editServer.address.host}:${editServer.port}',
        apiKey: 'image-test-key',
        model: 'gpt-image-2',
      );

      await expectLater(
        service.edit(imagePath: image.path, prompt: '编辑一下'),
        throwsA(
          isA<ImageGenerationException>().having(
            (error) => error.message,
            'message',
            contains('当前渠道不支持图片编辑接口'),
          ),
        ),
      );
    });
  });
}
