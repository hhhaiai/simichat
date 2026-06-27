import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/archive/local_transfer_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalDataTransferServer', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_transfer_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('serves a SimiChat export once with token and safe headers', () async {
      final file = await _writeExportFile(tempDir, [1, 2, 3, 4, 5]);
      final session =
          await const LocalDataTransferServer(
            tokenGenerator: _fixedToken,
          ).startExportTransfer(
            exportFile: file,
            address: InternetAddress.loopbackIPv4,
          );
      addTearDown(session.close);

      expect(
        session.loopbackDownloadUri.toString(),
        contains('token=fixed-token'),
      );
      expect(
        session.loopbackDownloadUri.toString(),
        isNot(contains(tempDir.path)),
      );

      final response = await _get(session.loopbackDownloadUri);
      final body = response.bodyBytes;

      expect(response.statusCode, HttpStatus.ok);
      expect(
        response.headers.value(HttpHeaders.contentTypeHeader),
        'application/gzip',
      );
      expect(
        response.headers.value(HttpHeaders.cacheControlHeader),
        'no-store',
      );
      expect(response.headers.value('x-content-type-options'), 'nosniff');
      expect(
        response.headers.value(HttpHeaders.contentDisposition),
        'attachment; filename="simichat-export-20260627-010203.tar.gz"',
      );
      expect(body, [1, 2, 3, 4, 5]);
      await session.closed.timeout(const Duration(seconds: 2));
      expect(session.completedDownloads, 1);
      expect(session.isClosed, isTrue);
    });

    test(
      'rejects wrong token without consuming the one-time download',
      () async {
        final file = await _writeExportFile(tempDir, utf8.encode('backup'));
        final session =
            await const LocalDataTransferServer(
              tokenGenerator: _fixedToken,
            ).startExportTransfer(
              exportFile: file,
              address: InternetAddress.loopbackIPv4,
            );
        addTearDown(session.close);

        final wrongToken = session
            .downloadUriForHost('127.0.0.1')
            .replace(queryParameters: {'token': 'wrong'});
        final rejected = await _get(wrongToken);
        expect(rejected.statusCode, HttpStatus.forbidden);
        expect(rejected.bodyText, isNot(contains(file.path)));
        expect(session.completedDownloads, 0);
        expect(session.isClosed, isFalse);

        final accepted = await _get(session.loopbackDownloadUri);
        expect(accepted.statusCode, HttpStatus.ok);
        expect(accepted.bodyBytes, utf8.encode('backup'));
      },
    );

    test('expires token and closes transfer session', () async {
      var now = DateTime.utc(2026, 6, 27, 1, 2, 3);
      final file = await _writeExportFile(tempDir, [9]);
      final session =
          await LocalDataTransferServer(
            now: () => now,
            tokenGenerator: _fixedToken,
          ).startExportTransfer(
            exportFile: file,
            address: InternetAddress.loopbackIPv4,
            ttl: const Duration(seconds: 1),
          );
      addTearDown(session.close);

      now = now.add(const Duration(seconds: 2));
      final response = await _get(session.loopbackDownloadUri);
      expect(response.statusCode, HttpStatus.gone);
      expect(response.bodyText, contains('过期'));
      await session.closed.timeout(const Duration(seconds: 2));
      expect(session.completedDownloads, 0);
    });

    test('does not expose files for invalid method or path', () async {
      final file = await _writeExportFile(tempDir, utf8.encode('backup'));
      final session =
          await const LocalDataTransferServer(
            tokenGenerator: _fixedToken,
          ).startExportTransfer(
            exportFile: file,
            address: InternetAddress.loopbackIPv4,
          );
      addTearDown(session.close);

      final missing = await _get(
        session.loopbackDownloadUri.replace(path: '/'),
      );
      expect(missing.statusCode, HttpStatus.notFound);
      expect(missing.bodyText, isNot(contains(file.path)));

      final post = await _post(session.loopbackDownloadUri);
      expect(post.statusCode, HttpStatus.methodNotAllowed);
      expect(post.headers.value(HttpHeaders.allowHeader), 'GET');
      expect(post.bodyText, isNot(contains(file.path)));

      final accepted = await _get(session.loopbackDownloadUri);
      expect(accepted.statusCode, HttpStatus.ok);
      expect(accepted.bodyBytes, utf8.encode('backup'));
    });

    test('rejects missing files and non SimiChat archive names', () async {
      await expectLater(
        const LocalDataTransferServer().startExportTransfer(
          exportFile: File('${tempDir.path}/simichat-export-missing.tar.gz'),
          address: InternetAddress.loopbackIPv4,
        ),
        throwsA(isA<LocalDataTransferException>()),
      );

      final notes = File('${tempDir.path}/notes.tar.gz');
      await notes.writeAsBytes([1], flush: true);
      await expectLater(
        const LocalDataTransferServer().startExportTransfer(
          exportFile: notes,
          address: InternetAddress.loopbackIPv4,
        ),
        throwsA(isA<LocalDataTransferException>()),
      );
    });
  });
}

String _fixedToken() => 'fixed-token';

Future<File> _writeExportFile(Directory dir, List<int> bytes) async {
  final file = File('${dir.path}/simichat-export-20260627-010203.tar.gz');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<_BufferedResponse> _get(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    return await _BufferedResponse.from(response);
  } finally {
    client.close(force: true);
  }
}

Future<_BufferedResponse> _post(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    final response = await request.close();
    return await _BufferedResponse.from(response);
  } finally {
    client.close(force: true);
  }
}

class _BufferedResponse {
  const _BufferedResponse({
    required this.statusCode,
    required this.headers,
    required List<int> body,
  }) : _body = body;

  final int statusCode;
  final HttpHeaders headers;
  final List<int> _body;

  List<int> get bodyBytes => List.unmodifiable(_body);
  String get bodyText => utf8.decode(_body);

  static Future<_BufferedResponse> from(HttpClientResponse response) async {
    final body = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    return _BufferedResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: body,
    );
  }
}
