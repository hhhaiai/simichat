import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_protocol.dart';
import 'attachment_helper.dart';
import 'sse_helper.dart';

class OllamaProtocol implements AiProtocol {
  @override
  Stream<AiChunk> sendStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
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
        final msg = <String, dynamic>{
          'role': m.role,
          'content': m.content,
        };
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
    });

    final request = http.Request('POST', Uri.parse(url));
    request.headers['Content-Type'] = 'application/json';
    request.body = body;

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('Ollama error ${response.statusCode}: $errorBody');
      }

      // Ollama returns newline-delimited JSON (not SSE)
      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final done = json['done'] as bool? ?? false;
          final message = json['message'] as Map<String, dynamic>?;
          if (message != null) {
            final content = message['content'] as String?;
            if (content != null && content.isNotEmpty) {
              yield AiChunk(content: content);
            }
          }
          if (done) return;
        } catch (e) {
          debugPrint('[Ollama] Parse error: $e\nLine: $line');
        }
      }
    } finally {
      client.close();
    }
  }

  /// 获取 Ollama 可用模型列表
  static Future<List<String>> fetchModels(String baseUrl) async {
    final normalized = normalizeUrl(baseUrl);
    final url = '$normalized/api/tags';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Ollama tags error ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final models = json['models'] as List?;
    if (models == null) return [];
    return models.map((m) => (m as Map<String, dynamic>)['name'] as String).toList();
  }
}
