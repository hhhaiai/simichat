import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/media/audio_transcription_service.dart';
import 'package:ai_chat_app/core/media/xai_speech_provider_profile.dart';
import 'package:ai_chat_app/core/media/xai_speech_to_text_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XaiSpeechToTextEngine', () {
    late Directory tempDir;
    late File audioFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_xai_stt_');
      audioFile = File('${tempDir.path}/voice.m4a');
      await audioFile.writeAsBytes([1, 2, 3, 4, 5]);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('uses /v1/stt multipart upload without a model field', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = Completer<({String contentType, String body})>();
      unawaited(
        server.forEach((request) async {
          final bodyBytes = await request.fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          );
          seen.complete((
            contentType: request.headers.value('content-type') ?? '',
            body: latin1.decode(bodyBytes),
          ));
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'text': '  xAI 转写  ', 'language': 'zh'}));
          await request.response.close();
        }),
      );

      final engine = XaiSpeechToTextEngine(
        baseUrl: 'http://${server.address.host}:${server.port}',
        apiKey: 'xai-test-key',
        language: 'zh',
      );
      final transcript = await engine.transcribe(
        AudioTranscriptionInput(
          audioPath: audioFile.path,
          fileName: 'voice.m4a',
          fileSize: await audioFile.length(),
        ),
      );

      expect(transcript, 'xAI 转写');
      final request = await seen.future;
      expect(request.contentType, startsWith('multipart/form-data;'));
      expect(request.body, contains('name="file"'));
      expect(request.body, contains('filename="voice.m4a"'));
      expect(request.body, isNot(contains('name="model"')));
      expect(request.body, isNot(contains('xai-test-key')));
      expect(request.body, isNot(contains('name="language"')));
    });

    test('can opt in to a gateway-specific language multipart field', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bodySeen = Completer<String>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          bodySeen.complete(body);
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'text': '兼容网关'}));
          await request.response.close();
        }),
      );

      final engine = XaiSpeechToTextEngine(
        baseUrl: 'http://${server.address.host}:${server.port}',
        apiKey: 'xai-test-key',
        language: 'zh',
        profile: const XaiSpeechProviderProfile(includeSttLanguageField: true),
      );
      expect(
        await engine.transcribe(
          AudioTranscriptionInput(
            audioPath: audioFile.path,
            fileName: 'voice.m4a',
            fileSize: await audioFile.length(),
          ),
        ),
        '兼容网关',
      );
      expect(await bodySeen.future, contains('name="language"'));
      expect(await bodySeen.future, contains('zh'));
    });

    test('supports profile-selected raw audio request body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bodySeen = Completer<List<int>>();
      final contentTypeSeen = Completer<String>();
      unawaited(
        server.forEach((request) async {
          final body = await request.fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          );
          bodySeen.complete(body);
          contentTypeSeen.complete(request.headers.value('content-type') ?? '');
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'text': 'raw body'}));
          await request.response.close();
        }),
      );

      final engine = XaiSpeechToTextEngine(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'xai-test-key',
        profile: const XaiSpeechProviderProfile(
          sttRequestBodyMode: XaiSpeechToTextRequestBodyMode.rawAudio,
        ),
      );
      final transcript = await engine.transcribe(
        AudioTranscriptionInput(
          audioPath: audioFile.path,
          fileName: 'voice.m4a',
          fileSize: await audioFile.length(),
        ),
      );

      expect(transcript, 'raw body');
      expect(await bodySeen.future, [1, 2, 3, 4, 5]);
      expect(await contentTypeSeen.future, 'audio/mp4');
    });

    test(
      'rejects malformed or incomplete JSON without echoing secrets',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) async {
            await request.drain<void>();
            request.response
              ..headers.contentType = ContentType.json
              ..write('{"error":"Bearer xai-test-key /private/voice.m4a"}');
            await request.response.close();
          }),
        );

        final engine = XaiSpeechToTextEngine(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'xai-test-key',
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
                .having((e) => e.message, 'safe message', contains('缺少 text'))
                .having(
                  (e) => e.message,
                  'no key or path',
                  allOf(
                    isNot(contains('xai-test-key')),
                    isNot(contains('/private/voice.m4a')),
                  ),
                ),
          ),
        );
      },
    );

    test(
      'propagates cancellation as an error instead of returning text',
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
                ..headers.contentType = ContentType.json
                ..write(jsonEncode({'text': 'must not be returned'}));
              await request.response.close();
            } catch (_) {
              // The client is expected to close the request after cancellation.
            }
          }),
        );

        final cancelToken = CancelToken();
        final engine = XaiSpeechToTextEngine(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'xai-test-key',
        );
        final operation = engine.transcribe(
          AudioTranscriptionInput(
            audioPath: audioFile.path,
            fileName: 'voice.m4a',
            fileSize: await audioFile.length(),
          ),
          cancelToken: cancelToken,
        );
        await requestReceived.future;
        cancelToken.cancel('focused test cancellation');

        await expectLater(
          operation,
          throwsA(
            isA<AudioTranscriptionException>().having(
              (e) => e.message,
              'message',
              contains('已取消'),
            ),
          ),
        );
      },
    );

    test(
      'rejects an already-cancelled operation before reading the file',
      () async {
        final cancelToken = CancelToken()..cancel('already cancelled');
        final engine = XaiSpeechToTextEngine(
          baseUrl: 'file:///not-used',
          apiKey: 'xai-test-key',
        );

        await expectLater(
          engine.transcribe(
            AudioTranscriptionInput(
              audioPath: audioFile.path,
              fileName: 'voice.m4a',
              fileSize: await audioFile.length(),
            ),
            cancelToken: cancelToken,
          ),
          throwsA(
            isA<AudioTranscriptionException>().having(
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
