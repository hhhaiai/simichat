import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../ai/attachment_helper.dart';
import '../ai/ai_protocol.dart';

const kOpenAiRelayDefaultMaxRequestBytes = 1024 * 1024;
const kOpenAiRelayDefaultMaxConcurrentRequests = 4;
const kOpenAiRelayRouteAliasDefault = 'simichat:default';
const kOpenAiRelayRouteAliasAuto = 'simichat:auto';
const kOpenAiRelayRouteAliasFree = 'simichat:free';
const kOpenAiRelayRouteAliasFast = 'simichat:fast';
const _openAiRelayCorsAllowedMethods = 'GET, POST, OPTIONS';
const _openAiRelayCorsAllowedHeaders = 'authorization, content-type';

enum OpenAiRelayRouteStrategy {
  direct,
  defaultModel,
  freeFirst,
  fastFirst;

  String get storageValue => switch (this) {
    OpenAiRelayRouteStrategy.direct => 'direct',
    OpenAiRelayRouteStrategy.defaultModel => 'default_model',
    OpenAiRelayRouteStrategy.freeFirst => 'free_first',
    OpenAiRelayRouteStrategy.fastFirst => 'fast_first',
  };

  String get label => switch (this) {
    OpenAiRelayRouteStrategy.direct => '指定模型',
    OpenAiRelayRouteStrategy.defaultModel => '默认模型',
    OpenAiRelayRouteStrategy.freeFirst => '免费优先',
    OpenAiRelayRouteStrategy.fastFirst => '本地/快速优先',
  };

  static OpenAiRelayRouteStrategy fromStorage(String? value) {
    return switch (value) {
      'default_model' => OpenAiRelayRouteStrategy.defaultModel,
      'free_first' => OpenAiRelayRouteStrategy.freeFirst,
      'fast_first' => OpenAiRelayRouteStrategy.fastFirst,
      _ => OpenAiRelayRouteStrategy.direct,
    };
  }
}

class OpenAiCompatibleRelayException implements Exception {
  const OpenAiCompatibleRelayException(this.message);

  final String message;

  @override
  String toString() => 'OpenAiCompatibleRelayException: $message';
}

class OpenAiCompatibleRelayModel {
  const OpenAiCompatibleRelayModel({
    required this.id,
    required this.modelName,
    required this.displayName,
    this.ownedBy = 'simichat',
    this.supportsVision = false,
  });

  final String id;
  final String modelName;
  final String displayName;
  final String ownedBy;
  final bool supportsVision;

  Map<String, dynamic> toOpenAiModelJson() => {
    'id': id,
    'object': 'model',
    'created': 0,
    'owned_by': ownedBy,
    'root': modelName,
    'parent': null,
    'permission': const [],
    'capabilities': supportsVision ? const ['chat', 'vision'] : const ['chat'],
    'supports_vision': supportsVision,
  };
}

typedef OpenAiRelayModelLister =
    FutureOr<List<OpenAiCompatibleRelayModel>> Function();
typedef OpenAiRelayModelResolver =
    FutureOr<OpenAiCompatibleRelayModel?> Function(String modelId);
typedef OpenAiRelayModelRouter =
    FutureOr<OpenAiCompatibleRelayRoute?> Function(String? modelId);
typedef OpenAiRelayForwarder =
    Stream<AiChunk> Function({
      required OpenAiCompatibleRelayModel model,
      required List<AiMessage> messages,
      String? systemPrompt,
    });
typedef OpenAiRelayAuditSink = void Function(OpenAiRelayAuditEvent event);

typedef OpenAiRelayRemoteImageFetcher =
    Future<OpenAiRelayRemoteImageFetchResult?> Function(
      Uri uri,
      OpenAiRelayRemoteImagePolicy policy,
    );

class OpenAiRelayRemoteImagePolicy {
  const OpenAiRelayRemoteImagePolicy({
    this.enabled = false,
    this.maxBytes = kAttachmentImageDataUrlMaxBytes,
    this.timeout = const Duration(seconds: 3),
  });

  const OpenAiRelayRemoteImagePolicy.disabled()
    : enabled = false,
      maxBytes = kAttachmentImageDataUrlMaxBytes,
      timeout = const Duration(seconds: 3);

  const OpenAiRelayRemoteImagePolicy.enabled({
    this.maxBytes = kAttachmentImageDataUrlMaxBytes,
    this.timeout = const Duration(seconds: 3),
  }) : enabled = true;

  final bool enabled;
  final int maxBytes;
  final Duration timeout;
}

class OpenAiRelayRemoteImageFetchResult {
  const OpenAiRelayRemoteImageFetchResult({
    required this.mimeType,
    required this.bytes,
  });

  final String mimeType;
  final List<int> bytes;
}

class OpenAiCompatibleRelayRoute {
  const OpenAiCompatibleRelayRoute({
    required this.primary,
    this.fallbacks = const [],
    this.routeCode = 'direct',
  });

  final OpenAiCompatibleRelayModel primary;
  final List<OpenAiCompatibleRelayModel> fallbacks;
  final String routeCode;

  List<OpenAiCompatibleRelayModel> get candidates => [primary, ...fallbacks];

  OpenAiCompatibleRelayRoute? requireVision() {
    final visionModels = [
      for (final candidate in candidates)
        if (candidate.supportsVision) candidate,
    ];
    if (visionModels.isEmpty) return null;
    return OpenAiCompatibleRelayRoute(
      primary: visionModels.first,
      fallbacks: visionModels.skip(1).toList(),
      routeCode: routeCode,
    );
  }
}

class OpenAiRelayAuditEvent {
  const OpenAiRelayAuditEvent({
    required this.method,
    required this.path,
    required this.statusCode,
    required this.code,
    required this.authorized,
    required this.startedAt,
    required this.completedAt,
    this.modelId,
    this.stream = false,
    this.activeRequests = 0,
  });

  final String method;
  final String path;
  final int statusCode;
  final String code;
  final bool authorized;
  final DateTime startedAt;
  final DateTime completedAt;
  final String? modelId;
  final bool stream;
  final int activeRequests;

  Duration get duration => completedAt.difference(startedAt);
}

