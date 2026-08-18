import 'package:ai_chat_app/core/ai/api_endpoint_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiEndpointResolver OpenAI-compatible paths', () {
    const cases = <Map<String, String>>[
      {
        'base': 'https://api.example.test',
        'expected': 'https://api.example.test/v1/chat/completions',
      },
      {
        'base': 'https://api.example.test/v1',
        'expected': 'https://api.example.test/v1/chat/completions',
      },
      {
        'base': 'https://api.example.test/v2/',
        'expected': 'https://api.example.test/v2/chat/completions',
      },
      {
        'base': 'https://api.example.test/v1/openai',
        'expected': 'https://api.example.test/v1/openai/chat/completions',
      },
      {
        'base': 'https://api.example.test/api/v3/',
        'expected': 'https://api.example.test/api/v3/chat/completions',
      },
      {
        'base': 'https://api.example.test/openai',
        'expected': 'https://api.example.test/openai/v1/chat/completions',
      },
    ];

    for (final testCase in cases) {
      final base = testCase['base']!;
      final expected = testCase['expected']!;
      test('resolves $base without a duplicate version path', () {
        expect(resolveOpenAiEndpoint(base, 'chat/completions'), expected);
      });
    }

    test('does not emit empty query or fragment delimiters', () {
      expect(
        resolveOpenAiEndpoint('https://api.example.test/', 'models'),
        'https://api.example.test/v1/models',
      );
    });

    test('preserves endpoint query parameters', () {
      expect(
        resolveGeminiEndpoint(
          'https://generativelanguage.example.test/v1beta',
          'models/gemini-test:streamGenerateContent?alt=sse',
        ),
        'https://generativelanguage.example.test/v1beta/models/gemini-test:streamGenerateContent?alt=sse',
      );
    });

    test('preserves a configured custom prefix for Claude and model fetch', () {
      expect(
        resolveClaudeEndpoint('https://relay.example.test/api/v3', 'messages'),
        'https://relay.example.test/api/v3/messages',
      );
      expect(
        resolveOpenAiEndpoint('https://relay.example.test/api/v3', 'models'),
        'https://relay.example.test/api/v3/models',
      );
    });

    test(
      'recognizes versioned Gemini beta prefixes without adding another one',
      () {
        expect(
          resolveGeminiEndpoint(
            'https://generativelanguage.example.test/v1beta1',
            'models',
          ),
          'https://generativelanguage.example.test/v1beta1/models',
        );
      },
    );

    test('uses protocol-specific defaults only for origin-only URLs', () {
      expect(
        resolveClaudeEndpoint('https://api.anthropic.example.test', 'messages'),
        'https://api.anthropic.example.test/v1/messages',
      );
      expect(
        resolveGeminiEndpoint(
          'https://generativelanguage.example.test',
          'models',
        ),
        'https://generativelanguage.example.test/v1beta/models',
      );
      expect(
        resolveOllamaEndpoint('http://ollama.example.test', 'api/chat'),
        'http://ollama.example.test/api/chat',
      );
    });

    test('keeps an endpoint that already includes the configured prefix', () {
      expect(
        resolveOpenAiEndpoint(
          'https://api.example.test/v1',
          '/v1/chat/completions',
        ),
        'https://api.example.test/v1/chat/completions',
      );
    });

    test('rejects non HTTP(S) base and endpoint schemes', () {
      expect(
        () => resolveOpenAiEndpoint('ftp://api.example.test', 'models'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => resolveOpenAiEndpoint(
          'https://api.example.test',
          'ftp://other.example.test/models',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('brackets a bare IPv6 host before constructing an endpoint', () {
      expect(normalizeUrl('::1'), 'http://[::1]');
      expect(resolveOpenAiEndpoint('::1', 'models'), 'http://[::1]/v1/models');
      expect(normalizeUrl('2001:db8::1/v1/'), 'http://[2001:db8::1]/v1');
    });

    test('strips a case-insensitive terminal /v1 while retaining query', () {
      expect(
        normalizeOpenAiBaseUrl('https://api.example.test/API/V1/?tenant=demo'),
        'https://api.example.test/API?tenant=demo',
      );
      expect(
        normalizeOpenAiBaseUrl('https://api.example.test/api/v2?version=v1'),
        'https://api.example.test/api/v2?version=v1',
      );
    });
  });
}
