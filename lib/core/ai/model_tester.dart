import 'dart:async';
import 'ai_protocol.dart';
import 'model_capability.dart';
import 'openai_chat_protocol.dart';
import 'openai_response_protocol.dart';
import 'openai_embedding_client.dart';
import 'claude_protocol.dart';
import 'gemini_protocol.dart';
import 'ollama_protocol.dart';

/// 模型连通性测试工具。
class ModelTester {
  /// 测试指定模型是否可用（30 秒超时）。
  static Future<String?> testModel({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
    String capability = ModelCapability.chat,
  }) async {
    if (ModelCapability.isEmbedding(capability)) {
      return _testEmbeddingModel(
        protocol: protocol,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
      );
    }
    return _testChatModel(
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
  }

  static Future<String?> _testEmbeddingModel({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    if (protocol != 'openai_chat' && protocol != 'openai_response') {
      return '当前协议暂不支持 Embedding 测试';
    }
    try {
      final result = await const OpenAiEmbeddingClient()
          .createEmbeddings(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            input: const ['ping'],
          )
          .timeout(const Duration(seconds: 30));
      if (result.vectors.isEmpty || result.vectors.first.isEmpty) {
        return 'Embedding 模型未返回向量';
      }
      return null;
    } on TimeoutException {
      return '测试超时（30秒），请检查网络或模型状态';
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> _testChatModel({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final AiProtocol adapter;
    switch (protocol) {
      case 'openai_chat':
        adapter = OpenAiChatProtocol();
        break;
      case 'openai_response':
        adapter = OpenAiResponseProtocol();
        break;
      case 'claude':
        adapter = ClaudeProtocol();
        break;
      case 'gemini':
        adapter = GeminiProtocol();
        break;
      case 'ollama':
        adapter = OllamaProtocol();
        break;
      default:
        return '不支持的协议: $protocol';
    }

    try {
      final messages = [AiMessage(role: 'user', content: 'Hi')];

      final stream = adapter.sendStream(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
      );

      final result = await stream
          .firstWhere(
            (chunk) =>
                (chunk.content != null && chunk.content!.isNotEmpty) ||
                (chunk.thinking != null && chunk.thinking!.isNotEmpty),
          )
          .timeout(const Duration(seconds: 30));

      if ((result.content != null && result.content!.isNotEmpty) ||
          (result.thinking != null && result.thinking!.isNotEmpty)) {
        return null;
      }
      return '模型未返回任何响应';
    } on TimeoutException {
      return '测试超时（30秒），请检查网络或模型状态';
    } catch (e) {
      return e.toString();
    }
  }
}