/// 本地 OpenAI 兼容中转服务 v1。
///
/// 默认只绑定 loopback，且必须配置本地 relayToken；不会向响应暴露上游
/// Base URL、API Key 或本机文件路径。当前 v1 支持文本 chat completions、
/// 模型列表与本地健康检查。
class OpenAiCompatibleRelayServer {
  const OpenAiCompatibleRelayServer({DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  Future<OpenAiCompatibleRelaySession> start({
    required String relayToken,
    required OpenAiRelayModelLister listModels,
    required OpenAiRelayModelResolver resolveModel,
    required OpenAiRelayForwarder forward,
    OpenAiRelayModelRouter? routeModel,
    InternetAddress? address,
    int port = 0,
    int maxRequestBytes = kOpenAiRelayDefaultMaxRequestBytes,
    int maxConcurrentRequests = kOpenAiRelayDefaultMaxConcurrentRequests,
    OpenAiRelayAuditSink? auditSink,
    OpenAiRelayRemoteImagePolicy remoteImagePolicy =
        const OpenAiRelayRemoteImagePolicy.disabled(),
    OpenAiRelayRemoteImageFetcher? remoteImageFetcher,
  }) async {
    if (relayToken.trim().length < 16) {
      throw const OpenAiCompatibleRelayException('本地中转令牌至少需要 16 个字符');
    }
    if (maxRequestBytes <= 0) {
      throw const OpenAiCompatibleRelayException('请求大小限制必须大于 0');
    }
    if (maxConcurrentRequests <= 0) {
      throw const OpenAiCompatibleRelayException('并发请求限制必须大于 0');
    }

    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    return OpenAiCompatibleRelaySession._(
      server: server,
      relayToken: relayToken,
      listModels: listModels,
      resolveModel: resolveModel,
      routeModel: routeModel,
      forward: forward,
      now: _now ?? DateTime.now,
      maxRequestBytes: maxRequestBytes,
      maxConcurrentRequests: maxConcurrentRequests,
      auditSink: auditSink,
      remoteImagePolicy: remoteImagePolicy,
      remoteImageFetcher: remoteImageFetcher,
    );
  }
}

class OpenAiCompatibleRelaySession {
  OpenAiCompatibleRelaySession._({
    required HttpServer server,
    required String relayToken,
    required OpenAiRelayModelLister listModels,
    required OpenAiRelayModelResolver resolveModel,
    required OpenAiRelayModelRouter? routeModel,
    required OpenAiRelayForwarder forward,
    required DateTime Function() now,
    required int maxRequestBytes,
    required int maxConcurrentRequests,
    required OpenAiRelayAuditSink? auditSink,
    required OpenAiRelayRemoteImagePolicy remoteImagePolicy,
    required OpenAiRelayRemoteImageFetcher? remoteImageFetcher,
  }) : _server = server,
       _relayToken = relayToken,
       _listModels = listModels,
       _resolveModel = resolveModel,
       _routeModel = routeModel,
       _forward = forward,
       _now = now,
       _maxRequestBytes = maxRequestBytes,
       _maxConcurrentRequests = maxConcurrentRequests,
       _auditSink = auditSink,
       _remoteImagePolicy = remoteImagePolicy,
       _remoteImageFetcher = remoteImageFetcher {
    _subscription = _server.listen(_handleRequest);
  }

  final HttpServer _server;
  final String _relayToken;
  final OpenAiRelayModelLister _listModels;
  final OpenAiRelayModelResolver _resolveModel;
  final OpenAiRelayModelRouter? _routeModel;
  final OpenAiRelayForwarder _forward;
  final DateTime Function() _now;
  final int _maxRequestBytes;
  final int _maxConcurrentRequests;
  final OpenAiRelayAuditSink? _auditSink;
  final OpenAiRelayRemoteImagePolicy _remoteImagePolicy;
  final OpenAiRelayRemoteImageFetcher? _remoteImageFetcher;
  late final StreamSubscription<HttpRequest> _subscription;
  int _activeChatRequests = 0;

  Uri get baseUri =>
      Uri(scheme: 'http', host: _server.address.address, port: _server.port);

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final startedAt = _now();
    var authorized = false;
    var outcome = const _OpenAiRelayOutcome(
      statusCode: HttpStatus.internalServerError,
      code: 'relay_error',
    );
    _applySafeHeaders(request.response);
    try {
      if (request.method == 'OPTIONS') {
        authorized = true;
        outcome = await _handleCorsPreflight(request);
        return;
      }

      if (!_isAuthorized(request)) {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.unauthorized,
          message: '缺少或错误的本地中转令牌',
          type: 'authentication_error',
          code: 'unauthorized',
        );
        outcome = const _OpenAiRelayOutcome(
          statusCode: HttpStatus.unauthorized,
          code: 'unauthorized',
        );
        return;
      }
      authorized = true;

      if (request.method == 'GET' &&
          (request.uri.path == '/health' || request.uri.path == '/v1/health')) {
        outcome = await _handleHealth(request);
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/v1/models') {
        outcome = await _handleModels(request);
        return;
      }

      if (request.method == 'POST' &&
          request.uri.path == '/v1/chat/completions') {
        outcome = await _handleChatCompletions(request);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/v1/responses') {
        outcome = await _handleResponses(request);
        return;
      }

      await _writeOpenAiError(
        request.response,
        statusCode: HttpStatus.notFound,
        message:
            '仅支持 /health、/v1/health、/v1/models、/v1/chat/completions 与 /v1/responses',
        type: 'invalid_request_error',
        code: 'not_found',
      );
      outcome = const _OpenAiRelayOutcome(
        statusCode: HttpStatus.notFound,
        code: 'not_found',
      );
    } catch (_) {
      try {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.internalServerError,
          message: '本地中转服务处理失败',
          type: 'server_error',
          code: 'relay_error',
        );
        outcome = const _OpenAiRelayOutcome(
          statusCode: HttpStatus.internalServerError,
          code: 'relay_error',
        );
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    } finally {
      _recordAudit(
        request,
        startedAt: startedAt,
        authorized: authorized,
        outcome: outcome,
      );
    }
  }

  Future<_OpenAiRelayOutcome> _handleCorsPreflight(HttpRequest request) async {
    if (!_isOpenAiRelayCorsPath(request.uri.path)) {
      await _writeOpenAiError(
        request.response,
        statusCode: HttpStatus.notFound,
        message:
            '仅支持 /health、/v1/health、/v1/models、/v1/chat/completions 与 /v1/responses',
        type: 'invalid_request_error',
        code: 'not_found',
      );
      return const _OpenAiRelayOutcome(
        statusCode: HttpStatus.notFound,
        code: 'not_found',
      );
    }

    _applyCorsPreflightHeaders(request.response);
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return const _OpenAiRelayOutcome(
      statusCode: HttpStatus.noContent,
      code: 'cors_preflight',
    );
  }

  Future<_OpenAiRelayOutcome> _handleHealth(HttpRequest request) async {
    await _writeJson(request.response, {
      'object': 'simichat.relay.health',
      'status': 'ok',
      'active_chat_requests': _activeChatRequests,
      'max_concurrent_chat_requests': _maxConcurrentRequests,
      'remote_image_download_enabled': _remoteImagePolicy.enabled,
    });
    return const _OpenAiRelayOutcome(statusCode: HttpStatus.ok, code: 'ok');
  }

