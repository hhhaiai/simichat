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

  // ---- SimiRouter mimo TTS 三种模式 ----
  group('SimiRouter mimo TTS modes', () {
    /// 起本地 mock 服务，断言请求体字段，返回音频字节。
    Future<Map<String, dynamic>> captureMimoRequest(
      String model,
      TextToSpeechInput input, {
      String speed = '1.5',
      String format = 'wav',
      String style = '',
      String? referenceAudioPath,
    }) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final payloadCompleter = Completer<Map<String, dynamic>>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          expect(request.headers.value(HttpHeaders.acceptHeader), 'audio/wav');
          payloadCompleter.complete(jsonDecode(body) as Map<String, dynamic>);
          request.response.headers.contentType = ContentType('audio', 'wav');
          request.response.add([0x52, 0x49, 0x46, 0x46]);
          await request.response.close();
        }),
      );

      final engine = OpenAiCompatibleTextToSpeechEngine(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'tts-test-key',
        model: model,
        speed: speed,
        responseFormat: format,
        style: style,
        referenceAudioPath: referenceAudioPath,
      );

      await engine.synthesize(input);
      return await payloadCompleter.future;
    }

    test('standard mode posts voice with speed and response_format', () async {
      final payload = await captureMimoRequest(
        'mimo-v2.5-tts',
        const TextToSpeechInput(text: '你好', voice: 'dean'),
      );
      expect(payload['model'], 'mimo-v2.5-tts');
      expect(payload['voice'], 'dean');
      expect(payload['input'], '你好');
      expect(payload['speed'], '1.5');
      expect(payload['response_format'], 'wav');
      expect(payload.containsKey('style'), isFalse);
    });

    test('voice design mode posts style instead of voice', () async {
      final payload = await captureMimoRequest(
        'mimo-v2.5-tts-voicedesign',
        const TextToSpeechInput(text: '你好', voice: 'alloy'),
        style: '温柔自然的年轻女声，普通话标准',
      );
      expect(payload['model'], 'mimo-v2.5-tts-voicedesign');
      expect(payload['style'], '温柔自然的年轻女声，普通话标准');
      expect(payload['speed'], '1.5');
      expect(payload['response_format'], 'wav');
      expect(payload.containsKey('voice'), isFalse);
    });

    test('voice design mode rejects empty style', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final engine = OpenAiCompatibleTextToSpeechEngine(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'tts-test-key',
        model: 'mimo-v2.5-tts-voicedesign',
      );
      await expectLater(
        engine.synthesize(const TextToSpeechInput(text: '你好', voice: 'alloy')),
        throwsA(
          isA<TextToSpeechException>().having(
            (e) => e.message,
            'message',
            contains('声音风格描述'),
          ),
        ),
      );
    });

    test('voice clone mode posts base64 data uri voice', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'simichat-tts-clone-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final reference = File('${tempDir.path}/reference.wav');
      await reference.writeAsBytes([0, 1, 2, 3, 4]);

      final payload = await captureMimoRequest(
        'mimo-v2.5-tts-voiceclone',
        const TextToSpeechInput(text: '你好', voice: 'alloy'),
        referenceAudioPath: reference.path,
      );
      expect(payload['model'], 'mimo-v2.5-tts-voiceclone');
      expect(
        payload['voice'],
        'data:audio/wav;base64,${base64Encode([0, 1, 2, 3, 4])}',
      );
      expect(payload['speed'], '1.5');
      expect(payload['response_format'], 'wav');
    });

    test('voice clone mode rejects missing reference audio', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final engine = OpenAiCompatibleTextToSpeechEngine(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'tts-test-key',
        model: 'mimo-v2.5-tts-voiceclone',
        referenceAudioPath: '/nonexistent/reference.wav',
      );
      await expectLater(
        engine.synthesize(const TextToSpeechInput(text: '你好', voice: 'alloy')),
        throwsA(
          isA<TextToSpeechException>().having(
            (e) => e.message,
            'message',
            contains('参考音频'),
          ),
        ),
      );
    });
  });
}
