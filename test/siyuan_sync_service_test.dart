import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/archive/siyuan_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SiyuanSyncService', () {
    late HttpServer server;
    late SiyuanSyncService service;
    final requests = <Map<String, dynamic>>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      service = SiyuanSyncService(
        apiBaseUrl: 'http://127.0.0.1:${server.port}',
      );
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        );
        requests.add({
          'path': request.uri.path,
          'auth': request.headers.value('Authorization'),
          'body': body.isEmpty ? null : jsonDecode(utf8.decode(body)),
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'code': 0,
              'data': {'box': 'box', 'path': '/x.md'},
            }),
          );
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('creates markdown doc under notebook', () async {
      final result = await service.exportConversation(
        token: 'siyuan-token',
        notebook: 'notebook-id',
        title: '会话标题',
        markdownContent: '# 摘要\n\n内容',
      );

      final call = requests.single;
      expect(call['path'], '/api/filetree/createDocWithMd');
      expect(call['auth'], 'Token siyuan-token');
      expect((call['body'] as Map)['notebook'], 'notebook-id');
      expect((call['body'] as Map)['markdown'], contains('摘要'));
      expect(result, isNotEmpty);
    });

    test('rejects empty token', () async {
      await expectLater(
        service.exportConversation(
          token: '  ',
          notebook: 'n',
          title: 't',
          markdownContent: 'c',
        ),
        throwsA(isA<SiyuanSyncException>()),
      );
    });
  });
}