  Future<_OpenAiRelayOutcome> _handleModels(HttpRequest request) async {
    final models = await Future.value(_listModels());
    await _writeJson(request.response, {
      'object': 'list',
      'data': [for (final model in models) model.toOpenAiModelJson()],
    });
    return const _OpenAiRelayOutcome(statusCode: HttpStatus.ok, code: 'ok');
  }

  Future<_OpenAiRelayOutcome> _handleResponses(HttpRequest request) async {
    if (_activeChatRequests >= _maxConcurrentRequests) {
      request.response.headers.set(HttpHeaders.retryAfterHeader, '1');
      await _writeOpenAiError(
        request.response,
        statusCode: HttpStatus.tooManyRequests,
        message: '本地中转并发请求过多，请稍后重试',
        type: 'rate_limit_error',
        code: 'concurrency_limit',
      );
      return const _OpenAiRelayOutcome(
        statusCode: HttpStatus.tooManyRequests,
        code: 'concurrency_limit',
      );
    }

    _activeChatRequests += 1;
    try {
      final Map<String, dynamic>? body;
      try {
        body = await _readJsonBody(request);
      } on _OpenAiRelayRequestTooLarge {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.requestEntityTooLarge,
          message: '请求体超过本地中转大小限制',
          type: 'invalid_request_error',
          code: 'request_too_large',
        );
        return const _OpenAiRelayOutcome(
          statusCode: HttpStatus.requestEntityTooLarge,
          code: 'request_too_large',
        );
      }
      if (body == null) {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: '请求体必须是 JSON 对象',
          type: 'invalid_request_error',
          code: 'invalid_json',
        );
        return const _OpenAiRelayOutcome(
          statusCode: HttpStatus.badRequest,
          code: 'invalid_json',
        );
      }

