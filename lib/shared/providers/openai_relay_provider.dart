import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';
import '../../core/relay/channel_model_relay_bridge.dart';
import '../../core/relay/openai_compatible_relay_server.dart';
import 'database_provider.dart';

const kOpenAiRelayTokenStorageKey = 'openai_relay_token_v1';
const kOpenAiRelayPortStorageKey = 'openai_relay_port_v1';
const kOpenAiRelayBindModeStorageKey = 'openai_relay_bind_mode_v1';
const kOpenAiRelayRouteStrategyStorageKey = 'openai_relay_route_strategy_v1';
const kOpenAiRelayMaxConcurrentRequestsStorageKey =
    'openai_relay_max_concurrent_requests_v1';
const kOpenAiRelayRemoteImageDownloadStorageKey =
    'openai_relay_remote_image_download_v1';
const kOpenAiRelayUsageStatsStorageKey = 'openai_relay_usage_stats_v1';
const kOpenAiRelayAuditLogStorageKey = 'openai_relay_audit_log_v1';
const kOpenAiRelayDefaultPort = 0;
const kOpenAiRelayMinTokenLength = 16;
const kOpenAiRelayDefaultConcurrentRequests =
    kOpenAiRelayDefaultMaxConcurrentRequests;
const kOpenAiRelayMinConcurrentRequests = 1;
const kOpenAiRelayMaxConcurrentRequests = 32;
const kOpenAiRelayMaxAuditLogEntries = 100;

enum OpenAiRelayStatus { stopped, starting, running, stopping, error }

enum OpenAiRelayBindMode {
  loopback,
  localNetwork;

  String get storageValue => switch (this) {
    OpenAiRelayBindMode.loopback => 'loopback',
    OpenAiRelayBindMode.localNetwork => 'local_network',
  };

  String get label => switch (this) {
    OpenAiRelayBindMode.loopback => '仅本机访问',
    OpenAiRelayBindMode.localNetwork => '局域网访问',
  };

  static OpenAiRelayBindMode fromStorage(String? value) {
    return switch (value) {
      'local_network' => OpenAiRelayBindMode.localNetwork,
      _ => OpenAiRelayBindMode.loopback,
    };
  }
}

class OpenAiRelayAuditSummary {
  const OpenAiRelayAuditSummary({
    this.totalRequests = 0,
    this.authorizedRequests = 0,
    this.rejectedRequests = 0,
    this.unauthorizedRequests = 0,
    this.rateLimitedRequests = 0,
    this.lastStatusCode,
    this.lastCode,
    this.lastRequestAt,
    this.lastDurationMs,
  });

  final int totalRequests;
  final int authorizedRequests;
  final int rejectedRequests;
  final int unauthorizedRequests;
  final int rateLimitedRequests;
  final int? lastStatusCode;
  final String? lastCode;
  final DateTime? lastRequestAt;
  final int? lastDurationMs;

  OpenAiRelayAuditSummary record(OpenAiRelayAuditEvent event) {
    final rejected = event.statusCode >= 400;
    return OpenAiRelayAuditSummary(
      totalRequests: totalRequests + 1,
      authorizedRequests: authorizedRequests + (event.authorized ? 1 : 0),
      rejectedRequests: rejectedRequests + (rejected ? 1 : 0),
      unauthorizedRequests: unauthorizedRequests + (!event.authorized ? 1 : 0),
      rateLimitedRequests:
          rateLimitedRequests + (event.code == 'concurrency_limit' ? 1 : 0),
      lastStatusCode: event.statusCode,
      lastCode: event.code,
      lastRequestAt: event.completedAt,
      lastDurationMs: event.duration.inMilliseconds,
    );
  }

  String get compactSummary {
    if (totalRequests == 0) return '暂无请求';
    final last = lastStatusCode == null ? '未知' : '$lastStatusCode/$lastCode';
    return '已处理 $totalRequests 次，拒绝 $rejectedRequests 次，并发拒绝 $rateLimitedRequests 次，最近 $last';
  }
}

class OpenAiRelayUsageStats {
  const OpenAiRelayUsageStats({
    this.totalRequests = 0,
    this.chatCompletionRequests = 0,
    this.streamedChatRequests = 0,
    this.successfulRequests = 0,
    this.rejectedRequests = 0,
    this.unauthorizedRequests = 0,
    this.rateLimitedRequests = 0,
    this.routedRequests = 0,
    this.upstreamErrors = 0,
    this.totalDurationMs = 0,
    this.lastStatusCode,
    this.lastCode,
    this.lastRequestAt,
  });

