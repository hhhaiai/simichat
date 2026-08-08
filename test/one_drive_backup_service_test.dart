import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/backup/one_drive_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OneDriveBackupService', () {
    late HttpServer server;
    late String restBase;
    final stored = <String, List<int>>{};
    String? lastAuth;

    setUp(() async {
      stored.clear();
      lastAuth = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      restBase = 'http://127.0.0.1:${server.port}/v1.0';
      server.listen((request) async {
        lastAuth = request.headers.value('Authorization');
        if (request.uri.path.endsWith('/content') && request.method == 'PUT') {
          final name = request.uri.pathSegments
              .lastWhere(
                (s) => s.endsWith(':'),
                orElse: () => request.uri.pathSegments.last,
              )
              .replaceAll(':', '');
          stored[name] = await request.fold<List<int>>(
            [],
            (acc, chunk) => acc..addAll(chunk),
          );
          request.response.statusCode = 201;
        } else if (request.uri.path.endsWith('/children')) {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'value': [
                  {'name': 'a.tar.gz', 'size': 10},
                  {'name': 'b.tar.gz', 'size': 20},
                  {'name': 'folder', 'size': 0},
                ],
              }),
            );
        } else if (request.uri.path.endsWith('/content') &&
            request.method == 'GET') {
          final name = request.uri.pathSegments
              .lastWhere(
                (s) => s.endsWith(':'),
                orElse: () => request.uri.pathSegments.last,
              )
              .replaceAll(':', '');
          final body = stored[name];
          if (body == null) {
            request.response.statusCode = 404;
          } else {
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.binary
              ..add(body);
          }
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    OneDriveBackupConfig config([String? passphrase]) => OneDriveBackupConfig(
      accessToken: 'graph-token',
      folder: 'backups',
      passphrase: passphrase ?? 'backup-secret-123',
    );

    test('uploadBackup sends encrypted file with bearer token', () async {
      final tmp = Directory.systemTemp.createTempSync('od-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final export = File('${tmp.path}/simichat-export-1.tar.gz')
        ..writeAsBytesSync([1, 2, 3]);

      final service = OneDriveBackupService(apiBaseUrl: restBase);
      await service.uploadBackup(exportFile: export, config: config());

      expect(lastAuth, 'Bearer graph-token');
      expect(stored['simichat-export-1.tar.gz'], isNotNull);
      final encryptedText = utf8.decode(stored['simichat-export-1.tar.gz']!);
      expect(encryptedText, startsWith('simichat-backup-v1:'));
    });

    test('listBackups filters tar.gz files', () async {
      final service = OneDriveBackupService(apiBaseUrl: restBase);
      final entries = await service.listBackups(config());
      expect(entries.map((e) => e.name), containsAll(['a.tar.gz', 'b.tar.gz']));
      expect(entries.any((e) => e.name == 'folder'), isFalse);
    });

    test('downloadBackup round-trips bytes', () async {
      final tmp = Directory.systemTemp.createTempSync('od-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final export = File('${tmp.path}/simichat-export-1.tar.gz')
        ..writeAsBytesSync([10, 20, 30]);

      final service = OneDriveBackupService(apiBaseUrl: restBase);
      await service.uploadBackup(exportFile: export, config: config());
      final restored = await service.downloadBackup(
        name: 'simichat-export-1.tar.gz',
        config: config(),
        downloadDirectory: Directory('${tmp.path}/restored'),
      );
      expect(restored.readAsBytesSync(), [10, 20, 30]);
    });

    test('rejects short passphrase', () async {
      final service = OneDriveBackupService(apiBaseUrl: restBase);
      await expectLater(
        service.listBackups(config('short')),
        throwsA(
          isA<OneDriveBackupException>().having(
            (e) => e.message,
            'message',
            contains('至少 8 位'),
          ),
        ),
      );
    });
  });
}
