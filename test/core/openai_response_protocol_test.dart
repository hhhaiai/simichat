import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/ai/openai_response_protocol.dart';

void main() {
  group('OpenAiResponseProtocol.extractChunksFromEventData', () {
    test('parses output_text delta events', () {
      final chunks = OpenAiResponseProtocol.extractChunksFromEventData(
        '{"output_index":0,"content_index":0,"delta":"Hi there! ","type":"response.output_text.delta"}',
        allowCompletedFallback: false,
      );

      expect(chunks.length, 1);
      expect(chunks.single.content, 'Hi there! ');
    });

    test('parses completed response fallback payloads', () {
      final chunks = OpenAiResponseProtocol.extractChunksFromEventData(
        '{"response":{"output":[{"type":"message","content":[{"type":"output_text","text":"Hi there! 👋 I\'m MiMo."}]}]},"type":"response.completed"}',
      );

      expect(chunks.length, 1);
      expect(chunks.single.content, "Hi there! 👋 I'm MiMo.");
    });

    test('parses output_item done payloads', () {
      final chunks = OpenAiResponseProtocol.extractChunksFromEventData(
        '{"output_index":0,"item":{"type":"message","content":[{"type":"output_text","text":"Hi there! 👋"}],"status":"completed"},"type":"response.output_item.done"}',
      );

      expect(chunks.length, 1);
      expect(chunks.single.content, 'Hi there! 👋');
    });

    test(
      'sends audio attachments as input_text with full base64 payload',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'simichat_response_audio_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final audio = File('${tempDir.path}/voice.wav');
        await audio.writeAsBytes([0x05, 0x06, 0x07]);

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
              'data: {"type":"response.output_text.delta","delta":"ok"}\n\n',
            );
            request.response.write(
              'data: {"type":"response.completed","response":{"output":[]}}\n\n',
            );
            await request.response.close();
          }),
        );

        final chunks = await OpenAiResponseProtocol()
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
        final input = payload['input'] as List<dynamic>;
        final content =
            (input.single as Map<String, dynamic>)['content'] as List<dynamic>;
        expect(content.first, {'type': 'input_text', 'text': '听一下'});
        final audioPart = content.last as Map<String, dynamic>;
        expect(audioPart['type'], 'input_text');
        expect(audioPart['text'], contains('[附件: audio]'));
        expect(audioPart['text'], contains('mime_type: audio/wav'));
        expect(audioPart['text'], contains('format: wav'));
        expect(audioPart['text'], contains(base64Encode([0x05, 0x06, 0x07])));
        expect(jsonEncode(payload), isNot(contains('base64 数据已省略')));
        expect(jsonEncode(payload), isNot(contains('input_audio')));
      },
    );
  });
}
