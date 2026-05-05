import 'dart:async';
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
  /// 测试指定模型是否可用（30 秒超时）
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

      // 30 秒超时
      final result = await stream
          .firstWhere(
            (chunk) =>
                (chunk.content != null && chunk.content!.isNotEmpty) ||
                (chunk.thinking != null && chunk.thinking!.isNotEmpty),
          )
          .timeout(const Duration(seconds: 30));

      // 收到有效内容即成功
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
