import 'dart:async';
import 'package:dio/dio.dart' show CancelToken;
import 'ai_protocol.dart';
import 'openai_chat_protocol.dart';
import 'openai_response_protocol.dart';
import 'claude_protocol.dart';
import 'gemini_protocol.dart';
import 'ollama_protocol.dart';

/// AI 服务：根据协议类型选择对应的适配器
class AiService {
  static final Map<String, AiProtocol> _protocols = {
    'openai_chat': OpenAiChatProtocol(),
    'openai_response': OpenAiResponseProtocol(),
    'claude': ClaudeProtocol(),
    'gemini': GeminiProtocol(),
    'ollama': OllamaProtocol(),
  };

  static AiProtocol getProtocol(String protocol) {
    final p = _protocols[protocol];
    if (p == null) throw UnsupportedError('Unknown protocol: $protocol');
    return p;
  }

  /// 流式发送消息
  static Stream<AiChunk> sendMessage({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
    CancelToken? cancelToken,
    bool jsonResponse = false,
  }) {
    return getProtocol(protocol).sendStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      systemPrompt: systemPrompt,
      cancelToken: cancelToken,
      jsonResponse: jsonResponse,
    );
  }
}
