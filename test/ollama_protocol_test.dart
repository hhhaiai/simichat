import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/attachment_helper.dart';
import 'package:ai_chat_app/core/ai/model_fetcher.dart';
import 'package:ai_chat_app/core/ai/ollama_protocol.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OllamaProtocol', () {
    test('defaults fetched model selection to gemma4 variants', () {
      final models = [
        const FetchedModel(id: 'qwen3:4b', capability: 'chat'),
        const FetchedModel(id: 'gemma4:latest', capability: 'chat'),
        const FetchedModel(id: 'gemma4:27b', capability: 'chat'),
      ];

      expect(
        ModelFetcher.defaultSelectedModelIds(models, preferredModel: 'gemma4'),
        {'gemma4:latest', 'gemma4:27b'},
      );
      expect(ModelFetcher.defaultSelectedModelIds(models), {
        'qwen3:4b',
        'gemma4:latest',
        'gemma4:27b',
      });
    });

    test('requests deterministic JSON mode for structured responses', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestBody = Completer<Map<String, dynamic>>();

      unawaited(
        server.forEach((request) async {
          requestBody.complete(
            (jsonDecode(await utf8.decodeStream(request)) as Map)
                .cast<String, dynamic>(),
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '${jsonEncode({
              'message': {'content': '{}'},
              'done': true,
            })}\n',
          );
          await request.response.close();
        }),
      );

      await OllamaProtocol()
          .sendStream(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: '',
            model: 'qwen-json-test',
            messages: const [AiMessage(role: 'user', content: 'json')],
            jsonResponse: true,
          )
          .toList();

      final body = await requestBody.future;
      expect(body['format'], 'json');
      expect(body['think'], isFalse);
      expect(body['options'], {'temperature': 0});
    });

    test('serializes image input through Ollama images', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final image = File('${Directory.systemTemp.path}/simichat-ollama.png');
      const imageBytes = [0x89, 0x50, 0x4e, 0x47];
      await image.writeAsBytes(imageBytes);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final requestBody = Completer<Map<String, dynamic>>();

      unawaited(
        server.forEach((request) async {
          requestBody.complete(
            (jsonDecode(await utf8.decodeStream(request)) as Map)
                .cast<String, dynamic>(),
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '${jsonEncode({
              'message': {'content': 'seen'},
              'done': true,
            })}\n',
          );
          await request.response.close();
        }),
      );

      final chunks = await OllamaProtocol()
          .sendStream(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: '',
            model: 'llava-test',
            messages: [
              AiMessage(
                role: 'user',
                content: '描述图片',
                attachments: [Attachment(type: 'image', path: image.path)],
              ),
            ],
          )
          .toList();

      expect(chunks.single.content, 'seen');
      expect(OllamaProtocol().nativeAttachmentTypes, {'image'});
      final body = await requestBody.future;
      final message =
          (body['messages'] as List<dynamic>).single as Map<String, dynamic>;
      expect(message['content'], '描述图片');
      expect(message['images'], [base64Encode(imageBytes)]);
    });

    test('does not silently drop audio input', () async {
      var requestSeen = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          requestSeen = true;
          await request.drain();
          await request.response.close();
        }),
      );

      await expectLater(
        OllamaProtocol()
            .sendStream(
              baseUrl: 'http://${server.address.host}:${server.port}',
              apiKey: '',
              // A model label must not make Ollama emit input_audio.
              model: 'audio4',
              messages: const [
                AiMessage(
                  role: 'user',
                  content: '听一下',
                  attachments: [
                    Attachment(type: 'audio', path: '/not-read/voice.wav'),
                  ],
                ),
              ],
            )
            .toList(),
        throwsA(
          isA<UnsupportedAttachmentException>()
              .having((error) => error.attachmentType, 'type', 'audio')
              .having((error) => error.protocol, 'protocol', 'ollama'),
        ),
      );
      expect(requestSeen, isFalse);
    });

    test('preserves Ollama thinking and content fields', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      unawaited(
        server.forEach((request) async {
          await utf8.decodeStream(request);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '${jsonEncode({
              'message': {'thinking': 'reasoning', 'content': 'answer'},
              'done': false,
            })}\n',
          );
          request.response.write('${jsonEncode({'done': true})}\n');
          await request.response.close();
        }),
      );

      final chunks = await OllamaProtocol()
          .sendStream(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: '',
            model: 'qwen3:4b',
            messages: const [AiMessage(role: 'user', content: 'hello')],
          )
          .toList();

      expect(chunks, hasLength(1));
      expect(chunks.single.thinking, 'reasoning');
      expect(chunks.single.content, 'answer');
    });

    test(
      'surfaces an NDJSON error line instead of ending successfully',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) async {
            await request.drain();
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              '${jsonEncode({'error': 'failed with sk-ollama-secret'})}\n',
            );
            await request.response.close();
          }),
        );

        await expectLater(
          OllamaProtocol()
              .sendStream(
                baseUrl: 'http://${server.address.host}:${server.port}',
                apiKey: '',
                model: 'qwen-test',
                messages: const [AiMessage(role: 'user', content: 'hello')],
              )
              .toList(),
          throwsA(
            isA<ProtocolStreamException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  ProtocolStreamErrorKind.failed,
                )
                .having(
                  (error) => error.message,
                  'safe message',
                  isNot(contains('sk-ollama-secret')),
                ),
          ),
        );
      },
    );

    test('surfaces malformed NDJSON and incomplete done_reason', () async {
      Future<void> expectKind(String line, ProtocolStreamErrorKind kind) async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        try {
          unawaited(
            server.forEach((request) async {
              await request.drain();
              request.response.headers.contentType = ContentType.json;
              request.response.write('$line\n');
              await request.response.close();
            }),
          );
          await expectLater(
            OllamaProtocol()
                .sendStream(
                  baseUrl: 'http://${server.address.host}:${server.port}',
                  apiKey: '',
                  model: 'qwen-test',
                  messages: const [AiMessage(role: 'user', content: 'hello')],
                )
                .toList(),
            throwsA(
              isA<ProtocolStreamException>().having(
                (error) => error.kind,
                'kind',
                kind,
              ),
            ),
          );
        } finally {
          await server.close(force: true);
        }
      }

      await expectKind('not-json', ProtocolStreamErrorKind.malformed);
      await expectKind(
        jsonEncode({'done': true, 'done_reason': 'length'}),
        ProtocolStreamErrorKind.incomplete,
      );
    });

    test('fetches local model tags without an API key', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      unawaited(
        server.forEach((request) async {
          expect(request.uri.path, '/api/tags');
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'models': [
                {'name': 'qwen3:4b'},
                {'name': 'llama3.2:3b'},
              ],
            }),
          );
          await request.response.close();
        }),
      );

      expect(
        await OllamaProtocol.fetchModels(
          'http://${server.address.host}:${server.port}',
        ),
        containsAll(<String>['qwen3:4b', 'llama3.2:3b']),
      );
    });

    test(
      'passes optional bearer auth when fetching proxied model tags',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final authorization = Completer<String?>();

        unawaited(
          server.forEach((request) async {
            if (!authorization.isCompleted) {
              authorization.complete(
                request.headers.value(HttpHeaders.authorizationHeader),
              );
            }
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'models': [
                  {'name': 'qwen3:4b'},
                ],
              }),
            );
            await request.response.close();
          }),
        );

        final models = await ModelFetcher.fetchOllamaModels(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'proxy-key',
        );

        expect(await authorization.future, 'Bearer proxy-key');
        expect(models, ['qwen3:4b']);
      },
    );

    test('stops streaming when cancel token is cancelled', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final firstChunkFlushed = Completer<void>();

      unawaited(
        server.forEach((request) async {
          await utf8.decodeStream(request);
          request.response.bufferOutput = false;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '${jsonEncode({
              'message': {'content': 'partial'},
              'done': false,
            })}\n',
          );
          await request.response.flush();
          if (!firstChunkFlushed.isCompleted) firstChunkFlushed.complete();
          await Future<void>.delayed(const Duration(seconds: 10));
        }),
      );

      final cancelToken = CancelToken();
      final chunks = <AiChunk>[];
      final errors = <Object>[];
      final firstChunkReceived = Completer<void>();
      final done = Completer<void>();
      final subscription = OllamaProtocol()
          .sendStream(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: '',
            model: 'llama-cancel-test',
            messages: const [AiMessage(role: 'user', content: 'stop')],
            cancelToken: cancelToken,
          )
          .listen(
            (chunk) {
              chunks.add(chunk);
              if (!firstChunkReceived.isCompleted) {
                firstChunkReceived.complete();
              }
            },
            onError: errors.add,
            onDone: done.complete,
          );
      addTearDown(subscription.cancel);

      await firstChunkFlushed.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('firstChunkFlushed'),
      );
      await firstChunkReceived.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('firstChunkReceived'),
      );

      cancelToken.cancel('stop');

      await done.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('cancelDone'),
      );
      expect(errors, isEmpty);
      expect(chunks.single.content, 'partial');
      expect(cancelToken.isCancelled, isTrue);
    });
  });
}
