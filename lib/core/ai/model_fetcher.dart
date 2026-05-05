import 'package:dio/dio.dart';

/// 从 OpenAI 兼容接口获取可用模型列表
class ModelFetcher {
  /// 非对话模型的关键词（embedding、reranker 等）
  static const _nonChatKeywords = [
    'embed', 'rerank', 'bge', 'clip', 'voyage', 'nomic', 'zerank',
    'zembed', 'jina', 'embedding', 'retriever',
  ];

  /// 获取模型列表（OpenAI Chat / Response 协议通用）
  /// 返回模型 ID 列表，按字母排序
  /// 自动过滤 embedding/reranker 等非对话模型
  static Future<List<String>> fetchOpenAIModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final dio = Dio();
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
                .toList() ?? [];

            // 排除纯 embedding/rerank 端点类型
            if (types.every((t) => t != 'openai' && t != 'chat')) return false;

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
      throw Exception('获取模型列表失败: ${e.message}');
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
      'claude-haiku-4-5-20251001',
    ];
  }

  /// 获取 Gemini 模型列表
  static Future<List<String>> fetchGeminiModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final dio = Dio();
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
      throw Exception('获取模型列表失败: ${e.message}');
    } finally {
      dio.close();
    }
  }

  /// 获取 Ollama 模型列表
  static Future<List<String>> fetchOllamaModels({
    required String baseUrl,
  }) async {
    final dio = Dio();
    final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/tags';
    try {
      final response = await dio.get(url);
      final data = response.data as Map<String, dynamic>;
      final models = data['models'] as List?;
      if (models == null) return [];
      return models
          .map((m) => (m as Map<String, dynamic>)['name'] as String?)
          .whereType<String>()
          .toList()
        ..sort();
    } on DioException catch (e) {
      throw Exception('获取 Ollama 模型列表失败: ${e.message}');
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
