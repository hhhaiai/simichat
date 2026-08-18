import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/attachment_helper.dart';
import 'package:ai_chat_app/core/ai/claude_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Future<T> _withClaudeSseServer<T>(
  String body,
  Future<T> Function(String baseUrl) action,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
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

Future<void> _expectClaudeError(
  String body, {
  required ProtocolStreamErrorKind kind,
}) async {
  await _withClaudeSseServer(body, (baseUrl) async {
    await expectLater(
      ClaudeProtocol()
          .sendStream(
            baseUrl: baseUrl,
            apiKey: 'claude-test-key',
            model: 'claude-test',
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

void main() {
  group('ClaudeProtocol stream terminal errors', () {
    test('serializes image input as a native Claude image block', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'simichat_claude_image_',
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
          if (!seenPayload.isCompleted) {
            seenPayload.complete(jsonDecode(body) as Map<String, dynamic>);
          }
          request.response
            ..headers.contentType = ContentType('text', 'event-stream')
            ..write(
              'data: ${jsonEncode({
                'type': 'content_block_delta',
                'delta': {'type': 'text_delta', 'text': 'seen'},
              })}\n\n',
            )
            ..write('data: ${jsonEncode({'type': 'message_stop'})}\n\n');
          await request.response.close();
        }),
      );

      final chunks = await ClaudeProtocol()
          .sendStream(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: 'claude-test-key',
            model: 'claude-vision-test',
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
      expect(ClaudeProtocol().nativeAttachmentTypes, {'image'});
      final payload = await seenPayload.future;
      final messages = payload['messages'] as List<dynamic>;
      final content =
          (messages.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content.first, {'type': 'text', 'text': '描述图片'});
      expect(content.last, {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/png',
          'data': base64Encode(imageBytes),
        },
      });
    });

    test(
      'rejects audio input even when the model id looks audio-capable',
      () async {
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
          ClaudeProtocol()
              .sendStream(
                baseUrl: 'http://${server.address.host}:${server.port}',
                apiKey: 'claude-test-key',
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
                .having((error) => error.protocol, 'protocol', 'claude'),
          ),
        );
        expect(requestSeen, isFalse);
      },
    );

    test('surfaces an event:error payload without leaking its diagnostic', () {
      final payload = jsonEncode({
        'message':
            'upstream failed with Bearer claude-secret at https://upstream.test/x',
      });
      return _expectClaudeError(
        'event: error\ndata: $payload\n\n',
        kind: ProtocolStreamErrorKind.failed,
      ).then((_) async {
        // The assertion above checks the terminal kind; this separate parser
        // check keeps the redaction contract directly observable.
        final error = ProtocolStreamException(
          'Bearer claude-secret https://upstream.test/x',
          protocol: 'claude',
        );
        expect(error.message, isNot(contains('claude-secret')));
        expect(error.message, isNot(contains('https://upstream.test')));
      });
    });

    test('surfaces a nested safety/refusal stop reason', () {
      final payload = jsonEncode({
        'type': 'message_delta',
        'delta': {'stop_reason': 'refusal'},
      });
      return _expectClaudeError(
        'data: $payload\n\n',
        kind: ProtocolStreamErrorKind.safety,
      );
    });

    test('surfaces max_tokens as an incomplete terminal result', () {
      final payload = jsonEncode({
        'type': 'message_delta',
        'delta': {'stop_reason': 'max_tokens'},
      });
      return _expectClaudeError(
        'data: $payload\n\n',
        kind: ProtocolStreamErrorKind.incomplete,
      );
    });

    test('does not swallow malformed JSON events', () {
      return _expectClaudeError(
        'data: not-json\n\n',
        kind: ProtocolStreamErrorKind.malformed,
      );
    });

    test('keeps normal text deltas and message_stop successful', () async {
      final body = [
        'event: content_block_delta\n'
            'data: ${jsonEncode({
              'type': 'content_block_delta',
              'delta': {'type': 'text_delta', 'text': '你好'},
            })}\n\n',
        'event: message_stop\n'
            'data: ${jsonEncode({'type': 'message_stop'})}\n\n',
      ].join();
      final chunks = await _withClaudeSseServer(body, (baseUrl) {
        return ClaudeProtocol()
            .sendStream(
              baseUrl: baseUrl,
              apiKey: 'claude-test-key',
              model: 'claude-test',
              messages: const [AiMessage(role: 'user', content: 'hello')],
            )
            .toList();
      });

      expect(chunks.single.content, '你好');
    });
  });
}
