import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/media/audio_transcription_service.dart';
import 'package:ai_chat_app/core/media/openai_speech_to_text_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenAiCompatibleSpeechToTextEngine', () {
    late Directory tempDir;
    late File audioFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_stt_engine_');
      audioFile = File('${tempDir.path}/voice.m4a');
      await audioFile.writeAsBytes([1, 2, 3, 4, 5]);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('posts OpenAI-compatible multipart transcription request', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = Completer<String>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          expect(request.method, 'POST');
          expect(request.uri.path, '/v1/audio/transcriptions');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer stt-test-key',
          );
          expect(body, contains('name="model"'));
          expect(body, contains('whisper-1'));
          expect(body, contains('filename="voice.m4a"'));
          expect(
            body,
            isNot(contains('name="language"')),
            reason: 'auto 表示服务端自动检测，不应作为字面语言代码发送',
          );
          seen.complete(body);
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'text': '  你好，SimiChat  '}));
          await request.response.close();
        }),
      );

      final engine = OpenAiCompatibleSpeechToTextEngine(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'stt-test-key',
      );

      final transcript = await engine.transcribe(
        AudioTranscriptionInput(
          audioPath: audioFile.path,
          fileName: 'voice.m4a',
          fileSize: await audioFile.length(),
        ),
      );

      expect(transcript, '你好，SimiChat');
      expect(await seen.future, isNot(contains('stt-test-key')));
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
                'message': 'failed for sk-live-secret and ${audioFile.path}',
              },
            }),
          );
          await request.response.close();
        }),
      );

      final engine = OpenAiCompatibleSpeechToTextEngine(
        baseUrl: 'http://${server.address.host}:${server.port}',
        apiKey: 'stt-test-key',
      );

      await expectLater(
        engine.transcribe(
          AudioTranscriptionInput(
            audioPath: audioFile.path,
            fileName: 'voice.m4a',
            fileSize: await audioFile.length(),
          ),
        ),
        throwsA(
          isA<AudioTranscriptionException>()
              .having((e) => e.message, 'message', contains('HTTP 500'))
              .having(
                (e) => e.message,
                'no api key',
                isNot(contains('sk-live-secret')),
              )
              .having(
                (e) => e.message,
                'no local path',
                isNot(contains(audioFile.path)),
              ),
        ),
      );
    });

    test('rejects non-http base url before network request', () async {
      final engine = OpenAiCompatibleSpeechToTextEngine(
        baseUrl: 'file:///tmp/stt',
        apiKey: 'stt-test-key',
      );

      await expectLater(
        engine.transcribe(
          AudioTranscriptionInput(
            audioPath: audioFile.path,
            fileName: 'voice.m4a',
            fileSize: await audioFile.length(),
          ),
        ),
        throwsA(
          isA<AudioTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('STT Base URL'),
          ),
        ),
      );
    });

    test('posts language field for mimo asr model', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = Completer<String>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          expect(body, contains('name="model"'));
          expect(body, contains('mimo-v2.5-asr'));
          expect(body, contains('name="language"'));
          expect(body, contains('zh'));
          seen.complete(body);
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'text': '你好'}));
          await request.response.close();
        }),
      );

      final tempDir = await Directory.systemTemp.createTemp('stt-language-');
      addTearDown(() => tempDir.delete(recursive: true));
      final audio = File('${tempDir.path}/voice.m4a');
      await audio.writeAsBytes([0, 1, 2, 3, 4]);

      final engine = OpenAiCompatibleSpeechToTextEngine(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'stt-test-key',
        model: 'mimo-v2.5-asr',
        language: 'zh',
      );
      final transcript = await engine.transcribe(
        AudioTranscriptionInput(
          audioPath: audio.path,
          fileName: 'voice.m4a',
          fileSize: 5,
        ),
      );
      expect(transcript, '你好');
      expect(await seen.future, isNot(contains('stt-test-key')));
    });

    test('resolves STT through a configured /api/v3 prefix', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          expect(request.uri.path, '/api/v3/audio/transcriptions');
          await request.drain<void>();
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'text': 'prefix ok'}));
          await request.response.close();
        }),
      );

      final engine = OpenAiCompatibleSpeechToTextEngine(
        baseUrl: 'http://${server.address.host}:${server.port}/api/v3',
        apiKey: 'stt-test-key',
      );
      final transcript = await engine.transcribe(
        AudioTranscriptionInput(
          audioPath: audioFile.path,
          fileName: 'voice.m4a',
          fileSize: await audioFile.length(),
        ),
      );

      expect(transcript, 'prefix ok');
    });
  });
}