      final modelId = body['model'];
      final sanitizedModelId = modelId is String ? modelId.trim() : '';
      if (sanitizedModelId.isEmpty && _routeModel == null) {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: '缺少 model',
          type: 'invalid_request_error',
          code: 'missing_model',
        );
        return const _OpenAiRelayOutcome(
          statusCode: HttpStatus.badRequest,
          code: 'missing_model',
        );
      }

      final parsed = await parseOpenAiRelayResponsesInputWithRemoteImages(
        body['input'],
        instructions: body['instructions'],
        remoteImagePolicy: _remoteImagePolicy,
        remoteImageFetcher: _remoteImageFetcher,
      );
      if (parsed == null) {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: 'input 必须是字符串或 OpenAI Responses 兼容消息数组',
          type: 'invalid_request_error',
          code: 'invalid_input',
        );
        return _OpenAiRelayOutcome(
          statusCode: HttpStatus.badRequest,
          code: 'invalid_input',
          modelId: sanitizedModelId,
        );
      }

      var route = await _resolveRoute(
        sanitizedModelId.isEmpty ? null : sanitizedModelId,
      );
      if (route == null) {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.notFound,
          message: sanitizedModelId.isEmpty ? '没有可用默认路由模型' : '模型不存在或未启用',
          type: 'invalid_request_error',
          code: 'model_not_found',
        );
        return _OpenAiRelayOutcome(
          statusCode: HttpStatus.notFound,
          code: 'model_not_found',
          modelId: sanitizedModelId,
        );
      }

      if (parsed.requiresVision) {
        final visionRoute = route.requireVision();
        if (visionRoute == null) {
          await _writeOpenAiError(
            request.response,
            statusCode: HttpStatus.badRequest,
            message: '请求包含图片，请选择支持视觉输入的模型',
            type: 'invalid_request_error',
            code: 'vision_model_required',
          );
          return _OpenAiRelayOutcome(
            statusCode: HttpStatus.badRequest,
            code: 'vision_model_required',
            modelId: sanitizedModelId,
          );
        }
        route = visionRoute;
      }

      final stream = body['stream'] == true;
      final responseId = 'resp-${_now().microsecondsSinceEpoch}';
      if (stream) {
        final model = route.primary;
        return await _writeStreamingResponse(
          request.response,
          id: responseId,
          model: model,
          messages: parsed.messages,
          systemPrompt: parsed.systemPrompt,
        );
      }

      return await _writeBufferedResponse(
        request.response,
        id: responseId,
        route: route,
        messages: parsed.messages,
        systemPrompt: parsed.systemPrompt,
      );
    } finally {
      _activeChatRequests -= 1;
    }
  }

  Future<_OpenAiRelayOutcome> _handleChatCompletions(
    HttpRequest request,
  ) async {
    if (_activeChatRequests >= _maxConcurrentRequests) {
      request.response.headers.set(HttpHeaders.retryAfterHeader, '1');
      await _writeOpenAiError(
        request.response,
        statusCode: HttpStatus.tooManyRequests,
        message: '本地中转并发请求过多，请稍后重试',
        type: 'rate_limit_error',
        code: 'concurrency_limit',
      );
      return const _OpenAiRelayOutcome(
        statusCode: HttpStatus.tooManyRequests,
        code: 'concurrency_limit',
      );
    }

    _activeChatRequests += 1;
    try {
      final Map<String, dynamic>? body;
      try {
        body = await _readJsonBody(request);
      } on _OpenAiRelayRequestTooLarge {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.requestEntityTooLarge,
          message: '请求体超过本地中转大小限制',
          type: 'invalid_request_error',
          code: 'request_too_large',
        );
        return const _OpenAiRelayOutcome(
          statusCode: HttpStatus.requestEntityTooLarge,
          code: 'request_too_large',
        );
      }
      if (body == null) {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: '请求体必须是 JSON 对象',
          type: 'invalid_request_error',
          code: 'invalid_json',
        );
        return const _OpenAiRelayOutcome(
          statusCode: HttpStatus.badRequest,
          code: 'invalid_json',
        );
      }

      final modelId = body['model'];
      final sanitizedModelId = modelId is String ? modelId.trim() : '';
      if (sanitizedModelId.isEmpty && _routeModel == null) {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: '缺少 model',
          type: 'invalid_request_error',
          code: 'missing_model',
        );
        return const _OpenAiRelayOutcome(
          statusCode: HttpStatus.badRequest,
          code: 'missing_model',
        );
      }

      final parsed = await parseOpenAiRelayMessagesWithRemoteImages(
        body['messages'],
        remoteImagePolicy: _remoteImagePolicy,
        remoteImageFetcher: _remoteImageFetcher,
      );
      if (parsed == null) {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: 'messages 必须是 OpenAI 兼容消息数组',
          type: 'invalid_request_error',
          code: 'invalid_messages',
        );
        return _OpenAiRelayOutcome(
          statusCode: HttpStatus.badRequest,
          code: 'invalid_messages',
          modelId: sanitizedModelId,
        );
      }

      var route = await _resolveRoute(
        sanitizedModelId.isEmpty ? null : sanitizedModelId,
      );
      if (route == null) {
        await _writeOpenAiError(
          request.response,
          statusCode: HttpStatus.notFound,
          message: sanitizedModelId.isEmpty ? '没有可用默认路由模型' : '模型不存在或未启用',
          type: 'invalid_request_error',
          code: 'model_not_found',
        );
        return _OpenAiRelayOutcome(
          statusCode: HttpStatus.notFound,
          code: 'model_not_found',
          modelId: sanitizedModelId,
        );
      }

      if (parsed.requiresVision) {
        final visionRoute = route.requireVision();
        if (visionRoute == null) {
          await _writeOpenAiError(
            request.response,
            statusCode: HttpStatus.badRequest,
            message: '请求包含图片，请选择支持视觉输入的模型',
            type: 'invalid_request_error',
            code: 'vision_model_required',
          );
          return _OpenAiRelayOutcome(
            statusCode: HttpStatus.badRequest,
            code: 'vision_model_required',
            modelId: sanitizedModelId,
          );
        }
        route = visionRoute;
      }

      final stream = body['stream'] == true;
      final completionId = 'chatcmpl-${_now().microsecondsSinceEpoch}';
      if (stream) {
        final model = route.primary;
        return await _writeStreamingCompletion(
          request.response,
          id: completionId,
          model: model,
          messages: parsed.messages,
          systemPrompt: parsed.systemPrompt,
        );
      }

      return await _writeBufferedCompletion(
        request.response,
        id: completionId,
        route: route,
        messages: parsed.messages,
        systemPrompt: parsed.systemPrompt,
      );
    } finally {
      _activeChatRequests -= 1;
    }
  }

  Future<OpenAiCompatibleRelayRoute?> _resolveRoute(String? modelId) async {
    final router = _routeModel;
    if (router != null) {
      return Future.value(router(modelId));
    }
    if (modelId == null) return null;
    final model = await Future.value(_resolveModel(modelId));
    return model == null ? null : OpenAiCompatibleRelayRoute(primary: model);
  }

  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > _maxRequestBytes) {
        throw const _OpenAiRelayRequestTooLarge();
      }
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<_OpenAiRelayOutcome> _writeBufferedCompletion(
    HttpResponse response, {
    required String id,
    required OpenAiCompatibleRelayRoute route,
    required List<AiMessage> messages,
    String? systemPrompt,
  }) async {
    for (final model in route.candidates) {
      final content = StringBuffer();
      final thinking = StringBuffer();
      try {
        await for (final chunk in _forward(
          model: model,
          messages: messages,
          systemPrompt: systemPrompt,
        )) {
          if (chunk.content != null) content.write(chunk.content);
          if (chunk.thinking != null) thinking.write(chunk.thinking);
        }
      } catch (_) {
        continue;
      }

      final message = <String, dynamic>{
        'role': 'assistant',
        'content': content.toString(),
      };
      if (thinking.isNotEmpty) {
        message['reasoning_content'] = thinking.toString();
      }

      await _writeJson(response, {
        'id': id,
        'object': 'chat.completion',
        'created': _createdSeconds(),
        'model': model.id,
        'choices': [
          {'index': 0, 'message': message, 'finish_reason': 'stop'},
        ],
        'usage': {
          'prompt_tokens': 0,
          'completion_tokens': 0,
          'total_tokens': 0,
        },
      });
      return _OpenAiRelayOutcome(
        statusCode: HttpStatus.ok,
        code: route.routeCode == 'direct' ? 'ok' : 'ok_${route.routeCode}',
        modelId: model.id,
      );
    }

    await _writeOpenAiError(
      response,
      statusCode: HttpStatus.badGateway,
      message: '上游模型调用失败，已尝试可用回退模型',
      type: 'server_error',
      code: 'upstream_error',
    );
    return _OpenAiRelayOutcome(
      statusCode: HttpStatus.badGateway,
      code: 'upstream_error',
      modelId: route.primary.id,
    );
  }

  Future<_OpenAiRelayOutcome> _writeBufferedResponse(
    HttpResponse response, {
    required String id,
    required OpenAiCompatibleRelayRoute route,
    required List<AiMessage> messages,
    String? systemPrompt,
  }) async {
    for (final model in route.candidates) {
      final content = StringBuffer();
      try {
        await for (final chunk in _forward(
          model: model,
          messages: messages,
          systemPrompt: systemPrompt,
        )) {
          if (chunk.content != null) content.write(chunk.content);
        }
      } catch (_) {
        continue;
      }

      final outputText = content.toString();
      await _writeJson(response, {
        'id': id,
        'object': 'response',
        'created_at': _createdSeconds(),
        'status': 'completed',
        'model': model.id,
        'output': [
          {
            'id': 'msg-${_createdSeconds()}',
            'type': 'message',
            'status': 'completed',
            'role': 'assistant',
            'content': [
              {
                'type': 'output_text',
                'text': outputText,
                'annotations': const [],
              },
            ],
          },
        ],
        'output_text': outputText,
        'usage': {'input_tokens': 0, 'output_tokens': 0, 'total_tokens': 0},
      });
      return _OpenAiRelayOutcome(
        statusCode: HttpStatus.ok,
        code: route.routeCode == 'direct' ? 'ok' : 'ok_${route.routeCode}',
        modelId: model.id,
      );
    }

    await _writeOpenAiError(
      response,
      statusCode: HttpStatus.badGateway,
      message: '上游模型调用失败，已尝试可用回退模型',
      type: 'server_error',
      code: 'upstream_error',
    );
    return _OpenAiRelayOutcome(
      statusCode: HttpStatus.badGateway,
      code: 'upstream_error',
      modelId: route.primary.id,
    );
  }

  Future<_OpenAiRelayOutcome> _writeStreamingCompletion(
    HttpResponse response, {
    required String id,
    required OpenAiCompatibleRelayModel model,
    required List<AiMessage> messages,
    String? systemPrompt,
  }) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    response.headers.set('Connection', 'keep-alive');

    try {
      var index = 0;
      await for (final chunk in _forward(
        model: model,
        messages: messages,
        systemPrompt: systemPrompt,
      )) {
        final delta = <String, dynamic>{};
        if (index == 0) delta['role'] = 'assistant';
        if (chunk.content != null && chunk.content!.isNotEmpty) {
          delta['content'] = chunk.content;
        }
        if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
          delta['reasoning_content'] = chunk.thinking;
        }
        if (delta.isEmpty) continue;
        response.write(
          'data: ${jsonEncode(_streamPayload(id, model.id, delta, null))}\n\n',
        );
        index += 1;
      }
    } catch (_) {
      response.write(
        'data: ${jsonEncode({
          'error': {'message': '上游模型调用失败', 'type': 'server_error', 'code': 'upstream_error'},
        })}\n\n',
      );
      response.write('data: [DONE]\n\n');
      await response.close();
      return _OpenAiRelayOutcome(
        statusCode: HttpStatus.ok,
        code: 'upstream_error',
        modelId: model.id,
        stream: true,
      );
    }
    response.write(
      'data: ${jsonEncode(_streamPayload(id, model.id, const {}, 'stop'))}\n\n',
    );
    response.write('data: [DONE]\n\n');
    await response.close();
    return _OpenAiRelayOutcome(
      statusCode: HttpStatus.ok,
      code: 'ok',
      modelId: model.id,
      stream: true,
    );
  }

  Future<_OpenAiRelayOutcome> _writeStreamingResponse(
    HttpResponse response, {
    required String id,
    required OpenAiCompatibleRelayModel model,
    required List<AiMessage> messages,
    String? systemPrompt,
  }) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    response.headers.set('Connection', 'keep-alive');

    final itemId = 'msg-${_createdSeconds()}';
    final createdPayload = {
      'type': 'response.created',
      'response': _responsesPayload(
        id: id,
        modelId: model.id,
        status: 'in_progress',
        outputText: '',
        itemId: itemId,
      ),
    };
    response.write(
      'event: response.created\n'
      'data: ${jsonEncode(createdPayload)}\n\n',
    );

    final inProgressPayload = {
      'type': 'response.in_progress',
      'response': _responsesPayload(
        id: id,
        modelId: model.id,
        status: 'in_progress',
        outputText: '',
        itemId: itemId,
      ),
    };
    response.write(
      'event: response.in_progress\n'
      'data: ${jsonEncode(inProgressPayload)}\n\n',
    );

    final itemAddedPayload = {
      'type': 'response.output_item.added',
      'response_id': id,
      'output_index': 0,
      'item': {
        'id': itemId,
        'type': 'message',
        'status': 'in_progress',
        'role': 'assistant',
        'content': const [],
      },
    };
    response.write(
      'event: response.output_item.added\n'
      'data: ${jsonEncode(itemAddedPayload)}\n\n',
    );
    final contentPartAddedPayload = {
      'type': 'response.content_part.added',
      'response_id': id,
      'item_id': itemId,
      'output_index': 0,
      'content_index': 0,
      'part': {'type': 'output_text', 'text': '', 'annotations': const []},
    };
    response.write(
      'event: response.content_part.added\n'
      'data: ${jsonEncode(contentPartAddedPayload)}\n\n',
    );

    final content = StringBuffer();
    try {
      await for (final chunk in _forward(
        model: model,
        messages: messages,
        systemPrompt: systemPrompt,
      )) {
        final delta = chunk.content;
        if (delta == null || delta.isEmpty) continue;
        content.write(delta);
        final deltaPayload = {
          'type': 'response.output_text.delta',
          'response_id': id,
          'item_id': itemId,
          'output_index': 0,
          'content_index': 0,
          'delta': delta,
        };
        response.write(
          'event: response.output_text.delta\n'
          'data: ${jsonEncode(deltaPayload)}\n\n',
        );
      }
    } catch (_) {
      final failedResponse = _responsesPayload(
        id: id,
        modelId: model.id,
        status: 'failed',
        outputText: content.toString(),
        itemId: itemId,
      );
      failedResponse['error'] = {
        'code': 'upstream_error',
        'message': '上游模型调用失败',
      };
      final failedPayload = {
        'type': 'response.failed',
        'response': failedResponse,
      };
      response.write(
        'event: response.failed\n'
        'data: ${jsonEncode(failedPayload)}\n\n',
      );
      response.write('data: [DONE]\n\n');
      await response.close();
      return _OpenAiRelayOutcome(
        statusCode: HttpStatus.ok,
        code: 'upstream_error',
        modelId: model.id,
        stream: true,
      );
    }

    final outputText = content.toString();
    final textDonePayload = {
      'type': 'response.output_text.done',
      'response_id': id,
      'item_id': itemId,
      'output_index': 0,
      'content_index': 0,
      'text': outputText,
    };
    response.write(
      'event: response.output_text.done\n'
      'data: ${jsonEncode(textDonePayload)}\n\n',
    );
    final completedPart = {
      'type': 'output_text',
      'text': outputText,
      'annotations': const [],
    };
    final contentPartDonePayload = {
      'type': 'response.content_part.done',
      'response_id': id,
      'item_id': itemId,
      'output_index': 0,
      'content_index': 0,
      'part': completedPart,
    };
    response.write(
      'event: response.content_part.done\n'
      'data: ${jsonEncode(contentPartDonePayload)}\n\n',
    );
    final itemDonePayload = {
      'type': 'response.output_item.done',
      'response_id': id,
      'output_index': 0,
      'item': {
        'id': itemId,
        'type': 'message',
        'status': 'completed',
        'role': 'assistant',
        'content': [completedPart],
      },
    };
    response.write(
      'event: response.output_item.done\n'
      'data: ${jsonEncode(itemDonePayload)}\n\n',
    );
    final completedPayload = {
      'type': 'response.completed',
      'response': _responsesPayload(
        id: id,
        modelId: model.id,
        status: 'completed',
        outputText: outputText,
        itemId: itemId,
      ),
    };
    response.write(
      'event: response.completed\n'
      'data: ${jsonEncode(completedPayload)}\n\n',
    );
    response.write('data: [DONE]\n\n');
    await response.close();
    return _OpenAiRelayOutcome(
      statusCode: HttpStatus.ok,
      code: 'ok',
      modelId: model.id,
      stream: true,
    );
  }

  Map<String, dynamic> _responsesPayload({
    required String id,
    required String modelId,
    required String status,
    required String outputText,
    String? itemId,
  }) {
    final resolvedItemId = itemId ?? 'msg-${_createdSeconds()}';
    return {
      'id': id,
      'object': 'response',
      'created_at': _createdSeconds(),
      'status': status,
      'model': modelId,
      'output': [
        {
          'id': resolvedItemId,
          'type': 'message',
          'status': status,
          'role': 'assistant',
          'content': [
            {
              'type': 'output_text',
              'text': outputText,
              'annotations': const [],
            },
          ],
        },
      ],
      'output_text': outputText,
      'usage': {'input_tokens': 0, 'output_tokens': 0, 'total_tokens': 0},
    };
  }

  Map<String, dynamic> _streamPayload(
    String id,
    String modelId,
    Map<String, dynamic> delta,
    String? finishReason,
  ) => {
    'id': id,
    'object': 'chat.completion.chunk',
    'created': _createdSeconds(),
    'model': modelId,
    'choices': [
      {'index': 0, 'delta': delta, 'finish_reason': finishReason},
    ],
  };

  bool _isAuthorized(HttpRequest request) {
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    return auth == 'Bearer $_relayToken';
  }

  int _createdSeconds() => _now().millisecondsSinceEpoch ~/ 1000;

  void _recordAudit(
    HttpRequest request, {
    required DateTime startedAt,
    required bool authorized,
    required _OpenAiRelayOutcome outcome,
  }) {
    final sink = _auditSink;
    if (sink == null) return;
    sink(
      OpenAiRelayAuditEvent(
        method: request.method,
        path: request.uri.path,
        statusCode: outcome.statusCode,
        code: outcome.code,
        authorized: authorized,
        startedAt: startedAt,
        completedAt: _now(),
        modelId: _safeOpenAiRelayAuditModelId(outcome.modelId),
        stream: outcome.stream,
        activeRequests: _activeChatRequests,
      ),
    );
  }
}

