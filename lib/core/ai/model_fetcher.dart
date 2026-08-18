import 'package:dio/dio.dart';

import 'http_helper.dart';
import 'model_capability.dart';
import 'sse_helper.dart';

class FetchedModel {
  final String id;
  final String capability;
  final Set<String> capabilities;

  const FetchedModel({
    required this.id,
    required this.capability,
    this.capabilities = const <String>{},
  });

  bool supports(String capability) {
    final expected = ModelCapability.normalize(capability);
    return ModelCapability.normalize(this.capability) == expected ||
        capabilities.any(
          (value) => ModelCapability.normalize(value) == expected,
        );
  }
}

/// 从 API 获取可用模型列表。
class ModelFetcher {
  /// 计算“获取模型”弹窗的默认勾选集合。
  ///
  /// 云端渠道保持旧行为：默认勾选所有新模型。Ollama 传入
  /// [preferredModel] 后，只默认勾选该模型及其 Ollama tag 变体
  /// （例如 `gemma4` / `gemma4:latest` / `gemma4:27b`），用户仍可手动调整。
  static Set<String> defaultSelectedModelIds(
    List<FetchedModel> models, {
    String? preferredModel,
  }) {
    final preferred = preferredModel?.trim().toLowerCase();
    if (preferred == null || preferred.isEmpty) {
      return models.map((model) => model.id).toSet();
    }

    return models
        .where((model) {
          final id = model.id.trim().toLowerCase();
          return id == preferred || id.startsWith('$preferred:');
        })
        .map((model) => model.id)
        .toSet();
  }

  static Dio _createDio() {
    final dio = createDio();
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.receiveTimeout = const Duration(seconds: 30);
    return dio;
  }

  static String _errorMessage(DioException e) {
    // HTTP status code errors provide more specific context
    final status = e.response?.statusCode;
    if (status == 401) return '认证失败，请检查 API Key';
    if (status == 403) return '权限不足，请检查 API Key 权限';
    if (status == 404) return '接口不存在，请检查 Base URL';
    if (status == 429) return '请求过于频繁，请稍后再试';
    // Delegate to centralized formatter for timeout and connection errors,
    // then remove accidental credential echoes from proxy/server diagnostics.
    return _sanitizeErrorMessage(formatDioError(e));
  }