  final int totalRequests;
  final int chatCompletionRequests;
  final int streamedChatRequests;
  final int successfulRequests;
  final int rejectedRequests;
  final int unauthorizedRequests;
  final int rateLimitedRequests;
  final int routedRequests;
  final int upstreamErrors;
  final int totalDurationMs;
  final int? lastStatusCode;
  final String? lastCode;
  final DateTime? lastRequestAt;

  OpenAiRelayUsageStats record(OpenAiRelayAuditEvent event) {
    final rejected = event.statusCode >= 400;
    final success = event.statusCode >= 200 && event.statusCode < 300;
    final isChat =
        event.path == '/v1/chat/completions' || event.path == '/v1/responses';
    return OpenAiRelayUsageStats(
      totalRequests: totalRequests + 1,
      chatCompletionRequests: chatCompletionRequests + (isChat ? 1 : 0),
      streamedChatRequests: streamedChatRequests + (event.stream ? 1 : 0),
      successfulRequests: successfulRequests + (success ? 1 : 0),
      rejectedRequests: rejectedRequests + (rejected ? 1 : 0),
      unauthorizedRequests: unauthorizedRequests + (!event.authorized ? 1 : 0),
      rateLimitedRequests:
          rateLimitedRequests + (event.code == 'concurrency_limit' ? 1 : 0),
      routedRequests: routedRequests + (event.code.startsWith('ok_') ? 1 : 0),
      upstreamErrors: upstreamErrors + (event.code == 'upstream_error' ? 1 : 0),
      totalDurationMs: totalDurationMs + event.duration.inMilliseconds,
      lastStatusCode: event.statusCode,
      lastCode: event.code,
      lastRequestAt: event.completedAt,
    );
  }

  double get averageDurationMs =>
      totalRequests == 0 ? 0 : totalDurationMs / totalRequests;

  String get compactSummary {
    if (totalRequests == 0) return '暂无累计用量';
    return '累计 $totalRequests 次，聊天 $chatCompletionRequests 次，成功 $successfulRequests 次，拒绝 $rejectedRequests 次，平均 ${averageDurationMs.toStringAsFixed(1)} ms';
  }

  Map<String, dynamic> toJson() => {
    'totalRequests': totalRequests,
    'chatCompletionRequests': chatCompletionRequests,
    'streamedChatRequests': streamedChatRequests,
    'successfulRequests': successfulRequests,
    'rejectedRequests': rejectedRequests,
    'unauthorizedRequests': unauthorizedRequests,
    'rateLimitedRequests': rateLimitedRequests,
    'routedRequests': routedRequests,
    'upstreamErrors': upstreamErrors,
    'totalDurationMs': totalDurationMs,
    'lastStatusCode': lastStatusCode,
    'lastCode': lastCode,
    'lastRequestAt': lastRequestAt?.toIso8601String(),
  };

  static OpenAiRelayUsageStats fromJson(Map<String, dynamic> json) {
    return OpenAiRelayUsageStats(
      totalRequests: _readInt(json['totalRequests']),
      chatCompletionRequests: _readInt(json['chatCompletionRequests']),
      streamedChatRequests: _readInt(json['streamedChatRequests']),
      successfulRequests: _readInt(json['successfulRequests']),
      rejectedRequests: _readInt(json['rejectedRequests']),
      unauthorizedRequests: _readInt(json['unauthorizedRequests']),
      rateLimitedRequests: _readInt(json['rateLimitedRequests']),
      routedRequests: _readInt(json['routedRequests']),
      upstreamErrors: _readInt(json['upstreamErrors']),
      totalDurationMs: _readInt(json['totalDurationMs']),
      lastStatusCode: json['lastStatusCode'] is int
          ? json['lastStatusCode'] as int
          : null,
      lastCode: json['lastCode'] is String ? json['lastCode'] as String : null,
      lastRequestAt: DateTime.tryParse(json['lastRequestAt'] as String? ?? ''),
    );
  }

  static int _readInt(Object? value) => value is int ? value : 0;
}

