import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

class ClaudeProtocol implements AiProtocol {
  @override
  Stream<AiChunk> sendStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
    CancelToken? cancelToken,
  }) async* {
    final normalized = normalizeUrl(baseUrl);
    final url = '$normalized/v1/messages';

    final msgList = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m.role == 'system') continue;
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        final loaded = await loadAttachments(m.attachments!);
        final content = <Map<String, dynamic>>[];
        if (m.content.isNotEmpty) {
          content.add({'type': 'text', 'text': m.content});
        }
        for (final att in loaded) {
          if (att.type == 'image') {
            content.add({
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': att.mimeType,
                'data': att.base64,
              },
            });
          } else {
            content.add({
              'type': 'text',
              'text': _unsupportedAttachmentText(att.type),
            });
          }
        }
        msgList.add({'role': m.role, 'content': content});
      } else {
        msgList.add({'role': m.role, 'content': m.content});
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 8192,
      'messages': msgList,
      'stream': true,
    };
    if (systemPrompt != null) {
      body['system'] = systemPrompt;
    }

    final byteStream = await openSseStream(
      SseRequestConfig(
        url: url,
        headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
        body: body,
        cancelToken: cancelToken,
      ),
    );

    await for (final event in parseSseStream(byteStream)) {
      try {
        final json = jsonDecode(event.data) as Map<String, dynamic>;
        final type = json['type'] as String?;
        if (type == 'content_block_delta') {
          final delta = json['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          final deltaType = delta['type'] as String?;
          if (deltaType == 'thinking_delta') {
            final thinking = delta['thinking'] as String?;
            if (thinking != null) yield AiChunk(thinking: thinking);
          } else if (deltaType == 'text_delta') {
            final text = delta['text'] as String?;
            if (text != null) yield AiChunk(content: text);
          }
        } else if (type == 'message_stop') {
          return;
        }
      } catch (e) {
        debugPrint('[Claude] SSE parse error: $e\nLine: ${event.data}');
      }
    }
  }
}

String _unsupportedAttachmentText(String type) {
  if (type == 'audio') {
    return '[附件: audio] 当前 Claude 协议不支持直接音频输入，请先转写后发送，或切换到支持音频输入的模型。';
  }
  return '[附件: $type] 当前协议不支持直接上传该类型附件。';
}
