import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

class OpenAiResponseProtocol implements AiProtocol {
  @override
  Stream<AiChunk> sendStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
  }) async* {
    final normalized = normalizeUrl(baseUrl);
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
            content.add({'type': 'input_text', 'text': '[附件: ${att.type}] base64 数据已省略'});
          }
        }
        inputList.add({'role': m.role, 'content': content});
      } else {
        inputList.add({'role': m.role, 'content': m.content});
      }
    }

    final byteStream = await openSseStream(SseRequestConfig(
      url: url,
      headers: {'Authorization': 'Bearer $apiKey'},
      body: {'model': model, 'input': inputList, 'stream': true},
    ));

    try {
      await for (final event in parseSseStream(byteStream)) {
        try {
          final json = jsonDecode(event.data) as Map<String, dynamic>;
          final type = json['type'] as String?;
          if (type == 'response.output_text.delta') {
            final delta = json['delta'] as String?;
            if (delta != null) yield AiChunk(content: delta);
          } else if (type == 'response.reasoning_text.delta') {
            final delta = json['delta'] as String?;
            if (delta != null) yield AiChunk(thinking: delta);
          } else if (type == 'response.completed') {
            return;
          }
        } catch (e) {
          debugPrint('[OpenAI Response] SSE parse error: $e\nLine: ${event.data}');
        }
      }
    } finally {}
  }
}
