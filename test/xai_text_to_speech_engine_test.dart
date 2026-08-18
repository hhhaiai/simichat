import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:ai_chat_app/core/media/xai_speech_provider_profile.dart';
import 'package:ai_chat_app/core/media/xai_text_to_speech_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XaiTextToSpeechEngine', () {
    test('uses /v1/tts JSON contract and returns raw audio bytes', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen =
          Completer<({String path, String body, String authorization})>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          seen.complete((
            path: request.uri.path,
            body: body,
            authorization:
                request.headers.value(HttpHeaders.authorizationHeader) ?? '',
          ));
          request.response
            ..headers.contentType = ContentType('audio', 'mpeg')
            ..add([0x49, 0x44, 0x33, 0x01]);
          await request.response.close();
        }),
      );

      final engine = XaiTextToSpeechEngine(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'xai-test-key',
      );
      final bytes = await engine.synthesize(
        const TextToSpeechInput(text: '  你好 xAI  ', voice: 'eve'),
      );

      expect(bytes, [0x49, 0x44, 0x33, 0x01]);
      final request = await seen.future;
      expect(request.path, '/v1/tts');
      expect(request.authorization, 'Bearer xai-test-key');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload, {
        'text': '你好 xAI',
        'voice_id': 'eve',
        'language': 'auto',
      });
      expect(payload.containsKey('model'), isFalse);
      expect(payload.containsKey('input'), isFalse);
      expect(payload.containsKey('voice'), isFalse);
      expect(payload.containsKey('response_format'), isFalse);
    });

    test(
      'serializes xAI speed and output format without OpenAI fields',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final seen = Completer<Map<String, dynamic>>();
        unawaited(
          server.forEach((request) async {
            final payload = jsonDecode(await utf8.decodeStream(request));
            seen.complete((payload as Map).cast<String, dynamic>());
            request.response
              ..headers.contentType = ContentType('audio', 'wav')
              ..add([0x52, 0x49, 0x46, 0x46]);
            await request.response.close();
          }),
        );

        final engine = XaiTextToSpeechEngine(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'xai-test-key',
          language: 'zh',
          speed: '1.2',
          responseFormat: 'wav',
        );
        expect(
          await engine.synthesize(
            const TextToSpeechInput(text: '可配置参数', voice: 'eve'),
          ),
          [0x52, 0x49, 0x46, 0x46],
        );

        final payload = await seen.future;
        expect(payload['text'], '可配置参数');
        expect(payload['voice_id'], 'eve');
        expect(payload['language'], 'zh');
        expect(payload['speed'], 1.2);
        expect(payload['output_format'], {'codec': 'wav'});
        expect(payload.containsKey('model'), isFalse);
        expect(payload.containsKey('input'), isFalse);
        expect(payload.containsKey('voice'), isFalse);
        expect(payload.containsKey('response_format'), isFalse);
      },
    );

    test(
      'accepts an explicit base64 audio field from a JSON response',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) async {
            await request.drain<void>();
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'audio': base64Encode([7, 8, 9]),
                }),
              );
            await request.response.close();
          }),
        );

        final engine = XaiTextToSpeechEngine(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'xai-test-key',
        );

        expect(
          await engine.synthesize(
            const TextToSpeechInput(text: 'json audio', voice: 'eve'),
          ),
          [7, 8, 9],
        );
      },
    );

    test(
      'rejects JSON error-shaped success body and oversized audio',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var returnJson = true;
        unawaited(
          server.forEach((request) async {
            await request.drain<void>();
            if (returnJson) {
              request.response
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'error': 'Bearer xai-test-key /Users/sanbo/voice.mp3',
                  }),
                );
            } else {
              request.response
                ..headers.contentType = ContentType('audio', 'mpeg')
                ..add([1, 2, 3, 4, 5]);
            }
            await request.response.close();
          }),
        );

        XaiTextToSpeechEngine build({XaiSpeechProviderProfile? profile}) =>
            XaiTextToSpeechEngine(
              baseUrl: 'http://${server.address.host}:${server.port}',
              apiKey: 'xai-test-key',
              profile:
                  profile ??
                  const XaiSpeechProviderProfile(maxTtsAudioBytes: 4),
            );

        await expectLater(
          build().synthesize(
            const TextToSpeechInput(text: 'hello', voice: 'eve'),
          ),
          throwsA(
            isA<TextToSpeechException>()
                .having((e) => e.message, 'json body', contains('不是音频'))
                .having(
                  (e) => e.message,
                  'safe message',
                  allOf(
                    isNot(contains('xai-test-key')),
                    isNot(contains('/Users/sanbo/voice.mp3')),
                  ),
                ),
          ),
        );

        returnJson = false;
        await expectLater(
          build().synthesize(
            const TextToSpeechInput(text: 'hello', voice: 'eve'),
          ),
          throwsA(
            isA<TextToSpeechException>().having(
              (e) => e.message,
              'size limit',
              contains('过大'),
            ),
          ),
        );
      },
    );

    test(
      'propagates cancellation as an error instead of returning audio',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requestReceived = Completer<void>();
        unawaited(
          server.forEach((request) async {
            await request.drain<void>();
            requestReceived.complete();
            await Future<void>.delayed(const Duration(seconds: 2));
            try {
              request.response
                ..headers.contentType = ContentType('audio', 'mpeg')
                ..add([1, 2, 3]);
              await request.response.close();
            } catch (_) {
              // Expected after the client cancels the request.
            }
          }),
        );

        final cancelToken = CancelToken();
        final engine = XaiTextToSpeechEngine(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'xai-test-key',
        );
        final operation = engine.synthesize(
          const TextToSpeechInput(text: 'hello', voice: 'eve'),
          cancelToken: cancelToken,
        );
        await requestReceived.future;
        cancelToken.cancel('focused test cancellation');

        await expectLater(
          operation,
          throwsA(
            isA<TextToSpeechException>().having(
              (e) => e.message,
              'message',
              contains('已取消'),
            ),
          ),
        );
      },
    );

    test(
      'rejects an already-cancelled operation before network validation',
      () async {
        final cancelToken = CancelToken()..cancel('already cancelled');
        final engine = XaiTextToSpeechEngine(
          baseUrl: 'file:///not-used',
          apiKey: 'xai-test-key',
        );

        await expectLater(
          engine.synthesize(
            const TextToSpeechInput(text: 'hello', voice: 'eve'),
            cancelToken: cancelToken,
          ),
          throwsA(
            isA<TextToSpeechException>().having(
              (e) => e.message,
              'message',
              contains('已取消'),
            ),
          ),
        );
      },
    );
  });
}
