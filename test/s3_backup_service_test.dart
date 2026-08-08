import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/backup/s3_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('S3BackupService', () {
    late HttpServer server;
    late String endpoint;
    final stored = <String, List<int>>{};
    String? lastAuth;

    setUp(() async {
      stored.clear();
      lastAuth = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      endpoint = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        lastAuth = request.headers.value('Authorization');
        final path = request.uri.path;
        if (request.method == 'GET' &&
            request.uri.queryParameters.containsKey('list-type')) {
          final keys = stored.keys
              .map(
                (k) =>
                    '<Contents><Key>$k</Key><Size>${stored[k]!.length}</Size></Contents>',
              )
              .join();
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType('application', 'xml')
            ..write(
              '<?xml version="1.0"?><ListBucketResult>$keys</ListBucketResult>',
            );
        } else if (request.method == 'PUT') {
          final key = path.split('/').last;
          stored[key] = await request.fold<List<int>>(
            [],
            (acc, chunk) => acc..addAll(chunk),
          );
          request.response.statusCode = 200;
        } else if (request.method == 'GET') {
          final key = path.split('/').last;
          final body = stored[key];
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

    S3BackupConfig config([String? passphrase]) => S3BackupConfig(
      endpoint: endpoint,
      region: 'us-east-1',
      accessKey: 'AKID',
      secretKey: 'SECRET',
      bucket: 'simichat-backups',
      passphrase: passphrase ?? 'backup-secret-123',
    );

    test(
      'uploadBackup signs with AWS4-HMAC-SHA256 and stores encrypted file',
      () async {
        final tmp = Directory.systemTemp.createTempSync('s3-test');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final export = File('${tmp.path}/simichat-export-1.tar.gz')
          ..writeAsBytesSync([1, 2, 3]);

        const service = S3BackupService();
        await service.uploadBackup(exportFile: export, config: config());

        expect(lastAuth, startsWith('AWS4-HMAC-SHA256 Credential='));
        expect(lastAuth, contains('SignedHeaders='));
        expect(lastAuth, contains('Signature='));
        expect(stored['simichat-export-1.tar.gz'], isNotNull);
        final encryptedText = utf8.decode(stored['simichat-export-1.tar.gz']!);
        expect(encryptedText, startsWith('simichat-backup-v1:'));
      },
    );

    test('listBackups parses ListObjectsV2 XML', () async {
      stored['a.tar.gz'] = [1, 2];
      stored['b.tar.gz'] = [3, 4, 5];

      const service = S3BackupService();
      final entries = await service.listBackups(config());

      expect(entries.map((e) => e.key), containsAll(['a.tar.gz', 'b.tar.gz']));
      expect(entries.firstWhere((e) => e.key == 'a.tar.gz').size, 2);
    });

    test('downloadBackup round-trips upload bytes', () async {
      final tmp = Directory.systemTemp.createTempSync('s3-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final export = File('${tmp.path}/simichat-export-1.tar.gz')
        ..writeAsBytesSync([10, 20, 30]);

      const service = S3BackupService();
      await service.uploadBackup(exportFile: export, config: config());
      final restored = await service.downloadBackup(
        key: 'simichat-export-1.tar.gz',
        config: config(),
        downloadDirectory: Directory('${tmp.path}/restored'),
      );

      expect(restored.readAsBytesSync(), [10, 20, 30]);
    });

    test('downloadBackup fails clearly with wrong passphrase', () async {
      final tmp = Directory.systemTemp.createTempSync('s3-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final export = File('${tmp.path}/simichat-export-1.tar.gz')
        ..writeAsBytesSync([1]);

      const service = S3BackupService();
      await service.uploadBackup(exportFile: export, config: config());
      await expectLater(
        service.downloadBackup(
          key: 'simichat-export-1.tar.gz',
          config: config('wrong-passphrase'),
          downloadDirectory: Directory('${tmp.path}/restored'),
        ),
        throwsA(
          isA<S3BackupException>().having(
            (e) => e.message,
            'message',
            contains('口令'),
          ),
        ),
      );
    });
  });
}
