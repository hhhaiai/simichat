import 'package:dio/dio.dart';

import 'http_helper.dart';
import 'model_capability.dart';
import 'sse_helper.dart';

class FetchedModel {
  final String id;
  final String capability;

  const FetchedModel({required this.id, required this.capability});
}

/// 从 API 获取可用模型列表。
class ModelFetcher {
  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static String _errorMessage(DioException e) {
    // HTTP status code errors provide more specific context
    final status = e.response?.statusCode;
    if (status == 401) return '认证失败，请检查 API Key';
    if (status == 403) return '权限不足，请检查 API Key 权限';
    if (status == 404) return '接口不存在，请检查 Base URL';
    if (status == 429) return '请求过于频繁，请稍后再试';
    // Delegate to centralized formatter for timeout and connection errors
    return formatDioError(e);
  }

  /// 获取 OpenAI 兼容接口的模型列表，并尽量识别 chat / embedding 能力。
  static Future<List<FetchedModel>> fetchOpenAIModelInfos({
    required String baseUrl,
    required String apiKey,
  }) async {
    final dio = _createDio();
    final normalizedUrl = '${normalizeOpenAiBaseUrl(baseUrl)}/v1/models';

    try {
      final response = await dio.get(
        normalizedUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      return parseOpenAIModels(data);
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    } finally {
      dio.close();
    }
  }

  static List<FetchedModel> parseOpenAIModels(Map<String, dynamic> data) {
    final modelList = data['data'] as List?;
    if (modelList == null) return [];

    final models = <FetchedModel>[];
    for (final raw in modelList) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'] as String?;
      if (id == null || id.isEmpty) continue;
      models.add(
        FetchedModel(
          id: id,
          capability: ModelCapability.inferFromModel(id, metadata: raw),
        ),
      );
    }
    models.sort((a, b) {
      final capabilityOrder = a.capability.compareTo(b.capability);
      if (capabilityOrder != 0) return capabilityOrder;
      return a.id.compareTo(b.id);
    });
    return models;
  }

  /// 获取 OpenAI 兼容接口的模型名称列表（兼容旧调用）。
  static Future<List<String>> fetchOpenAIModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final models = await fetchOpenAIModelInfos(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    return models.map((m) => m.id).toList();
  }

  /// 获取 Claude 模型列表（Anthropic API 没有列表端点，返回已知模型）
  static Future<List<String>> fetchClaudeModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    return [
      'claude-opus-4-20250514',
      'claude-sonnet-4-20250514',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
      'claude-3-opus-20240229',
      'claude-3-haiku-20240307',
      'claude-haiku-4-5-20251001',
    ];
  }

  /// 获取 Gemini 模型列表（返回全部，不做过滤）
  static Future<List<String>> fetchGeminiModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final dio = _createDio();
    final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1beta/models';

    try {
      final response = await dio.get(
        url,
        options: Options(headers: {'x-goog-api-key': apiKey}),
      );

      final data = response.data as Map<String, dynamic>;
      final modelList = data['models'] as List?;

      if (modelList == null) return [];

      return modelList
          .map((m) {
            final name = m['name'] as String?;
            if (name == null) return null;
            return name.contains('/') ? name.split('/').last : name;
          })
          .whereType<String>()
          .toList()
        ..sort();
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    } finally {
      dio.close();
    }
  }

  /// 获取 Ollama 模型列表
  static Future<List<String>> fetchOllamaModels({
    required String baseUrl,
  }) async {
    final dio = _createDio();
    final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/tags';
    try {
      final response = await dio.get(url);
      final data = response.data as Map<String, dynamic>;
      final models = data['models'] as List?;
      if (models == null) return [];
      return models
          .map((m) {
            final name = (m as Map<String, dynamic>)['name'] as String?;
            if (name == null) return null;
            return name.endsWith(':latest')
                ? name.substring(0, name.length - 7)
                : name;
          })
          .whereType<String>()
          .toList()
        ..sort();
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    } finally {
      dio.close();
    }
  }

  /// 根据协议类型自动获取模型列表；非 OpenAI-compatible 协议默认为 chat 模型。
  static Future<List<FetchedModel>> fetchModelInfos({
    required String protocol,
    required String baseUrl,
    required String apiKey,
  }) async {
    switch (protocol) {
      case 'openai_chat':
      case 'openai_response':
        return fetchOpenAIModelInfos(baseUrl: baseUrl, apiKey: apiKey);
      case 'claude':
        return (await fetchClaudeModels(baseUrl: baseUrl, apiKey: apiKey))
            .map((id) => FetchedModel(id: id, capability: ModelCapability.chat))
            .toList();
      case 'gemini':
        return (await fetchGeminiModels(baseUrl: baseUrl, apiKey: apiKey))
            .map((id) => FetchedModel(id: id, capability: ModelCapability.chat))
            .toList();
      case 'ollama':
        return (await fetchOllamaModels(baseUrl: baseUrl))
            .map((id) => FetchedModel(id: id, capability: ModelCapability.chat))
            .toList();
      default:
        throw UnsupportedError('不支持的协议: $protocol');
    }
  }

  /// 兼容旧调用：只返回模型名。
  static Future<List<String>> fetchModels({
    required String protocol,
    required String baseUrl,
    required String apiKey,
  }) async {
    final models = await fetchModelInfos(
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    return models.map((m) => m.id).toList();
  }
}
