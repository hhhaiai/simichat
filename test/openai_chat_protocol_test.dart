import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/ai/openai_chat_protocol.dart';

void main() {
  group('OpenAiChatProtocol.extractChunksFromEventData', () {
    test('parses grok-style reasoning and content deltas', () {
      final reasoningChunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"index":0,"delta":{"role":"assistant","reasoning_content":"Understanding\\n"}}]}',
      );
      final contentChunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"}}]}',
      );

      expect(reasoningChunks.single.thinking, 'Understanding\n');
      expect(contentChunks.single.content, 'Hello');
    });

    test('parses mimo-style reasoning and content deltas', () {
      final reasoningChunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"delta":{"content":null,"role":null,"tool_calls":null,"reasoning_content":"嗯，用户"}}]}',
      );
      final contentChunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"delta":{"content":"你好","role":null,"tool_calls":null,"reasoning_content":null}}]}',
      );

      expect(reasoningChunks.single.thinking, '嗯，用户');
      expect(contentChunks.single.content, '你好');
    });

    test('parses message fallback payloads', () {
      final chunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"choices":[{"message":{"role":"assistant","content":"Hello!","reasoning_content":"thinking"}}]}',
      );

      expect(chunks.length, 2);
      expect(chunks.first.thinking, 'thinking');
      expect(chunks.last.content, 'Hello!');
    });

    test('parses full chat completion payloads from non-stream responses', () {
      final chunks = OpenAiChatProtocol.extractChunksFromEventData(
        '{"id":"x","choices":[{"message":{"content":"Hi there! 👋 How are you doing today?","role":"assistant","tool_calls":null,"reasoning_content":"The user is asking me to say hi."}}]}',
      );

      expect(chunks.length, 2);
      expect(chunks.first.thinking, 'The user is asking me to say hi.');
      expect(chunks.last.content, 'Hi there! 👋 How are you doing today?');
    });

    test('sends audio attachments as text with full base64 payload', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'simichat_openai_audio_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final audio = File('${tempDir.path}/voice.m4a');
      await audio.writeAsBytes([0x01, 0x02, 0x03, 0x04]);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seenPayload = Completer<Map<String, dynamic>>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          seenPayload.complete(jsonDecode(body) as Map<String, dynamic>);
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n',
          );
          await request.response.close();
        }),
      );

      final chunks = await OpenAiChatProtocol()
          .sendStream(
            baseUrl: 'http://${server.address.host}:${server.port}/v1',
            apiKey: 'test-key',
            model: 'gpt-audio-test',
            messages: [
              AiMessage(
                role: 'user',
                content: '听一下',
                attachments: [Attachment(type: 'audio', path: audio.path)],
              ),
            ],
          )
          .toList();

      expect(chunks.single.content, 'ok');
      final payload = await seenPayload.future;
      final messages = payload['messages'] as List<dynamic>;
      final content =
          (messages.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content.first, {'type': 'text', 'text': '听一下'});
      final audioPart = content.last as Map<String, dynamic>;
      expect(audioPart['type'], 'text');
      expect(audioPart['text'], contains('[附件: audio]'));
      expect(audioPart['text'], contains('mime_type: audio/mp4'));
      expect(audioPart['text'], contains('format: m4a'));
      expect(
        audioPart['text'],
        contains(base64Encode([0x01, 0x02, 0x03, 0x04])),
      );
      expect(jsonEncode(payload), isNot(contains('base64 数据已省略')));
      expect(jsonEncode(payload), isNot(contains('input_audio')));
    });

    test('sends image attachments as OpenAI image_url data URLs', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'simichat_openai_image_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final image = File('${tempDir.path}/photo.png');
      const imageBytes = [0x89, 0x50, 0x4e, 0x47];
      await image.writeAsBytes(imageBytes);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seenPayload = Completer<Map<String, dynamic>>();
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decodeStream(request);
          seenPayload.complete(jsonDecode(body) as Map<String, dynamic>);
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: {"choices":[{"delta":{"content":"seen"}}]}\n\n',
          );
          await request.response.close();
        }),
      );

      final chunks = await OpenAiChatProtocol()
          .sendStream(
            baseUrl: 'http://${server.address.host}:${server.port}/v1',
            apiKey: 'test-key',
            model: 'gpt-vision-test',
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
      final payload = await seenPayload.future;
      final messages = payload['messages'] as List<dynamic>;
      final content =
          (messages.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content.first, {'type': 'text', 'text': '描述图片'});
      final imagePart = content.last as Map<String, dynamic>;
      expect(imagePart['type'], 'image_url');
      expect(imagePart['image_url'], {
        'url': 'data:image/png;base64,${base64Encode(imageBytes)}',
      });
    });

    test(
      'cancels SSE cancel token when stream subscription is cancelled',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requestSeen = Completer<void>();
        final responseFlushed = Completer<void>();
        unawaited(
          server.forEach((request) async {
            if (!requestSeen.isCompleted) requestSeen.complete();
            await utf8.decodeStream(request);
            request.response.bufferOutput = false;
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            request.response.write(
              'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
            );
            await request.response.flush();
            if (!responseFlushed.isCompleted) responseFlushed.complete();
            await Future<void>.delayed(const Duration(seconds: 10));
          }),
        );

        final cancelToken = CancelToken();
        final chunks = <AiChunk>[];
        final firstChunk = Completer<void>();
        final subscription = OpenAiChatProtocol()
            .sendStream(
              baseUrl: 'http://${server.address.host}:${server.port}/v1',
              apiKey: 'test-key',
              model: 'gpt-cancel-test',
              messages: const [AiMessage(role: 'user', content: 'stop')],
              cancelToken: cancelToken,
            )
            .listen((chunk) {
              chunks.add(chunk);
              if (!firstChunk.isCompleted) firstChunk.complete();
            });

        await requestSeen.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('requestSeen'),
        );
        await responseFlushed.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('responseFlushed'),
        );
        await firstChunk.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('firstChunk'),
        );
        await subscription.cancel();

        expect(chunks.single.content, 'partial');
        expect(cancelToken.isCancelled, isTrue);
      },
    );
  });
}
