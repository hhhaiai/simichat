import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken, Options;
import 'package:flutter/foundation.dart';
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'http_helper.dart';
import 'sse_helper.dart';

class OpenAiChatProtocol implements AiProtocol {
  static List<AiChunk> extractChunksFromEventData(String eventData) {
    final json = jsonDecode(eventData) as Map<String, dynamic>;
    final chunks = <AiChunk>[];

    void addChunk({String? content, String? thinking}) {
      if ((content != null && content.isNotEmpty) ||
          (thinking != null && thinking.isNotEmpty)) {
        chunks.add(AiChunk(content: content, thinking: thinking));
      }
    }

    String? extractText(dynamic value) {
      if (value is String) return value;
      if (value is List) {
        final texts = value
            .map((item) {
              if (item is String) return item;
              if (item is Map<String, dynamic>) {
                return item['text'] ?? item['content'] ?? item['value'];
              }
              return null;
            })
            .whereType<String>()
            .toList();
        if (texts.isNotEmpty) return texts.join();
      }
      return null;
    }

    final choices = json['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      for (final choice in choices.whereType<Map>()) {
        final delta = (choice['delta'] as Map?)?.cast<String, dynamic>();
        final message = (choice['message'] as Map?)?.cast<String, dynamic>();

        if (delta != null) {
          addChunk(thinking: extractText(delta['reasoning_content']));
          addChunk(thinking: extractText(delta['reasoning']));
          addChunk(content: extractText(delta['content']));
        }

        if (message != null) {
          addChunk(thinking: extractText(message['reasoning_content']));
          addChunk(thinking: extractText(message['reasoning']));
          addChunk(content: extractText(message['content']));
        }
      }
    }

    addChunk(content: extractText(json['content']));
    addChunk(content: extractText(json['output_text']));
    addChunk(thinking: extractText(json['reasoning_content']));

    return chunks;
  }

  static ({String content, String? thinking}) extractMessageFromResponseData(
    Map<String, dynamic> json,
  ) {
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      return (content: '', thinking: null);
    }
    final first = choices.first;
    if (first is! Map) {
      return (content: '', thinking: null);
    }
    final message = (first['message'] as Map?)?.cast<String, dynamic>();
    if (message == null) {
      return (content: '', thinking: null);
    }
    final content = message['content'] as String? ?? '';
    final thinking = message['reasoning_content'] as String?;
    return (content: content, thinking: thinking);
  }

  static Future<({String content, String? thinking})> fetchMessageOnce({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
    CancelToken? cancelToken,
  }) async {
    final normalized = normalizeOpenAiBaseUrl(baseUrl);
    final url = '$normalized/v1/chat/completions';

    final msgList = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      msgList.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        final loaded = await loadAttachments(m.attachments!);
        final content = <Map<String, dynamic>>[];
        if (m.content.isNotEmpty) {
          content.add({'type': 'text', 'text': m.content});
        }
        for (final att in loaded) {
          if (att.type == 'image') {
            content.add({
              'type': 'image_url',
              'image_url': {'url': 'data:${att.mimeType};base64,${att.base64}'},
            });
          } else {
            content.add({
              'type': 'text',
              'text': '[附件: ${att.type}] base64 数据已省略',
            });
          }
        }
        msgList.add({'role': m.role, 'content': content});
      } else {
        msgList.add({'role': m.role, 'content': m.content});
      }
    }

    final dio = getDio(url);
    final response = await dio.post<Map<String, dynamic>>(
      url,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ),
      data: jsonEncode({'model': model, 'messages': msgList, 'stream': false}),
      cancelToken: cancelToken,
    );

    final data = response.data;
    if (data == null) {
      return (content: '', thinking: null);
    }
    return extractMessageFromResponseData(data);
  }

  @override
  Stream<AiChunk> sendStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
    CancelToken? cancelToken,
  }) async* {
    final normalized = normalizeOpenAiBaseUrl(baseUrl);
    final url = '$normalized/v1/chat/completions';

    final msgList = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      msgList.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        final loaded = await loadAttachments(m.attachments!);
        final content = <Map<String, dynamic>>[];
        if (m.content.isNotEmpty) {
          content.add({'type': 'text', 'text': m.content});
        }
        for (final att in loaded) {
          if (att.type == 'image') {
            content.add({
              'type': 'image_url',
              'image_url': {'url': 'data:${att.mimeType};base64,${att.base64}'},
            });
          } else {
            content.add({
              'type': 'text',
              'text': '[附件: ${att.type}] base64 数据已省略',
            });
          }
        }
        msgList.add({'role': m.role, 'content': content});
      } else {
        msgList.add({'role': m.role, 'content': m.content});
      }
    }

    final byteStream = await openSseStream(
      SseRequestConfig(
        url: url,
        headers: {'Authorization': 'Bearer $apiKey'},
        body: {'model': model, 'messages': msgList, 'stream': true},
        cancelToken: cancelToken,
      ),
    );

    await for (final event in parseSseStream(byteStream)) {
      try {
        for (final chunk in extractChunksFromEventData(event.data)) {
          yield chunk;
        }
      } catch (e) {
        debugPrint('[OpenAI Chat] SSE parse error: $e\nLine: ${event.data}');
      }
    }
  }
}