class _OpenAiRelayOutcome {
  const _OpenAiRelayOutcome({
    required this.statusCode,
    required this.code,
    this.modelId,
    this.stream = false,
  });

  final int statusCode;
  final String code;
  final String? modelId;
  final bool stream;
}

class _OpenAiRelayRequestTooLarge implements Exception {
  const _OpenAiRelayRequestTooLarge();
}

class OpenAiRelayParsedMessages {
  const OpenAiRelayParsedMessages({
    required this.messages,
    required this.systemPrompt,
    this.omittedPartTypes = const {},
    this.attachedImageCount = 0,
  });

  final List<AiMessage> messages;
  final String? systemPrompt;
  final Map<String, int> omittedPartTypes;
  final int attachedImageCount;

  int get omittedPartCount =>
      omittedPartTypes.values.fold<int>(0, (total, count) => total + count);

  bool get requiresVision => attachedImageCount > 0;
}

OpenAiRelayParsedMessages? parseOpenAiRelayMessages(dynamic rawMessages) {
  if (rawMessages is! List) return null;
  final messages = <AiMessage>[];
  final systemPrompts = <String>[];
  final omittedPartTypes = <String, int>{};
  var attachedImageCount = 0;
  for (final raw in rawMessages) {
    if (raw is! Map) return null;
    final role = raw['role'];
    if (role is! String || role.trim().isEmpty) return null;
    final parsedContent = _parseOpenAiRelayContent(raw['content']);
    if (parsedContent == null) return null;
    _mergeOpenAiRelayOmittedPartTypes(
      omittedPartTypes,
      parsedContent.omittedPartTypes,
    );
    if (role == 'system') {
      if (parsedContent.text.trim().isNotEmpty) {
        systemPrompts.add(parsedContent.text.trim());
      }
      continue;
    }
    attachedImageCount += parsedContent.attachments.length;
    messages.add(
      AiMessage(
        role: role,
        content: parsedContent.text,
        attachments: parsedContent.attachments.isEmpty
            ? null
            : List.unmodifiable(parsedContent.attachments),
      ),
    );
  }
  return OpenAiRelayParsedMessages(
    messages: messages,
    systemPrompt: systemPrompts.isEmpty ? null : systemPrompts.join('\n\n'),
    omittedPartTypes: Map.unmodifiable(omittedPartTypes),
    attachedImageCount: attachedImageCount,
  );
}

