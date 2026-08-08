import 'dart:convert';

import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/core/search/web_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 注入固定结果的搜索服务。
class _FakeWebSearchService extends WebSearchService {
  const _FakeWebSearchService();

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int maxResults = 5,
  }) async {
    return const [
      WebSearchResult(
        title: 'Flutter',
        snippet: '跨平台 UI 框架',
        url: 'https://flutter.dev',
      ),
    ];
  }
}

void main() {
  group('AppNativeMcpTransport web_search tool', () {
    test('lists simichat.web_search in tools', () async {
      final transport = AppNativeMcpTransport();
      final messages = <Map<String, dynamic>>[];
      await transport.connect(messages.add);

      Map<String, dynamic>? result;
      await transport.send({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
        'params': <String, dynamic>{},
      });
      for (final message in messages) {
        if (message['id'] == 1) {
          result = message['result'] as Map<String, dynamic>;
        }
      }
      final tools = result?['tools'] as List? ?? [];
      expect(
        tools.any((t) {
          if (t is! Map) return false;
          if (t['name'] != 'simichat.web_search') return false;
          final schema = t['inputSchema'] as Map;
          final required = schema['required'] as List;
          return required.contains('query');
        }),
        isTrue,
      );
    });

    test('calls web_search and returns results', () async {
      final transport = AppNativeMcpTransport(
        webSearch: _FakeWebSearchService(),
      );
      final messages = <Map<String, dynamic>>[];
      await transport.connect(messages.add);

      await transport.send({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {
          'name': 'simichat.web_search',
          'arguments': {'query': 'flutter'},
        },
      });
      await transport.disconnect();

      Map<String, dynamic>? result;
      for (final message in messages) {
        if (message['id'] == 2) {
          result = message['result'] as Map<String, dynamic>;
        }
      }
      expect(result, isNotNull);
      final content = result!['content'] as List;
      final text = (content.first as Map)['text'] as String;
      expect(text, contains('flutter.dev'));
    });

    test('web_search returns isError for empty query', () async {
      final transport = AppNativeMcpTransport(
        webSearch: _FakeWebSearchService(),
      );
      final messages = <Map<String, dynamic>>[];
      await transport.connect(messages.add);

      await transport.send({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'simichat.web_search',
          'arguments': {'query': '  '},
        },
      });
      await transport.disconnect();

      Map<String, dynamic>? result;
      for (final message in messages) {
        if (message['id'] == 3) {
          result = message['result'] as Map<String, dynamic>;
        }
      }
      expect(result?['isError'], isTrue);
      expect(jsonEncode(result?['content']), contains('非空 query'));
    });
  });
}
