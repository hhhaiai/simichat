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

    test('parses single channel object at root', () {
      final channels = ModelChannelImportParser.parse('''
      {
        "presetId": "mistral",
        "apiKey": "mistral-test-key",
        "models": ["mistral-small-latest"]
      }
      ''');

      expect(channels, hasLength(1));
      expect(channels.single.name, 'Mistral AI');
      expect(channels.single.baseUrl, 'https://api.mistral.ai/v1');
      expect(channels.single.protocol, 'openai_chat');
      expect(channels.single.apiKey, 'mistral-test-key');
      expect(channels.single.models.single.name, 'mistral-small-latest');
    });

    test('parses single model shorthand fields', () {
      final fromModelField = ModelChannelImportParser.parse('''
      {
        "presetId": "groq",
        "apiKey": "groq-test-key",
        "model": "llama-3.1-8b-instant"
      }
      ''');
      final fromModelsString = ModelChannelImportParser.parse('''
      {
        "presetId": "mistral",
        "apiKey": "mistral-test-key",
        "models": "mistral-small-latest"
      }
      ''');

      expect(fromModelField.single.models.single.name, 'llama-3.1-8b-instant');
      expect(fromModelsString.single.models.single.name, 'mistral-small-latest');
    });

    test('fills missing channel fields from provider preset id', () {
      final channels = ModelChannelImportParser.parse('''
      {
        "channels": [
          {
            "presetId": "groq",
            "apiKey": "groq-test-key",
            "models": ["llama-3.1-8b-instant"]
          }
        ]
      }
      ''');

      expect(channels.single.name, 'Groq');
      expect(channels.single.baseUrl, 'https://api.groq.com/openai/v1');
      expect(channels.single.protocol, 'openai_chat');
      expect(channels.single.apiKey, 'groq-test-key');
      expect(channels.single.models.single.name, 'llama-3.1-8b-instant');
    });

    test('matches provider preset id case-insensitively', () {
      final channels = ModelChannelImportParser.parse('''
      [
        {
          "provider": "Groq",
          "apiKey": "groq-test-key",
          "models": ["llama-3.1-8b-instant"]
        }
      ]
      ''');

      expect(channels.single.name, 'Groq');
      expect(channels.single.baseUrl, 'https://api.groq.com/openai/v1');
      expect(channels.single.protocol, 'openai_chat');
    });

    test('matches provider preset display name', () {
      final channels = ModelChannelImportParser.parse('''
      [
        {
          "provider": "Mistral AI",
          "apiKey": "mistral-test-key",
          "models": ["mistral-small-latest"]
        }
      ]
      ''');

      expect(channels.single.name, 'Mistral AI');
      expect(channels.single.baseUrl, 'https://api.mistral.ai/v1');
      expect(channels.single.protocol, 'openai_chat');
      expect(channels.single.models.single.name, 'mistral-small-latest');
    });

    test('matches slash-separated provider preset short name', () {
      final channels = ModelChannelImportParser.parse('''
      [
        {
          "provider": "Kimi",
          "apiKey": "kimi-test-key",
          "models": ["moonshot-v1-8k"]
        }
      ]
      ''');

      expect(channels.single.name, 'Kimi / Moonshot AI');
      expect(channels.single.baseUrl, 'https://api.moonshot.ai/v1');
      expect(channels.single.protocol, 'openai_chat');
      expect(channels.single.models.single.name, 'moonshot-v1-8k');
    });

    test('matches provider preset display name with slash spacing differences', () {
      final channels = ModelChannelImportParser.parse('''
      [
        {
          "provider": "Kimi/Moonshot AI",
          "apiKey": "kimi-test-key",
          "models": ["moonshot-v1-8k"]
        }
      ]
      ''');

      expect(channels.single.name, 'Kimi / Moonshot AI');
      expect(channels.single.baseUrl, 'https://api.moonshot.ai/v1');
      expect(channels.single.protocol, 'openai_chat');
      expect(channels.single.models.single.name, 'moonshot-v1-8k');
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

    test('sanitizes secret-like unknown provider preset diagnostics', () {
      const secret = 'sk-test-secret-provider-1234567890';
      try {
        ModelChannelImportParser.parse('''
        [{"provider":"$secret","apiKey":"safe-user-key","models":["model-a"]}]
        ''');
        fail('should throw');
      } on ModelChannelImportParseException catch (e) {
        expect(e.message, contains('未知厂商预设'));
        expect(e.message, contains('[已隐藏]'));
        expect(e.message, isNot(contains(secret)));
      }
    });
  });
}
