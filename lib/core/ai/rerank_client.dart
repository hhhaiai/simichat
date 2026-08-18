import 'package:dio/dio.dart';

import 'http_helper.dart';
import 'sse_helper.dart';

class RerankResult {
  final int index;
  final double score;

  const RerankResult({required this.index, required this.score});
}

class RerankResponse {
  final String model;
  final List<RerankResult> results;

  const RerankResponse({required this.model, required this.results});
}

/// Generic OpenAI-compatible `/v1/rerank` client.
/// Covers Jina / Cohere / OpenAI-compatible wire shapes in one tolerant
/// parser.
class RerankClient {
  const RerankClient();

  Future<RerankResponse> rerank({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String query,
    required List<String> documents,
    int? topN,
  }) async {
    if (query.trim().isEmpty) {
      throw ArgumentError.value(query, 'query', 'query must not be empty');
    }
    if (documents.isEmpty) {
      throw ArgumentError.value(
        documents,
        'documents',
        'documents must not be empty',
      );
    }

    final dio = createDio();
    final url = buildRerankUrl(baseUrl);
    try {
      final response = await dio.post<Map<String, dynamic>>(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'query': query,
          'documents': documents,
          'top_n': ?topN,
        },
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException('Empty rerank response');
      }
      return parseRerankResponse(data, fallbackModel: model);
    } on DioException catch (e) {
      throw Exception(formatDioError(e));
    } finally {
      dio.close();
    }
  }

  static String buildRerankUrl(String baseUrl) {
    return resolveOpenAiEndpoint(baseUrl, 'rerank');
  }

  /// Parse a rerank response across wire variants:
  /// - Jina / Cohere: `results: [{index, relevance_score}]`
  /// - OpenAI-compatible clones: `results: [{index, score}]`, occasionally
  ///   nested as `relevance_score: {score: 0.9}` / `{value: 0.9}`.
  /// Results are sorted by score descending.
  static RerankResponse parseRerankResponse(
    Map<String, dynamic> json, {
    required String fallbackModel,
  }) {
    final rawResults = json['results'];
    if (rawResults is! List) {
      throw const FormatException('Rerank response missing results list');
    }

    final results = <RerankResult>[];
    for (final item in rawResults) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid rerank result item');
      }
      final rawIndex = item['index'];
      final score = _parseScore(item['relevance_score'] ?? item['score']);
      if (rawIndex is! num || score == null) {
        throw const FormatException(
          'Rerank result missing index or score',
        );
      }
      results.add(RerankResult(index: rawIndex.toInt(), score: score));
    }

    results.sort((a, b) => b.score.compareTo(a.score));

    return RerankResponse(
      model: json['model']?.toString() ?? fallbackModel,
      results: List.unmodifiable(results),
    );
  }

  static double? _parseScore(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is Map<String, dynamic>) {
      final nested = value['score'] ?? value['value'];
      if (nested is num) return nested.toDouble();
    }
    return null;
  }
}
