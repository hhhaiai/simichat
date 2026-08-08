import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/search/web_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebSearchService', () {
    late HttpServer server;
    late WebSearchService service;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      service = WebSearchService(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('returns abstract and related topics', () async {
      server.listen((request) async {
        expect(request.uri.queryParameters['q'], 'flutter 是什么');
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'AbstractText': 'Flutter 是 Google 的跨平台 UI 框架。',
              'Heading': 'Flutter',
              'AbstractURL': 'https://flutter.dev',
              'RelatedTopics': [
                {'Text': 'Flutter 用 Dart 编写。', 'FirstURL': 'https://dart.dev'},
                {
                  'Text': 'Flutter 支持 iOS/Android。',
                  'FirstURL': 'https://flutter.dev',
                },
              ],
            }),
          );
        await request.response.close();
      });

      final results = await service.search('flutter 是什么');
      expect(results.length, 3);
      expect(results.first.title, 'Flutter');
      expect(results.first.snippet, contains('跨平台'));
      expect(results.first.url, 'https://flutter.dev');
      expect(results.map((r) => r.title), contains('相关'));
    });

    test('throws friendly error on empty query', () async {
      await expectLater(
        service.search('   '),
        throwsA(
          isA<WebSearchException>().having(
            (e) => e.message,
            'message',
            contains('不能为空'),
          ),
        ),
      );
    });

    test('throws friendly error when no results', () async {
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, dynamic>{}));
        await request.response.close();
      });
      await expectLater(
        service.search('不存在的内容'),
        throwsA(isA<WebSearchException>()),
      );
    });
  });
}
