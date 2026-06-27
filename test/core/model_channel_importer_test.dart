import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/ai/model_channel_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelChannelImportParser', () {
    test('parses channels wrapper and normalizes base url and models', () {
      final channels = ModelChannelImportParser.parse('''
      {
        "channels": [
          {
            "name": "Free Router",
            "baseUrl": "free.example.com/v1/",
            "protocol": "openai_chat",
            "apiKey": "free-test-key",
            "models": [
              "free-chat",
              {"id": "free-embed", "capability": "embedding"},
              {"name": "free-chat", "capability": "chat"}
            ]
          }
        ]
      }
      ''');

      expect(channels, hasLength(1));
      expect(channels.single.name, 'Free Router');
      expect(channels.single.baseUrl, 'https://free.example.com/v1');
      expect(channels.single.protocol, 'openai_chat');
      expect(channels.single.apiKey, 'free-test-key');
      expect(channels.single.models, hasLength(2));
      expect(channels.single.models.first.name, 'free-chat');
      expect(channels.single.models.last.name, 'free-embed');
      expect(channels.single.models.last.capability, ModelCapability.embedding);
    });

    test('parses root array and allows ollama without api key', () {
      final channels = ModelChannelImportParser.parse('''
      [
        {
          "name": "Local Ollama",
          "base_url": "localhost:11434",
          "protocol": "ollama",
          "models": [{"modelName": "llama3.1"}]
        }
      ]
      ''');

      expect(channels.single.baseUrl, 'http://localhost:11434');
      expect(channels.single.apiKey, isEmpty);
      expect(channels.single.models.single.name, 'llama3.1');
    });

    test('rejects non-json and missing api key for remote providers', () {
      expect(
        () => ModelChannelImportParser.parse('not json'),
        throwsA(isA<ModelChannelImportParseException>()),
      );
      expect(
        () => ModelChannelImportParser.parse('''
        [{"name":"Bad","baseUrl":"https://example.com","protocol":"openai_chat"}]
        '''),
        throwsA(isA<ModelChannelImportParseException>()),
      );
    });

    test('rejects unsupported protocols without echoing api key', () {
      const key = 'free-test-key';
      try {
        ModelChannelImportParser.parse('''
        [{"name":"Bad","baseUrl":"https://example.com","protocol":"bad","apiKey":"$key"}]
        ''');
        fail('should throw');
      } on ModelChannelImportParseException catch (e) {
        expect(e.message, contains('协议不支持'));
        expect(e.message, isNot(contains(key)));
      }
    });
  });
}
