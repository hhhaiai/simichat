import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'http_client_adapter_factory.dart';

/// 测试注入点：非 null 时 `getDio` 返回该工厂构造的实例，
/// 不再走真实网络与缓存。widget 测试的 FakeAsync 环境无法完成
/// 真实 socket 事件，相关协议测试统一用 fake adapter 回环。
@visibleForTesting
Dio Function(String baseUrl)? debugDioFactory;

/// 按 baseUrl 缓存 Dio 实例，复用连接池
final Map<String, Dio> _dioCache = {};

/// 缓存实例的最后使用时间
final Map<String, DateTime> _dioLastUsed = {};

/// 最大缓存实例数
const _maxCacheSize = 20;

/// 缓存过期时间
const _cacheExpiry = Duration(hours: 1);

/// 获取或创建 Dio 实例
Dio getDio(String baseUrl) {
  final factory = debugDioFactory;
  if (factory != null) return factory(baseUrl);
  final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');

  // 清理过期缓存
  _cleanupCache();

  _dioLastUsed[normalized] = DateTime.now();
  return _dioCache.putIfAbsent(normalized, () {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    configureDioTransport(dio);
    return dio;
  });
}

/// 清理过期和超量的 Dio 缓存
void _cleanupCache() {
  final now = DateTime.now();

  // 移除过期的实例
  final expiredKeys = _dioLastUsed.entries
      .where((e) => now.difference(e.value) > _cacheExpiry)
      .map((e) => e.key)
      .toList();

  for (final key in expiredKeys) {
    _dioCache.remove(key)?.close();
    _dioLastUsed.remove(key);
  }

  // 如果仍然超过最大数量，移除最旧的
  if (_dioCache.length > _maxCacheSize) {
    final sortedEntries = _dioLastUsed.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final toRemove = sortedEntries.take(_dioCache.length - _maxCacheSize);
    for (final entry in toRemove) {
      _dioCache.remove(entry.key)?.close();
      _dioLastUsed.remove(entry.key);
    }
  }
}

/// 清理所有 Dio 缓存（应用退出时调用）
void disposeAllDio() {
  for (final dio in _dioCache.values) {
    dio.close();
  }
  _dioCache.clear();
  _dioLastUsed.clear();
}

/// 创建带超时的 Dio 实例（不缓存，用于模型获取等一次性请求）
Dio createDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
  configureDioTransport(dio);
  return dio;
}

/// 将 DioException 转换为用户友好的错误消息
String formatDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return '连接超时，请检查网络或稍后重试';
    case DioExceptionType.connectionError:
      return _formatConnectionError(e);
    case DioExceptionType.badResponse:
      return _formatHttpError(e.response?.statusCode, e.response?.data);
    case DioExceptionType.cancel:
      return '请求已取消';
    default:
      return '网络错误: ${e.message ?? "未知错误"}';
  }
}

/// 将连接错误解析为具体原因
String _formatConnectionError(DioException e) {
  final error = e.error;
  final detail = error?.toString() ?? e.message ?? '';

  // 尝试提取 OS Error 详细信息
  if (error != null && error is! String) {
    try {
      final osError = (error as dynamic).osError;
      if (osError != null) {
        final errorCode = (osError as dynamic).errorCode;
        final message = (osError as dynamic).message;
        if (errorCode != null || message != null) {
          return '无法连接到服务器（$message，错误码: $errorCode），请检查网络和 Base URL';
        }
      }
    } catch (_) {}
  }

  if (detail.contains('SocketException') ||
      detail.contains('Connection refused')) {
    return '连接被拒绝，请检查 Base URL 和端口是否正确';
  }
  if (detail.contains('HandshakeException') || detail.contains('CERTIFICATE')) {
    return 'SSL/TLS 证书验证失败，请检查 Base URL 是否正确或证书是否有效';
  }
  if (detail.contains('FormatException') ||
      detail.contains('Invalid argument')) {
    return 'Base URL 格式错误，请检查是否包含 http:// 或 https://';
  }
  if (detail.contains('No address associated') ||
      detail.contains('nodename nor servname') ||
      detail.contains('getaddrinfo')) {
    return 'DNS 解析失败，无法找到服务器地址，请检查 Base URL';
  }
  if (detail.contains('Network is unreachable') ||
      detail.contains('No route to host')) {
    return '网络不可达，请检查网络连接';
  }
  if (detail.contains('Connection timed out')) {
    return '连接超时，请检查网络或 Base URL 是否正确';
  }

  return '无法连接到服务器，请检查网络和 Base URL（$detail）';
}

String _formatHttpError(int? statusCode, dynamic responseData) {
  String? serverMessage;
  try {
    if (responseData is Map) {
      serverMessage = responseData['error']?['message']?.toString();
    }
  } catch (_) {}

  switch (statusCode) {
    case 401:
      return 'API Key 无效，请检查设置中的密钥';
    case 403:
      return '访问被拒绝，请检查 API Key 权限';
    case 429:
      return '请求频率超限，请稍后重试';
    case 500:
    case 502:
    case 503:
      return '服务器错误 ($statusCode)，请稍后重试';
    default:
      if (serverMessage != null) return serverMessage;
      return 'HTTP 错误 $statusCode';
  }
}
