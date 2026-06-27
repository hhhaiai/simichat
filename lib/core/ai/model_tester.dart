import 'dart:async';
import 'ai_protocol.dart';
import 'model_capability.dart';
import 'openai_chat_protocol.dart';
import 'openai_response_protocol.dart';
import 'openai_embedding_client.dart';
import 'claude_protocol.dart';
import 'gemini_protocol.dart';
import 'ollama_protocol.dart';

class ModelTestResult {
  final bool success;
  final String summary;
  final String detail;
  final String suggestion;
  final int? statusCode;
  final int attempts;

  const ModelTestResult({
    required this.success,
    required this.summary,
    this.detail = '',
    this.suggestion = '',
    this.statusCode,
    this.attempts = 1,
  });

  factory ModelTestResult.success({int attempts = 1}) {
    return ModelTestResult(
      success: true,
      summary: '连接成功',
      suggestion: '模型已返回有效响应，可以用于对话。',
      attempts: attempts,
    );
  }

  factory ModelTestResult.failure(String rawError, {int attempts = 1}) {
    final sanitized = _sanitize(rawError);
    final statusCode = _parseStatusCode(sanitized);
    final lower = sanitized.toLowerCase();

    if (statusCode == 401) {
      return ModelTestResult(
        success: false,
        summary: '认证失败',
        detail: sanitized,
        suggestion: '请检查 API Key 是否正确、是否过期，或是否填入了对应厂商的 Key。',
        statusCode: statusCode,
        attempts: attempts,
      );
    }
    if (statusCode == 403) {
      return ModelTestResult(
        success: false,
        summary: '权限不足',
        detail: sanitized,
        suggestion: '请检查账号是否开通该模型、Key 权限范围、地域或组织权限。',
        statusCode: statusCode,
        attempts: attempts,
      );
    }
    if (statusCode == 404) {
      return ModelTestResult(
        success: false,
        summary: '接口或模型不存在',
        detail: sanitized,
        suggestion: '请检查 Base URL 是否选对厂商预设，或模型名称是否存在。',
        statusCode: statusCode,
        attempts: attempts,
      );
    }
    if (statusCode == 429) {
      return ModelTestResult(
        success: false,
        summary: '请求过于频繁或额度不足',
        detail: sanitized,
        suggestion: '请稍后重试，或检查免费额度、限速和账户余额。',
        statusCode: statusCode,
        attempts: attempts,
      );
    }
    if (statusCode != null && statusCode >= 500) {
      return ModelTestResult(
        success: false,
        summary: '厂商服务异常',
        detail: sanitized,
        suggestion: '请稍后重试；如果持续失败，请切换模型或厂商渠道。',
        statusCode: statusCode,
        attempts: attempts,
      );
    }
    if (lower.contains('timeout') || sanitized.contains('超时')) {
      return ModelTestResult(
        success: false,
        summary: '测试超时',
        detail: sanitized,
        suggestion: '请检查网络、代理、Base URL，或稍后重试。',
        attempts: attempts,
      );
    }
    if (sanitized.contains('不支持的协议') || sanitized.contains('暂不支持')) {
      return ModelTestResult(
        success: false,
        summary: '协议不支持',
        detail: sanitized,
        suggestion: '请切换协议类型，或改用支持该能力的模型。',
        attempts: attempts,
      );
    }
    if (sanitized.contains('未返回')) {
      return ModelTestResult(
        success: false,
        summary: '模型无有效响应',
        detail: sanitized,
        suggestion: '请确认模型名称和模型能力是否匹配。',
        attempts: attempts,
      );
    }
    return ModelTestResult(
      success: false,
      summary: '连接失败',
      detail: sanitized,
      suggestion: '请检查渠道配置、模型名称、网络环境和厂商状态。',
      statusCode: statusCode,
      attempts: attempts,
    );
  }

  bool get retried => attempts > 1;

  int get retryCount => attempts > 1 ? attempts - 1 : 0;

  String get compactMessage {
    final parts = [
      summary,
      if (!success && statusCode != null) 'HTTP $statusCode',
      if (retried) '已重试 $retryCount 次',
      if (!success && suggestion.isNotEmpty) suggestion,
    ];
    return parts.join(' · ');
  }

  static int? _parseStatusCode(String error) {
    final bracketed = RegExp(r'\[(\d{3})\]').firstMatch(error);
    if (bracketed != null) return int.tryParse(bracketed.group(1)!);
    final status = RegExp(
      r'(?:status|HTTP)\s*[:=]?\s*(\d{3})',
    ).firstMatch(error);
    if (status != null) return int.tryParse(status.group(1)!);
    return null;
  }

  static String _sanitize(String raw) {
    return raw
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'), 'Bearer ***')
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{6,}'), 'sk-***')
        .replaceAll(RegExp(r'AIza[0-9A-Za-z_-]{10,}'), 'AIza***')
        .trim();
  }
}

class ModelTestRetryPolicy {
  final int maxAttempts;
  final Duration initialDelay;
  final double backoffFactor;

  const ModelTestRetryPolicy({
    this.maxAttempts = 2,
    this.initialDelay = const Duration(milliseconds: 500),
    this.backoffFactor = 2,
  });

  const ModelTestRetryPolicy.noRetry()
    : maxAttempts = 1,
      initialDelay = Duration.zero,
      backoffFactor = 1;

  bool shouldRetry(ModelTestResult result) {
    if (result.success) return false;
    final statusCode = result.statusCode;
    if (statusCode == 408 ||
        statusCode == 409 ||
        statusCode == 425 ||
        statusCode == 429) {
      return true;
    }
    if (statusCode != null && statusCode >= 500) return true;
    if (result.summary == '测试超时') return true;

    final lower = result.detail.toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection failed');
  }

  Duration delayBeforeAttempt(int nextAttempt) {
    if (nextAttempt <= 1 || initialDelay == Duration.zero) {
      return Duration.zero;
    }
    final multiplier = _pow(backoffFactor, nextAttempt - 2);
    return Duration(
      milliseconds: (initialDelay.inMilliseconds * multiplier).round(),
    );
  }

  double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }
}

typedef RawModelTestRunner = Future<String?> Function();

/// 模型连通性测试工具。
class ModelTester {
  static Future<ModelTestResult> testModelDetailed({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
    String capability = ModelCapability.chat,
    ModelTestRetryPolicy retryPolicy = const ModelTestRetryPolicy(),
    RawModelTestRunner? testRunner,
  }) async {
    final runner =
        testRunner ??
        () => testModel(
          protocol: protocol,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          capability: capability,
        );

    final maxAttempts = retryPolicy.maxAttempts < 1
        ? 1
        : retryPolicy.maxAttempts;
    ModelTestResult? lastResult;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final delay = retryPolicy.delayBeforeAttempt(attempt);
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }

      try {
        final error = await runner();
        lastResult = error == null
            ? ModelTestResult.success(attempts: attempt)
            : ModelTestResult.failure(error, attempts: attempt);
      } catch (e) {
        lastResult = ModelTestResult.failure(e.toString(), attempts: attempt);
      }

      if (lastResult.success ||
          attempt >= maxAttempts ||
          !retryPolicy.shouldRetry(lastResult)) {
        return lastResult;
      }
    }

    return lastResult ?? ModelTestResult.failure('模型测试未执行');
  }

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
