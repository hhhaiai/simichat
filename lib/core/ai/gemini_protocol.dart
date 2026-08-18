import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

class GeminiProtocol implements AiProtocol {
  @override
  Set<String> get nativeAttachmentTypes => const {'image', 'audio'};

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
    final encodedModel = Uri.encodeComponent(model.trim());
    final url = resolveGeminiEndpoint(
      baseUrl,
      'models/$encodedModel:streamGenerateContent?alt=sse',
    );

    final contents = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = m.role == 'assistant' ? 'model' : 'user';
      final parts = <Map<String, dynamic>>[];
      if (m.content.isNotEmpty) {
        parts.add({'text': m.content});
      }
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        for (final attachment in m.attachments!) {
          if (!nativeAttachmentTypes.contains(attachment.type)) {
            throwUnsupportedAttachment('gemini', attachment.type);
          }
        }
        final loaded = await loadAttachments(m.attachments!);
        for (final att in loaded) {
          if ((att.type == 'image' || att.type == 'audio') &&
              nativeAttachmentTypes.contains(att.type) &&
              att.base64.isNotEmpty) {
            parts.add({
              'inlineData': {'mimeType': att.mimeType, 'data': att.base64},
            });
          } else {
            throwUnsupportedAttachment('gemini', att.type);
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
      final json = _decodeEvent(event.data);
      _throwForTerminalEvent(json, eventType: event.eventType);
      final candidates = json['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final candidate = candidates.first;
        if (candidate is! Map) continue;
        final content = candidate['content'];
        final parts = content is Map ? content['parts'] as List? : null;
        if (parts != null) {
          for (final part in parts) {
            if (part is! Map) continue;
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
    }
  }

  static Map<String, dynamic> _decodeEvent(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) throw const FormatException('not an object');
      return decoded.cast<String, dynamic>();
    } catch (_) {
      throw ProtocolStreamException(
        'Gemini 流事件格式无效',
        protocol: 'gemini',
        kind: ProtocolStreamErrorKind.malformed,
        code: 'invalid_event',
      );
    }
  }

  static void _throwForTerminalEvent(
    Map<String, dynamic> json, {
    String? eventType,
  }) {
    final error = json['error'];
    if (error != null) {
      throw ProtocolStreamException(
        _remoteErrorMessage(error),
        protocol: 'gemini',
        kind: ProtocolStreamErrorKind.failed,
        code: _remoteErrorCode(error),
      );
    }
    final feedback = json['promptFeedback'];
    if (feedback is Map) {
      final reason = feedback['blockReason']?.toString();
      if (reason != null &&
          reason.isNotEmpty &&
          reason != 'BLOCK_REASON_UNSPECIFIED') {
        throw ProtocolStreamException(
          'Gemini 请求被安全策略拦截',
          protocol: 'gemini',
          kind: ProtocolStreamErrorKind.safety,
          code: reason,
        );
      }
    }
    final eventName = eventType?.toLowerCase();
    if (eventName == 'error' || eventName == 'failed') {
      throw ProtocolStreamException(
        _remoteErrorMessage(json),
        protocol: 'gemini',
        kind: ProtocolStreamErrorKind.failed,
        code: _remoteErrorCode(json) ?? eventName,
      );
    }
    final candidates = json['candidates'];
    if (candidates is! List) return;
    for (final candidate in candidates) {
      if (candidate is! Map) continue;
      final reason = candidate['finishReason']?.toString().toUpperCase();
      switch (reason) {
        case 'SAFETY':
        case 'BLOCKLIST':
        case 'PROHIBITED_CONTENT':
        case 'SPII':
        case 'RECITATION':
          throw ProtocolStreamException(
            'Gemini 响应被安全策略拦截',
            protocol: 'gemini',
            kind: ProtocolStreamErrorKind.safety,
            code: reason,
          );
        case 'MAX_TOKENS':
          throw ProtocolStreamException(
            'Gemini 响应未完整结束',
            protocol: 'gemini',
            kind: ProtocolStreamErrorKind.incomplete,
            code: reason,
          );
        case 'OTHER':
          throw ProtocolStreamException(
            'Gemini 上游生成失败',
            protocol: 'gemini',
            kind: ProtocolStreamErrorKind.failed,
            code: reason,
          );
      }
    }
  }

  static String _remoteErrorMessage(dynamic value) {
    if (value is Map) {
      final message = value['message'] ?? value['status'] ?? value['detail'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    if (value is String && value.trim().isNotEmpty) return value;
    return 'Gemini 上游返回错误';
  }

  static String? _remoteErrorCode(dynamic value) {
    if (value is Map) {
      final code = value['status'] ?? value['code'];
      if (code != null && code.toString().trim().isNotEmpty) {
        return code.toString();
      }
    }
    return null;
  }
}
