import 'package:dio/dio.dart';

import '../ai/http_helper.dart';

class SiyuanSyncException implements Exception {
  final String message;
  const SiyuanSyncException(this.message);

  @override
  String toString() => message;
}

/// 把会话 Markdown 导出为思源笔记文档。
///
/// 通过思源 HTTP API `POST /api/filetree/createDocWithMd` 在指定笔记本下创建文档。
/// `baseUrl` 为思源 API 地址（如 `http://127.0.0.1:6806`）。
class SiyuanSyncService {
  const SiyuanSyncService({String? apiBaseUrl}) : _apiBaseUrl = apiBaseUrl;

  static const kDefaultApiBaseUrl = 'http://127.0.0.1:6806';

  final String? _apiBaseUrl;

  String get _endpoint {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  Future<String> exportConversation({
    required String token,
    required String notebook,
    required String title,
    required String markdownContent,
  }) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      throw const SiyuanSyncException('思源 Token 未配置');
    }
    final normalizedNotebook = notebook.trim();
    if (normalizedNotebook.isEmpty) {
      throw const SiyuanSyncException('笔记本 ID 未配置');
    }
    final trimmedTitle = title.trim().isEmpty ? 'SimiChat 会话' : title.trim();
    final content = markdownContent.trim();
    if (content.isEmpty) {
      throw const SiyuanSyncException('会话内容为空');
    }

    // 思源路径形如 `/2026-08/会话标题`。
    final path = '/${trimmedTitle.replaceAll(RegExp(r'[/\\]'), '-')}';

    final dio = createDio();
    dio.options.headers['Authorization'] = 'Token $normalizedToken';
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_endpoint/api/filetree/createDocWithMd',
        options: Options(responseType: ResponseType.json),
        data: {
          'notebook': normalizedNotebook,
          'path': path,
          'markdown': content,
        },
      );
      final code = response.data?['code'];
      if (code != 0) {
        final msg = response.data?['msg'];
        throw SiyuanSyncException('思源创建文档失败${msg != null ? '：$msg' : ''}');
      }
      final data = response.data?['data'];
      return data is Map && data['box'] != null
          ? '${data['box']}${data['path'] ?? path}'
          : path;
    } on DioException catch (e) {
      throw SiyuanSyncException(_formatSiyuanError(e));
    }
  }

  String _formatSiyuanError(DioException e) {
    final status = e.response?.statusCode;
    if (status != null && status >= 400) {
      switch (status) {
        case 401:
        case 403:
          return '思源 Token 无效或无权限（$status）';
        case 404:
          return '笔记本不存在或无权限（404）';
        default:
          return 'HTTP $status';
      }
    }
    return e.message ?? '网络错误';
  }
}
