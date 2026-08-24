import 'package:dio/dio.dart';

import '../ai/http_helper.dart';

/// SimiRouter（new-api 风格中转站）账户用量查询。
///
/// 实测契约（2026-08）：
/// - `GET /v1/dashboard/billing/usage` → `{"object":"list","total_usage":<quota>}`
/// - `GET /v1/dashboard/billing/subscription` → `has_payment_method` /
///   `soft_limit_usd` / `hard_limit_usd` / `access_until`
/// - new-api 配额换算：1 USD = 500000 quota；`soft_limit_usd` 为
///   `100000000`（哨兵值）时表示未设限额。
class SimiRouterBillingClient {
  const SimiRouterBillingClient();

  static const quotaPerUsd = 500000.0;
  static const unlimitedLimitSentinelUsd = 100000000;

  /// 拉取用量与限额。`baseUrl` 是渠道的完整 Base URL（含 /v1）。
  Future<SimiRouterBillingSnapshot> fetch({
    required String baseUrl,
    required String apiKey,
    Uri? usageEndpoint,
    Uri? subscriptionEndpoint,
  }) async {
    final usageUri =
        usageEndpoint ??
        Uri.parse('${_trimSlash(baseUrl)}/dashboard/billing/usage');
    final subscriptionUri =
        subscriptionEndpoint ??
        Uri.parse('${_trimSlash(baseUrl)}/dashboard/billing/subscription');
    final dio = createDio();
    final headers = {'Authorization': 'Bearer $apiKey'};

    final usageResponse = await dio.get<Map<String, dynamic>>(
      usageUri.toString(),
      options: Options(headers: headers, responseType: ResponseType.json),
    );
    final totalUsage =
        (usageResponse.data?['total_usage'] as num?)?.toDouble() ?? 0;

    var softLimitUsd = unlimitedLimitSentinelUsd.toDouble();
    var hardLimitUsd = unlimitedLimitSentinelUsd.toDouble();
    var hasPaymentMethod = false;
    try {
      final subscriptionResponse = await dio.get<Map<String, dynamic>>(
        subscriptionUri.toString(),
        options: Options(headers: headers, responseType: ResponseType.json),
      );
      final data = subscriptionResponse.data;
      softLimitUsd =
          (data?['soft_limit_usd'] as num?)?.toDouble() ?? softLimitUsd;
      hardLimitUsd =
          (data?['hard_limit_usd'] as num?)?.toDouble() ?? hardLimitUsd;
      hasPaymentMethod = data?['has_payment_method'] == true;
    } catch (_) {
      // 订阅接口失败不影响用量展示。
    }

    return SimiRouterBillingSnapshot(
      usedUsd: totalUsage / quotaPerUsd,
      softLimitUsd: softLimitUsd >= unlimitedLimitSentinelUsd
          ? null
          : softLimitUsd,
      hardLimitUsd: hardLimitUsd >= unlimitedLimitSentinelUsd
          ? null
          : hardLimitUsd,
      hasPaymentMethod: hasPaymentMethod,
    );
  }

