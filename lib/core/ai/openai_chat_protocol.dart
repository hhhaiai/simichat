import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken, Options;
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'http_helper.dart';
import 'sse_helper.dart';

class OpenAiChatProtocol implements AiProtocol {
  static const _nativeAttachmentTypes = {'image', 'audio'};

  @override
  Set<String> get nativeAttachmentTypes => _nativeAttachmentTypes;

  static String? _extractTextValue(dynamic value) {
    if (value is String) return value;
    if (value is List) {
      final texts = value
          .map((item) {
            if (item is String) return item;
            if (item is Map) {
              final text = item['text'] ?? item['content'] ?? item['value'];
              return text is String ? text : null;
            }
            return null;
          })
          .whereType<String>()
          .toList();
      if (texts.isNotEmpty) return texts.join();
    }
    return null;
  }

  static List<AiChunk> extractChunksFromEventData(String eventData) {
    final json = jsonDecode(eventData) as Map<String, dynamic>;
    final chunks = <AiChunk>[];

    void addChunk({String? content, String? thinking}) {
      if ((content != null && content.isNotEmpty) ||
          (thinking != null && thinking.isNotEmpty)) {
        chunks.add(AiChunk(content: content, thinking: thinking));
      }
    }

    final choices = json['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      for (final choice in choices.whereType<Map>()) {
        final delta = (choice['delta'] as Map?)?.cast<String, dynamic>();
        final message = (choice['message'] as Map?)?.cast<String, dynamic>();

        if (delta != null) {
          addChunk(thinking: _extractTextValue(delta['reasoning_content']));
          addChunk(thinking: _extractTextValue(delta['reasoning']));
          addChunk(content: _extractTextValue(delta['content']));
        }

        if (message != null) {
          addChunk(thinking: _extractTextValue(message['reasoning_content']));
          addChunk(thinking: _extractTextValue(message['reasoning']));
          addChunk(content: _extractTextValue(message['content']));
        }
      }
    }

    addChunk(content: _extractTextValue(json['content']));
    addChunk(content: _extractTextValue(json['output_text']));
    addChunk(thinking: _extractTextValue(json['reasoning_content']));

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
    final content = _extractTextValue(message['content']) ?? '';
    final thinking =
        _extractTextValue(message['reasoning_content']) ??
        _extractTextValue(message['reasoning']);
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
    final url = resolveOpenAiEndpoint(baseUrl, 'chat/completions');

    final msgList = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      msgList.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        for (final attachment in m.attachments!) {
          if (!_nativeAttachmentTypes.contains(attachment.type)) {
            throwUnsupportedAttachment('openai_chat', attachment.type);
          }
        }
        final loaded = await loadAttachments(m.attachments!);
        final content = <Map<String, dynamic>>[];
        if (m.content.isNotEmpty) {
          content.add({'type': 'text', 'text': m.content});
        }
        for (final att in loaded) {
          if (att.type == 'image' && _nativeAttachmentTypes.contains('image')) {
            content.add({
              'type': 'image_url',
              'image_url': {'url': 'data:${att.mimeType};base64,${att.base64}'},
            });
          } else if (att.type == 'audio' &&
              _nativeAttachmentTypes.contains('audio')) {
            content.add(buildOpenAiChatAudioPart(att));
          } else {
            throwUnsupportedAttachment('openai_chat', att.type);
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
    bool jsonResponse = false,
  }) async* {
    final url = resolveOpenAiEndpoint(baseUrl, 'chat/completions');

    final msgList = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      msgList.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        for (final attachment in m.attachments!) {
          if (!nativeAttachmentTypes.contains(attachment.type)) {
            throwUnsupportedAttachment('openai_chat', attachment.type);
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
              'type': 'image_url',
              'image_url': {'url': 'data:${att.mimeType};base64,${att.base64}'},
            });
          } else if (att.type == 'audio' &&
              nativeAttachmentTypes.contains('audio')) {
            content.add(buildOpenAiChatAudioPart(att));
          } else {
            throwUnsupportedAttachment('openai_chat', att.type);
          }
        }
        msgList.add({'role': m.role, 'content': content});
      } else {
        msgList.add({'role': m.role, 'content': m.content});
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': msgList,
      'stream': true,
      if (jsonResponse) 'response_format': {'type': 'json_object'},
    };

    try {
      final byteStream = await openSseStream(
        SseRequestConfig(
          url: url,
          headers: {'Authorization': 'Bearer $apiKey'},
          body: body,
          cancelToken: cancelToken,
        ),
      );

      await for (final event in parseSseStream(byteStream)) {
        final json = _decodeEvent(event.data);
        _throwForTerminalEvent(json, eventType: event.eventType);
        for (final chunk in extractChunksFromEventData(event.data)) {
          yield chunk;
        }
      }
    } on ProtocolStreamException {
      // A CancelToken can be cancelled before Dio has received response
      // headers. Treat that path the same as cancellation of the response
      // stream; callers should not see a retryable error for an intentional
      // stop.
      if (cancelToken?.isCancelled ?? false) return;
      rethrow;
    }
  }

  static Map<String, dynamic> _decodeEvent(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) throw const FormatException('not an object');
      return decoded.cast<String, dynamic>();
    } catch (_) {
      throw ProtocolStreamException(
        'OpenAI Chat 流事件格式无效',
        protocol: 'openai_chat',
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
        protocol: 'openai_chat',
        kind: ProtocolStreamErrorKind.failed,
        code: _remoteErrorCode(error),
      );
    }
    final type = (json['type'] ?? eventType)?.toString().toLowerCase();
    if (type == 'error' || type == 'response.error') {
      throw ProtocolStreamException(
        _remoteErrorMessage(json),
        protocol: 'openai_chat',
        kind: ProtocolStreamErrorKind.failed,
        code: _remoteErrorCode(json),
      );
    }

    final choices = json['choices'];
    if (choices is! List) return;
    for (final rawChoice in choices) {
      if (rawChoice is! Map) continue;
      final reason = rawChoice['finish_reason']?.toString().toLowerCase();
      switch (reason) {
        case 'content_filter':
        case 'safety':
        case 'blocked':
          throw ProtocolStreamException(
            'OpenAI Chat 响应被安全策略拦截',
            protocol: 'openai_chat',
            kind: ProtocolStreamErrorKind.safety,
            code: reason,
          );
        case 'length':
        case 'max_tokens':
        case 'incomplete':
          throw ProtocolStreamException(
            'OpenAI Chat 响应未完整结束',
            protocol: 'openai_chat',
            kind: ProtocolStreamErrorKind.incomplete,
            code: reason,
          );
        case 'error':
        case 'failed':
          throw ProtocolStreamException(
            'OpenAI Chat 上游生成失败',
            protocol: 'openai_chat',
            kind: ProtocolStreamErrorKind.failed,
            code: reason,
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
    return 'OpenAI Chat 上游返回错误';
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