  static String _sanitizeErrorMessage(String message) {
    var sanitized = message;
    sanitized = sanitized.replaceAll(
      RegExp(r'Bearer\s+[^\s,;}]+', caseSensitive: false),
      'Bearer ***',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'(api[_-]?key|authorization|token|secret)\s*[:=]\s*[^\s,;}]+',
        caseSensitive: false,
      ),
      'credential=***',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'sk-[A-Za-z0-9_-]{6,}', caseSensitive: false),
      'sk-***',
    );
    return sanitized;
  }

  static Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is! Map) return null;
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) result[entry.key as String] = entry.value;
    }
    return result;
  }

  /// 获取 OpenAI 兼容接口的模型列表，并尽量识别 chat / embedding 能力。
  static Future<List<FetchedModel>> fetchOpenAIModelInfos({
    required String baseUrl,
    required String apiKey,
  }) async {
    final dio = _createDio();
    final normalizedUrl = resolveOpenAiEndpoint(baseUrl, 'models');

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

      final data = _asStringMap(response.data);
      return data == null ? const [] : parseOpenAIModels(data);
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    } finally {
      dio.close();
    }
  }

  static List<FetchedModel> parseOpenAIModels(Map<String, dynamic> data) {
    final modelList = data['data'];
    if (modelList is! Iterable) return [];

    final models = <FetchedModel>[];
    final seen = <String>{};
    for (final raw in modelList) {
      final metadata = _asStringMap(raw);
      if (metadata == null) continue;
      final rawId = metadata['id'];
      if (rawId is! String) continue;
      final id = rawId.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      final capabilities = ModelCapability.capabilitiesFromMetadata(
        id,
        metadata: metadata,
      );
      models.add(
        FetchedModel(
          id: id,
          capability: ModelCapability.primaryCapability(id, metadata: metadata),
          capabilities: Set.unmodifiable(capabilities),
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

  /// 获取 Gemini 模型列表；只保留可生成内容的模型。
  static Future<List<String>> fetchGeminiModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final models = await fetchGeminiModelInfos(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    return models.map((model) => model.id).toList(growable: false);
  }

  /// 获取并分页读取 Gemini 模型能力。
  ///
  /// `supportedGenerationMethods` 缺少 `generateContent` /
  /// `streamGenerateContent` 的条目（例如只支持 `embedContent` 的模型）
  /// 不会进入聊天模型列表。
  static Future<List<FetchedModel>> fetchGeminiModelInfos({
    required String baseUrl,
    required String apiKey,
    int pageSize = 100,
    int maxPages = 100,
  }) async {
    if (pageSize <= 0 || maxPages <= 0) return const [];

    final dio = _createDio();
    final url = resolveGeminiEndpoint(baseUrl, 'models');

    try {
      final result = <FetchedModel>[];
      final seen = <String>{};
      final requestedPageTokens = <String?>{};
      String? pageToken;
      for (var page = 0; page < maxPages; page++) {
        if (!requestedPageTokens.add(pageToken)) break;
        final query = <String, dynamic>{'pageSize': pageSize};
        if (pageToken != null && pageToken.isNotEmpty) {
          query['pageToken'] = pageToken;
        }
        final response = await dio.get(
          url,
          queryParameters: query,
          options: Options(headers: {'x-goog-api-key': apiKey}),
        );

        final data = _asStringMap(response.data);
        if (data == null) break;
        final modelList = data['models'];
        if (modelList is List) {
          for (final raw in modelList) {
            final metadata = _asStringMap(raw);
            if (metadata == null) continue;
            final methods = metadata['supportedGenerationMethods'];
            if (methods is! List ||
                !methods.any(
                  (method) => switch (method.toString().toLowerCase()) {
                    'generatecontent' || 'streamgeneratecontent' => true,
                    _ => false,
                  },
                )) {
              continue;
            }
            final rawNameValue = metadata['name'];
            if (rawNameValue is! String) continue;
            final rawName = rawNameValue.trim();
            if (rawName.isEmpty) continue;
            final id =
                (rawName.contains('/')
                        ? rawName.substring(rawName.lastIndexOf('/') + 1)
                        : rawName)
                    .trim();
            if (id.isEmpty) continue;
            if (!seen.add(id)) continue;
            final discoveredCapability = ModelCapability.primaryCapability(
              id,
              metadata: metadata,
              inferFromModelName: false,
            );
            final supportsVision = ModelCapability.supportsVisionModel(
              capability: discoveredCapability,
              modelId: id,
              protocol: 'gemini',
            );
            final capabilities = <String>{
              ...ModelCapability.capabilitiesFromMetadata(
                id,
                metadata: metadata,
                inferFromModelName: false,
              ),
              if (supportsVision) ModelCapability.vision,
            };
            result.add(
              FetchedModel(
                id: id,
                capability: supportsVision
                    ? ModelCapability.vision
                    : discoveredCapability,
                capabilities: Set.unmodifiable(capabilities),
              ),
            );
          }
        }

        final next = data['nextPageToken']?.toString();
        if (next == null || next.isEmpty || next == pageToken) break;
        pageToken = next;
      }
      result.sort((a, b) => a.id.compareTo(b.id));
      return result;
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    } finally {
      dio.close();
    }
  }

  /// 获取 Ollama 模型名称列表（兼容旧调用，不请求 /api/show）。
  static Future<List<String>> fetchOllamaModels({
    required String baseUrl,
    String apiKey = '',
  }) async {
    final dio = _createDio();
    final url = resolveOllamaEndpoint(baseUrl, 'api/tags');
    try {
      final token = apiKey.trim();
      final response = await dio.get(
        url,
        options: token.isEmpty
            ? null
            : Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = _asStringMap(response.data);
      final models = data?['models'];
      if (models is! Iterable) return const [];

      final names = <String>[];
      final seen = <String>{};
      for (final raw in models) {
        final metadata = _asStringMap(raw);
        final rawName = metadata?['name'];
        if (rawName is! String) continue;
        final trimmed = rawName.trim();
        if (trimmed.isEmpty) continue;
        final name = trimmed.endsWith(':latest')
            ? trimmed.substring(0, trimmed.length - 7)
            : trimmed;
        if (name.isNotEmpty && seen.add(name)) names.add(name);
      }
      names.sort();
      return names;
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    } finally {
      dio.close();
    }
  }

  /// 获取 Ollama 模型及 `/api/show` 能力；show 失败时保留模型但只给出
  /// 保守的 chat 能力，不把未知模型标成 video/music。
  static Future<List<FetchedModel>> fetchOllamaModelInfos({
    required String baseUrl,
    String apiKey = '',
  }) async {
    final names = await fetchOllamaModels(baseUrl: baseUrl, apiKey: apiKey);
    if (names.isEmpty) return const [];

    final dio = _createDio();
    final showUrl = resolveOllamaEndpoint(baseUrl, 'api/show');
    final token = apiKey.trim();
    final headers = token.isEmpty
        ? <String, String>{}
        : <String, String>{'Authorization': 'Bearer $token'};
    try {
      final result = <FetchedModel>[];
      for (final id in names) {
        Map<String, dynamic>? metadata;
        try {
          final response = await dio.post<Map<String, dynamic>>(
            showUrl,
            data: {'name': id},
            options: Options(headers: headers),
          );
          metadata = _asStringMap(response.data);
        } on DioException {
          // Model listing remains useful when an older Ollama/proxy does not
          // expose /api/show.
        } on FormatException {
          // A proxy may return a non-JSON body for /api/show; keep the tag.
        } on TypeError {
          // The same conservative fallback applies to an invalid JSON shape.
        }
        final capabilities = ModelCapability.capabilitiesFromMetadata(
          id,
          metadata: metadata,
          inferFromModelName: false,
        );
        result.add(
          FetchedModel(
            id: id,
            capability: ModelCapability.primaryCapability(
              id,
              metadata: metadata,
              inferFromModelName: false,
            ),
            capabilities: Set.unmodifiable(capabilities),
          ),
        );
      }
      return result;
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
    switch (protocol.trim().toLowerCase()) {
      case 'openai_chat':
      case 'openai_response':
        return fetchOpenAIModelInfos(baseUrl: baseUrl, apiKey: apiKey);
      case 'claude':
        return (await fetchClaudeModels(baseUrl: baseUrl, apiKey: apiKey))
            .map(
              (id) => FetchedModel(
                id: id,
                capability:
                    ModelCapability.supportsVisionModel(
                      capability: ModelCapability.chat,
                      modelId: id,
                      protocol: 'claude',
                    )
                    ? ModelCapability.vision
                    : ModelCapability.chat,
              ),
            )
            .toList();
      case 'gemini':
        return fetchGeminiModelInfos(baseUrl: baseUrl, apiKey: apiKey);
      case 'ollama':
        return fetchOllamaModelInfos(baseUrl: baseUrl, apiKey: apiKey);
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