Future<OpenAiRelayParsedMessages?> parseOpenAiRelayMessagesWithRemoteImages(
  dynamic rawMessages, {
  OpenAiRelayRemoteImagePolicy remoteImagePolicy =
      const OpenAiRelayRemoteImagePolicy.disabled(),
  OpenAiRelayRemoteImageFetcher? remoteImageFetcher,
}) async {
  if (!remoteImagePolicy.enabled) return parseOpenAiRelayMessages(rawMessages);
  if (rawMessages is! List) return null;
  final messages = <AiMessage>[];
  final systemPrompts = <String>[];
  final omittedPartTypes = <String, int>{};
  var attachedImageCount = 0;
  for (final raw in rawMessages) {
    if (raw is! Map) return null;
    final role = raw['role'];
    if (role is! String || role.trim().isEmpty) return null;
    final parsedContent = await _parseOpenAiRelayContentWithRemoteImages(
      raw['content'],
      remoteImagePolicy: remoteImagePolicy,
      remoteImageFetcher: remoteImageFetcher,
    );
    if (parsedContent == null) return null;
    _mergeOpenAiRelayOmittedPartTypes(
      omittedPartTypes,
      parsedContent.omittedPartTypes,
    );
    if (role == 'system') {
      if (parsedContent.text.trim().isNotEmpty) {
        systemPrompts.add(parsedContent.text.trim());
      }
      continue;
    }
    attachedImageCount += parsedContent.attachments.length;
    messages.add(
      AiMessage(
        role: role,
        content: parsedContent.text,
        attachments: parsedContent.attachments.isEmpty
            ? null
            : List.unmodifiable(parsedContent.attachments),
      ),
    );
  }
  return OpenAiRelayParsedMessages(
    messages: messages,
    systemPrompt: systemPrompts.isEmpty ? null : systemPrompts.join('\n\n'),
    omittedPartTypes: Map.unmodifiable(omittedPartTypes),
    attachedImageCount: attachedImageCount,
  );
}

OpenAiRelayParsedMessages? parseOpenAiRelayResponsesInput(
  dynamic rawInput, {
  dynamic instructions,
}) {
  final rawMessages = _normalizeOpenAiRelayResponsesInput(rawInput);
  if (rawMessages == null) return null;
  return _withOpenAiRelayResponseInstructions(
    parseOpenAiRelayMessages(rawMessages),
    instructions,
  );
}

Future<OpenAiRelayParsedMessages?>
parseOpenAiRelayResponsesInputWithRemoteImages(
  dynamic rawInput, {
  dynamic instructions,
  OpenAiRelayRemoteImagePolicy remoteImagePolicy =
      const OpenAiRelayRemoteImagePolicy.disabled(),
  OpenAiRelayRemoteImageFetcher? remoteImageFetcher,
}) async {
  final rawMessages = _normalizeOpenAiRelayResponsesInput(rawInput);
  if (rawMessages == null) return null;
  final parsed = await parseOpenAiRelayMessagesWithRemoteImages(
    rawMessages,
    remoteImagePolicy: remoteImagePolicy,
    remoteImageFetcher: remoteImageFetcher,
  );
  return _withOpenAiRelayResponseInstructions(parsed, instructions);
}

List<Map<String, dynamic>>? _normalizeOpenAiRelayResponsesInput(
  dynamic rawInput,
) {
  if (rawInput is String) {
    return [
      {'role': 'user', 'content': rawInput},
    ];
  }
  if (rawInput is! List) return null;
  final messages = <Map<String, dynamic>>[];
  for (final item in rawInput) {
    if (item is String) {
      messages.add({'role': 'user', 'content': item});
      continue;
    }
    if (item is! Map) return null;
    final role = item['role'];
    final type = item['type'];
    if (role is String && role.trim().isNotEmpty) {
      messages.add({
        'role': role,
        'content': item['content'] ?? item['text'] ?? '',
      });
      continue;
    }
    if (type == 'message') return null;
    if (type is String && type.trim().isNotEmpty) {
      messages.add({
        'role': 'user',
        'content': [Map<String, dynamic>.from(item)],
      });
      continue;
    }
    return null;
  }
  return messages;
}