  /// new-api / CCSwitch account profile endpoint.  This is intentionally a
  /// separate snapshot from billing usage: the former is the account's
  /// remaining quota / identity while the latter is spend over time.
  Future<SimiRouterAccountSnapshot> fetchAccount({
    required String baseUrl,
    required String apiKey,
    String? newApiUser,
    Uri? endpoint,
  }) async {
    final root = _rootUrl(baseUrl);
    final uri = endpoint ?? Uri.parse('$root/api/user/self');
    final headers = <String, String>{
      'Authorization': 'Bearer ${apiKey.trim()}',
      'Content-Type': 'application/json',
      'New-Api-User': (newApiUser?.trim().isNotEmpty == true
          ? newApiUser!.trim()
          : '1'),
    };
    final dio = createDio();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        uri.toString(),
        options: Options(headers: headers, responseType: ResponseType.json),
      );
      final raw = response.data;
      if (raw == null) {
        throw const SimiRouterBillingException('账号额度接口返回为空');
      }
      final data = raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : raw;
      final userId = _firstString(data, const ['id', 'user_id', 'userId']);
      final username = _firstString(data, const ['username', 'name', 'email']);
      final quota = _firstNumber(data, const [
        'quota',
        'balance',
        'remain_quota',
        'remaining_quota',
        'remainingQuota',
      ]);
      final usedQuota = _firstNumber(data, const [
        'used_quota',
        'usedQuota',
        'total_usage',
        'totalUsage',
      ]);
      if (userId == null &&
          username == null &&
          quota == null &&
          usedQuota == null) {
        throw const SimiRouterBillingException('账号额度接口未返回可识别字段');
      }
      return SimiRouterAccountSnapshot(
        userId: userId,
        username: username,
        remainingQuota: quota,
        usedQuota: usedQuota,
      );
    } on SimiRouterBillingException {
      rethrow;
    } on DioException catch (error) {
      throw SimiRouterBillingException(_accountHttpError(error));
    }
  }

  static String _rootUrl(String value) {
    var root = _trimSlash(value.trim());
    root = root.replaceFirst(RegExp(r'/v1$'), '');
    return root;
  }

  static String? _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return value.toString();
    }
    return null;
  }

  static double? _firstNumber(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String _accountHttpError(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return '账号额度鉴权失败，请检查 Token / New-Api-User';
    }
    if (status == 404) return '当前渠道未提供 /api/user/self 账号接口';
    if (status == 429) return '账号额度查询被限流，请稍后重试';
    return '账号额度查询失败（HTTP ${status ?? '网络错误'}）';
  }

  static String _trimSlash(String value) {
    return value.replaceAll(RegExp(r'/+$'), '');
  }
}

class SimiRouterBillingException implements Exception {
  const SimiRouterBillingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SimiRouterAccountSnapshot {
  const SimiRouterAccountSnapshot({
    this.userId,
    this.username,
    this.remainingQuota,
    this.usedQuota,
  });

  final String? userId;
  final String? username;
  final double? remainingQuota;
  final double? usedQuota;

  String get remainingLabel => _quotaLabel(remainingQuota);
  String get usedLabel => _quotaLabel(usedQuota);

  String get compactLabel {
    final identity = username ?? (userId == null ? null : '账号 $userId');
    final values = <String>[
      ?identity,
      if (remainingQuota != null) '剩余 $remainingLabel',
      if (usedQuota != null) '账号已用 $usedLabel',
    ];
    return values.isEmpty ? '账号额度已更新' : values.join(' · ');
  }

  static String _quotaLabel(double? quota) {
    if (quota == null) return '';
    final usd = quota / SimiRouterBillingClient.quotaPerUsd;
    if (usd < 0.01) return quota <= 0 ? '0' : '<0.01 USD';
    return '${usd.toStringAsFixed(2)} USD';
  }
}

class SimiRouterBillingSnapshot {
  const SimiRouterBillingSnapshot({
    required this.usedUsd,
    this.softLimitUsd,
    this.hardLimitUsd,
    this.hasPaymentMethod = false,
  });

  final double usedUsd;
  final double? softLimitUsd;
  final double? hardLimitUsd;
  final bool hasPaymentMethod;

  String get usedLabel {
    if (usedUsd < 0.01) {
      return usedUsd <= 0 ? '\$0' : '<\$0.01';
    }
    return '\$${usedUsd.toStringAsFixed(2)}';
  }

  String get limitLabel {
    final limit = softLimitUsd ?? hardLimitUsd;
    if (limit == null) return '未设限额';
    if (limit >= 1000) return '限额 \$${(limit / 1000).toStringAsFixed(1)}k';
    return '限额 \$${limit.toStringAsFixed(2)}';
  }
}
