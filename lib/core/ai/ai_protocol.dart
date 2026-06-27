import 'dart:async';
import 'package:dio/dio.dart' show CancelToken;

/// 统一的 AI 消息格式
class AiMessage {
  final String role; // user | assistant | system
  final String content;
  final List<Attachment>? attachments;

  const AiMessage({
    required this.role,
    required this.content,
    this.attachments,
  });
}

class Attachment {
  final String type; // image | pdf | audio | document
  final String path;
  final String? mimeType;

  const Attachment({required this.type, required this.path, this.mimeType});
}

/// 流式响应块，携带正文和可选的思考内容
class AiChunk {
  final String? content;
  final String? thinking;

  const AiChunk({this.content, this.thinking});
}

/// AI 协议适配器接口
abstract class AiProtocol {
  /// 流式发送，返回 token 增量流
  Stream<AiChunk> sendStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
    CancelToken? cancelToken,
  });
}
