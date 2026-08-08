import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

const ollamaConnectTimeout = Duration(seconds: 15);
const ollamaIdleTimeout = Duration(minutes: 5);

class OllamaProtocol implements AiProtocol {
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
    final url = '$normalized/api/chat';

    final msgList = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      msgList.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      if (m.attachments != null && m.attachments!.isNotEmpty) {
        final loaded = await loadAttachments(m.attachments!);
        final images = <String>[];
        for (final att in loaded) {
          if (att.type == 'image') {
            images.add(att.base64);
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
        final compactError = errorBody.length > 1024
            ? '${errorBody.substring(0, 1024)}...'
            : errorBody;
        throw Exception('Ollama error ${response.statusCode}: $compactError');
      }

      // Ollama returns newline-delimited JSON (not SSE)
      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(ollamaIdleTimeout);

      await for (final line in stream) {
        if (cancelToken?.isCancelled ?? false) return;
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final done = json['done'] as bool? ?? false;
          final message = json['message'] as Map<String, dynamic>?;
          if (message != null) {
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
        } catch (e) {
          // 不打印原始响应，避免把用户内容或模型输出写入日志。
          debugPrint('[Ollama] Ignored malformed NDJSON chunk: $e');
        }
      }
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) {
        return;
      }
      if (e is TimeoutException) {
        throw Exception('Ollama 响应超时，请检查服务是否已启动或模型是否正在加载');
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 获取 Ollama 可用模型列表
  static Future<List<String>> fetchModels(
    String baseUrl, {
    String apiKey = '',
  }) async {
    final normalized = normalizeUrl(baseUrl);
    final url = '$normalized/api/tags';
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
        final compactError = response.body.length > 1024
            ? '${response.body.substring(0, 1024)}...'
            : response.body;
        throw Exception(
          'Ollama tags error ${response.statusCode}: $compactError',
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
}
