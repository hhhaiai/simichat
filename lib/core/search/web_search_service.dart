import 'package:dio/dio.dart';

import '../ai/http_helper.dart';

/// 网页搜索结果。
class WebSearchResult {
  final String title;
  final String snippet;
  final String? url;

  const WebSearchResult({required this.title, required this.snippet, this.url});

  Map<String, dynamic> toJson() => {
    'title': title,
    'snippet': snippet,
    if (url != null) 'url': url,
  };
}

class WebSearchException implements Exception {
  final String message;
  const WebSearchException(this.message);

  @override
  String toString() => message;
}

/// 免 Key 的网页搜索：DuckDuckGo Instant Answer API。
///
/// 返回摘要 + 相关话题，适合作为 RAG / 工具调用的轻量来源。
class WebSearchService {
  const WebSearchService({Uri? endpoint}) : _endpoint = endpoint;

  /// 可注入的端点（测试用）；默认 DuckDuckGo Instant Answer。
  final Uri? _endpoint;

  static const _maxQueryLength = 200;

  Future<List<WebSearchResult>> search(
    String query, {
    int maxResults = 5,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw const WebSearchException('搜索关键词不能为空');
    }
    if (trimmed.length > _maxQueryLength) {
      throw const WebSearchException('搜索关键词过长');
    }

    final endpoint = _endpoint ?? Uri.https('api.duckduckgo.com', '/');
    final uri = endpoint.replace(
      queryParameters: {
        'q': trimmed,
        'format': 'json',
        'no_html': '1',
        'skip_disambig': '1',
      },
    );

    final dio = createDio();
    final List<WebSearchResult> results;
    try {
      final response = await dio.get<Map<String, dynamic>>(
        uri.toString(),
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data ?? const <String, dynamic>{};
      results = _extractResults(data, maxResults);
    } on DioException catch (e) {
      throw WebSearchException(formatDioError(e));
    }

    if (results.isEmpty) {
      throw const WebSearchException('未找到相关结果');
    }
    return results;
  }

  List<WebSearchResult> _extractResults(
    Map<String, dynamic> data,
    int maxResults,
  ) {
    final results = <WebSearchResult>[];

    final abstractText = data['AbstractText'] as String?;
    if (abstractText != null && abstractText.trim().isNotEmpty) {
      results.add(
        WebSearchResult(
          title: (data['Heading'] as String?)?.trim().isNotEmpty == true
              ? (data['Heading'] as String).trim()
              : '摘要',
          snippet: abstractText.trim(),
          url: data['AbstractURL'] as String?,
        ),
      );
    }

    final related = data['RelatedTopics'];
    if (related is List) {
      for (final item in related) {
        if (results.length >= maxResults) break;
        if (item is! Map) continue;
        final text = item['Text'] as String?;
        final url = item['FirstURL'] as String?;
        final topics = item['Topics'];
        if (topics is List) {
          for (final sub in topics) {
            if (results.length >= maxResults) break;
            if (sub is! Map) continue;
            final subText = sub['Text'] as String?;
            if (subText != null && subText.trim().isNotEmpty) {
              results.add(
                WebSearchResult(
                  title: '相关',
                  snippet: subText.trim(),
                  url: sub['FirstURL'] as String?,
                ),
              );
            }
          }
        } else if (text != null && text.trim().isNotEmpty) {
          results.add(
            WebSearchResult(title: '相关', snippet: text.trim(), url: url),
          );
        }
      }
    }

    return results.take(maxResults).toList(growable: false);
  }
}
