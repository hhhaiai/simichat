import 'dart:convert';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';

class NotionSyncException implements Exception {
  final String message;
  const NotionSyncException(this.message);

  @override
  String toString() => message;
}

/// Notion 同步结果。
class NotionSyncResult {
  final String pageId;
  final String pageUrl;
  final int blockCount;
  const NotionSyncResult({
    required this.pageId,
    required this.pageUrl,
    required this.blockCount,
  });
}

/// 校验 Notion Integration Token。
String normalizeNotionToken(String token) {
  final value = token.trim();
  if (value.isEmpty) {
    throw const NotionSyncException('Notion Token 未配置');
  }
  return value;
}

/// 校验 Notion 父页面 ID（支持完整 URL 或裸 ID）。
String normalizeNotionParentId(String parentId) {
  final value = parentId.trim();
  if (value.isEmpty) {
    throw const NotionSyncException('父页面 ID 未配置');
  }
  final match = RegExp(r'[a-f0-9]{32}').firstMatch(value);
  if (match == null) {
    throw const NotionSyncException('父页面 ID 格式无效');
  }
  return match.group(0)!;
}

/// 把 SimiChat 会话 Markdown 导出为 Notion 页面。
///
/// - 使用 Integration Token（Bearer 鉴权）；
/// - 在指定父页面下创建子页面（标题）；
/// - 把 Markdown 拆成 heading / paragraph 块批量写入。
class NotionSyncService {
  const NotionSyncService({String? apiBaseUrl}) : _apiBaseUrl = apiBaseUrl;

  static const kDefaultApiBaseUrl = 'https://api.notion.com';

  final String? _apiBaseUrl;

  String get _endpoint {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}/v1';
  }

  Future<NotionSyncResult> exportConversation({
    required String token,
    required String parentPageId,
    required String title,
    required String markdownContent,
  }) async {
    final normalizedToken = normalizeNotionToken(token);
    final normalizedParent = normalizeNotionParentId(parentPageId);
    final trimmedTitle = title.trim().isEmpty ? 'SimiChat 会话' : title.trim();
    if (markdownContent.trim().isEmpty) {
      throw const NotionSyncException('会话内容为空');
    }

    final dio = _dioFor(normalizedToken);

    // 1. 创建页面。
    final Map<String, dynamic> page;
    try {
      final pageResponse = await dio.post<Map<String, dynamic>>(
        '$_endpoint/pages',
        options: Options(
          headers: {'Notion-Version': '2022-06-28'},
          responseType: ResponseType.json,
        ),
        data: {
          'parent': {'page_id': normalizedParent},
          'properties': {
            'title': {
              'title': [
                {
                  'type': 'text',
                  'text': {'content': trimmedTitle},
                },
              ],
            },
          },
        },
      );
      page = pageResponse.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw NotionSyncException(_formatNotionError(e, '创建页面失败'));
    }

    final pageId = page['id'] as String?;
    if (pageId == null) {
      throw const NotionSyncException('Notion 未返回页面 ID');
    }
    final pageUrl = page['url'] as String? ?? '';

    // 2. 拆块并写入子块。
    final blocks = _markdownToBlocks(markdownContent);
    if (blocks.isNotEmpty) {
      try {
        await dio.patch<Map<String, dynamic>>(
          '$_endpoint/blocks/$pageId/children',
          options: Options(
            headers: {'Notion-Version': '2022-06-28'},
            responseType: ResponseType.json,
          ),
          data: {'children': blocks},
        );
      } on DioException catch (e) {
        throw NotionSyncException(_formatNotionError(e, '写入内容失败'));
      }
    }

    return NotionSyncResult(
      pageId: pageId,
      pageUrl: pageUrl,
      blockCount: blocks.length,
    );
  }

  /// 简单 Markdown → Notion 块：`# ` / `## ` 标题 + 段落。
  List<Map<String, dynamic>> _markdownToBlocks(String markdown) {
    final blocks = <Map<String, dynamic>>[];
    for (final rawLine in const LineSplitter().convert(markdown)) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;
      if (line.startsWith('## ')) {
        blocks.add(_block('heading_2', line.substring(3).trim()));
      } else if (line.startsWith('# ')) {
        blocks.add(_block('heading_1', line.substring(2).trim()));
      } else if (line.startsWith('### ')) {
        blocks.add(_block('heading_3', line.substring(4).trim()));
      } else {
        blocks.add(_block('paragraph', line.trim()));
      }
      if (blocks.length >= 100) break; // Notion 单次子块上限保护。
    }
    return blocks;
  }

  Map<String, dynamic> _block(String type, String text) {
    return {
      'object': 'block',
      'type': type,
      type: {
        'rich_text': [
          {
            'type': 'text',
            'text': {'content': text},
          },
        ],
      },
    };
  }

  Dio _dioFor(String token) {
    final dio = createDio();
    dio.options.headers['Authorization'] = 'Bearer $token';
    dio.options.headers['Notion-Version'] = '2022-06-28';
    return dio;
  }

  String _formatNotionError(DioException e, String action) {
    final status = e.response?.statusCode;
    if (status != null && status >= 400) {
      String? message;
      try {
        final data = e.response?.data;
        if (data is Map) message = data['message']?.toString();
      } catch (_) {}
      switch (status) {
        case 401:
          return '$action：Notion Token 无效（401）';
        case 404:
          return '$action：父页面不存在或无权限（404）';
        default:
          return '$action：HTTP $status${message != null ? '：$message' : ''}';
      }
    }
    return '$action：${e.message ?? '网络错误'}';
  }
}
