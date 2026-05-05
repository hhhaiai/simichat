import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

class OpenAiChatProtocol implements AiProtocol {
  @override
  Stream<AiChunk> sendStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
  }) async* {
    final normalized = normalizeUrl(baseUrl);
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
            content.add({'type': 'text', 'text': '[附件: ${att.type}] base64 数据已省略'});
          }
        }
        msgList.add({'role': m.role, 'content': content});
      } else {
        msgList.add({'role': m.role, 'content': m.content});
      }
    }

    final byteStream = await openSseStream(SseRequestConfig(
      url: url,
      headers: {'Authorization': 'Bearer $apiKey'},
      body: {'model': model, 'messages': msgList, 'stream': true},
    ));

    try {
      await for (final event in parseSseStream(byteStream)) {
        try {
          final json = jsonDecode(event.data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;

            // 检查 reasoning_content（DeepSeek R1 等模型）
            final reasoning = delta['reasoning_content'] as String?;
            final content = delta['content'] as String?;

            if (reasoning != null) {
              yield AiChunk(thinking: reasoning);
            }
            if (content != null) {
              yield AiChunk(content: content);
            }
          }
        } catch (e) {
          debugPrint('[OpenAI Chat] SSE parse error: $e\nLine: ${event.data}');
        }
      }
    } finally {}
  }
}
