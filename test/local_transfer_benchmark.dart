import 'dart:io';

import 'package:ai_chat_app/core/archive/local_transfer_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local transfer benchmark', () async {
    const byteCount = int.fromEnvironment(
      'SIMICHAT_TRANSFER_BENCH_BYTES',
      defaultValue: 1024 * 1024,
    );
    final tempDir = await Directory.systemTemp.createTemp(
      'simichat_transfer_bench_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final file = File('${tempDir.path}/simichat-export-20260627-010203.tar.gz');
    await file.writeAsBytes(
      List<int>.generate(byteCount, (index) => index % 251),
      flush: true,
    );

    final session =
        await const LocalDataTransferServer(
          tokenGenerator: _fixedToken,
        ).startExportTransfer(
          exportFile: file,
          address: InternetAddress.loopbackIPv4,
        );
    addTearDown(session.close);

    final watch = Stopwatch()..start();
    final downloaded = await _download(session.loopbackDownloadUri);
    watch.stop();
    await session.closed.timeout(const Duration(seconds: 2));

    stdout.writeln(
      [
        'local_transfer_benchmark',
        'bytes=$byteCount',
        'download_ms=${watch.elapsedMilliseconds}',
        'downloaded_bytes=${downloaded.length}',
      ].join(' '),
    );

    expect(downloaded.length, byteCount);
    expect(session.completedDownloads, 1);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

String _fixedToken() => 'bench-token';

Future<List<int>> _download(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    return await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
  } finally {
    client.close(force: true);
  }
}
