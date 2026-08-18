import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/media/xai_custom_voice_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XaiCustomVoiceAdapter', () {
    late Directory tempDir;
    late File referenceAudio;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_xai_voice_');
      referenceAudio = File('${tempDir.path}/reference.wav');
      await referenceAudio.writeAsBytes([0x52, 0x49, 0x46, 0x46, 1, 2]);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test(
      'uploads multipart reference audio and returns server voice_id',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final seen =
            Completer<({String path, String contentType, String body})>();
        unawaited(
          server.forEach((request) async {
            final bytes = await request.fold<List<int>>(
              <int>[],
              (buffer, chunk) => buffer..addAll(chunk),
            );
            seen.complete((
              path: request.uri.path,
              contentType: request.headers.value('content-type') ?? '',
              body: latin1.decode(bytes),
            ));
            request.response
              ..statusCode = HttpStatus.created
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({'voice_id': 'ab12cd34', 'name': 'Test voice'}),
              );
            await request.response.close();
          }),
        );

        final result =
            await XaiCustomVoiceAdapter(
              baseUrl: 'http://${server.address.host}:${server.port}',
              apiKey: 'xai-test-key',
            ).createVoice(
              XaiCustomVoiceRequest(
                audioPath: referenceAudio.path,
                fileName: 'reference.wav',
                name: 'Test voice',
                description: 'A calm test narrator',
                language: 'zh',
                gender: 'neutral',
                accent: 'American',
                age: 'young',
                tone: 'calm',
                useCase: 'conversational',
              ),
            );

        expect(result.voiceId, 'ab12cd34');
        final request = await seen.future;
        expect(request.path, '/v1/custom-voices');
        expect(request.contentType, startsWith('multipart/form-data;'));
        expect(request.body, contains('name="file"'));
        expect(request.body, contains('filename="reference.wav"'));
        expect(request.body, contains('name="name"'));
        expect(request.body, contains('Test voice'));
        expect(request.body, contains('name="description"'));
        expect(request.body, contains('A calm test narrator'));
        expect(request.body, contains('name="language"'));
        expect(request.body, contains('zh'));
        expect(request.body, contains('name="gender"'));
        expect(request.body, contains('neutral'));
        expect(request.body, contains('name="accent"'));
        expect(request.body, contains('American'));
        expect(request.body, contains('name="age"'));
        expect(request.body, contains('young'));
        expect(request.body, isNot(contains('xai-test-key')));
      },
    );

    test('rejects a response without a valid voice_id', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.created
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'name': 'missing id'}));
          await request.response.close();
        }),
      );

      await expectLater(
        XaiCustomVoiceAdapter(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'xai-test-key',
        ).createVoice(XaiCustomVoiceRequest(audioPath: referenceAudio.path)),
        throwsA(
          isA<XaiCustomVoiceException>().having(
            (error) => error.message,
            'message',
            contains('voice_id'),
          ),
        ),
      );
    });

    test(
      'sanitizes permission failures instead of exposing response data',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) async {
            await request.drain<void>();
            request.response
              ..statusCode = HttpStatus.forbidden
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'error':
                      'Bearer xai-secret /Users/private/reference.wav raw body',
                }),
              );
            await request.response.close();
          }),
        );

        await expectLater(
          XaiCustomVoiceAdapter(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: 'xai-secret',
          ).createVoice(XaiCustomVoiceRequest(audioPath: referenceAudio.path)),
          throwsA(
            isA<XaiCustomVoiceException>()
                .having((error) => error.message, 'message', contains('403'))
                .having(
                  (error) => error.message,
                  'message does not contain token',
                  isNot(contains('xai-secret')),
                )
                .having(
                  (error) => error.message,
                  'message does not contain path',
                  isNot(contains(referenceAudio.path)),
                ),
          ),
        );
      },
    );

    test('maps HTTP 413 to the documented duration/size boundary', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.requestEntityTooLarge
            ..write('oversized reference');
          await request.response.close();
        }),
      );

      await expectLater(
        XaiCustomVoiceAdapter(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'xai-test-key',
        ).createVoice(XaiCustomVoiceRequest(audioPath: referenceAudio.path)),
        throwsA(
          isA<XaiCustomVoiceException>().having(
            (error) => error.message,
            'message',
            allOf(contains('413'), contains('120 秒')),
          ),
        ),
      );
    });
  });
}
