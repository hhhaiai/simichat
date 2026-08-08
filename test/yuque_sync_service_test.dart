import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/archive/yuque_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YuqueSyncService', () {
    late HttpServer server;
    late YuqueSyncService service;
    final requests = <Map<String, dynamic>>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      service = YuqueSyncService(
        apiBaseUrl: 'http://127.0.0.1:${server.port}/api/v2',
      );
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        );
        requests.add({
          'path': request.uri.path,
          'token': request.headers.value('X-Auth-Token'),
          'body': body.isEmpty ? null : jsonDecode(utf8.decode(body)),
        });
        request.response
          ..statusCode = 201
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'data': {'slug': 'doc-123', 'title': 'title'},
            }),
          );
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('creates markdown doc under repo namespace', () async {
      final slug = await service.exportConversation(
        token: 'yuque-token',
        namespace: 'me/repo',
        title: '会话标题',
        markdownContent: '# 摘要\n\n内容',
      );

      expect(slug, 'doc-123');
      final call = requests.single;
      expect(call['path'], '/api/v2/repos/me/repo/docs');
      expect(call['token'], 'yuque-token');
      expect((call['body'] as Map)['title'], '会话标题');
      expect((call['body'] as Map)['format'], 'markdown');
      expect((call['body'] as Map)['body'], contains('摘要'));
    });

    test('rejects invalid namespace', () async {
      await expectLater(
        service.exportConversation(
          token: 't',
          namespace: 'bad-namespace',
          title: 't',
          markdownContent: 'c',
        ),
        throwsA(
          isA<YuqueSyncException>().having(
            (e) => e.message,
            'message',
            contains('namespace'),
          ),
        ),
      );
    });
  });
}
