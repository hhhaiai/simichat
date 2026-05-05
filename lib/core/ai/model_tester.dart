import 'ai_protocol.dart';
import 'openai_chat_protocol.dart';
import 'openai_response_protocol.dart';
import 'claude_protocol.dart';
import 'gemini_protocol.dart';
import 'ollama_protocol.dart';

/// 模型连通性测试工具
///
/// 发送一条极简消息（"Hi"）验证模型是否可用。
/// 返回 null 表示连接成功，否则返回错误信息。
class ModelTester {
  /// 测试指定模型是否可用。
  ///
  /// [protocol] 协议类型（openai_chat / openai_response / claude / gemini / ollama）
  /// [baseUrl] 渠道 API 地址
  /// [apiKey] API 密钥（Ollama 可传空字符串）
  /// [model] 模型名称
  static Future<String?> testModel({
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
      final messages = [
        AiMessage(role: 'user', content: 'Hi'),
      ];

      final stream = adapter.sendStream(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
      );

      // 等待第一个有效 chunk 即判定成功
      await for (final chunk in stream) {
        if (chunk.content != null && chunk.content!.isNotEmpty) {
          return null; // 成功
        }
        if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
          return null; // thinking 内容也算响应
        }
      }

      // 流结束却没有任何有效内容
      return '模型未返回任何响应';
    } catch (e) {
      return e.toString();
    }
  }
}
