import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/attachment_helper.dart';
import 'package:ai_chat_app/core/ai/gemini_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Future<T> _withGeminiSseServer<T>(
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

Future<void> _expectGeminiError(
  String body, {
  required ProtocolStreamErrorKind kind,
}) async {
  await _withGeminiSseServer(body, (baseUrl) async {
    await expectLater(
      GeminiProtocol()
          .sendStream(
            baseUrl: baseUrl,
            apiKey: 'gemini-test-key',
            model: 'gemini-test',
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
  group('GeminiProtocol stream terminal errors', () {
    test('serializes native image and audio inlineData parts', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'simichat_gemini_multimodal_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final image = File('${tempDir.path}/photo.png');
      final audio = File('${tempDir.path}/voice.wav');
      const imageBytes = [0x89, 0x50, 0x4e, 0x47];
      const audioBytes = [0x01, 0x02, 0x03];
      await image.writeAsBytes(imageBytes);
      await audio.writeAsBytes(audioBytes);

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
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'seen'},
                      ],
                    },
                  },
                ],
              })}\n\n',
            );
          await request.response.close();
        }),
      );

      final chunks = await GeminiProtocol()
          .sendStream(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: 'gemini-test-key',
            // The audio-shaped model id is not consulted by the serializer;
            // Gemini's explicit protocol contract enables this native branch.
            model: 'audio4',
            messages: [
              AiMessage(
                role: 'user',
                content: '请看并听取',
                attachments: [
                  Attachment(type: 'image', path: image.path),
                  Attachment(type: 'audio', path: audio.path),
                ],
              ),
            ],
          )
          .toList();

      expect(chunks.single.content, 'seen');
      expect(
        GeminiProtocol().nativeAttachmentTypes,
        containsAll(<String>['image', 'audio']),
      );
      final payload = await seenPayload.future;
      final contents = payload['contents'] as List<dynamic>;
      final parts =
          (contents.single as Map<String, dynamic>)['parts'] as List<dynamic>;
      expect(parts.first, {'text': '请看并听取'});
      expect(parts[1], {
        'inlineData': {
          'mimeType': 'image/png',
          'data': base64Encode(imageBytes),
        },
      });
      expect(parts[2], {
        'inlineData': {
          'mimeType': 'audio/wav',
          'data': base64Encode(audioBytes),
        },
      });
    });

    test('rejects PDF input instead of converting it to prompt text', () async {
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
        GeminiProtocol()
            .sendStream(
              baseUrl: 'http://${server.address.host}:${server.port}',
              apiKey: 'gemini-test-key',
              model: 'gemini-test',
              messages: const [
                AiMessage(
                  role: 'user',
                  content: '读取',
                  attachments: [
                    Attachment(type: 'pdf', path: '/not-read/report.pdf'),
                  ],
                ),
              ],
            )
            .toList(),
        throwsA(
          isA<UnsupportedAttachmentException>()
              .having((error) => error.attachmentType, 'type', 'pdf')
              .having((error) => error.protocol, 'protocol', 'gemini'),
        ),
      );
      expect(requestSeen, isFalse);
    });

    test('surfaces an event:error payload', () {
      final payload = jsonEncode({
        'message':
            'failed with sk-gemini-secret at https://upstream.test/gemini',
      });
      return _expectGeminiError(
        'event: error\ndata: $payload\n\n',
        kind: ProtocolStreamErrorKind.failed,
      );
    });

    test('surfaces promptFeedback safety blocks', () {
      final payload = jsonEncode({
        'promptFeedback': {'blockReason': 'SAFETY'},
      });
      return _expectGeminiError(
        'data: $payload\n\n',
        kind: ProtocolStreamErrorKind.safety,
      );
    });

    test('surfaces MAX_TOKENS as an incomplete result', () {
      final payload = jsonEncode({
        'candidates': [
          {
            'finishReason': 'MAX_TOKENS',
            'content': {'parts': []},
          },
        ],
      });
      return _expectGeminiError(
        'data: $payload\n\n',
        kind: ProtocolStreamErrorKind.incomplete,
      );
    });

    test('does not swallow malformed JSON events', () {
      return _expectGeminiError(
        'data: not-json\n\n',
        kind: ProtocolStreamErrorKind.malformed,
      );
    });

    test('keeps ordinary candidate text successful', () async {
      final payload = jsonEncode({
        'candidates': [
          {
            'finishReason': 'STOP',
            'content': {
              'parts': [
                {'text': '你好'},
              ],
            },
          },
        ],
      });
      final chunks = await _withGeminiSseServer('data: $payload\n\n', (
        baseUrl,
      ) {
        return GeminiProtocol()
            .sendStream(
              baseUrl: baseUrl,
              apiKey: 'gemini-test-key',
              model: 'gemini-test',
              messages: const [AiMessage(role: 'user', content: 'hello')],
            )
            .toList();
      });

      expect(chunks.single.content, '你好');
    });
  });
}
