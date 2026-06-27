import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/media/openai_text_to_speech_engine.dart';
import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenAiCompatibleTextToSpeechEngine', () {
    test('posts OpenAI-compatible speech request and returns bytes', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = Completer<String>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          expect(request.method, 'POST');
          expect(request.uri.path, '/v1/audio/speech');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer tts-test-key',
          );
          expect(request.headers.contentType?.mimeType, 'application/json');
          final payload = jsonDecode(body) as Map<String, dynamic>;
          expect(payload['model'], 'tts-1');
          expect(payload['voice'], 'alloy');
          expect(payload['input'], '你好 SimiChat');
          expect(payload['response_format'], 'mp3');
          seen.complete(body);
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.add([0x49, 0x44, 0x33, 0x01]);
          await request.response.close();
        }),
      );

      final engine = OpenAiCompatibleTextToSpeechEngine(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'tts-test-key',
      );

      final bytes = await engine.synthesize(
        const TextToSpeechInput(text: '  你好   SimiChat ', voice: 'alloy'),
      );

      expect(bytes, [0x49, 0x44, 0x33, 0x01]);
      expect(await seen.future, isNot(contains('tts-test-key')));
    });

    test('sanitizes provider failure body, key and local path', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          await request.drain<void>();
          request.response.statusCode = 500;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'error': {
                'message': 'failed for sk-live-secret and /private/tmp/tts.mp3',
              },
            }),
          );
          await request.response.close();
        }),
      );

      final engine = OpenAiCompatibleTextToSpeechEngine(
        baseUrl: 'http://${server.address.host}:${server.port}',
        apiKey: 'tts-test-key',
      );

      await expectLater(
        engine.synthesize(
          const TextToSpeechInput(text: 'hello', voice: 'alloy'),
        ),
        throwsA(
          isA<TextToSpeechException>()
              .having((e) => e.message, 'message', contains('HTTP 500'))
              .having(
                (e) => e.message,
                'no api key',
                isNot(contains('sk-live-secret')),
              )
              .having(
                (e) => e.message,
                'no local path',
                isNot(contains('/private/tmp/tts.mp3')),
              ),
        ),
      );
    });

    test('rejects non-http base url before network request', () async {
      final engine = OpenAiCompatibleTextToSpeechEngine(
        baseUrl: 'file:///tmp/tts',
        apiKey: 'tts-test-key',
      );

      await expectLater(
        engine.synthesize(
          const TextToSpeechInput(text: 'hello', voice: 'alloy'),
        ),
        throwsA(
          isA<TextToSpeechException>().having(
            (e) => e.message,
            'message',
            contains('TTS Base URL'),
          ),
        ),
      );
    });

    test('maps 401 without exposing the configured key', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          await request.drain<void>();
          request.response.statusCode = 401;
          await request.response.close();
        }),
      );

      final engine = OpenAiCompatibleTextToSpeechEngine(
        baseUrl: 'http://${server.address.host}:${server.port}',
        apiKey: 'tts-test-key',
      );

      await expectLater(
        engine.synthesize(
          const TextToSpeechInput(text: 'hello', voice: 'alloy'),
        ),
        throwsA(
          isA<TextToSpeechException>()
              .having((e) => e.message, 'message', contains('API Key 无效'))
              .having(
                (e) => e.message,
                'no configured key',
                isNot(contains('tts-test-key')),
              ),
        ),
      );
    });
  });
}
