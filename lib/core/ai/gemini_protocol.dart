import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

class GeminiProtocol implements AiProtocol {
  @override
  Stream<AiChunk> sendStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
    CancelToken? cancelToken,
    bool jsonResponse = false,
  }) async* {
    final normalized = normalizeUrl(baseUrl);
    final url =
        '$normalized/v1beta/models/$model:streamGenerateContent?alt=sse';

    final contents = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = m.role == 'assistant' ? 'model' : 'user';
      final parts = <Map<String, dynamic>>[];
      if (m.content.isNotEmpty) {
        parts.add({'text': m.content});
      }
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        final loaded = await loadAttachments(m.attachments!);
        for (final att in loaded) {
          if ((att.type == 'image' || att.type == 'audio') &&
              att.base64.isNotEmpty) {
            parts.add({
              'inlineData': {'mimeType': att.mimeType, 'data': att.base64},
            });
          } else {
            parts.add({'text': _unsupportedAttachmentText(att.type)});
          }
        }
      }
      contents.add({'role': role, 'parts': parts});
    }

    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': {},
    };
    if (systemPrompt != null) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemPrompt},
        ],
      };
    }

    final byteStream = await openSseStream(
      SseRequestConfig(
        url: url,
        headers: {'x-goog-api-key': apiKey},
        body: body,
        cancelToken: cancelToken,
      ),
    );

    await for (final event in parseSseStream(byteStream)) {
      try {
        final json = jsonDecode(event.data) as Map<String, dynamic>;
        final candidates = json['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null) {
            for (final part in parts) {
              final text = part['text'] as String?;
              if (text == null) continue;
              final isThought = part['thought'] == true;
              if (isThought) {
                yield AiChunk(thinking: text);
              } else {
                yield AiChunk(content: text);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Gemini] SSE parse error: $e\nLine: ${event.data}');
      }
    }
  }
}

String _unsupportedAttachmentText(String type) {
  if (type == 'audio') {
    return '[附件: audio] 当前 Gemini 模型不支持直接音频输入，请先转写后发送，或切换到支持音频输入的 Gemini 模型。';
  }
  return '[附件: $type] 当前协议不支持直接上传该类型附件。';
}
