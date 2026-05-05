import 'package:dio/dio.dart';

import 'http_helper.dart';

class EmbeddingResponse {
  final String model;
  final List<List<double>> vectors;

  const EmbeddingResponse({required this.model, required this.vectors});
}

/// Generic OpenAI-compatible `/v1/embeddings` client.
class OpenAiEmbeddingClient {
  const OpenAiEmbeddingClient();

  Future<EmbeddingResponse> createEmbeddings({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<String> input,
  }) async {
    if (input.isEmpty) {
      throw ArgumentError.value(input, 'input', 'input must not be empty');
    }

    final dio = createDio();
    final url = buildEmbeddingsUrl(baseUrl);
    try {
      final response = await dio.post<Map<String, dynamic>>(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {'model': model, 'input': input},
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException('Empty embeddings response');
      }
      return parseEmbeddingResponse(data, fallbackModel: model);
    } on DioException catch (e) {
      throw Exception(formatDioError(e));
    } finally {
      dio.close();
    }
  }

  static String buildEmbeddingsUrl(String baseUrl) {
    return "${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/embeddings";
  }

  static EmbeddingResponse parseEmbeddingResponse(
    Map<String, dynamic> json, {
    required String fallbackModel,
  }) {
    final rawData = json['data'];
    if (rawData is! List) {
      throw const FormatException('Embeddings response missing data list');
    }

    final vectors = <List<double>>[];
    for (final item in rawData) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid embedding item');
      }
      final rawEmbedding = item['embedding'];
      if (rawEmbedding is! List) {
        throw const FormatException('Embedding item missing vector');
      }
      vectors.add(
        rawEmbedding
            .map((value) {
              if (value is num) return value.toDouble();
              throw const FormatException(
                'Embedding vector contains non-numeric value',
              );
            })
            .toList(growable: false),
      );
    }

    return EmbeddingResponse(
      model: json['model']?.toString() ?? fallbackModel,
      vectors: List.unmodifiable(vectors),
    );
  }
}
