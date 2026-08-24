import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

class OpenAiResponseProtocol implements AiProtocol {
  // Responses has a first-class `input_file` part.  `document` is a real
  // protocol part, not a filename-only compatibility placeholder: the chat
  // provider suppresses text extraction for this route, so each document is
  // sent exactly once as base64 file data with its original safe filename.
  static const _nativeAttachmentTypes = {'image', 'pdf', 'document'};

  @override
  Set<String> get nativeAttachmentTypes => _nativeAttachmentTypes;

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

    if (type == 'response.output_text.done') {
      addChunk(content: json['text'] as String?);
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
    bool jsonResponse = false,
  }) async* {
    final url = resolveOpenAiEndpoint(baseUrl, 'responses');

    final inputList = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      inputList.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        for (final attachment in m.attachments!) {
          if (!nativeAttachmentTypes.contains(attachment.type)) {
            throwUnsupportedAttachment('openai_response', attachment.type);
          }
        }
        final loaded = await loadAttachments(m.attachments!);
        final content = <Map<String, dynamic>>[];
        if (m.content.isNotEmpty) {
          content.add({'type': 'input_text', 'text': m.content});
        }
        for (final att in loaded) {
          final attachmentType = att.type.trim().toLowerCase();
          if (attachmentType == 'image' &&
              nativeAttachmentTypes.contains('image')) {
            content.add({
              'type': 'input_image',
              'image_url': 'data:${att.mimeType};base64,${att.base64}',
            });
          } else if ((attachmentType == 'pdf' ||
                  attachmentType == 'document') &&
              nativeAttachmentTypes.contains(attachmentType)) {
            if (att.base64.isEmpty || att.fileName?.trim().isEmpty != false) {
              throw AttachmentLoadException(
                attachmentType: attachmentType,
                kind: AttachmentLoadFailureKind.empty,
                message: '附件内容为空，未发送；已保留输入和附件。',
              );
            }
            content.add({
              'type': 'input_file',
              'file_data': 'data:${att.mimeType};base64,${att.base64}',
              'filename': att.fileName,
            });
          } else if (attachmentType == 'audio') {
            throwUnsupportedAudioAttachment('openai_response');
          } else {
            throwUnsupportedAttachment('openai_response', attachmentType);
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
    var emittedCompletedFallback = false;

    List<AiChunk> fallbackChunksWithoutSeenDeltas(String data) {
      return extractChunksFromEventData(data, allowCompletedFallback: true)
          .where((chunk) {
            final hasContent = chunk.content?.isNotEmpty == true;
            final hasThinking = chunk.thinking?.isNotEmpty == true;
            return (hasContent && !sawContentDelta) ||
                (hasThinking && !sawThinkingDelta);
          })
          .toList(growable: false);
    }

    await for (final event in parseSseStream(byteStream)) {
      final json = _decodeEvent(event.data);
      _throwForTerminalEvent(json, eventType: event.eventType);
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

      final type = json['type'] as String?;
      if (type == 'response.completed') {
        if (!emittedCompletedFallback) {
          final fallbackChunks = fallbackChunksWithoutSeenDeltas(event.data);
          for (final chunk in fallbackChunks) {
            yield chunk;
          }
          emittedCompletedFallback = true;
        }
        return;
      }
      if ((type == 'response.output_item.done' ||
              type == 'response.content_part.done' ||
              type == 'response.output_text.done') &&
          !emittedCompletedFallback) {
        final fallbackChunks = fallbackChunksWithoutSeenDeltas(event.data);
        for (final chunk in fallbackChunks) {
          yield chunk;
        }
        emittedCompletedFallback = fallbackChunks.isNotEmpty;
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
        'OpenAI Responses 流事件格式无效',
        protocol: 'openai_response',
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
    final error =
        json['error'] ??
        (json['response'] is Map ? (json['response'] as Map)['error'] : null);
    if (error != null || type == 'error' || type == 'response.error') {
      throw ProtocolStreamException(
        _remoteErrorMessage(error ?? json),
        protocol: 'openai_response',
        kind: ProtocolStreamErrorKind.failed,
        code: _remoteErrorCode(error ?? json),
      );
    }
    if (type == 'response.refusal.delta' || type == 'response.refusal.done') {
      throw ProtocolStreamException(
        'OpenAI Responses 响应被安全策略拒绝',
        protocol: 'openai_response',
        kind: ProtocolStreamErrorKind.safety,
        code: type,
      );
    }
    if (type == 'response.failed' || type == 'response.incomplete') {
      throw ProtocolStreamException(
        type == 'response.incomplete'
            ? 'OpenAI Responses 响应未完整结束'
            : 'OpenAI Responses 上游生成失败',
        protocol: 'openai_response',
        kind: type == 'response.incomplete'
            ? ProtocolStreamErrorKind.incomplete
            : ProtocolStreamErrorKind.failed,
        code: type,
      );
    }
    final response = json['response'];
    if (response is! Map) return;
    final status = response['status']?.toString().toLowerCase();
    if (status == 'failed' || status == 'incomplete') {
      throw ProtocolStreamException(
        status == 'incomplete'
            ? 'OpenAI Responses 响应未完整结束'
            : 'OpenAI Responses 上游生成失败',
        protocol: 'openai_response',
        kind: status == 'incomplete'
            ? ProtocolStreamErrorKind.incomplete
            : ProtocolStreamErrorKind.failed,
        code: status,
      );
    }
  }

  static String _remoteErrorMessage(dynamic value) {
    if (value is Map) {
      final message = value['message'] ?? value['detail'] ?? value['error'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    if (value is String && value.trim().isNotEmpty) return value;
    return 'OpenAI Responses 上游返回错误';
  }

  static String? _remoteErrorCode(dynamic value) {
    if (value is Map) {
      final code = value['code'] ?? value['type'] ?? value['status'];
      if (code != null && code.toString().trim().isNotEmpty) {
        return code.toString();
      }
    }
    return null;
  }
}
