import 'package:dio/dio.dart';

/// 从 API 获取可用模型列表（不做过滤，返回全部模型）
class ModelFetcher {
  static Dio _createDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));

  static String _errorMessage(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) return '认证失败，请检查 API Key';
    if (status == 403) return '权限不足，请检查 API Key 权限';
    if (status == 404) return '接口不存在，请检查 Base URL';
    if (status == 429) return '请求过于频繁，请稍后再试';
    if (e.type == DioExceptionType.connectionTimeout) return '连接超时，请检查网络';
    if (e.type == DioExceptionType.receiveTimeout) return '响应超时，请检查网络';
    if (e.type == DioExceptionType.connectionError) return '无法连接，请检查 Base URL 和网络';
    return '请求失败: ${e.message}';
  }

  /// 获取 OpenAI 兼容接口的模型列表（返回全部，不做过滤）
  static Future<List<String>> fetchOpenAIModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final dio = _createDio();
    final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/models';

    try {
      final response = await dio.get(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final modelList = data['data'] as List?;

      if (modelList == null) return [];

      return modelList
          .map((m) => m['id'] as String?)
          .whereType<String>()
          .toList()
        ..sort();
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    } finally {
      dio.close();
    }
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
        options: Options(
          headers: {'x-goog-api-key': apiKey},
        ),
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
            return name.endsWith(':latest') ? name.substring(0, name.length - 7) : name;
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

  /// 根据协议类型自动获取模型列表
  static Future<List<String>> fetchModels({
    required String protocol,
    required String baseUrl,
    required String apiKey,
  }) async {
    switch (protocol) {
      case 'openai_chat':
      case 'openai_response':
        return fetchOpenAIModels(baseUrl: baseUrl, apiKey: apiKey);
      case 'claude':
        return fetchClaudeModels(baseUrl: baseUrl, apiKey: apiKey);
      case 'gemini':
        return fetchGeminiModels(baseUrl: baseUrl, apiKey: apiKey);
      case 'ollama':
        return fetchOllamaModels(baseUrl: baseUrl);
      default:
        throw UnsupportedError('不支持的协议: $protocol');
    }
  }
}
