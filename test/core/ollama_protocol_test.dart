import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/ollama_protocol.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OllamaProtocol', () {
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
