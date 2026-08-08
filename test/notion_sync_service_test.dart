import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/archive/notion_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotionSyncService', () {
    late HttpServer server;
    late NotionSyncService service;
    final requests = <Map<String, dynamic>>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      service = NotionSyncService(
        apiBaseUrl: 'http://127.0.0.1:${server.port}',
      );
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        );
        requests.add({
          'method': request.method,
          'path': request.uri.path,
          'auth': request.headers.value('Authorization'),
          'body': body.isEmpty ? null : jsonDecode(utf8.decode(body)),
        });
        if (request.uri.path == '/v1/pages') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'id': 'page-123',
                'url': 'https://www.notion.so/page-123',
              }),
            );
        } else if (request.uri.path.contains('/blocks/') &&
            request.uri.path.endsWith('/children')) {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'results': []}));
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('creates page and writes blocks from markdown', () async {
      final result = await service.exportConversation(
        token: 'secret-token',
        parentPageId: 'https://www.notion.so/abcdef1234567890abcdef1234567890',
        title: '会话标题',
        markdownContent: '# 摘要\n\n## 关键点\n\n第一段内容',
      );

      expect(result.pageId, 'page-123');
      expect(result.blockCount, 3);

      final pageCall = requests.firstWhere((r) => r['path'] == '/v1/pages');
      expect(pageCall['auth'], 'Bearer secret-token');
      expect(
        ((pageCall['body'] as Map)['properties']['title']['title'] as List)
            .first['text']['content'],
        '会话标题',
      );

      final childrenCall = requests.firstWhere(
        (r) => r['path'] == '/v1/blocks/page-123/children',
      );
      final children = ((childrenCall['body'] as Map)['children'] as List);
      expect((children.first as Map)['type'], 'heading_1');
      expect(
        ((children[1] as Map)['heading_2']['rich_text'] as List)
            .first['text']['content'],
        '关键点',
      );
    });

    test('rejects invalid token before calling upstream', () async {
      await expectLater(
        service.exportConversation(
          token: '  ',
          parentPageId: 'abcdef1234567890abcdef1234567890',
          title: 't',
          markdownContent: 'c',
        ),
        throwsA(isA<NotionSyncException>()),
      );
    });

    test('rejects malformed parent id', () async {
      await expectLater(
        service.exportConversation(
          token: 't',
          parentPageId: 'not-a-uuid',
          title: 't',
          markdownContent: 'c',
        ),
        throwsA(
          isA<NotionSyncException>().having(
            (e) => e.message,
            'message',
            contains('格式无效'),
          ),
        ),
      );
    });

    test('throws friendly error on 401', () async {
      // 覆盖 server 默认行为前先关闭当前监听会麻烦，这里用单独 server。
      final bad = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => bad.close(force: true));
      bad.listen((request) async {
        request.response
          ..statusCode = 401
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'message': 'invalid token'}));
        await request.response.close();
      });
      final s2 = NotionSyncService(apiBaseUrl: 'http://127.0.0.1:${bad.port}');
      await expectLater(
        s2.exportConversation(
          token: 'bad',
          parentPageId: 'abcdef1234567890abcdef1234567890',
          title: 't',
          markdownContent: 'c',
        ),
        throwsA(
          isA<NotionSyncException>().having(
            (e) => e.message,
            'message',
            contains('401'),
          ),
        ),
      );
    });
  });
}