class OpenAiRelayAuditLogEntry {
  const OpenAiRelayAuditLogEntry({
    required this.method,
    required this.path,
    required this.statusCode,
    required this.code,
    required this.authorized,
    required this.completedAt,
    this.modelId,
    this.stream = false,
    this.durationMs = 0,
    this.activeRequests = 0,
  });

  final String method;
  final String path;
  final int statusCode;
  final String code;
  final bool authorized;
  final DateTime completedAt;
  final String? modelId;
  final bool stream;
  final int durationMs;
  final int activeRequests;

  String get compactSummary {
    final model = modelId == null || modelId!.isEmpty ? '' : ' · $modelId';
    final streamLabel = stream ? ' · 流式' : '';
    return '$method $path → $statusCode/$code$model$streamLabel';
  }

  Map<String, dynamic> toJson() => {
    'method': method,
    'path': path,
    'statusCode': statusCode,
    'code': code,
    'authorized': authorized,
    'completedAt': completedAt.toIso8601String(),
    'modelId': modelId,
    'stream': stream,
    'durationMs': durationMs,
    'activeRequests': activeRequests,
  };

  static OpenAiRelayAuditLogEntry fromEvent(OpenAiRelayAuditEvent event) {
    return OpenAiRelayAuditLogEntry(
      method: event.method,
      path: event.path,
      statusCode: event.statusCode,
      code: event.code,
      authorized: event.authorized,
      completedAt: event.completedAt,
      modelId: _sanitizeNullable(event.modelId),
      stream: event.stream,
      durationMs: event.duration.inMilliseconds,
      activeRequests: event.activeRequests,
    );
  }

  static OpenAiRelayAuditLogEntry? fromJson(Map<String, dynamic> json) {
    final method = _sanitizeRequired(json['method']);
    final path = _sanitizeRequired(json['path']);
    final code = _sanitizeRequired(json['code']);
    final completedAt = DateTime.tryParse(json['completedAt'] as String? ?? '');
    if (method.isEmpty || path.isEmpty || code.isEmpty || completedAt == null) {
      return null;
    }
    return OpenAiRelayAuditLogEntry(
      method: method,
      path: path,
      statusCode: _readInt(json['statusCode']),
      code: code,
      authorized: json['authorized'] == true,
      completedAt: completedAt,
      modelId: _sanitizeNullable(json['modelId']),
      stream: json['stream'] == true,
      durationMs: _readInt(json['durationMs']),
      activeRequests: _readInt(json['activeRequests']),
    );
  }

  static String _sanitizeRequired(Object? value) {
    if (value is! String) return '';
    return _sanitizeString(value) ?? '';
  }

  static String? _sanitizeNullable(Object? value) {
    if (value is! String) return null;
    return _sanitizeString(value);
  }

