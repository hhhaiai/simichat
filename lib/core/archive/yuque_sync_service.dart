import 'package:dio/dio.dart';

import '../ai/http_helper.dart';

class YuqueSyncException implements Exception {
  final String message;
  const YuqueSyncException(this.message);

  @override
  String toString() => message;
}

/// 校验语雀 Token。
String normalizeYuqueToken(String token) {
  final value = token.trim();
  if (value.isEmpty) {
    throw const YuqueSyncException('语雀 Token 未配置');
  }
  return value;
}

/// 校验语雀仓库 namespace（格式 `login/slug`）。
String normalizeYuqueNamespace(String namespace) {
  final value = namespace.trim();
  if (!RegExp(r'^[^/]+/[^/]+$').hasMatch(value)) {
    throw const YuqueSyncException('语雀仓库 namespace 格式无效（应为 login/slug）');
  }
  return value;
}

/// 把会话 Markdown 导出为语雀文档。
///
/// 使用 Token（`X-Auth-Token`）在指定仓库（namespace）下创建 markdown 文档。
class YuqueSyncService {
  const YuqueSyncService({String? apiBaseUrl}) : _apiBaseUrl = apiBaseUrl;

  static const kDefaultApiBaseUrl = 'https://www.yuque.com/api/v2';

  final String? _apiBaseUrl;

  String get _endpoint {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  Future<String> exportConversation({
    required String token,
    required String namespace,
    required String title,
    required String markdownContent,
  }) async {
    final normalizedToken = normalizeYuqueToken(token);
    final normalizedNamespace = normalizeYuqueNamespace(namespace);
    final trimmedTitle = title.trim().isEmpty ? 'SimiChat 会话' : title.trim();
    if (markdownContent.trim().isEmpty) {
      throw const YuqueSyncException('会话内容为空');
    }

    final dio = createDio();
    dio.options.headers['X-Auth-Token'] = normalizedToken;
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_endpoint/repos/$normalizedNamespace/docs',
        options: Options(responseType: ResponseType.json),
        data: {
          'title': trimmedTitle,
          'format': 'markdown',
          'body': markdownContent,
        },
      );
      final data = response.data;
      final inner = data?['data'];
      if (inner is Map) {
        return (inner['slug'] ?? '').toString();
      }
      // 部分旧版接口直接返回 data 结构。
      if (data != null && data['slug'] != null) {
        return data['slug'].toString();
      }
      throw const YuqueSyncException('语雀未返回文档信息');
    } on DioException catch (e) {
      throw YuqueSyncException(_formatYuqueError(e));
    }
  }

  String _formatYuqueError(DioException e) {
    final status = e.response?.statusCode;
    if (status != null && status >= 400) {
      String? message;
      try {
        final data = e.response?.data;
        if (data is Map) message = data['message']?.toString();
      } catch (_) {}
      switch (status) {
        case 401:
          return '语雀 Token 无效（401）';
        case 403:
          return '无权访问该仓库（403）';
        case 404:
          return '语雀仓库不存在或无权限（404）';
        default:
          return 'HTTP $status${message != null ? '：$message' : ''}';
      }
    }
    return e.message ?? '网络错误';
  }
}
