import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/backup/webdav_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebDavBackupService', () {
    late HttpServer server;
    late String baseUrl;
    final storedFiles = <String, List<int>>{};
    String? lastAuth;

    setUp(() async {
      storedFiles.clear();
      lastAuth = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}/dav/';
      server.listen((request) async {
        lastAuth = request.headers.value('Authorization');
        final path = request.uri.path;
        if (request.method == 'PROPFIND') {
          final files = storedFiles.keys
              .map(
                (name) =>
                    '<d:response>'
                    '<d:href>/dav/$name</d:href>'
                    '<d:propstat><d:prop>'
                    '<d:getcontentlength>${storedFiles[name]!.length}</d:getcontentlength>'
                    '<d:getlastmodified>Wed, 01 Jan 2025 00:00:00 GMT</d:getlastmodified>'
                    '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
                    '</d:response>',
              )
              .join();
          request.response
            ..statusCode = 207
            ..headers.contentType = ContentType('application', 'xml')
            ..write('<d:multistatus xmlns:d="DAV:">$files</d:multistatus>');
        } else if (request.method == 'PUT') {
          final name = path.split('/').last;
          final body = await request.fold<List<int>>(
            [],
            (acc, chunk) => acc..addAll(chunk),
          );
          storedFiles[name] = body;
          request.response.statusCode = 201;
        } else if (request.method == 'GET') {
          final name = path.split('/').last;
          final body = storedFiles[name];
          if (body == null) {
            request.response.statusCode = 404;
          } else {
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.binary
              ..add(body);
          }
        } else {
          request.response.statusCode = 405;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    WebDavBackupConfig config([String? passphrase]) => WebDavBackupConfig(
      baseUrl: baseUrl,
      username: 'user',
      password: 'pass',
      passphrase: passphrase ?? 'backup-secret-123',
    );

    test('uploadBackup PUTs passphrase-encrypted file', () async {
      final tmp = Directory.systemTemp.createTempSync('wd-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final export = File('${tmp.path}/simichat-export-20260807.tar.gz')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);

      const service = WebDavBackupService();
      await service.uploadBackup(exportFile: export, config: config());

      expect(storedFiles.keys, contains('simichat-export-20260807.tar.gz'));
      expect(lastAuth, startsWith('Basic '));
      // 远端内容是加密后的文本（非原始字节）。
      final encryptedText = utf8.decode(
        storedFiles['simichat-export-20260807.tar.gz']!,
      );
      expect(encryptedText, startsWith('simichat-backup-v1:'));
      expect(encryptedText, isNot(contains('AAAA')));
    });

    test('listBackups parses PROPFIND multistatus', () async {
      storedFiles['a.tar.gz'] = [1, 2];
      storedFiles['b.tar.gz'] = [3, 4, 5];

      const service = WebDavBackupService();
      final entries = await service.listBackups(config());

      expect(entries.map((e) => e.name), containsAll(['a.tar.gz', 'b.tar.gz']));
      final a = entries.firstWhere((e) => e.name == 'a.tar.gz');
      expect(a.size, 2);
      expect(a.modifiedAt, isNotNull);
    });

    test('downloadBackup round-trips upload bytes', () async {
      final tmp = Directory.systemTemp.createTempSync('wd-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final export = File('${tmp.path}/simichat-export-20260807.tar.gz')
        ..writeAsBytesSync([10, 20, 30, 40]);

      const service = WebDavBackupService();
      await service.uploadBackup(exportFile: export, config: config());

      final restored = await service.downloadBackup(
        name: 'simichat-export-20260807.tar.gz',
        config: config(),
        downloadDirectory: Directory('${tmp.path}/restored'),
      );

      expect(restored.readAsBytesSync(), [10, 20, 30, 40]);
    });

    test('downloadBackup fails clearly with wrong passphrase', () async {
      final tmp = Directory.systemTemp.createTempSync('wd-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final export = File('${tmp.path}/simichat-export-20260807.tar.gz')
        ..writeAsBytesSync([1, 2, 3]);

      const service = WebDavBackupService();
      await service.uploadBackup(exportFile: export, config: config());

      await expectLater(
        service.downloadBackup(
          name: 'simichat-export-20260807.tar.gz',
          config: config('wrong-passphrase'),
          downloadDirectory: Directory('${tmp.path}/restored'),
        ),
        throwsA(
          isA<WebDavBackupException>().having(
            (e) => e.message,
            'message',
            contains('口令'),
          ),
        ),
      );
    });

    test('validate rejects short passphrase and bad base url', () {
      const service = WebDavBackupService();
      expect(
        () => service.listBackups(config('short')),
        throwsA(
          isA<WebDavBackupException>().having(
            (e) => e.message,
            'message',
            contains('至少 8 位'),
          ),
        ),
      );
      expect(
        () => service.listBackups(
          WebDavBackupConfig(
            baseUrl: 'ftp://bad',
            username: 'u',
            password: 'p',
            passphrase: 'backup-secret-123',
          ),
        ),
        throwsA(
          isA<WebDavBackupException>().having(
            (e) => e.message,
            'message',
            contains('仅支持 HTTP(S)'),
          ),
        ),
      );
    });
  });
}
