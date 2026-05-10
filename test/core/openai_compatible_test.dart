import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/ai/model_fetcher.dart';
import 'package:ai_chat_app/core/ai/openai_embedding_client.dart';
import 'package:ai_chat_app/core/ai/sse_helper.dart';

void main() {
  group('OpenAI-compatible model parsing', () {
    test('infers embedding models from common ids', () {
      expect(
        ModelCapability.inferFromModel('BAAI/bge-m3'),
        ModelCapability.embedding,
      );
      expect(
        ModelCapability.inferFromModel('text-embedding-3-large'),
        ModelCapability.embedding,
      );
      expect(
        ModelCapability.inferFromModel('grok-4.20-0309'),
        ModelCapability.chat,
      );
      expect(
        ModelCapability.inferFromModel('mimo-v2.5-pro'),
        ModelCapability.chat,
      );
    });

    test('parses /v1/models with capability metadata', () {
      final models = ModelFetcher.parseOpenAIModels({
        'data': [
          {'id': 'grok-4.20-0309'},
          {'id': 'BAAI/bge-m3'},
          {'id': 'custom-vector', 'type': 'embedding'},
        ],
      });

      expect(
        models.map((m) => m.id),
        containsAll(['grok-4.20-0309', 'BAAI/bge-m3', 'custom-vector']),
      );
      expect(
        models.firstWhere((m) => m.id == 'grok-4.20-0309').capability,
        ModelCapability.chat,
      );
      expect(
        models.firstWhere((m) => m.id == 'BAAI/bge-m3').capability,
        ModelCapability.embedding,
      );
      expect(
        models.firstWhere((m) => m.id == 'custom-vector').capability,
        ModelCapability.embedding,
      );
    });
  });

  group('OpenAI-compatible embeddings', () {
    test('normalizes host-only and localhost base urls', () {
      expect(normalizeUrl('api.openai.com'), 'https://api.openai.com');
      expect(normalizeUrl('api.openai.com/v1/'), 'https://api.openai.com/v1');
      expect(normalizeUrl('localhost:11434'), 'http://localhost:11434');
      expect(normalizeUrl('47.85.40.209:5001'), 'http://47.85.40.209:5001');
      expect(
        normalizeOpenAiBaseUrl('api.openai.com/v1'),
        'https://api.openai.com',
      );
    });

    test('builds stable embeddings endpoint', () {
      expect(
        OpenAiEmbeddingClient.buildEmbeddingsUrl('https://router.tumuer.me/'),
        'https://router.tumuer.me/v1/embeddings',
      );
    });

    test('parses embeddings response vectors', () {
      final parsed = OpenAiEmbeddingClient.parseEmbeddingResponse({
        'model': 'BAAI/bge-m3',
        'data': [
          {
            'embedding': [0, 1.5, -2],
          },
          {
            'embedding': [3.25, 4, 5],
          },
        ],
      }, fallbackModel: 'fallback');

      expect(parsed.model, 'BAAI/bge-m3');
      expect(parsed.vectors, [
        [0.0, 1.5, -2.0],
        [3.25, 4.0, 5.0],
      ]);
    });
  });
}
