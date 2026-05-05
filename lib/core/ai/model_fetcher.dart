import 'package:dio/dio.dart';

/// 从 OpenAI 兼容接口获取可用模型列表
class ModelFetcher {
  /// 非对话模型的关键词（embedding、reranker 等）
  static const _nonChatKeywords = [
    'embed', 'rerank', 'bge', 'clip', 'voyage', 'nomic', 'zerank',
    'zembed', 'jina', 'embedding', 'retriever',
  ];

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

  /// 获取模型列表（OpenAI Chat / Response 协议通用）
  /// 返回模型 ID 列表，按字母排序
  /// 自动过滤 embedding/reranker 等非对话模型
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

      // 过滤：只保留对话模型，排除 embedding/reranker
      final models = modelList
          .where((m) {
            final id = (m['id'] as String? ?? '').toLowerCase();
            final types = (m['supported_endpoint_types'] as List?)
                ?.map((e) => e.toString())
                .toList();

            // 如果有 supported_endpoint_types 字段，排除纯 embedding/rerank 端点
            if (types != null && types.isNotEmpty &&
                types.every((t) => t != 'openai' && t != 'chat')) {
              return false;
            }

            // 排除名称包含非对话关键词的模型
            if (_nonChatKeywords.any((kw) => id.contains(kw))) return false;

            return true;
          })
          .map((m) => m['id'] as String?)
          .whereType<String>()
          .toList()
        ..sort();

      return models;
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    } finally {
      dio.close();
    }
  }

  /// 获取 Claude 模型列表（Anthropic API）
  static Future<List<String>> fetchClaudeModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    // Claude API 没有标准的 models 列表端点
    // 返回已知的常用模型
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

  /// 获取 Gemini 模型列表
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

      final models = modelList
          .map((m) {
            final name = m['name'] as String?;
            if (name == null) return null;
            // 格式: "models/gemini-pro" → "gemini-pro"
            return name.contains('/') ? name.split('/').last : name;
          })
          .whereType<String>()
          .where((name) => name.contains('gemini'))
          .toList()
        ..sort();

      return models;
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
            // 去除 :latest 后缀
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
