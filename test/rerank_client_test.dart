import 'package:ai_chat_app/core/ai/rerank_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RerankClient.parseRerankResponse', () {
    test('parses Jina / Cohere shape with relevance_score', () {
      final response = RerankClient.parseRerankResponse(
        {
          'model': 'jina-reranker-v2-base-multilingual',
          'results': [
            {'index': 0, 'relevance_score': 0.12},
            {'index': 1, 'relevance_score': 0.97},
            {'index': 2, 'relevance_score': 0.55},
          ],
        },
        fallbackModel: 'fallback',
      );

      expect(response.model, 'jina-reranker-v2-base-multilingual');
      expect(response.results, hasLength(3));
    });

    test('sorts results by score descending', () {
      final response = RerankClient.parseRerankResponse(
        {
          'results': [
            {'index': 0, 'score': 0.2},
            {'index': 1, 'score': 0.9},
            {'index': 2, 'score': 0.5},
          ],
        },
        fallbackModel: 'fallback',
      );

      expect(response.results.map((r) => r.index).toList(), [1, 2, 0]);
      expect(response.results.first.score, 0.9);
    });

    test('parses nested score maps from compatible clones', () {
      final response = RerankClient.parseRerankResponse(
        {
          'results': [
            {'index': 0, 'relevance_score': {'score': 0.8}},
            {'index': 1, 'score': {'value': 0.4}},
          ],
        },
        fallbackModel: 'fallback',
      );

      expect(response.results.map((r) => r.score).toList(), [0.8, 0.4]);
    });

    test('falls back to provided model when response omits it', () {
      final response = RerankClient.parseRerankResponse(
        {
          'results': [
            {'index': 0, 'relevance_score': 1.0},
          ],
        },
        fallbackModel: 'fallback-model',
      );

      expect(response.model, 'fallback-model');
    });

    test('throws FormatException when results list is missing', () {
      expect(
        () => RerankClient.parseRerankResponse(
          {'model': 'm'},
          fallbackModel: 'fallback',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => RerankClient.parseRerankResponse(
          {'results': 'not-a-list'},
          fallbackModel: 'fallback',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when an item lacks index or score', () {
      expect(
        () => RerankClient.parseRerankResponse(
          {
            'results': [
              {'index': 0},
            ],
          },
          fallbackModel: 'fallback',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => RerankClient.parseRerankResponse(
          {
            'results': [
              {'relevance_score': 0.9},
            ],
          },
          fallbackModel: 'fallback',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