OpenAiRelayParsedMessages? _withOpenAiRelayResponseInstructions(
  OpenAiRelayParsedMessages? parsed,
  dynamic instructions,
) {
  if (parsed == null) return null;
  if (instructions == null) return parsed;
  if (instructions is! String) return null;
  final normalized = instructions.trim();
  if (normalized.isEmpty) return parsed;
  final systemPrompt = parsed.systemPrompt == null
      ? normalized
      : '$normalized\n\n${parsed.systemPrompt}';
  return OpenAiRelayParsedMessages(
    messages: parsed.messages,
    systemPrompt: systemPrompt,
    omittedPartTypes: parsed.omittedPartTypes,
    attachedImageCount: parsed.attachedImageCount,
  );
}

class _OpenAiRelayParsedContent {
  const _OpenAiRelayParsedContent({
    required this.text,
    required this.omittedPartTypes,
    required this.attachments,
  });

  final String text;
  final Map<String, int> omittedPartTypes;
  final List<Attachment> attachments;
}

_OpenAiRelayParsedContent? _parseOpenAiRelayContent(dynamic rawContent) {
  if (rawContent == null) {
    return const _OpenAiRelayParsedContent(
      text: '',
      omittedPartTypes: {},
      attachments: [],
    );
  }
  if (rawContent is String) {
    return _OpenAiRelayParsedContent(
      text: rawContent,
      omittedPartTypes: const {},
      attachments: const [],
    );
  }
  if (rawContent is List) {
    final parts = <String>[];
    final omittedPartTypes = <String, int>{};
    final attachments = <Attachment>[];
    for (final item in rawContent) {
      if (item is String) {
        parts.add(item);
        continue;
      }
      if (item is! Map) return null;
      final type = _sanitizeOpenAiRelayPartType(item['type']);
      if (_isOpenAiRelayTextPart(type)) {
        final text = item['text'];
        if (text is String) parts.add(text);
        continue;
      }
      if (type == 'unknown') {
        final text = item['text'];
        if (text is String) {
          parts.add(text);
          continue;
        }
      }
      final inlineImage = _openAiRelayInlineImageAttachment(type, item);
      if (inlineImage != null) {
        attachments.add(inlineImage);
        continue;
      }
      _incrementOpenAiRelayOmittedPart(omittedPartTypes, type);
      parts.add(_openAiRelayOmittedPartPlaceholder(type));
    }
    return _OpenAiRelayParsedContent(
      text: parts.join('\n'),
      omittedPartTypes: Map.unmodifiable(omittedPartTypes),
      attachments: List.unmodifiable(attachments),
    );
  }
  return null;
}

Future<_OpenAiRelayParsedContent?> _parseOpenAiRelayContentWithRemoteImages(
  dynamic rawContent, {
  required OpenAiRelayRemoteImagePolicy remoteImagePolicy,
  OpenAiRelayRemoteImageFetcher? remoteImageFetcher,
}) async {
  if (rawContent == null) {
    return const _OpenAiRelayParsedContent(
      text: '',
      omittedPartTypes: {},
      attachments: [],
    );
  }
  if (rawContent is String) {
    return _OpenAiRelayParsedContent(
      text: rawContent,
      omittedPartTypes: const {},
      attachments: const [],
    );
  }
  if (rawContent is List) {
    final parts = <String>[];
    final omittedPartTypes = <String, int>{};
    final attachments = <Attachment>[];
    for (final item in rawContent) {
      if (item is String) {
        parts.add(item);
        continue;
      }
      if (item is! Map) return null;
      final type = _sanitizeOpenAiRelayPartType(item['type']);
      if (_isOpenAiRelayTextPart(type)) {
        final text = item['text'];
        if (text is String) parts.add(text);
        continue;
      }
      if (type == 'unknown') {
        final text = item['text'];
        if (text is String) {
          parts.add(text);
          continue;
        }
      }
      final inlineImage = _openAiRelayInlineImageAttachment(type, item);
      if (inlineImage != null) {
        attachments.add(inlineImage);
        continue;
      }
      final remoteImage = await _openAiRelayRemoteImageAttachment(
        type,
        item,
        policy: remoteImagePolicy,
        fetcher: remoteImageFetcher,
      );
      if (remoteImage != null) {
        attachments.add(remoteImage);
        continue;
      }
      _incrementOpenAiRelayOmittedPart(omittedPartTypes, type);
      parts.add(_openAiRelayOmittedPartPlaceholder(type));
    }
    return _OpenAiRelayParsedContent(
      text: parts.join('\n'),
      omittedPartTypes: Map.unmodifiable(omittedPartTypes),
      attachments: List.unmodifiable(attachments),
    );
  }
  return null;
}

const _openAiRelayTextPartTypes = {'text', 'input_text', 'output_text'};

const _openAiRelayMultimodalPartTypes = {
  'image',
  'image_url',
  'input_image',
  'input_audio',
  'audio',
  'input_file',
  'file',
  'document',
  'video',
  'input_video',
};

bool _isOpenAiRelayTextPart(String type) {
  return _openAiRelayTextPartTypes.contains(type);
}

String _sanitizeOpenAiRelayPartType(dynamic rawType) {
  if (rawType is! String) return 'unknown';
  final normalized = rawType.trim().toLowerCase();
  if (RegExp(r'^[a-z0-9_.-]{1,48}$').hasMatch(normalized)) {
    return normalized;
  }
  return 'unknown';
}

String _openAiRelayOmittedPartPlaceholder(String type) {
  final note = _openAiRelayMultimodalPartTypes.contains(type)
      ? '多模态内容已安全省略'
      : '非文本内容已安全省略';
  return '[已省略非文本内容: $type（$note）]';
}

Attachment? _openAiRelayInlineImageAttachment(String type, Map item) {
  if (!_isOpenAiRelayImagePart(type)) return null;
  final dataUrl = _extractOpenAiRelayImageDataUrl(type, item);
  if (dataUrl == null) return null;
  final parsed = parseAttachmentImageDataUrl(dataUrl);
  if (parsed == null) return null;
  return Attachment(
    type: 'image',
    path: dataUrl.trim(),
    mimeType: parsed.mimeType,
  );
}

bool _isOpenAiRelayImagePart(String type) {
  return type == 'image_url' || type == 'input_image' || type == 'image';
}

