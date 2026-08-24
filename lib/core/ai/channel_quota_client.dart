import 'package:dio/dio.dart';

import 'http_helper.dart';

/// A single rolling quota window returned by an account provider.
class ChannelQuotaWindow {
  const ChannelQuotaWindow({
    required this.label,
    required this.utilization,
    this.resetsAt,
  });

  final String label;

  /// Percentage in the provider response (0..100).  Some providers call
  /// this field `utilization`, while others expose a ratio.
  final double utilization;
  final DateTime? resetsAt;

  String get utilizationLabel => '${utilization.round()}%';

  String get resetLabel {
    final value = resetsAt?.toLocal();
    if (value == null) return '';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '重置 $month-$day $hour:$minute';
  }
}

/// A normalized account quota snapshot.
///
/// CCSwitch's Claude account view uses the Anthropic OAuth usage endpoint.  A
/// SimiChat channel can hold the same OAuth token in its encrypted API-key
/// field, so querying it here keeps the feature available on Android without
/// requiring the desktop CCSwitch process to be running.
class ChannelQuotaSnapshot {
  const ChannelQuotaSnapshot({
    required this.provider,
    required this.fetchedAt,
    this.usedUsd,
    this.limitUsd,
    this.windows = const <ChannelQuotaWindow>[],
  });

  final String provider;
  final DateTime fetchedAt;
  final double? usedUsd;
  final double? limitUsd;
  final List<ChannelQuotaWindow> windows;

  String get compactLabel {
    if (windows.isNotEmpty) {
      return windows
          .map((window) {
            final reset = window.resetLabel;
            return '${window.label} ${window.utilizationLabel}'
                '${reset.isEmpty ? '' : ' · $reset'}';
          })
          .join('  ');
    }
    if (usedUsd != null) {
      final used = usedUsd! < 0.01
          ? (usedUsd! <= 0 ? '\$0' : '<\$0.01')
          : '\$${usedUsd!.toStringAsFixed(2)}';
      if (limitUsd == null) return '已用 $used · 未设限额';
      return '已用 $used · 限额 \$${limitUsd!.toStringAsFixed(2)}';
    }
    return '额度已更新';
  }
}

class ChannelQuotaException implements Exception {
  const ChannelQuotaException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Queries provider account quota using the same contracts used by CCSwitch
/// and new-api compatible relays.
class ChannelQuotaClient {
  const ChannelQuotaClient();

  Future<ChannelQuotaSnapshot> fetch({
    required String protocol,
    required String baseUrl,
    required String apiKey,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const ChannelQuotaException('当前渠道没有 API Key / OAuth Token');
    }
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw const ChannelQuotaException('Base URL 无效，无法查询额度');
    }

    if (_isClaude(protocol, base)) {
      return _fetchAnthropicOAuth(base, key);
    }
    return _fetchNewApi(baseUrl, key);
  }

  bool _isClaude(String protocol, Uri base) {
    final normalized = protocol.trim().toLowerCase();
    return normalized == 'claude' ||
        base.host.toLowerCase() == 'api.anthropic.com' ||
        base.host.toLowerCase().contains('anthropic');
  }

  Future<ChannelQuotaSnapshot> _fetchAnthropicOAuth(
    Uri base,
    String apiKey,
  ) async {
    // The endpoint is rooted at the Anthropic origin, not under /v1.
    final endpoint = base.replace(path: '/api/oauth/usage', query: null);
    final dio = createDio();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        endpoint.toString(),
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 12),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
            // CCSwitch sends this beta header for OAuth usage on Claude.
            'anthropic-beta': 'oauth-2025-04-20',
            'anthropic-version': '2023-06-01',
          },
        ),
      );
      final data = response.data;
      if (data == null) {
        throw const ChannelQuotaException('额度接口返回为空');
      }
      final windows = <ChannelQuotaWindow>[];
      for (final entry in data.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final raw = value['utilization'];
        final utilization = _asPercent(raw);
        if (utilization == null) continue;
        windows.add(
          ChannelQuotaWindow(
            label: _anthropicWindowLabel(entry.key),
            utilization: utilization,
            resetsAt: _parseDate(value['resets_at']),
          ),
        );
      }
      if (windows.isEmpty) {
        throw const ChannelQuotaException('额度接口未返回可识别的使用窗口');
      }
      return ChannelQuotaSnapshot(
        provider: 'Anthropic / CCSwitch',
        fetchedAt: DateTime.now(),
        windows: windows,
      );
    } on DioException catch (error) {
      throw ChannelQuotaException(_quotaHttpError(error));
    }
  }

  Future<ChannelQuotaSnapshot> _fetchNewApi(
    String baseUrl,
    String apiKey,
  ) async {
    final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final usageEndpoint = '$normalized/dashboard/billing/usage';
    final subscriptionEndpoint = '$normalized/dashboard/billing/subscription';
    final dio = createDio();
    try {
      final usage = await dio.get<Map<String, dynamic>>(
        usageEndpoint,
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 12),
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
      );
      final data = usage.data ?? const <String, dynamic>{};
      final usedQuota = _firstNumber(data, const [
        'total_usage',
        'totalUsage',
        'used_quota',
        'usedQuota',
      ]);
      final usedUsd = usedQuota == null ? null : usedQuota / 500000.0;
      var limitUsd = _firstNumber(data, const [
        'soft_limit_usd',
        'softLimitUsd',
        'hard_limit_usd',
        'hardLimitUsd',
      ]);
      try {
        final subscription = await dio.get<Map<String, dynamic>>(
          subscriptionEndpoint,
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(seconds: 8),
            headers: {'Authorization': 'Bearer $apiKey'},
          ),
        );
        limitUsd ??= _firstNumber(subscription.data, const [
          'soft_limit_usd',
          'softLimitUsd',
          'hard_limit_usd',
          'hardLimitUsd',
        ]);
      } on DioException {
        // Usage is still useful if the optional subscription endpoint is not
        // exposed by a relay.
      }
      if (usedUsd == null && limitUsd == null) {
        throw const ChannelQuotaException('额度接口未返回可识别的用量');
      }
      return ChannelQuotaSnapshot(
        provider: 'OpenAI 兼容 / new-api',
        fetchedAt: DateTime.now(),
        usedUsd: usedUsd,
        limitUsd: limitUsd != null && limitUsd >= 100000000 ? null : limitUsd,
      );
    } on DioException catch (error) {
      throw ChannelQuotaException(_quotaHttpError(error));
    }
  }

  static double? _firstNumber(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return null;
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toDouble();
    }
    return null;
  }

  static double? _asPercent(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    // Anthropic returns 0..100; tolerate ratio-shaped responses too.
    return value >= 0 && value <= 1 ? value * 100 : value.clamp(0, 100);
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static String _anthropicWindowLabel(String key) {
    return switch (key) {
      'five_hour' => '5 小时',
      'seven_day' => '7 天',
      'seven_day_opus' => '7 天 Opus',
      'seven_day_sonnet' => '7 天 Sonnet',
      'seven_day_cowork' => '7 天 Cowork',
      _ => key.replaceAll('_', ' '),
    };
  }

  static String _quotaHttpError(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return '额度接口鉴权失败，请检查 API Key / OAuth Token';
    }
    if (status == 404) return '当前渠道未提供额度查询接口';
    if (status == 429) return '额度查询被限流，请稍后重试';
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return '额度查询超时，请检查网络';
    }
    return '额度查询失败（HTTP ${status ?? '网络错误'}）';
  }
}
