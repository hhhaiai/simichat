import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

class ClaudeProtocol implements AiProtocol {
  @override
  Set<String> get nativeAttachmentTypes => const {'image'};

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
    final url = resolveClaudeEndpoint(baseUrl, 'messages');

    final msgList = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m.role == 'system') continue;
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        for (final attachment in m.attachments!) {
          if (!nativeAttachmentTypes.contains(attachment.type)) {
            throwUnsupportedAttachment('claude', attachment.type);
          }
        }
        final loaded = await loadAttachments(m.attachments!);
        final content = <Map<String, dynamic>>[];
        if (m.content.isNotEmpty) {
          content.add({'type': 'text', 'text': m.content});
        }
        for (final att in loaded) {
          if (att.type == 'image' && nativeAttachmentTypes.contains('image')) {
            content.add({
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': att.mimeType,
                'data': att.base64,
              },
            });
          } else {
            throwUnsupportedAttachment('claude', att.type);
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
      final json = _decodeEvent(event.data);
      _throwForTerminalEvent(json, eventType: event.eventType);
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
      } else if (type == 'message_delta') {
        final delta = json['delta'];
        final stopReason = delta is Map
            ? delta['stop_reason']?.toString().toLowerCase()
            : null;
        if (stopReason == 'max_tokens' || stopReason == 'length') {
          throw ProtocolStreamException(
            'Claude 响应未完整结束',
            protocol: 'claude',
            kind: ProtocolStreamErrorKind.incomplete,
            code: stopReason,
          );
        }
      } else if (type == 'message_stop') {
        return;
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
        'Claude 流事件格式无效',
        protocol: 'claude',
        kind: ProtocolStreamErrorKind.malformed,
        code: 'invalid_event',
      );
    }
  }

  static void _throwForTerminalEvent(
    Map<String, dynamic> json, {
    String? eventType,
  }) {
    final type = (json['type'] ?? eventType)?.toString().toLowerCase() ?? '';
    final error = json['error'];
    if (type == 'error' || error != null) {
      throw ProtocolStreamException(
        _remoteErrorMessage(error ?? json),
        protocol: 'claude',
        kind: ProtocolStreamErrorKind.failed,
        code: _remoteErrorCode(error ?? json),
      );
    }
    final blockReason = json['stop_reason']?.toString().toLowerCase();
    if (blockReason == 'refusal' || blockReason == 'safety') {
      throw ProtocolStreamException(
        'Claude 响应被安全策略拒绝',
        protocol: 'claude',
        kind: ProtocolStreamErrorKind.safety,
        code: blockReason,
      );
    }
    final message = json['message'];
    if (message is Map) {
      final stopReason = message['stop_reason']?.toString().toLowerCase();
      if (stopReason == 'refusal' ||
          stopReason == 'safety' ||
          stopReason == 'blocked') {
        throw ProtocolStreamException(
          'Claude 响应被安全策略拒绝',
          protocol: 'claude',
          kind: ProtocolStreamErrorKind.safety,
          code: stopReason,
        );
      }
      if (stopReason == 'max_tokens' || stopReason == 'length') {
        throw ProtocolStreamException(
          'Claude 响应未完整结束',
          protocol: 'claude',
          kind: ProtocolStreamErrorKind.incomplete,
          code: stopReason,
        );
      }
    }
    final delta = json['delta'];
    if (delta is Map) {
      final stopReason = delta['stop_reason']?.toString().toLowerCase();
      if (stopReason == 'refusal' ||
          stopReason == 'safety' ||
          stopReason == 'blocked') {
        throw ProtocolStreamException(
          'Claude 响应被安全策略拒绝',
          protocol: 'claude',
          kind: ProtocolStreamErrorKind.safety,
          code: stopReason,
        );
      }
    }
  }

  static String _remoteErrorMessage(dynamic value) {
    if (value is Map) {
      final message = value['message'] ?? value['detail'] ?? value['error'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    if (value is String && value.trim().isNotEmpty) return value;
    return 'Claude 上游返回错误';
  }

  static String? _remoteErrorCode(dynamic value) {
    if (value is Map) {
      final code = value['type'] ?? value['code'] ?? value['status'];
      if (code != null && code.toString().trim().isNotEmpty) {
        return code.toString();
      }
    }
    return null;
  }
}
