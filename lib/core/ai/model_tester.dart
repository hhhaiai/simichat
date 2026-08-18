import 'dart:async';

import 'package:dio/dio.dart';

import 'ai_protocol.dart';
import 'api_endpoint_resolver.dart';
import 'model_capability.dart';
import 'http_helper.dart';
import 'openai_chat_protocol.dart';
import 'openai_response_protocol.dart';
import 'openai_embedding_client.dart';
import 'rerank_client.dart';
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

  /// 媒体模型跳过测试：不判失败，也不参与一键剔除。
  final bool skipped;

  const ModelTestResult({
    required this.success,
    required this.summary,
    this.detail = '',
    this.suggestion = '',
    this.statusCode,
    this.attempts = 1,
    this.skipped = false,
  });

  factory ModelTestResult.success({int attempts = 1}) {
    return ModelTestResult(
      success: true,
      summary: '连接成功',
      suggestion: '模型已返回有效响应，可以用于对话。',
      attempts: attempts,
    );
  }

  factory ModelTestResult.skipped({required String reason}) {
    return ModelTestResult(
      success: false,
      skipped: true,
      summary: '未测试',
      detail: reason,
      suggestion: reason,
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

  /// 永久性配置类失败（Key / 权限 / 模型不存在 / 协议不支持）。
  /// 一键剔除只对这类失败自动删除；临时失败（429 / 5xx / 超时 /
  /// 连接失败）可能是网络抖动，绝不应自动删除模型。
  bool get isPermanentFailure {
    if (success || skipped) return false;
    return statusCode == 401 ||
        statusCode == 403 ||
        statusCode == 404 ||
        summary == '协议不支持' ||
        summary == '接口或模型不存在';
  }

  int get retryCount => attempts > 1 ? attempts - 1 : 0;

  String get compactMessage {
    if (skipped) return '$summary · $detail';
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
    final skipped = skippedForCapability(capability, modelId: model);
    if (skipped != null) return skipped;

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

  /// 语音识别模型名提示（whisper / transcri / asr 等），这些模型无法用
  /// 廉价的 TTS 请求探测，测试时直接跳过。
  static const _asrModelHints = [
    'whisper',
    'transcri',
    'speech-to-text',
    'speech_to_text',
    'asr-',
    '-asr',
  ];

  static bool _isAsrModelName(String modelId) {
    final id = modelId.trim().toLowerCase();
    return _asrModelHints.any(id.contains);
  }

  /// 返回不需要真实请求的跳过结果。视频 / 音乐生成任务昂贵且异步，
  /// 语音识别需要音频文件，都不适合批量连通性探测——跳过意味着
  /// 保留模型，绝不因为"无法测试"而删除。
  static ModelTestResult? skippedForCapability(
    String capability, {
    required String modelId,
  }) {
    final normalized = ModelCapability.normalize(capability);
    switch (normalized) {
      case ModelCapability.video:
        return ModelTestResult.skipped(
          reason: '视频生成模型不参与连通性测试，保留不剔除',
        );
      case ModelCapability.music:
        return ModelTestResult.skipped(
          reason: '音乐生成模型不参与连通性测试，保留不剔除',
        );
      case ModelCapability.audio:
        if (_isAsrModelName(modelId)) {
          return ModelTestResult.skipped(
            reason: '语音识别模型暂不支持连通性测试，保留不剔除',
          );
        }
        return null;
      default:
        return null;
    }
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
    if (ModelCapability.isRerank(capability)) {
      return _testRerankModel(
        protocol: protocol,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
      );
    }
    if (ModelCapability.isImage(capability)) {
      return _testImageModel(
        protocol: protocol,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
      );
    }
    if (ModelCapability.isAudio(capability) && !_isAsrModelName(model)) {
      return _testSpeechModel(
        protocol: protocol,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
      );
    }
    if (skippedForCapability(capability, modelId: model) != null) {
      // 媒体模型（视频 / 音乐 / ASR）不进对话测试路径；testModelDetailed
      // 会在更早的位置拦截，这里是直接调用 testModel 时的兜底。
      return 'SKIP:${skippedForCapability(capability, modelId: model)!.detail}';
    }
    return _testChatModel(
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
  }

  /// 生图模型连通性：真实调用 /v1/images/generations 生成一张最小图。
  /// 这是显式的用户动作，产生一次真实生成成本。
  static Future<String?> _testImageModel({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    if (protocol != 'openai_chat' && protocol != 'openai_response') {
      return '当前协议暂不支持图片生成测试';
    }
    try {
      final dio = createDio();
      final response = await dio.post<Map<String, dynamic>>(
        resolveOpenAiEndpoint(baseUrl, 'images/generations').toString(),
        data: <String, dynamic>{
          'model': model,
          'prompt': 'ping',
          'n': 1,
          'size': '1024x1024',
        },
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          responseType: ResponseType.json,
        ),
      );
      final data = response.data;
      final items = data?['data'];
      if (items is List && items.isNotEmpty) {
        final first = items.first;
        if (first is Map &&
            (first['b64_json'] != null ||
                first['url'] != null ||
                first['image_url'] != null)) {
          return null;
        }
      }
      return '生图模型未返回图片数据';
    } on TimeoutException {
      return '测试超时（30秒），请检查网络或模型状态';
    } catch (e) {
      return e.toString();
    }
  }

  /// TTS 类音频模型连通性：短文本合成请求，成本可忽略。
  static Future<String?> _testSpeechModel({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    if (protocol != 'openai_chat' && protocol != 'openai_response') {
      return '当前协议暂不支持语音合成测试';
    }
    try {
      final dio = createDio();
      final response = await dio.post<List<int>>(
        resolveOpenAiEndpoint(baseUrl, 'audio/speech').toString(),
        data: <String, dynamic>{
          'model': model,
          'input': '连接测试',
          'voice': 'alloy',
        },
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          responseType: ResponseType.bytes,
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        return '语音合成模型未返回音频数据';
      }
      return null;
    } on TimeoutException {
      return '测试超时（30秒），请检查网络或模型状态';
    } catch (e) {
      return e.toString();
    }
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

  static Future<String?> _testRerankModel({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    if (protocol != 'openai_chat' && protocol != 'openai_response') {
      return '当前协议暂不支持 Rerank 测试';
    }
    try {
      final result = await const RerankClient()
          .rerank(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            query: 'ping',
            documents: const ['pong', 'ping pong'],
          )
          .timeout(const Duration(seconds: 30));
      if (result.results.isEmpty) {
        return 'Rerank 模型未返回结果';
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
