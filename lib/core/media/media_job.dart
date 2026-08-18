import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;

const int universalMediaDiagnosticMaxLength = 512;

/// Redact values that may be surfaced in a task error, recovery snapshot, or
/// local database. This deliberately keeps ordinary provider messages intact
/// while removing credentials, URLs, and machine-local paths.
String? sanitizeUniversalMediaDiagnostic(
  Object? value, {
  int maxLength = universalMediaDiagnosticMaxLength,
}) {
  if (maxLength <= 0) {
    throw ArgumentError.value(maxLength, 'maxLength', '必须大于 0');
  }
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;

  var safe = raw.replaceAll(RegExp(r'\s+'), ' ');
  safe = safe.replaceAll(
    RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    'Bearer ***',
  );
  safe = safe.replaceAllMapped(
    RegExp(
      r'''((?:api[_-]?key|access[_-]?token|token|secret|password))\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;&]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=***',
  );
  safe = safe.replaceAll(
    RegExp(r'\bsk-[A-Za-z0-9_-]+', caseSensitive: false),
    'sk-***',
  );
  safe = safe.replaceAll(
    RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false),
    '[链接]',
  );
  safe = safe.replaceAll(
    RegExp(
      r'''(?:[A-Za-z]:[\\/](?:Users|home|private|var)[^\s<>"']*|/(?:Users|home|private|var)/[^\s<>"']+)''',
      caseSensitive: false,
    ),
    '[本机路径]',
  );
  return safe.length <= maxLength ? safe : '${safe.substring(0, maxLength)}...';
}

const Object _universalMediaCopyWithUnset = Object();

/// 媒体任务的业务类型。
enum UniversalMediaKind { image, video, music }

/// 媒体接口的已知协议族。
///
/// `auto` 保持旧调用方的路径推断；其它值用于把 OpenAI Images、OpenAI
/// Videos、xAI Videos 和完全自定义的异步任务明确区分开，避免 adapter
/// 根据一个模糊的 endpoint 猜错请求体或轮询地址。
enum UniversalMediaProtocol {
  auto,
  openAiImages,
  openAiVideo,
  xAiVideo,
  configuredAsync,
}

/// 提交请求的编码方式。
///
/// `auto` 会在存在本地参考图时选择 multipart（xAI 视频仍使用 JSON data
/// URL）；`json` / `multipart` 可用于需要固定 wire format 的视频、音乐或
/// OpenAI-compatible 中转站。
enum UniversalMediaRequestFormat { auto, json, multipart }

/// 媒体任务状态。
///
/// `expired` 表示服务端报告任务过期，或本地轮询达到 deadline /
/// maxAttempts；它和 `failed` 分开，便于调用方决定是否允许重试。
enum UniversalMediaJobStatus { pending, completed, failed, expired, cancelled }

extension UniversalMediaJobStatusX on UniversalMediaJobStatus {
  bool get isTerminal => this != UniversalMediaJobStatus.pending;
}

/// 一次媒体任务的协议与异步路由配置。
///
/// URL 模板支持 `{id}`、`{job_id}`、`{request_id}` 和 `{identifier}`，替换
/// 时会对服务端任务 ID 做 URL 编码。模板可以是绝对 HTTP(S) URL，也可以
/// 是相对当前提交 URL 的路径；服务端响应里的显式 URL 优先级更高。
class UniversalMediaTaskOptions {
  const UniversalMediaTaskOptions({
    this.protocol = UniversalMediaProtocol.auto,
    this.requestFormat = UniversalMediaRequestFormat.auto,
    this.referenceField,
    this.pollUrlTemplate,
    this.contentUrlTemplate,
    this.cancelUrlTemplate,
  });

  const UniversalMediaTaskOptions.openAiImages({
    this.requestFormat = UniversalMediaRequestFormat.auto,
    this.referenceField,
  }) : protocol = UniversalMediaProtocol.openAiImages,
       pollUrlTemplate = null,
       contentUrlTemplate = null,
       cancelUrlTemplate = null;

  const UniversalMediaTaskOptions.openAiVideo({
    this.requestFormat = UniversalMediaRequestFormat.auto,
    this.referenceField = 'input_reference',
    this.pollUrlTemplate,
    this.contentUrlTemplate,
    this.cancelUrlTemplate,
  }) : protocol = UniversalMediaProtocol.openAiVideo;

  const UniversalMediaTaskOptions.xAiVideo({
    this.pollUrlTemplate,
    this.contentUrlTemplate,
    this.cancelUrlTemplate,
  }) : protocol = UniversalMediaProtocol.xAiVideo,
       requestFormat = UniversalMediaRequestFormat.json,
       referenceField = null;

  const UniversalMediaTaskOptions.configuredAsync({
    this.requestFormat = UniversalMediaRequestFormat.json,
    this.referenceField,
    this.pollUrlTemplate,
    this.contentUrlTemplate,
    this.cancelUrlTemplate,
  }) : protocol = UniversalMediaProtocol.configuredAsync;

  final UniversalMediaProtocol protocol;
  final UniversalMediaRequestFormat requestFormat;
  final String? referenceField;
  final String? pollUrlTemplate;
  final String? contentUrlTemplate;
  final String? cancelUrlTemplate;

  void validate() {
    for (final entry in <String, String?>{
      'referenceField': referenceField,
      'pollUrlTemplate': pollUrlTemplate,
      'contentUrlTemplate': contentUrlTemplate,
      'cancelUrlTemplate': cancelUrlTemplate,
    }.entries) {
      final value = entry.value;
      if (value != null && value.length > 1024) {
        throw ArgumentError.value(value, entry.key, '不能超过 1024 个字符');
      }
      if (value != null && value.contains('\n')) {
        throw ArgumentError.value(value, entry.key, '不能包含换行');
      }
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'protocol': protocol.name,
    'request_format': requestFormat.name,
    if (referenceField != null) 'reference_field': referenceField,
    if (pollUrlTemplate != null) 'poll_url_template': pollUrlTemplate,
    if (contentUrlTemplate != null) 'content_url_template': contentUrlTemplate,
    if (cancelUrlTemplate != null) 'cancel_url_template': cancelUrlTemplate,
  };

  factory UniversalMediaTaskOptions.fromJson(Map<String, dynamic> value) {
    UniversalMediaProtocol parseProtocol(dynamic raw) {
      final normalized = raw?.toString().trim().toLowerCase();
      return UniversalMediaProtocol.values.firstWhere(
        (item) => item.name.toLowerCase() == normalized,
        orElse: () => UniversalMediaProtocol.auto,
      );
    }

    UniversalMediaRequestFormat parseFormat(dynamic raw) {
      final normalized = raw?.toString().trim().toLowerCase();
      return UniversalMediaRequestFormat.values.firstWhere(
        (item) => item.name.toLowerCase() == normalized,
        orElse: () => UniversalMediaRequestFormat.auto,
      );
    }

    String? optionalString(dynamic raw) {
      final text = raw?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final result = UniversalMediaTaskOptions(
      protocol: parseProtocol(value['protocol']),
      requestFormat: parseFormat(
        value['request_format'] ?? value['requestFormat'],
      ),
      referenceField: optionalString(
        value['reference_field'] ?? value['referenceField'],
      ),
      pollUrlTemplate: optionalString(
        value['poll_url_template'] ?? value['pollUrlTemplate'],
      ),
      contentUrlTemplate: optionalString(
        value['content_url_template'] ?? value['contentUrlTemplate'],
      ),
      cancelUrlTemplate: optionalString(
        value['cancel_url_template'] ?? value['cancelUrlTemplate'],
      ),
    );
    result.validate();
    return result;
  }
}

/// 生成媒体的本地安全结果。
///
/// 该类型原本位于 `universal_media_service.dart`，保留同名 public API，
/// 只是移动到任务模型文件，使任务状态可以安全地携带完成后的结果。
class UniversalMediaAsset {
  final Uint8List bytes;
  final String mimeType;
  final String extension;

  const UniversalMediaAsset({
    required this.bytes,
    required this.mimeType,
    required this.extension,
  });
}

/// 可供进程内跟踪、或由上层自行保存的任务状态。
///
/// 这里不负责写数据库，也不会暗示 App 重启后任务会自动恢复。`toRecoveryJson`
/// 只包含重新定位服务端任务所需的字段，不包含媒体二进制；调用方如需跨重启
/// 恢复，应自行持久化这些字段并在重启后显式调用 `pollJob`。
class UniversalMediaJob {
  UniversalMediaJob({
    required this.id,
    required this.kind,
    required this.status,
    this.jobId,
    this.requestId,
    this.pollUrl,
    this.cancelUrl,
    this.contentUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.attempts = 0,
    String? error,
    this.asset,
    this.endpointStyle = UniversalMediaEndpointStyle.auto,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) : createdAt = (createdAt ?? DateTime.now()).toUtc(),
       updatedAt = (updatedAt ?? createdAt ?? DateTime.now()).toUtc(),
       error = sanitizeUniversalMediaDiagnostic(error),
       metadata = Map<String, dynamic>.unmodifiable(metadata);

  final String id;
  final UniversalMediaKind kind;
  final UniversalMediaJobStatus status;

  /// 服务端显式返回的 `job_id` / `id`。
  final String? jobId;

  /// xAI 等服务常用的 `request_id`。
  final String? requestId;

  final Uri? pollUrl;
  final Uri? cancelUrl;
  final Uri? contentUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int attempts;
  final String? error;
  final UniversalMediaAsset? asset;
  final UniversalMediaEndpointStyle endpointStyle;
  final Map<String, dynamic> metadata;

  String get providerId => requestId ?? jobId ?? id;

  bool get isPending => status == UniversalMediaJobStatus.pending;

  bool get isTerminal => status.isTerminal;

  UniversalMediaJob copyWith({
    String? id,
    UniversalMediaKind? kind,
    UniversalMediaJobStatus? status,
    Object? jobId = _universalMediaCopyWithUnset,
    Object? requestId = _universalMediaCopyWithUnset,
    Object? pollUrl = _universalMediaCopyWithUnset,
    Object? cancelUrl = _universalMediaCopyWithUnset,
    Object? contentUrl = _universalMediaCopyWithUnset,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? attempts,
    Object? error = _universalMediaCopyWithUnset,
    Object? asset = _universalMediaCopyWithUnset,
    UniversalMediaEndpointStyle? endpointStyle,
    Map<String, dynamic>? metadata,
  }) {
    return UniversalMediaJob(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      jobId: identical(jobId, _universalMediaCopyWithUnset)
          ? this.jobId
          : jobId as String?,
      requestId: identical(requestId, _universalMediaCopyWithUnset)
          ? this.requestId
          : requestId as String?,
      pollUrl: identical(pollUrl, _universalMediaCopyWithUnset)
          ? this.pollUrl
          : pollUrl as Uri?,
      cancelUrl: identical(cancelUrl, _universalMediaCopyWithUnset)
          ? this.cancelUrl
          : cancelUrl as Uri?,
      contentUrl: identical(contentUrl, _universalMediaCopyWithUnset)
          ? this.contentUrl
          : contentUrl as Uri?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attempts: attempts ?? this.attempts,
      error: identical(error, _universalMediaCopyWithUnset)
          ? this.error
          : error as String?,
      asset: identical(asset, _universalMediaCopyWithUnset)
          ? this.asset
          : asset as UniversalMediaAsset?,
      endpointStyle: endpointStyle ?? this.endpointStyle,
      metadata: metadata ?? this.metadata,
    );
  }

  /// 导出可恢复任务的元数据，不写入 `asset.bytes`。
  Map<String, dynamic> toRecoveryJson() {
    return <String, dynamic>{
      'id': id,
      'kind': kind.name,
      'status': status.name,
      if (jobId != null) 'job_id': jobId,
      if (requestId != null) 'request_id': requestId,
      if (pollUrl != null) 'poll_url': pollUrl.toString(),
      if (cancelUrl != null) 'cancel_url': cancelUrl.toString(),
      if (contentUrl != null) 'content_url': contentUrl.toString(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'attempts': attempts,
      if (error != null) 'error': sanitizeUniversalMediaDiagnostic(error),
      'endpoint_style': endpointStyle.name,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  factory UniversalMediaJob.fromRecoveryJson(Map<String, dynamic> value) {
    final kind = _kindFromRecovery(
      _firstValue(value, const <String>[
        'kind',
        'media_kind',
        'mediaKind',
        'type',
      ]),
    );
    final status = _statusFromRecovery(
      _firstValue(value, const <String>[
        'status',
        'state',
        'task_status',
        'taskStatus',
        'phase',
      ]),
    );
    final style = _endpointStyleFromRecovery(
      _firstValue(value, const <String>['endpoint_style', 'endpointStyle']),
    );
    final id = _nonEmptyString(
      _firstValue(value, const <String>[
        'id',
        'operation_id',
        'operationId',
        'task_id',
        'taskId',
        'job_id',
        'jobId',
        'request_id',
        'requestId',
      ]),
    );
    if (id == null || id.isEmpty) {
      throw const FormatException('媒体任务恢复数据缺少 id');
    }
    return UniversalMediaJob(
      id: id,
      kind: kind,
      status: status,
      jobId: _nonEmptyString(
        _firstValue(value, const <String>[
          'job_id',
          'jobId',
          'task_id',
          'taskId',
          'provider_job_id',
          'providerJobId',
          'generation_id',
          'generationId',
          'video_id',
          'videoId',
          'operation_id',
          'operationId',
        ]),
      ),
      requestId: _nonEmptyString(
        _firstValue(value, const <String>[
          'request_id',
          'requestId',
          'requestID',
        ]),
      ),
      pollUrl: _parseHttpUri(
        _firstValue(value, const <String>[
          'poll_url',
          'pollUrl',
          'status_url',
          'statusUrl',
          'polling_url',
          'pollingUrl',
          'retrieve_url',
          'retrieveUrl',
          'status_endpoint',
          'statusEndpoint',
        ]),
      ),
      cancelUrl: _parseHttpUri(
        _firstValue(value, const <String>[
          'cancel_url',
          'cancelUrl',
          'delete_url',
          'deleteUrl',
          'cancel_endpoint',
          'cancelEndpoint',
          'delete_endpoint',
          'deleteEndpoint',
        ]),
      ),
      contentUrl: _parseHttpUri(
        _firstValue(value, const <String>[
          'content_url',
          'contentUrl',
          'output_url',
          'outputUrl',
          'asset_url',
          'assetUrl',
          'public_url',
          'publicUrl',
        ]),
      ),
      createdAt: _parseDate(
        _firstValue(value, const <String>['created_at', 'createdAt']),
      ),
      updatedAt: _parseDate(
        _firstValue(value, const <String>['updated_at', 'updatedAt']),
      ),
      attempts: _nonNegativeInt(
        _firstValue(value, const <String>[
          'attempts',
          'poll_attempts',
          'pollAttempts',
          'poll_count',
          'pollCount',
        ]),
      ),
      error: _recoveryError(value['error']),
      endpointStyle: style,
      metadata: _mapValue(
        _firstValue(value, const <String>['metadata', 'meta']),
      ),
    );
  }
}

class UniversalMediaJobResult {
  const UniversalMediaJobResult({required this.job, this.asset});

  final UniversalMediaJob job;
  final UniversalMediaAsset? asset;

  bool get isPending => job.status == UniversalMediaJobStatus.pending;

  bool get isCompleted =>
      job.status == UniversalMediaJobStatus.completed && asset != null;
}

/// 轮询的硬边界。所有字段均有限制，避免调用方意外开启无限轮询。
class UniversalMediaPollingOptions {
  const UniversalMediaPollingOptions({
    this.maxAttempts = 60,
    this.deadline = const Duration(minutes: 10),
    this.initialBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 15),
    this.backoffMultiplier = 1.6,
  });

  final int maxAttempts;
  final Duration deadline;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final double backoffMultiplier;

  void validate() {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', '必须大于 0');
    }
    if (deadline <= Duration.zero) {
      throw ArgumentError.value(deadline, 'deadline', '必须大于 0');
    }
    if (initialBackoff < Duration.zero) {
      throw ArgumentError.value(initialBackoff, 'initialBackoff', '不能为负数');
    }
    if (maxBackoff < Duration.zero) {
      throw ArgumentError.value(maxBackoff, 'maxBackoff', '不能为负数');
    }
    if (backoffMultiplier < 1) {
      throw ArgumentError.value(
        backoffMultiplier,
        'backoffMultiplier',
        '必须大于或等于 1',
      );
    }
  }

  Duration delayAfterAttempt(int attempt) {
    if (attempt <= 0 || initialBackoff == Duration.zero) {
      return Duration.zero;
    }
    var factor = 1.0;
    for (var index = 1; index < attempt; index++) {
      factor *= backoffMultiplier;
      if (factor.isInfinite || factor > 1e12) {
        factor = 1e12;
        break;
      }
    }
    final rawMillis = initialBackoff.inMilliseconds * factor;
    final boundedMillis = math.min(maxBackoff.inMilliseconds, rawMillis.ceil());
    return Duration(milliseconds: math.max(0, boundedMillis));
  }
}

/// adapter 的 submit 输入。
class UniversalMediaSubmitRequest {
  const UniversalMediaSubmitRequest({
    required this.baseUri,
    required this.apiKey,
    required this.kind,
    required this.model,
    required this.prompt,
    required this.endpoint,
    required this.endpointStyle,
    this.taskOptions = const UniversalMediaTaskOptions(),
    this.referenceImagePath,
    this.extra = const <String, dynamic>{},
    this.cancelToken,
  });

  final Uri baseUri;
  final String apiKey;
  final UniversalMediaKind kind;
  final String model;
  final String prompt;
  final String endpoint;
  final UniversalMediaEndpointStyle endpointStyle;
  final UniversalMediaTaskOptions taskOptions;
  final String? referenceImagePath;
  final Map<String, dynamic> extra;
  final CancelToken? cancelToken;
}

class UniversalMediaPollRequest {
  const UniversalMediaPollRequest({
    required this.baseUri,
    required this.apiKey,
    required this.job,
    this.cancelToken,
  });

  final Uri baseUri;
  final String apiKey;
  final UniversalMediaJob job;
  final CancelToken? cancelToken;
}

class UniversalMediaCancelRequest {
  const UniversalMediaCancelRequest({
    required this.baseUri,
    required this.apiKey,
    required this.job,
    this.cancelToken,
  });

  final Uri baseUri;
  final String apiKey;
  final UniversalMediaJob job;
  final CancelToken? cancelToken;
}

/// adapter 的统一 HTTP 返回值。
///
/// adapter 只负责 HTTP 传输；状态、任务 id 和媒体候选由
/// `UniversalMediaResponseParser` 统一解析，方便不同厂商共用同一套服务逻辑。
class UniversalMediaHttpResponse {
  UniversalMediaHttpResponse({
    required this.statusCode,
    required this.requestUri,
    required List<int> bytes,
    Map<String, String> headers = const <String, String>{},
  }) : bytes = Uint8List.fromList(bytes),
       headers = Map<String, String>.unmodifiable(headers);

  final int statusCode;
  final Uri requestUri;
  final Uint8List bytes;
  final Map<String, String> headers;

  String? header(String name) {
    final wanted = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }
}

/// 媒体服务 adapter contract。
///
/// 自定义厂商可以实现这三个动作；服务层仍会统一完成状态映射、轮询边界、
/// URL / base64 / data URI / 二进制解析和大小限制。
abstract interface class UniversalMediaAdapter {
  Future<UniversalMediaHttpResponse> submit(
    UniversalMediaSubmitRequest request,
  );

  Future<UniversalMediaHttpResponse> poll(UniversalMediaPollRequest request);

  Future<UniversalMediaHttpResponse> cancel(
    UniversalMediaCancelRequest request,
  );
}

/// 轮询 URL 的常见协议形状。
enum UniversalMediaEndpointStyle { auto, custom, openAiVideo, xAiRequestId }

/// OpenAI 视频和 xAI `request_id` 任务 URL 构造器。
///
/// 该类不发请求，便于 adapter / 单元测试直接验证 URL。对于
/// `/v1/videos/generations`，两种内建风格都会构造 `/v1/videos/{id}`；
/// 对其它 `.../generations` 路径则替换 `generations` 为任务 id。
class UniversalMediaEndpointBuilder {
  const UniversalMediaEndpointBuilder._();

  /// 将自定义异步 URL 模板解析为绝对 HTTP(S) URL。
  static Uri? templateUrl({
    required Uri submitUri,
    required String template,
    required String identifier,
  }) {
    final rawTemplate = template.trim();
    if (rawTemplate.isEmpty) return null;
    final encoded = Uri.encodeComponent(identifier);
    final expanded = rawTemplate
        .replaceAll('{id}', encoded)
        .replaceAll('{job_id}', encoded)
        .replaceAll('{request_id}', encoded)
        .replaceAll('{identifier}', encoded);
    final parsed = Uri.tryParse(expanded);
    if (parsed == null) return null;
    final resolved = parsed.hasScheme ? parsed : submitUri.resolveUri(parsed);
    final scheme = resolved.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || resolved.host.isEmpty) {
      return null;
    }
    return resolved;
  }

  static Uri openAiVideoPollUrl({
    required Uri submitUri,
    required String videoId,
  }) {
    final segments = submitUri.pathSegments;
    final videoIndex = _lastSegmentIndex(
      segments,
      (segment) => segment.toLowerCase() == 'videos',
    );
    final prefix = videoIndex < 0
        ? <String>['v1', 'videos']
        : segments.sublist(0, videoIndex + 1);
    return _replacePath(submitUri, <String>[...prefix, videoId]);
  }

  static Uri xAiRequestIdPollUrl({
    required Uri submitUri,
    required String requestId,
  }) {
    final segments = submitUri.pathSegments;
    final videoIndex = _lastSegmentIndex(
      segments,
      (segment) => segment.toLowerCase() == 'videos',
    );
    if (videoIndex >= 0) {
      // xAI uses the same `/v1/videos/{request_id}` retrieval path for
      // generations, edits and extensions. Do not append the id below
      // `/videos/edits` or `/videos/extensions`.
      return _replacePath(submitUri, <String>[
        ...segments.sublist(0, videoIndex + 1),
        requestId,
      ]);
    }
    final generationIndex = _lastSegmentIndex(
      segments,
      (segment) =>
          segment.toLowerCase() == 'generations' ||
          segment.toLowerCase() == 'generation',
    );
    final prefix = generationIndex >= 0
        ? segments.sublist(0, generationIndex)
        : segments;
    return _replacePath(submitUri, <String>[...prefix, requestId]);
  }

  static Uri openAiVideoContentUrl({
    required Uri submitUri,
    required String videoId,
  }) {
    final pollUrl = openAiVideoPollUrl(submitUri: submitUri, videoId: videoId);
    return _replacePath(pollUrl, <String>[...pollUrl.pathSegments, 'content']);
  }

  static Uri buildPollUrl({
    required Uri submitUri,
    required String identifier,
    UniversalMediaEndpointStyle style = UniversalMediaEndpointStyle.auto,
    Uri? explicitUrl,
  }) {
    if (explicitUrl != null) return explicitUrl;
    switch (style) {
      case UniversalMediaEndpointStyle.openAiVideo:
        return openAiVideoPollUrl(submitUri: submitUri, videoId: identifier);
      case UniversalMediaEndpointStyle.xAiRequestId:
        return xAiRequestIdPollUrl(submitUri: submitUri, requestId: identifier);
      case UniversalMediaEndpointStyle.custom:
      case UniversalMediaEndpointStyle.auto:
        if (submitUri.pathSegments.any(
          (segment) => segment.toLowerCase() == 'videos',
        )) {
          return openAiVideoPollUrl(submitUri: submitUri, videoId: identifier);
        }
        return xAiRequestIdPollUrl(submitUri: submitUri, requestId: identifier);
    }
  }

  static Uri _replacePath(Uri source, List<String> segments) {
    return Uri(
      scheme: source.scheme,
      userInfo: source.userInfo,
      host: source.host,
      port: source.port,
      pathSegments: segments,
      query: source.hasQuery ? source.query : null,
    );
  }

  static int _lastSegmentIndex(
    List<String> segments,
    bool Function(String segment) predicate,
  ) {
    for (var index = segments.length - 1; index >= 0; index--) {
      if (predicate(segments[index])) return index;
    }
    return -1;
  }
}

/// JSON / 二进制响应中的媒体候选，尚未下载远端 URL。
class UniversalMediaPayload {
  const UniversalMediaPayload({
    this.bytes,
    this.value,
    this.isBase64 = false,
    this.mimeType,
    this.requiresAuth = false,
  });

  final Uint8List? bytes;
  final String? value;
  final bool isBase64;
  final String? mimeType;
  final bool requiresAuth;

  bool get isBinary => bytes != null;

  bool get isString => value != null;
}

/// `UniversalMediaResponseParser` 的结果。
class UniversalMediaParsedResponse {
  const UniversalMediaParsedResponse({
    required this.status,
    required this.statusCode,
    this.identifier,
    this.jobId,
    this.requestId,
    this.pollUrl,
    this.cancelUrl,
    this.contentUrl,
    this.media,
    this.error,
    this.providerStatus,
    this.endpointStyle = UniversalMediaEndpointStyle.auto,
  });

  final UniversalMediaJobStatus status;
  final int statusCode;
  final String? identifier;
  final String? jobId;
  final String? requestId;
  final Uri? pollUrl;
  final Uri? cancelUrl;
  final Uri? contentUrl;
  final UniversalMediaPayload? media;
  final String? error;
  final String? providerStatus;
  final UniversalMediaEndpointStyle endpointStyle;

  bool get hasMedia => media != null;
}

/// 识别常见图片 / 视频 / 音乐响应形状，包含 OpenAI 视频和 xAI request_id。
class UniversalMediaResponseParser {
  const UniversalMediaResponseParser._();

  static UniversalMediaParsedResponse parse({
    required UniversalMediaKind kind,
    required int statusCode,
    required Map<String, String> headers,
    required List<int> body,
    Uri? submitUri,
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    String? mimeHint,
  }) {
    taskOptions.validate();
    final contentType = _header(headers, 'content-type') ?? '';
    final normalizedContentType = contentType
        .split(';')
        .first
        .trim()
        .toLowerCase();
    final explicitBinaryContentType =
        normalizedContentType.startsWith('image/') ||
        normalizedContentType.startsWith('video/') ||
        normalizedContentType.startsWith('audio/') ||
        normalizedContentType == 'application/octet-stream';
    final looksLikeJson =
        !explicitBinaryContentType &&
        (normalizedContentType.contains('json') || _looksLikeJson(body));

    if (body.isEmpty) {
      final location = _parseHttpUri(
        _header(headers, 'location'),
        base: submitUri,
      );
      final status = location != null && statusCode >= 200 && statusCode < 300
          ? UniversalMediaJobStatus.pending
          : _statusForHttpCode(statusCode);
      return UniversalMediaParsedResponse(
        status: status,
        statusCode: statusCode,
        pollUrl: status == UniversalMediaJobStatus.pending ? location : null,
        error: status.isTerminal ? '接口未返回媒体内容' : null,
        endpointStyle: endpointStyle,
      );
    }

    if (!looksLikeJson) {
      final status = statusCode < 200 || statusCode >= 300
          ? _statusForHttpCode(statusCode)
          : UniversalMediaJobStatus.completed;
      return UniversalMediaParsedResponse(
        status: status,
        statusCode: statusCode,
        media: status == UniversalMediaJobStatus.completed
            ? UniversalMediaPayload(
                bytes: Uint8List.fromList(body),
                mimeType: _binaryMimeHint(
                  contentType: contentType,
                  mimeHint: mimeHint,
                  kind: kind,
                ),
              )
            : null,
        error: status == UniversalMediaJobStatus.completed
            ? null
            : '媒体接口返回 HTTP $statusCode',
        endpointStyle: endpointStyle,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(body).replaceFirst('\uFEFF', ''));
    } catch (_) {
      return UniversalMediaParsedResponse(
        status: UniversalMediaJobStatus.failed,
        statusCode: statusCode,
        error: '媒体接口返回格式异常',
        endpointStyle: endpointStyle,
      );
    }

    final root = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{'data': decoded};
    final providerStatus = _findString(root, const <String>[
      'status',
      'state',
      'task_status',
      'taskStatus',
      'phase',
      'task_state',
      'taskState',
    ]);
    final jobId = _findString(root, const <String>[
      'job_id',
      'jobId',
      'task_id',
      'taskId',
      'generation_id',
      'generationId',
      'video_id',
      'videoId',
      'operation_id',
      'operationId',
    ]);
    final requestId = _findString(root, const <String>[
      'request_id',
      'requestId',
    ]);
    final genericId = _findString(root, const <String>['id']);
    final identifier = requestId ?? jobId ?? genericId;
    final media = _findMedia(
      root,
      kind: kind,
      contentType: contentType,
      mimeHint: mimeHint,
    );
    final explicitPoll =
        _findUri(root, const <String>[
          'poll_url',
          'pollUrl',
          'status_url',
          'statusUrl',
          'check_url',
          'checkUrl',
          'polling_url',
          'pollingUrl',
          'retrieve_url',
          'retrieveUrl',
          'status_endpoint',
          'statusEndpoint',
        ], base: submitUri) ??
        _parseHttpUri(_header(headers, 'location'), base: submitUri);
    final explicitCancel = _findUri(root, const <String>[
      'cancel_url',
      'cancelUrl',
      'delete_url',
      'deleteUrl',
      'cancel_endpoint',
      'cancelEndpoint',
      'delete_endpoint',
      'deleteEndpoint',
    ], base: submitUri);
    final success = _findBoolean(root, const <String>['success', 'ok']);
    final status = _resolveStatus(
      statusCode: statusCode,
      providerStatus: providerStatus,
      identifier: identifier,
      media: media,
      success: success,
      root: root,
    );
    final error =
        sanitizeUniversalMediaDiagnostic(_findError(root)) ??
        (status == UniversalMediaJobStatus.failed
            ? '媒体任务失败'
            : status == UniversalMediaJobStatus.expired
            ? '媒体任务已过期'
            : null);
    final style = _effectiveEndpointStyle(
      endpointStyle: endpointStyle,
      taskOptions: taskOptions,
      requestId: requestId,
    );
    final configuredPoll = identifier != null && submitUri != null
        ? UniversalMediaEndpointBuilder.templateUrl(
            submitUri: submitUri,
            template: taskOptions.pollUrlTemplate ?? '',
            identifier: identifier,
          )
        : null;
    final pollUrl =
        status == UniversalMediaJobStatus.pending &&
            identifier != null &&
            submitUri != null
        ? UniversalMediaEndpointBuilder.buildPollUrl(
            submitUri: submitUri,
            identifier: identifier,
            style: style,
            explicitUrl: explicitPoll ?? configuredPoll,
          )
        : explicitPoll ?? configuredPoll;
    final configuredCancel = identifier != null && submitUri != null
        ? UniversalMediaEndpointBuilder.templateUrl(
            submitUri: submitUri,
            template: taskOptions.cancelUrlTemplate ?? '',
            identifier: identifier,
          )
        : null;
    final cancelUrl =
        explicitCancel ??
        configuredCancel ??
        (identifier != null &&
                submitUri != null &&
                (style == UniversalMediaEndpointStyle.openAiVideo ||
                    style == UniversalMediaEndpointStyle.custom ||
                    (style == UniversalMediaEndpointStyle.auto &&
                        submitUri.pathSegments.any(
                          (segment) => segment.toLowerCase() == 'videos',
                        )))
            ? UniversalMediaEndpointBuilder.buildPollUrl(
                submitUri: submitUri,
                identifier: identifier,
                style: style,
              )
            : null);
    var contentUrl = media?.value != null && submitUri != null
        ? _parseHttpUri(media!.value!, base: submitUri)
        : null;
    contentUrl ??= identifier != null && submitUri != null
        ? UniversalMediaEndpointBuilder.templateUrl(
            submitUri: submitUri,
            template: taskOptions.contentUrlTemplate ?? '',
            identifier: identifier,
          )
        : null;
    if (contentUrl == null &&
        status == UniversalMediaJobStatus.completed &&
        identifier != null &&
        submitUri != null &&
        (style == UniversalMediaEndpointStyle.openAiVideo ||
            (style == UniversalMediaEndpointStyle.auto &&
                submitUri.pathSegments.any(
                  (segment) => segment.toLowerCase() == 'videos',
                )))) {
      contentUrl = UniversalMediaEndpointBuilder.openAiVideoContentUrl(
        submitUri: submitUri,
        videoId: identifier,
      );
    }

    return UniversalMediaParsedResponse(
      status: status,
      statusCode: statusCode,
      identifier: identifier,
      jobId: jobId,
      requestId: requestId,
      pollUrl: pollUrl,
      cancelUrl: cancelUrl,
      contentUrl: contentUrl,
      media: media,
      error: error,
      providerStatus: providerStatus,
      endpointStyle: style,
    );
  }

  static UniversalMediaEndpointStyle _effectiveEndpointStyle({
    required UniversalMediaEndpointStyle endpointStyle,
    required UniversalMediaTaskOptions taskOptions,
    required String? requestId,
  }) {
    if (endpointStyle != UniversalMediaEndpointStyle.auto) {
      return endpointStyle;
    }
    return switch (taskOptions.protocol) {
      UniversalMediaProtocol.openAiVideo =>
        UniversalMediaEndpointStyle.openAiVideo,
      UniversalMediaProtocol.xAiVideo =>
        UniversalMediaEndpointStyle.xAiRequestId,
      _ =>
        requestId != null
            ? UniversalMediaEndpointStyle.xAiRequestId
            : UniversalMediaEndpointStyle.auto,
    };
  }

  static UniversalMediaJobStatus _resolveStatus({
    required int statusCode,
    required String? providerStatus,
    required String? identifier,
    required UniversalMediaPayload? media,
    required bool? success,
    required Map<String, dynamic> root,
  }) {
    // An HTTP error is authoritative even when a proxy echoes a stale
    // `status: completed` or media field in its error envelope.
    if (statusCode == 410 || _containsExpiredMarker(root)) {
      return UniversalMediaJobStatus.expired;
    }
    if (statusCode < 200 || statusCode >= 300) {
      return _statusForHttpCode(statusCode);
    }
    if (success == false) return UniversalMediaJobStatus.failed;
    final normalized = providerStatus?.trim().toLowerCase();
    final fromProvider = _statusFromString(normalized);
    if (fromProvider != null) {
      if (fromProvider == UniversalMediaJobStatus.pending && media != null) {
        return UniversalMediaJobStatus.completed;
      }
      return fromProvider;
    }
    if (media != null) return UniversalMediaJobStatus.completed;
    if (statusCode == 202 || identifier != null) {
      return UniversalMediaJobStatus.pending;
    }
    return UniversalMediaJobStatus.failed;
  }

  static UniversalMediaJobStatus? _statusFromString(String? value) {
    switch (value) {
      case 'pending':
      case 'queued':
      case 'in_progress':
      case 'in-progress':
      case 'inprogress':
      case 'in progress':
      case 'processing':
      case 'running':
      case 'waiting':
      case 'not_started':
      case 'not-started':
      case 'submitted':
      case 'created':
      case 'starting':
      case 'generating':
        return UniversalMediaJobStatus.pending;
      case 'completed':
      case 'complete':
      case 'succeeded':
      case 'success':
      case 'done':
      case 'ready':
        return UniversalMediaJobStatus.completed;
      case 'failed':
      case 'failure':
      case 'error':
        return UniversalMediaJobStatus.failed;
      case 'expired':
      case 'timeout':
      case 'timed_out':
      case 'timed-out':
        return UniversalMediaJobStatus.expired;
      case 'cancelled':
      case 'canceled':
      case 'aborted':
        return UniversalMediaJobStatus.cancelled;
      default:
        return null;
    }
  }

  static UniversalMediaJobStatus _statusForHttpCode(int statusCode) {
    if (statusCode == 410) return UniversalMediaJobStatus.expired;
    if (statusCode >= 400) return UniversalMediaJobStatus.failed;
    return statusCode == 202
        ? UniversalMediaJobStatus.pending
        : UniversalMediaJobStatus.failed;
  }

  static UniversalMediaPayload? _findMedia(
    Map<String, dynamic> root, {
    required UniversalMediaKind kind,
    required String contentType,
    String? mimeHint,
  }) {
    final inheritedMime = contentType.toLowerCase().contains('json')
        ? (mimeHint ?? '')
        : contentType;
    final direct = _findMediaInMap(
      root,
      kind: kind,
      inheritedMime: inheritedMime,
    );
    return direct;
  }

  static UniversalMediaPayload? _findMediaInMap(
    Map<String, dynamic> value, {
    required UniversalMediaKind kind,
    required String inheritedMime,
  }) {
    final mime = _mimeFromMap(value, kind: kind) ?? inheritedMime;
    for (final key in const <String>['bytes', 'byte_data', 'binary']) {
      final bytes = _bytesFromJson(value[key]);
      if (bytes != null) {
        return UniversalMediaPayload(bytes: bytes, mimeType: mime);
      }
    }
    for (final key in const <String>[
      'b64_json',
      'b64Json',
      'base64_json',
      'base64Json',
      'base64',
      'base64_data',
      'base64Data',
      'b64',
      'image_base64',
      'imageBase64',
      'video_base64',
      'videoBase64',
      'audio_base64',
      'audioBase64',
      'media_base64',
      'mediaBase64',
    ]) {
      final candidate = value[key];
      if (candidate is String && candidate.trim().isNotEmpty) {
        return UniversalMediaPayload(
          value: candidate.trim(),
          isBase64: true,
          mimeType: mime,
        );
      }
    }
    for (final key in const <String>[
      'data_uri',
      'dataUri',
      'data_url',
      'dataUrl',
      'url',
      'video_url',
      'videoUrl',
      'audio_url',
      'audioUrl',
      'image_url',
      'imageUrl',
      'download_url',
      'downloadUrl',
      'download_uri',
      'downloadUri',
      'signed_url',
      'signedUrl',
      'output_url',
      'outputUrl',
      'asset_url',
      'assetUrl',
      'public_url',
      'publicUrl',
      'content_url',
      'contentUrl',
      'file_url',
      'fileUrl',
      'media_url',
      'mediaUrl',
      'uri',
    ]) {
      final candidate = value[key];
      if (candidate is String && candidate.trim().isNotEmpty) {
        return UniversalMediaPayload(value: candidate.trim(), mimeType: mime);
      }
    }

    for (final key in const <String>[
      'data',
      'output',
      'result',
      'media',
      'file',
      'file_output',
      'fileOutput',
      'asset',
      'assets',
      'download',
      'links',
      'video',
      'videos',
      'audio',
      'music',
      'image',
      'images',
      'content',
      'body',
      'payload',
    ]) {
      final nested = value[key];
      final found = _findMediaInValue(
        nested,
        kind: kind,
        inheritedMime: mime,
        allowShortBase64: key == 'data' || key == 'output' || key == 'content',
      );
      if (found != null) return found;
    }
    return null;
  }

  static UniversalMediaPayload? _findMediaInValue(
    dynamic value, {
    required UniversalMediaKind kind,
    required String inheritedMime,
    bool allowShortBase64 = false,
  }) {
    if (value is Map) {
      final map = _stringKeyedMap(value);
      if (map == null) return null;
      return _findMediaInMap(map, kind: kind, inheritedMime: inheritedMime);
    }
    if (value is List) {
      final bytes = _bytesFromJson(value);
      if (bytes != null) {
        return UniversalMediaPayload(bytes: bytes, mimeType: inheritedMime);
      }
      for (final item in value) {
        final found = _findMediaInValue(
          item,
          kind: kind,
          inheritedMime: inheritedMime,
          allowShortBase64: allowShortBase64,
        );
        if (found != null) return found;
      }
      return null;
    }
    if (value is String) {
      final candidate = value.trim();
      if (candidate.isEmpty) return null;
      if (_isDataUri(candidate) ||
          _isHttpUrl(candidate) ||
          _isRelativeMediaUrl(candidate)) {
        return UniversalMediaPayload(value: candidate, mimeType: inheritedMime);
      }
      if (_looksLikeBase64(candidate, allowShort: allowShortBase64)) {
        return UniversalMediaPayload(
          value: candidate,
          isBase64: true,
          mimeType: inheritedMime,
        );
      }
    }
    return null;
  }

  static String? _mimeFromMap(
    Map<String, dynamic> value, {
    required UniversalMediaKind kind,
  }) {
    for (final key in const <String>[
      'mime_type',
      'mimeType',
      'content_type',
      'contentType',
      'media_type',
      'mediaType',
      'type',
    ]) {
      final candidate = value[key];
      if (candidate is String && candidate.contains('/')) {
        return candidate.trim();
      }
    }
    for (final key in const <String>[
      'output_format',
      'outputFormat',
      'format',
      'extension',
      'file_extension',
      'fileExtension',
    ]) {
      final candidate = value[key];
      if (candidate is! String) continue;
      final format = candidate.trim().toLowerCase().replaceFirst('.', '');
      final mime = switch (format) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'avif' => 'image/avif',
        'mp4' => 'video/mp4',
        'webm' =>
          kind == UniversalMediaKind.video ? 'video/webm' : 'audio/webm',
        'mov' || 'qt' => 'video/quicktime',
        'mp3' || 'mpeg' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'ogg' || 'oga' => 'audio/ogg',
        'opus' => 'audio/opus',
        'm4a' || 'mp4a' => 'audio/mp4',
        'aac' => 'audio/aac',
        'flac' => 'audio/flac',
        _ => null,
      };
      if (mime != null) return mime;
    }
    return null;
  }

  static Uint8List? _bytesFromJson(dynamic value) {
    if (value is! List || value.isEmpty) return null;
    final bytes = <int>[];
    for (final item in value) {
      if (item is! num || item % 1 != 0 || item < 0 || item > 255) {
        return null;
      }
      bytes.add(item.toInt());
    }
    return Uint8List.fromList(bytes);
  }

  static Map<String, dynamic>? _stringKeyedMap(Map value) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) return null;
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static String? _findString(dynamic value, List<String> keys) {
    if (value is Map) {
      for (final key in keys) {
        final candidate = value[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
      for (final nested in value.values) {
        final found = _findString(nested, keys);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final nested in value) {
        final found = _findString(nested, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static bool? _findBoolean(dynamic value, List<String> keys) {
    if (value is Map) {
      for (final key in keys) {
        final candidate = value[key];
        if (candidate is bool) return candidate;
        if (candidate is String) {
          final normalized = candidate.trim().toLowerCase();
          if (normalized == 'true') return true;
          if (normalized == 'false') return false;
        }
      }
      for (final nested in value.values) {
        final found = _findBoolean(nested, keys);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final nested in value) {
        final found = _findBoolean(nested, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static Uri? _findUri(dynamic value, List<String> keys, {required Uri? base}) {
    if (value is Map) {
      for (final key in keys) {
        final candidate = value[key];
        final uri = _uriFromCandidate(candidate, base: base);
        if (uri != null) return uri;
      }
      for (final nested in value.values) {
        final found = _findUri(nested, keys, base: base);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final nested in value) {
        final found = _findUri(nested, keys, base: base);
        if (found != null) return found;
      }
    }
    return null;
  }

  static Uri? _uriFromCandidate(dynamic value, {required Uri? base}) {
    if (value is String && value.trim().isNotEmpty) {
      return _parseHttpUri(value.trim(), base: base);
    }
    if (value is Map) {
      for (final key in const <String>['url', 'href', 'uri', 'endpoint']) {
        final nested = value[key];
        if (nested is String) {
          final uri = _parseHttpUri(nested, base: base);
          if (uri != null) return uri;
        }
      }
    }
    return null;
  }

  static String? _findError(dynamic value) {
    if (value is Map) {
      final error = value['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
      if (error is Map) {
        final message = error['message'] ?? error['detail'] ?? error['reason'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      for (final key in const <String>[
        'failure_reason',
        'failureReason',
        'failure',
        'errors',
        'error_message',
        'errorMessage',
        'detail',
        'message',
      ]) {
        final message = value[key];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      for (final nested in value.values) {
        final found = _findError(nested);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final nested in value) {
        final found = _findError(nested);
        if (found != null) return found;
      }
    }
    return null;
  }

  static bool _containsExpiredMarker(dynamic value) {
    if (value is Map) {
      for (final key in const <String>['expired', 'is_expired', 'isExpired']) {
        if (value[key] == true) return true;
        if (value[key] is String &&
            (value[key] as String).trim().toLowerCase() == 'true') {
          return true;
        }
      }
      return value.values.any(_containsExpiredMarker);
    }
    if (value is List) return value.any(_containsExpiredMarker);
    return false;
  }

  static Uri? _parseHttpUri(dynamic value, {Uri? base}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = Uri.tryParse(text);
    if (parsed == null) return null;
    final resolved = parsed.hasScheme ? parsed : base?.resolveUri(parsed);
    if (resolved == null || !_isHttpUrl(resolved.toString())) return null;
    return resolved;
  }

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    final scheme = uri?.scheme.toLowerCase();
    return uri != null &&
        uri.host.isNotEmpty &&
        (scheme == 'http' || scheme == 'https');
  }

  static bool _isDataUri(String value) =>
      value.trim().toLowerCase().startsWith('data:');

  static bool _isRelativeMediaUrl(String value) {
    return value.startsWith('/') ||
        value.startsWith('./') ||
        value.startsWith('../');
  }

  static bool _looksLikeBase64(String value, {bool allowShort = false}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '');
    if ((!allowShort && normalized.length < 16) ||
        normalized.length < 4 ||
        normalized.contains('://') ||
        _isDataUri(normalized) ||
        normalized.length % 4 == 1) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(normalized);
  }

  static bool _looksLikeJson(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final text = utf8
        .decode(bytes.take(64).toList(), allowMalformed: true)
        .replaceFirst('\uFEFF', '')
        .trimLeft();
    return text.startsWith('{') || text.startsWith('[');
  }

  static String? _header(Map<String, String> headers, String name) {
    final wanted = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  static String _binaryMimeHint({
    required String contentType,
    required String? mimeHint,
    required UniversalMediaKind kind,
  }) {
    final normalized = contentType.split(';').first.trim().toLowerCase();
    final matchesKind = switch (kind) {
      UniversalMediaKind.image => normalized.startsWith('image/'),
      UniversalMediaKind.video => normalized.startsWith('video/'),
      UniversalMediaKind.music => normalized.startsWith('audio/'),
    };
    if (mimeHint != null &&
        mimeHint.trim().isNotEmpty &&
        (!matchesKind ||
            normalized == 'application/octet-stream' ||
            normalized == 'application/json')) {
      return mimeHint;
    }
    return contentType.isEmpty ? (mimeHint ?? '') : contentType;
  }
}

dynamic _firstValue(Map<String, dynamic> value, List<String> keys) {
  for (final key in keys) {
    if (value.containsKey(key)) return value[key];
  }
  return null;
}

UniversalMediaKind _kindFromRecovery(dynamic value) {
  switch (value?.toString().trim().toLowerCase()) {
    case 'image':
      return UniversalMediaKind.image;
    case 'music':
    case 'audio':
    case 'sound':
      return UniversalMediaKind.music;
    case 'video':
      return UniversalMediaKind.video;
    default:
      return UniversalMediaKind.video;
  }
}

UniversalMediaJobStatus _statusFromRecovery(dynamic value) {
  final normalized = value
      ?.toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  switch (normalized) {
    case 'pending':
    case 'queued':
    case 'in_progress':
    case 'inprogress':
    case 'processing':
    case 'running':
    case 'submitted':
    case 'created':
    case 'starting':
    case 'generating':
      return UniversalMediaJobStatus.pending;
    case 'completed':
    case 'complete':
    case 'succeeded':
    case 'success':
    case 'done':
    case 'ready':
      return UniversalMediaJobStatus.completed;
    case 'failed':
    case 'failure':
    case 'error':
      return UniversalMediaJobStatus.failed;
    case 'expired':
    case 'timeout':
    case 'timed_out':
      return UniversalMediaJobStatus.expired;
    case 'cancelled':
    case 'canceled':
    case 'aborted':
      return UniversalMediaJobStatus.cancelled;
    default:
      return UniversalMediaJobStatus.pending;
  }
}

UniversalMediaEndpointStyle _endpointStyleFromRecovery(dynamic value) {
  final normalized = value
      ?.toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '')
      .replaceAll('_', '');
  switch (normalized) {
    case 'custom':
      return UniversalMediaEndpointStyle.custom;
    case 'openaivideo':
    case 'openai':
      return UniversalMediaEndpointStyle.openAiVideo;
    case 'xairequestid':
    case 'xai':
      return UniversalMediaEndpointStyle.xAiRequestId;
    default:
      return UniversalMediaEndpointStyle.auto;
  }
}

String? _nonEmptyString(dynamic value) {
  if (value == null || value is Map || value is List) return null;
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

String? _recoveryError(dynamic value) {
  final direct = _nonEmptyString(value);
  if (direct != null) return sanitizeUniversalMediaDiagnostic(direct);
  if (value is Map) {
    return sanitizeUniversalMediaDiagnostic(
      _nonEmptyString(value['message'] ?? value['detail'] ?? value['reason']),
    );
  }
  return null;
}

DateTime _parseDate(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return (parsed ?? DateTime.now()).toUtc();
}

int _nonNegativeInt(dynamic value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed == null || parsed < 0 ? 0 : parsed;
}

Uri? _parseHttpUri(dynamic value) {
  final parsed = Uri.tryParse(value?.toString() ?? '');
  final scheme = parsed?.scheme.toLowerCase();
  if (parsed == null || (scheme != 'http' && scheme != 'https')) {
    return null;
  }
  return parsed;
}

Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) result[entry.key as String] = entry.value;
    }
    return result;
  }
  return <String, dynamic>{};
}
