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
      softLimitUsd = (data?['soft_limit_usd'] as num?)?.toDouble() ?? softLimitUsd;
      hardLimitUsd = (data?['hard_limit_usd'] as num?)?.toDouble() ?? hardLimitUsd;
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

  static String _trimSlash(String value) {
    return value.replaceAll(RegExp(r'/+$'), '');
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
