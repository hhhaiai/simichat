import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

class OpenAiResponseProtocol implements AiProtocol {
  static List<AiChunk> extractChunksFromEventData(
    String eventData, {
    bool allowCompletedFallback = true,
  }) {
    final json = jsonDecode(eventData) as Map<String, dynamic>;
    final type = json['type'] as String?;
    final chunks = <AiChunk>[];

    void addChunk({String? content, String? thinking}) {
      if ((content != null && content.isNotEmpty) ||
          (thinking != null && thinking.isNotEmpty)) {
        chunks.add(AiChunk(content: content, thinking: thinking));
      }
    }

    void extractOutputTextParts(dynamic contentList) {
      if (contentList is! List) return;
      for (final item in contentList.whereType<Map>()) {
        final type = item['type'];
        if (type == 'output_text') {
          addChunk(content: item['text'] as String?);
        } else if (type == 'reasoning_text') {
          addChunk(thinking: item['text'] as String?);
        }
      }
    }

    if (type == 'response.output_text.delta') {
      addChunk(content: json['delta'] as String?);
      return chunks;
    }
    if (type == 'response.reasoning_text.delta') {
      addChunk(thinking: json['delta'] as String?);
      return chunks;
    }
    if (!allowCompletedFallback) {
      return chunks;
    }

    if (type == 'response.content_part.done') {
      final part = (json['part'] as Map?)?.cast<String, dynamic>();
      if (part != null) {
        if (part['type'] == 'output_text') {
          addChunk(content: part['text'] as String?);
        } else if (part['type'] == 'reasoning_text') {
          addChunk(thinking: part['text'] as String?);
        }
      }
      return chunks;
    }

    if (type == 'response.output_item.done') {
      final item = (json['item'] as Map?)?.cast<String, dynamic>();
      if (item != null) {
        extractOutputTextParts(item['content']);
      }
      return chunks;
    }

    if (type == 'response.completed') {
      final response = (json['response'] as Map?)?.cast<String, dynamic>();
      final output = response?['output'];
      if (output is List) {
        for (final item in output.whereType<Map>()) {
          extractOutputTextParts(item['content']);
        }
      }
    }

    return chunks;
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
    final url = '$normalized/v1/responses';

    final inputList = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      inputList.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        final loaded = await loadAttachments(m.attachments!);
        final content = <Map<String, dynamic>>[];
        if (m.content.isNotEmpty) {
          content.add({'type': 'input_text', 'text': m.content});
        }
        for (final att in loaded) {
          if (att.type == 'image') {
            content.add({
              'type': 'input_image',
              'image_url': 'data:${att.mimeType};base64,${att.base64}',
            });
          } else {
            content.add({
              'type': 'input_text',
              'text': '[附件: ${att.type}] base64 数据已省略',
            });
          }
        }
        inputList.add({'role': m.role, 'content': content});
      } else {
        inputList.add({'role': m.role, 'content': m.content});
      }
    }

    final byteStream = await openSseStream(
      SseRequestConfig(
        url: url,
        headers: {'Authorization': 'Bearer $apiKey'},
        body: {'model': model, 'input': inputList, 'stream': true},
        cancelToken: cancelToken,
      ),
    );

    var sawContentDelta = false;
    var sawThinkingDelta = false;

    await for (final event in parseSseStream(byteStream)) {
      try {
        final previewChunks = extractChunksFromEventData(
          event.data,
          allowCompletedFallback: false,
        );
        for (final chunk in previewChunks) {
          if (chunk.content != null && chunk.content!.isNotEmpty) {
            sawContentDelta = true;
          }
          if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
            sawThinkingDelta = true;
          }
          yield chunk;
        }

        final json = jsonDecode(event.data) as Map<String, dynamic>;
        final type = json['type'] as String?;
        if (type == 'response.completed') {
          if (!sawContentDelta || !sawThinkingDelta) {
            final fallbackChunks = extractChunksFromEventData(
              event.data,
              allowCompletedFallback: true,
            );
            for (final chunk in fallbackChunks) {
              if (chunk.content != null &&
                  chunk.content!.isNotEmpty &&
                  sawContentDelta) {
                continue;
              }
              if (chunk.thinking != null &&
                  chunk.thinking!.isNotEmpty &&
                  sawThinkingDelta) {
                continue;
              }
              yield chunk;
            }
          }
          return;
        } else if ((type == 'response.output_item.done' ||
                type == 'response.content_part.done') &&
            !sawContentDelta &&
            !sawThinkingDelta) {
          final fallbackChunks = extractChunksFromEventData(
            event.data,
            allowCompletedFallback: true,
          );
          for (final chunk in fallbackChunks) {
            yield chunk;
          }
        }
      } catch (e) {
        debugPrint(
          '[OpenAI Response] SSE parse error: $e\nLine: ${event.data}',
        );
      }
    }
  }
}