  static String? _sanitizeString(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final safe = trimmed
        .replaceAll(RegExp(r'[\r\n\t]'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    return safe.length <= 160 ? safe : safe.substring(0, 160);
  }

  static int _readInt(Object? value) => value is int ? value : 0;
}

class OpenAiRelayState {
  const OpenAiRelayState({
    this.status = OpenAiRelayStatus.stopped,
    this.token,
    this.requestedPort = kOpenAiRelayDefaultPort,
    this.bindMode = OpenAiRelayBindMode.loopback,
    this.routeStrategy = OpenAiRelayRouteStrategy.direct,
    this.maxConcurrentRequests = kOpenAiRelayDefaultConcurrentRequests,
    this.allowRemoteImageDownload = false,
    this.baseUri,
    this.lanAddresses = const [],
    this.errorMessage,
    this.auditSummary = const OpenAiRelayAuditSummary(),
    this.usageStats = const OpenAiRelayUsageStats(),
    this.auditLog = const [],
  });

  final OpenAiRelayStatus status;
  final String? token;
  final int requestedPort;
  final OpenAiRelayBindMode bindMode;
  final OpenAiRelayRouteStrategy routeStrategy;
  final int maxConcurrentRequests;
  final bool allowRemoteImageDownload;
  final Uri? baseUri;
  final List<String> lanAddresses;
  final String? errorMessage;
  final OpenAiRelayAuditSummary auditSummary;
  final OpenAiRelayUsageStats usageStats;
  final List<OpenAiRelayAuditLogEntry> auditLog;

  bool get isRunning => status == OpenAiRelayStatus.running && baseUri != null;
  bool get isBusy =>
      status == OpenAiRelayStatus.starting ||
      status == OpenAiRelayStatus.stopping;
  bool get hasToken => token != null && token!.trim().isNotEmpty;

  String? get openAiBaseUrl {
    final uri = baseUri;
    if (uri == null) return null;
    if (bindMode == OpenAiRelayBindMode.localNetwork &&
        uri.host == InternetAddress.anyIPv4.address &&
        lanAddresses.isNotEmpty) {
      return uri.replace(host: lanAddresses.first).resolve('/v1').toString();
    }
    return uri.resolve('/v1').toString();
  }

  List<String> get localNetworkBaseUrls {
    final uri = baseUri;
    if (uri == null || bindMode != OpenAiRelayBindMode.localNetwork) {
      return const [];
    }
    return [
      for (final address in lanAddresses)
        uri.replace(host: address).resolve('/v1').toString(),
    ];
  }

  String get bindAddressLabel => switch (bindMode) {
    OpenAiRelayBindMode.loopback => InternetAddress.loopbackIPv4.address,
    OpenAiRelayBindMode.localNetwork => '0.0.0.0（局域网）',
  };

  String get routeStrategyLabel => routeStrategy.label;

  String get remoteImageDownloadLabel =>
      allowRemoteImageDownload ? '已开启（仅公网图片）' : '默认关闭';

  String get maskedToken {
    final value = token;
    if (value == null || value.isEmpty) return '未生成';
    if (value.length <= 8) return '已保存';
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  OpenAiRelayState copyWith({
    OpenAiRelayStatus? status,
    Object? token = _unchanged,
    int? requestedPort,
    OpenAiRelayBindMode? bindMode,
    OpenAiRelayRouteStrategy? routeStrategy,
    int? maxConcurrentRequests,
    bool? allowRemoteImageDownload,
    Object? baseUri = _unchanged,
    List<String>? lanAddresses,
    Object? errorMessage = _unchanged,
    OpenAiRelayAuditSummary? auditSummary,
    OpenAiRelayUsageStats? usageStats,
    List<OpenAiRelayAuditLogEntry>? auditLog,
  }) {
    return OpenAiRelayState(
      status: status ?? this.status,
      token: identical(token, _unchanged) ? this.token : token as String?,
      requestedPort: requestedPort ?? this.requestedPort,
      bindMode: bindMode ?? this.bindMode,
      routeStrategy: routeStrategy ?? this.routeStrategy,
      maxConcurrentRequests:
          maxConcurrentRequests ?? this.maxConcurrentRequests,
      allowRemoteImageDownload:
          allowRemoteImageDownload ?? this.allowRemoteImageDownload,
      baseUri: identical(baseUri, _unchanged) ? this.baseUri : baseUri as Uri?,
      lanAddresses: lanAddresses ?? this.lanAddresses,
      errorMessage: identical(errorMessage, _unchanged)
          ? this.errorMessage
          : errorMessage as String?,
      auditSummary: auditSummary ?? this.auditSummary,
      usageStats: usageStats ?? this.usageStats,
      auditLog: auditLog ?? this.auditLog,
    );
  }
}

const _unchanged = Object();

String generateOpenAiRelayToken({int bytes = 32}) {
  if (bytes < 16) {
    throw ArgumentError.value(bytes, 'bytes', '至少需要 16 字节随机数');
  }
  final random = Random.secure();
  final data = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64UrlEncode(data).replaceAll('=', '');
}

int normalizeOpenAiRelayPort(int port) {
  if (port < 0 || port > 65535) {
    throw const OpenAiCompatibleRelayException('本地中转端口必须在 0 到 65535 之间');
  }
  return port;
}

int normalizeOpenAiRelayMaxConcurrentRequests(int value) {
  if (value < kOpenAiRelayMinConcurrentRequests ||
      value > kOpenAiRelayMaxConcurrentRequests) {
    throw const OpenAiCompatibleRelayException('本地中转并发上限必须在 1 到 32 之间');
  }
  return value;
}

Future<List<String>> listOpenAiRelayLanAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final addresses = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.isLoopback) continue;
        final value = address.address.trim();
        if (value.isEmpty || value == InternetAddress.anyIPv4.address) {
          continue;
        }
        addresses.add(value);
      }
    }
    return addresses.toList()..sort();
  } catch (_) {
    return const [];
  }
}

