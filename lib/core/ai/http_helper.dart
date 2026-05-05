import 'package:dio/dio.dart';

/// 按 baseUrl 缓存 Dio 实例，复用连接池
final Map<String, Dio> _dioCache = {};

/// 获取或创建 Dio 实例
Dio getDio(String baseUrl) {
  final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');
  return _dioCache.putIfAbsent(normalized, () => Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
    sendTimeout: const Duration(seconds: 30),
  )));
}

/// 创建带超时的 Dio 实例（不缓存，用于模型获取等一次性请求）
Dio createDio() {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
  ));
}

/// 将 DioException 转换为用户友好的错误消息
String formatDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return '连接超时，请检查网络或稍后重试';
    case DioExceptionType.connectionError:
      return '无法连接到服务器，请检查网络和 Base URL';
    case DioExceptionType.badResponse:
      return _formatHttpError(e.response?.statusCode, e.response?.data);
    case DioExceptionType.cancel:
      return '请求已取消';
    default:
      return '网络错误: ${e.message ?? "未知错误"}';
  }
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
