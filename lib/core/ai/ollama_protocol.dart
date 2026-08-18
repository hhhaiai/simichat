import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'package:http/http.dart' as http;
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

const ollamaConnectTimeout = Duration(seconds: 15);
const ollamaIdleTimeout = Duration(minutes: 5);

class OllamaProtocol implements AiProtocol {
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
    final url = resolveOllamaEndpoint(baseUrl, 'api/chat');

    final msgList = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      msgList.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        for (final attachment in m.attachments!) {
          if (!nativeAttachmentTypes.contains(attachment.type)) {
            throwUnsupportedAttachment('ollama', attachment.type);
          }
        }
        final loaded = await loadAttachments(m.attachments!);
        final images = <String>[];
        for (final att in loaded) {
          if (att.type == 'image' && nativeAttachmentTypes.contains('image')) {
            images.add(att.base64);
          } else {
            throwUnsupportedAttachment('ollama', att.type);
          }
        }
        final msg = <String, dynamic>{'role': m.role, 'content': m.content};
        if (images.isNotEmpty) {
          msg['images'] = images;
        }
        msgList.add(msg);
      } else {
        msgList.add({'role': m.role, 'content': m.content});
      }
    }

    final body = jsonEncode({
      'model': model,
      'messages': msgList,
      'stream': true,
      if (jsonResponse) ...{
        'format': 'json',
        'think': false,
        'options': {'temperature': 0},
      },
    });

    final request = http.Request('POST', Uri.parse(url));
    request.headers['Content-Type'] = 'application/json';
    final token = apiKey.trim();
    if (token.isNotEmpty) {
      // 本地 Ollama 通常不需要鉴权，但允许用户通过反向代理暴露一个
      // 需要 Bearer 鉴权的 Ollama 兼容端点。
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.body = body;

    final client = http.Client();
    if (cancelToken != null) {
      unawaited(
        cancelToken.whenCancel.then((_) {
          client.close();
        }),
      );
    }
    try {
      final response = await client.send(request).timeout(ollamaConnectTimeout);
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString().timeout(
          ollamaConnectTimeout,
        );
        throw ProtocolStreamException(
          _safeRemoteError(errorBody, statusCode: response.statusCode),
          protocol: 'ollama',
          kind: ProtocolStreamErrorKind.remote,
          code: 'http_${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      // Ollama returns newline-delimited JSON (not SSE)
      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(ollamaIdleTimeout);

      await for (final line in stream) {
        if (cancelToken?.isCancelled ?? false) return;
        if (line.trim().isEmpty) continue;
        final Map<String, dynamic> json;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) throw const FormatException('not an object');
          json = decoded.cast<String, dynamic>();
        } catch (_) {
          throw ProtocolStreamException(
            'Ollama NDJSON 流事件格式无效',
            protocol: 'ollama',
            kind: ProtocolStreamErrorKind.malformed,
            code: 'invalid_ndjson',
          );
        }

        final error = json['error'];
        if (error != null) {
          throw ProtocolStreamException(
            _safeRemoteError(error),
            protocol: 'ollama',
            kind: ProtocolStreamErrorKind.failed,
            code: 'upstream_error',
          );
        }
        final doneReason = json['done_reason']?.toString().toLowerCase();
        if (doneReason == 'length' || doneReason == 'max_tokens') {
          throw ProtocolStreamException(
            'Ollama 响应未完整结束',
            protocol: 'ollama',
            kind: ProtocolStreamErrorKind.incomplete,
            code: doneReason,
          );
        }
        if (doneReason == 'error' || doneReason == 'failed') {
          throw ProtocolStreamException(
            'Ollama 上游生成失败',
            protocol: 'ollama',
            kind: ProtocolStreamErrorKind.failed,
            code: doneReason,
          );
        }

        final done = json['done'] as bool? ?? false;
        final message = json['message'];
        if (message is Map) {
          final content = message['content']?.toString();
          final thinking = message['thinking']?.toString();
          if ((content != null && content.isNotEmpty) ||
              (thinking != null && thinking.isNotEmpty)) {
            yield AiChunk(
              content: content?.isNotEmpty == true ? content : null,
              thinking: thinking?.isNotEmpty == true ? thinking : null,
            );
          }
        }
        if (done) return;
      }
    } on ProtocolStreamException {
      if (cancelToken?.isCancelled ?? false) return;
      rethrow;
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) {
        return;
      }
      if (e is TimeoutException) {
        throw ProtocolStreamException(
          'Ollama 响应超时，请检查服务是否已启动或模型是否正在加载',
          protocol: 'ollama',
          kind: ProtocolStreamErrorKind.transport,
          code: 'timeout',
        );
      }
      throw ProtocolStreamException(
        e.toString(),
        protocol: 'ollama',
        kind: ProtocolStreamErrorKind.transport,
      );
    } finally {
      client.close();
    }
  }

  /// 获取 Ollama 可用模型列表
  static Future<List<String>> fetchModels(
    String baseUrl, {
    String apiKey = '',
  }) async {
    final url = resolveOllamaEndpoint(baseUrl, 'api/tags');
    final client = http.Client();
    try {
      final headers = <String, String>{};
      final token = apiKey.trim();
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await client
          .get(Uri.parse(url), headers: headers)
          .timeout(ollamaConnectTimeout);
      if (response.statusCode != 200) {
        throw ProtocolStreamException(
          _safeRemoteError(response.body, statusCode: response.statusCode),
          protocol: 'ollama',
          kind: ProtocolStreamErrorKind.remote,
          code: 'http_${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final models = json['models'] as List?;
      if (models == null) return [];
      return models
          .whereType<Map<String, dynamic>>()
          .map((m) => m['name']?.toString())
          .whereType<String>()
          .where((name) => name.trim().isNotEmpty)
          .toList();
    } on TimeoutException {
      throw Exception('Ollama 连接超时，请检查服务是否已启动和 Base URL');
    } finally {
      client.close();
    }
  }

  static String _safeRemoteError(dynamic value, {int? statusCode}) {
    if (statusCode == 401) return 'Ollama API Key 无效';
    if (statusCode == 403) return 'Ollama 访问被拒绝';
    if (statusCode == 404) return 'Ollama 接口不存在，请检查 Base URL';
    if (statusCode != null && statusCode >= 500) {
      return 'Ollama 服务暂时不可用';
    }
    if (value is Map) {
      final message = value['error'] ?? value['message'] ?? value['detail'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return _safeRemoteError(decoded);
      } catch (_) {}
    }
    return 'Ollama 上游返回错误';
  }
}
