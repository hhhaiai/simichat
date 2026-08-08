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
  });
}