final openAiRelayControllerProvider =
    StateNotifierProvider<OpenAiRelayController, OpenAiRelayState>((ref) {
      return OpenAiRelayController(ref);
    });

class OpenAiRelayController extends StateNotifier<OpenAiRelayState> {
  OpenAiRelayController(this._ref) : super(const OpenAiRelayState()) {
    ready = _loadConfig();
  }

  final Ref _ref;
  OpenAiCompatibleRelaySession? _session;
  late final Future<void> ready;
  Future<void> _usageStatsPersistQueue = Future<void>.value();
  Future<void> _auditLogPersistQueue = Future<void>.value();
  int _usageStatsPersistEpoch = 0;
  int _auditLogPersistEpoch = 0;

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedToken = prefs.getString(kOpenAiRelayTokenStorageKey);
    var token = state.token;
    if (encryptedToken != null && encryptedToken.isNotEmpty) {
      try {
        token = KeyEncryptor.decrypt(encryptedToken);
      } catch (_) {
        token = null;
      }
    }
    final port = normalizeOpenAiRelayPort(
      prefs.getInt(kOpenAiRelayPortStorageKey) ?? kOpenAiRelayDefaultPort,
    );
    final bindMode = OpenAiRelayBindMode.fromStorage(
      prefs.getString(kOpenAiRelayBindModeStorageKey),
    );
    final routeStrategy = OpenAiRelayRouteStrategy.fromStorage(
      prefs.getString(kOpenAiRelayRouteStrategyStorageKey),
    );
    final maxConcurrentRequests = normalizeOpenAiRelayMaxConcurrentRequests(
      prefs.getInt(kOpenAiRelayMaxConcurrentRequestsStorageKey) ??
          kOpenAiRelayDefaultConcurrentRequests,
    );
    final allowRemoteImageDownload =
        prefs.getBool(kOpenAiRelayRemoteImageDownloadStorageKey) ?? false;
    final usageStats = _loadUsageStats(prefs);
    final auditLog = _loadAuditLog(prefs);
    state = state.copyWith(
      token: token,
      requestedPort: port,
      bindMode: bindMode,
      routeStrategy: routeStrategy,
      maxConcurrentRequests: maxConcurrentRequests,
      allowRemoteImageDownload: allowRemoteImageDownload,
      usageStats: usageStats,
      auditLog: auditLog,
      errorMessage: null,
    );
    unawaited(_refreshLanAddressesNow());
  }

  Future<void> saveConfig({
    required String token,
    required int requestedPort,
    OpenAiRelayBindMode? bindMode,
    OpenAiRelayRouteStrategy? routeStrategy,
    int? maxConcurrentRequests,
    bool? allowRemoteImageDownload,
  }) async {
    await ready;
    final nextToken = _validateToken(token);
    final nextPort = normalizeOpenAiRelayPort(requestedPort);
    final nextBindMode = bindMode ?? state.bindMode;
    final nextRouteStrategy = routeStrategy ?? state.routeStrategy;
    final nextMaxConcurrentRequests = normalizeOpenAiRelayMaxConcurrentRequests(
      maxConcurrentRequests ?? state.maxConcurrentRequests,
    );
    final nextAllowRemoteImageDownload =
        allowRemoteImageDownload ?? state.allowRemoteImageDownload;
    await _persistConfig(
      token: nextToken,
      requestedPort: nextPort,
      bindMode: nextBindMode,
      routeStrategy: nextRouteStrategy,
      maxConcurrentRequests: nextMaxConcurrentRequests,
      allowRemoteImageDownload: nextAllowRemoteImageDownload,
    );
    state = state.copyWith(
      token: nextToken,
      requestedPort: nextPort,
      bindMode: nextBindMode,
      routeStrategy: nextRouteStrategy,
      maxConcurrentRequests: nextMaxConcurrentRequests,
      allowRemoteImageDownload: nextAllowRemoteImageDownload,
      errorMessage: null,
    );
    if (state.isRunning) {
      await start(
        token: nextToken,
        requestedPort: nextPort,
        bindMode: nextBindMode,
        routeStrategy: nextRouteStrategy,
        maxConcurrentRequests: nextMaxConcurrentRequests,
        allowRemoteImageDownload: nextAllowRemoteImageDownload,
      );
    }
  }

  Future<String> generateAndSaveToken() async {
    await ready;
    final token = generateOpenAiRelayToken();
    await _persistConfig(
      token: token,
      requestedPort: state.requestedPort,
      bindMode: state.bindMode,
      routeStrategy: state.routeStrategy,
      maxConcurrentRequests: state.maxConcurrentRequests,
      allowRemoteImageDownload: state.allowRemoteImageDownload,
    );
    state = state.copyWith(token: token, errorMessage: null);
    return token;
  }

  Future<void> setBindMode(OpenAiRelayBindMode bindMode) async {
    await ready;
    if (bindMode == state.bindMode) return;
    await _persistBindMode(bindMode);
    state = state.copyWith(bindMode: bindMode, errorMessage: null);
    if (state.isRunning) {
      await start(bindMode: bindMode);
    }
  }

  Future<void> setRouteStrategy(OpenAiRelayRouteStrategy routeStrategy) async {
    await ready;
    if (routeStrategy == state.routeStrategy) return;
    await _persistRouteStrategy(routeStrategy);
    state = state.copyWith(routeStrategy: routeStrategy, errorMessage: null);
    if (state.isRunning) {
      await start(routeStrategy: routeStrategy);
    }
  }

  Future<void> setMaxConcurrentRequests(int maxConcurrentRequests) async {
    await ready;
    final next = normalizeOpenAiRelayMaxConcurrentRequests(
      maxConcurrentRequests,
    );
    if (next == state.maxConcurrentRequests) return;
    await _persistMaxConcurrentRequests(next);
    state = state.copyWith(maxConcurrentRequests: next, errorMessage: null);
    if (state.isRunning) {
      await start(maxConcurrentRequests: next);
    }
  }

  Future<void> setAllowRemoteImageDownload(bool allow) async {
    await ready;
    if (allow == state.allowRemoteImageDownload) return;
    await _persistAllowRemoteImageDownload(allow);
    state = state.copyWith(allowRemoteImageDownload: allow, errorMessage: null);
    if (state.isRunning) {
      await start(allowRemoteImageDownload: allow);
    }
  }

  Future<void> clearUsageStats() async {
    await ready;
    _usageStatsPersistEpoch += 1;
    try {
      await _usageStatsPersistQueue;
    } catch (_) {
      // 持久化失败不应阻断用户清空本地统计；下一次请求会重建统计。
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kOpenAiRelayUsageStatsStorageKey);
    state = state.copyWith(usageStats: const OpenAiRelayUsageStats());
  }

  Future<void> clearAuditLog() async {
    await ready;
    _auditLogPersistEpoch += 1;
    try {
      await _auditLogPersistQueue;
    } catch (_) {
      // 审计明细是本地脱敏辅助信息，清空失败不影响主链路。
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kOpenAiRelayAuditLogStorageKey);
    state = state.copyWith(auditLog: const []);
  }

  String exportAuditReportJson({DateTime? generatedAt}) {
    final payload = {
      'schema': 'simichat.openai_relay_audit.v1',
      'generatedAt': (generatedAt ?? DateTime.now()).toIso8601String(),
      'privacy':
          'Local redacted relay audit only. No prompts, message bodies, bearer tokens, API keys, upstream base URLs, local file paths, or raw user content are included.',
      'usageStats': state.usageStats.toJson(),
      'auditLogCount': state.auditLog.length,
      'auditLog': [for (final entry in state.auditLog) entry.toJson()],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> refreshLanAddresses() async {
    await ready;
    await _refreshLanAddressesNow();
  }

  Future<void> _refreshLanAddressesNow() async {
    final addresses = await listOpenAiRelayLanAddresses();
    if (!mounted) return;
    state = state.copyWith(lanAddresses: addresses);
  }

  Future<void> start({
    String? token,
    int? requestedPort,
    OpenAiRelayBindMode? bindMode,
    OpenAiRelayRouteStrategy? routeStrategy,
    int? maxConcurrentRequests,
    bool? allowRemoteImageDownload,
  }) async {
    await ready;
    if (state.isBusy) return;
    final nextToken = _validateToken(
      token == null || token.trim().isEmpty
          ? state.token ?? generateOpenAiRelayToken()
          : token,
    );
    final nextPort = normalizeOpenAiRelayPort(
      requestedPort ?? state.requestedPort,
    );
    final nextBindMode = bindMode ?? state.bindMode;
    final nextRouteStrategy = routeStrategy ?? state.routeStrategy;
    final nextMaxConcurrentRequests = normalizeOpenAiRelayMaxConcurrentRequests(
      maxConcurrentRequests ?? state.maxConcurrentRequests,
    );
    final nextAllowRemoteImageDownload =
        allowRemoteImageDownload ?? state.allowRemoteImageDownload;
    if (nextBindMode == OpenAiRelayBindMode.localNetwork) {
      unawaited(_refreshLanAddressesNow());
    }

    state = state.copyWith(
      status: OpenAiRelayStatus.starting,
      token: nextToken,
      requestedPort: nextPort,
      bindMode: nextBindMode,
      routeStrategy: nextRouteStrategy,
      maxConcurrentRequests: nextMaxConcurrentRequests,
      allowRemoteImageDownload: nextAllowRemoteImageDownload,
      errorMessage: null,
      auditSummary: const OpenAiRelayAuditSummary(),
    );
    try {
      await _session?.close();
      _session = null;
      final bridge = ChannelModelRelayBridge(
        channelDao: _ref.read(channelDaoProvider),
        routeStrategy: nextRouteStrategy,
      );
      final session = await const OpenAiCompatibleRelayServer().start(
        relayToken: nextToken,
        listModels: bridge.listModels,
        resolveModel: bridge.resolveModel,
        routeModel: bridge.routeModel,
        forward: bridge.forward,
        address: nextBindMode == OpenAiRelayBindMode.localNetwork
            ? InternetAddress.anyIPv4
            : InternetAddress.loopbackIPv4,
        port: nextPort,
        maxConcurrentRequests: nextMaxConcurrentRequests,
        auditSink: _recordAudit,
        remoteImagePolicy: nextAllowRemoteImageDownload
            ? const OpenAiRelayRemoteImagePolicy.enabled()
            : const OpenAiRelayRemoteImagePolicy.disabled(),
      );
      _session = session;
      await _persistConfig(
        token: nextToken,
        requestedPort: nextPort,
        bindMode: nextBindMode,
        routeStrategy: nextRouteStrategy,
        maxConcurrentRequests: nextMaxConcurrentRequests,
        allowRemoteImageDownload: nextAllowRemoteImageDownload,
      );
      state = state.copyWith(
        status: OpenAiRelayStatus.running,
        baseUri: session.baseUri,
        errorMessage: null,
      );
    } on Object catch (error) {
      await _session?.close();
      _session = null;
      state = state.copyWith(
        status: OpenAiRelayStatus.error,
        baseUri: null,
        errorMessage: _safeErrorMessage(error),
      );
    }
  }

  Future<void> stop() async {
    await ready;
    if (!state.isRunning && _session == null) {
      state = state.copyWith(
        status: OpenAiRelayStatus.stopped,
        baseUri: null,
        errorMessage: null,
      );
      return;
    }
    state = state.copyWith(status: OpenAiRelayStatus.stopping);
    try {
      await _session?.close();
      _session = null;
      state = state.copyWith(
        status: OpenAiRelayStatus.stopped,
        baseUri: null,
        errorMessage: null,
      );
    } catch (_) {
      _session = null;
      state = state.copyWith(
        status: OpenAiRelayStatus.error,
        baseUri: null,
        errorMessage: '本地中转停止失败，请重启应用后重试',
      );
    }
  }

  void _recordAudit(OpenAiRelayAuditEvent event) {
    if (!mounted) return;
    final usageStats = state.usageStats.record(event);
    final auditLog = <OpenAiRelayAuditLogEntry>[
      OpenAiRelayAuditLogEntry.fromEvent(event),
      ...state.auditLog,
    ].take(kOpenAiRelayMaxAuditLogEntries).toList(growable: false);
    state = state.copyWith(
      auditSummary: state.auditSummary.record(event),
      usageStats: usageStats,
      auditLog: auditLog,
    );
    _queuePersistUsageStats(usageStats);
    _queuePersistAuditLog(auditLog);
  }

  Future<void> _persistConfig({
    required String token,
    required int requestedPort,
    required OpenAiRelayBindMode bindMode,
    required OpenAiRelayRouteStrategy routeStrategy,
    required int maxConcurrentRequests,
    required bool allowRemoteImageDownload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kOpenAiRelayTokenStorageKey,
      KeyEncryptor.encrypt(token),
    );
    await prefs.setInt(kOpenAiRelayPortStorageKey, requestedPort);
    await prefs.setString(
      kOpenAiRelayBindModeStorageKey,
      bindMode.storageValue,
    );
    await prefs.setString(
      kOpenAiRelayRouteStrategyStorageKey,
      routeStrategy.storageValue,
    );
    await prefs.setInt(
      kOpenAiRelayMaxConcurrentRequestsStorageKey,
      maxConcurrentRequests,
    );
    await prefs.setBool(
      kOpenAiRelayRemoteImageDownloadStorageKey,
      allowRemoteImageDownload,
    );
  }

  Future<void> _persistBindMode(OpenAiRelayBindMode bindMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kOpenAiRelayBindModeStorageKey,
      bindMode.storageValue,
    );
  }

  Future<void> _persistRouteStrategy(
    OpenAiRelayRouteStrategy routeStrategy,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kOpenAiRelayRouteStrategyStorageKey,
      routeStrategy.storageValue,
    );
  }

  Future<void> _persistMaxConcurrentRequests(int maxConcurrentRequests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      kOpenAiRelayMaxConcurrentRequestsStorageKey,
      maxConcurrentRequests,
    );
  }

  Future<void> _persistAllowRemoteImageDownload(bool allow) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOpenAiRelayRemoteImageDownloadStorageKey, allow);
  }

  Future<void> _persistUsageStats(OpenAiRelayUsageStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kOpenAiRelayUsageStatsStorageKey, jsonEncode(stats));
  }

  void _queuePersistUsageStats(OpenAiRelayUsageStats stats) {
    final epoch = _usageStatsPersistEpoch;
    _usageStatsPersistQueue = _usageStatsPersistQueue
        .catchError((_) {
          // 统计是本地脱敏辅助信息，写入失败不影响 relay 主链路。
        })
        .then((_) async {
          if (epoch != _usageStatsPersistEpoch) return;
          await _persistUsageStats(stats);
        });
    unawaited(_usageStatsPersistQueue);
  }

  Future<void> _persistAuditLog(List<OpenAiRelayAuditLogEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kOpenAiRelayAuditLogStorageKey,
      jsonEncode([for (final entry in entries) entry.toJson()]),
    );
  }

  void _queuePersistAuditLog(List<OpenAiRelayAuditLogEntry> entries) {
    final epoch = _auditLogPersistEpoch;
    _auditLogPersistQueue = _auditLogPersistQueue
        .catchError((_) {
          // 审计明细是本地脱敏辅助信息，写入失败不影响 relay 主链路。
        })
        .then((_) async {
          if (epoch != _auditLogPersistEpoch) return;
          await _persistAuditLog(entries);
        });
    unawaited(_auditLogPersistQueue);
  }

  OpenAiRelayUsageStats _loadUsageStats(SharedPreferences prefs) {
    final raw = prefs.getString(kOpenAiRelayUsageStatsStorageKey);
    if (raw == null || raw.isEmpty) return const OpenAiRelayUsageStats();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? OpenAiRelayUsageStats.fromJson(decoded)
          : const OpenAiRelayUsageStats();
    } catch (_) {
      return const OpenAiRelayUsageStats();
    }
  }

  List<OpenAiRelayAuditLogEntry> _loadAuditLog(SharedPreferences prefs) {
    final raw = prefs.getString(kOpenAiRelayAuditLogStorageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            if (OpenAiRelayAuditLogEntry.fromJson(item) != null)
              OpenAiRelayAuditLogEntry.fromJson(item)!,
      ].take(kOpenAiRelayMaxAuditLogEntries).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  String _validateToken(String token) {
    final value = token.trim();
    if (value.length < kOpenAiRelayMinTokenLength) {
      throw const OpenAiCompatibleRelayException('本地中转令牌至少需要 16 个字符');
    }
    return value;
  }

  String _safeErrorMessage(Object error) {
    if (error is OpenAiCompatibleRelayException) return error.message;
    return '本地中转启动失败，请检查端口是否被占用或稍后重试';
  }

  @override
  void dispose() {
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.close());
    super.dispose();
  }
}
