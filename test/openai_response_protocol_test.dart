import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/attachment_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/ai/openai_response_protocol.dart';

Future<T> _withOpenAiResponseSseServer<T>(
  String body,
  Future<T> Function(String baseUrl) action,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
      await request.drain();
      request.response
        ..headers.contentType = ContentType('text', 'event-stream')
        ..add(utf8.encode(body));
      await request.response.close();
    }),
  );
  try {
    return await action('http://${server.address.host}:${server.port}');
  } finally {
    await server.close(force: true);
  }
}

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

    test('does not duplicate delta text from output_item.done/completed', () async {
      final body = [
        'data: {"type":"response.output_text.delta","delta":"hello"}\n\n',
        'data: {"type":"response.output_item.done","item":{"type":"message","content":[{"type":"output_text","text":"hello"}]}}\n\n',
        'data: {"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"hello"}]}]}}\n\n',
      ].join();
      final chunks = await _withOpenAiResponseSseServer(body, (baseUrl) {
        return OpenAiResponseProtocol()
            .sendStream(
              baseUrl: baseUrl,
              apiKey: 'response-test-key',
              model: 'gpt-response-test',
              messages: const [AiMessage(role: 'user', content: 'hello')],
            )
            .toList();
      });

      expect(chunks.map((chunk) => chunk.content), ['hello']);
    });

    test('surfaces Responses failed, refusal, and incomplete events', () async {
      Future<void> expectKind(
        String event,
        ProtocolStreamErrorKind kind,
      ) async {
        await _withOpenAiResponseSseServer(event, (baseUrl) async {
          await expectLater(
            OpenAiResponseProtocol()
                .sendStream(
                  baseUrl: baseUrl,
                  apiKey: 'response-test-key',
                  model: 'gpt-response-test',
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
        });
      }

      await expectKind(
        'event: error\ndata: {"message":"failed"}\n\n',
        ProtocolStreamErrorKind.failed,
      );
      await expectKind(
        'data: {"type":"response.refusal.done","refusal":"blocked"}\n\n',
        ProtocolStreamErrorKind.safety,
      );
      await expectKind(
        'data: {"type":"response.incomplete"}\n\n',
        ProtocolStreamErrorKind.incomplete,
      );
    });

    test(
      'rejects audio attachments when Responses has no native audio mapping',
      () async {
        expect(OpenAiResponseProtocol().nativeAttachmentTypes, {
          'image',
          'pdf',
        });
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
        var requestSeen = false;
        unawaited(
          server.forEach((request) async {
            requestSeen = true;
            await request.drain();
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

        await expectLater(
          OpenAiResponseProtocol()
              .sendStream(
                baseUrl: 'http://${server.address.host}:${server.port}/v1',
                apiKey: 'test-key',
                // An audio-looking model id is not evidence that Responses
                // supports input_audio. This adapter has no native mapping.
                model: 'audio4',
                messages: [
                  AiMessage(
                    role: 'user',
                    content: '听一下',
                    attachments: [Attachment(type: 'audio', path: audio.path)],
                  ),
                ],
              )
              .toList(),
          throwsA(
            isA<UnsupportedAttachmentException>()
                .having(
                  (error) => error.attachmentType,
                  'attachment type',
                  'audio',
                )
                .having(
                  (error) => error.protocol,
                  'protocol',
                  'openai_response',
                ),
          ),
        );
        expect(requestSeen, isFalse);
      },
    );

    test('sends image attachments as Responses input_image data URLs', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'simichat_response_image_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final image = File('${tempDir.path}/photo.webp');
      const imageBytes = [0x52, 0x49, 0x46, 0x46];
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
            'data: {"type":"response.output_text.delta","delta":"seen"}\n\n',
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
      final input = payload['input'] as List<dynamic>;
      final content =
          (input.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content.first, {'type': 'input_text', 'text': '描述图片'});
      final imagePart = content.last as Map<String, dynamic>;
      expect(imagePart, {
        'type': 'input_image',
        'image_url': 'data:image/webp;base64,${base64Encode(imageBytes)}',
      });
    });

    test('sends PDF attachments as Responses input_file data URLs', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'simichat_response_pdf_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final nestedDir = Directory('${tempDir.path}/nested');
      await nestedDir.create();
      final pdf = File('${nestedDir.path}/report.pdf');
      const pdfBytes = [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37];
      await pdf.writeAsBytes(pdfBytes);

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
            'data: {"type":"response.output_text.delta","delta":"seen"}\n\n',
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
            model: 'gpt-response-file-test',
            messages: [
              AiMessage(
                role: 'user',
                content: '总结 PDF',
                attachments: [Attachment(type: 'pdf', path: pdf.path)],
              ),
            ],
          )
          .toList();

      expect(chunks.single.content, 'seen');
      final payload = await seenPayload.future;
      final input = payload['input'] as List<dynamic>;
      final content =
          (input.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content.first, {'type': 'input_text', 'text': '总结 PDF'});
      final filePart = content.last as Map<String, dynamic>;
      expect(filePart, {
        'type': 'input_file',
        'file_data': 'data:application/pdf;base64,${base64Encode(pdfBytes)}',
        'filename': 'report.pdf',
      });
      expect(jsonEncode(filePart), isNot(contains(tempDir.path)));
    });
  });
}
