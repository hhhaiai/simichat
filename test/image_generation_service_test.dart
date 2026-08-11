import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/image_generation_service.dart';
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