String? _extractOpenAiRelayImageDataUrl(String type, Map item) {
  if (type == 'image_url') {
    final imageUrl = item['image_url'];
    if (imageUrl is Map) {
      final url = imageUrl['url'];
      return url is String ? url : null;
    }
    return imageUrl is String ? imageUrl : null;
  }

  final imageUrl = item['image_url'];
  if (imageUrl is String) return imageUrl;
  if (imageUrl is Map) {
    final url = imageUrl['url'];
    if (url is String) return url;
  }

  final data = item['data'];
  if (data is String && data.trim().startsWith('data:image/')) return data;
  return null;
}

Future<Attachment?> _openAiRelayRemoteImageAttachment(
  String type,
  Map item, {
  required OpenAiRelayRemoteImagePolicy policy,
  OpenAiRelayRemoteImageFetcher? fetcher,
}) async {
  if (!policy.enabled || !_isOpenAiRelayImagePart(type)) return null;
  final url = _extractOpenAiRelayImageDataUrl(type, item);
  if (url == null || url.trim().startsWith('data:')) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !isSafeOpenAiRelayRemoteImageUri(uri)) return null;
  final fetched = await (fetcher ?? _defaultOpenAiRelayRemoteImageFetcher)(
    uri,
    policy,
  );
  if (fetched == null) return null;
  final mimeType = _normalizeOpenAiRelayRemoteImageMimeType(fetched.mimeType);
  if (mimeType == null) return null;
  if (fetched.bytes.isEmpty || fetched.bytes.length > policy.maxBytes) {
    return null;
  }
  final dataUrl = 'data:$mimeType;base64,${base64Encode(fetched.bytes)}';
  final parsed = parseAttachmentImageDataUrl(
    dataUrl,
    maxBytes: policy.maxBytes,
  );
  if (parsed == null) return null;
  return Attachment(type: 'image', path: dataUrl, mimeType: parsed.mimeType);
}

Future<OpenAiRelayRemoteImageFetchResult?>
_defaultOpenAiRelayRemoteImageFetcher(
  Uri uri,
  OpenAiRelayRemoteImagePolicy policy,
) async {
  if (!isSafeOpenAiRelayRemoteImageUri(uri)) return null;
  List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(uri.host).timeout(policy.timeout);
  } catch (_) {
    return null;
  }
  if (addresses.isEmpty || addresses.any(_isUnsafeOpenAiRelayAddress)) {
    return null;
  }

  final client = HttpClient()..connectionTimeout = policy.timeout;
  try {
    final request = await client.getUrl(uri).timeout(policy.timeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'image/*');
    final response = await request.close().timeout(policy.timeout);
    if (response.statusCode != HttpStatus.ok) return null;
    final contentLength = response.contentLength;
    if (contentLength > policy.maxBytes) return null;
    final mimeType = _normalizeOpenAiRelayRemoteImageMimeType(
      response.headers.contentType?.mimeType ?? '',
    );
    if (mimeType == null) return null;

    final bytes = <int>[];
    await for (final chunk in response.timeout(policy.timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > policy.maxBytes) return null;
    }
    if (bytes.isEmpty) return null;
    return OpenAiRelayRemoteImageFetchResult(mimeType: mimeType, bytes: bytes);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

bool isSafeOpenAiRelayRemoteImageUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return false;
  final host = uri.host.trim();
  if (uri.userInfo.isNotEmpty || host.isEmpty) return false;
  final normalizedHost = host.toLowerCase().replaceAll(RegExp(r'\.+$'), '');
  if (normalizedHost == 'localhost' || normalizedHost.endsWith('.localhost')) {
    return false;
  }
  final hostAddress = InternetAddress.tryParse(host);
  if (hostAddress != null && _isUnsafeOpenAiRelayAddress(hostAddress)) {
    return false;
  }
  return true;
}

String? _normalizeOpenAiRelayRemoteImageMimeType(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'image/jpg' => 'image/jpeg',
    'image/jpeg' ||
    'image/png' ||
    'image/gif' ||
    'image/webp' ||
    'image/bmp' => normalized,
    _ => null,
  };
}

bool _isUnsafeOpenAiRelayAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  final raw = address.rawAddress;
  if (raw.length == 4) return _isUnsafeOpenAiRelayIpv4(raw);
  if (raw.length == 16) return _isUnsafeOpenAiRelayIpv6(raw);
  return true;
}

bool _isUnsafeOpenAiRelayIpv4(List<int> raw) {
  final a = raw[0];
  final b = raw[1];
  if (a == 0 || a == 10 || a == 127) return true;
  if (a == 100 && b >= 64 && b <= 127) return true;
  if (a == 169 && b == 254) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  if (a >= 224) return true;
  if (a == 255) return true;
  return false;
}

bool _isUnsafeOpenAiRelayIpv6(List<int> raw) {
  if (raw.every((b) => b == 0)) return true;
  if ((raw[0] & 0xfe) == 0xfc) return true;
  if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return true;
  final isMappedIpv4 =
      raw.take(10).every((b) => b == 0) && raw[10] == 0xff && raw[11] == 0xff;
  if (isMappedIpv4) return _isUnsafeOpenAiRelayIpv4(raw.sublist(12));
  return false;
}

void _incrementOpenAiRelayOmittedPart(Map<String, int> target, String type) {
  target[type] = (target[type] ?? 0) + 1;
}

void _mergeOpenAiRelayOmittedPartTypes(
  Map<String, int> target,
  Map<String, int> source,
) {
  for (final entry in source.entries) {
    target[entry.key] = (target[entry.key] ?? 0) + entry.value;
  }
}

String? _safeOpenAiRelayAuditModelId(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 160) return null;
  if (!RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(trimmed)) return null;
  return trimmed;
}

bool _isOpenAiRelayCorsPath(String path) =>
    path == '/health' ||
    path == '/v1/health' ||
    path == '/v1/models' ||
    path == '/v1/chat/completions' ||
    path == '/v1/responses';

void _applySafeHeaders(HttpResponse response) {
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set('Access-Control-Expose-Headers', 'content-type');
  response.headers.add(HttpHeaders.varyHeader, 'Origin');
}

void _applyCorsPreflightHeaders(HttpResponse response) {
  response.headers.set(
    'Access-Control-Allow-Methods',
    _openAiRelayCorsAllowedMethods,
  );
  response.headers.set(
    'Access-Control-Allow-Headers',
    _openAiRelayCorsAllowedHeaders,
  );
  response.headers.set('Access-Control-Max-Age', '600');
  response.headers.add(HttpHeaders.varyHeader, 'Access-Control-Request-Method');
  response.headers.add(
    HttpHeaders.varyHeader,
    'Access-Control-Request-Headers',
  );
}

Future<void> _writeJson(
  HttpResponse response,
  Map<String, dynamic> json,
) async {
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(json));
  await response.close();
}

Future<void> _writeOpenAiError(
  HttpResponse response, {
  required int statusCode,
  required String message,
  required String type,
  required String code,
}) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(
    jsonEncode({
      'error': {'message': message, 'type': type, 'code': code},
    }),
  );
  await response.close();
}
