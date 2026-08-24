import 'dart:async';
import 'package:dio/dio.dart' show CancelToken;

export 'protocol_stream_exception.dart';

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
  final String type; // image | pdf | audio | video | document
  final String path;
  final String? mimeType;

  /// 用户可见的原始文件名。协议适配器在原生 file part 中必须使用它，
  /// 不能从应用私有归档路径反推出带随机前缀的名字。
  final String? fileName;

  const Attachment({
    required this.type,
    required this.path,
    this.mimeType,
    this.fileName,
  });
}

/// 流式响应块，携带正文和可选的思考内容
class AiChunk {
  final String? content;
  final String? thinking;

  const AiChunk({this.content, this.thinking});
}

/// AI 协议适配器接口
abstract class AiProtocol {
  /// Attachment parts emitted by this adapter as real protocol input.
  ///
  /// This is deliberately a protocol contract, not a model-name heuristic.
  /// In particular, an `audio` model label must not make an adapter emit an
  /// `input_audio` part unless the adapter explicitly declares it here.
  Set<String> get nativeAttachmentTypes;

  /// 流式发送，返回 token 增量流
  Stream<AiChunk> sendStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
    CancelToken? cancelToken,
    bool jsonResponse = false,
  });
}
