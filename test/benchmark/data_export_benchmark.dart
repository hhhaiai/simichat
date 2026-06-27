import 'dart:io';

import 'package:ai_chat_app/core/archive/data_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('local data export benchmark', () async {
    SharedPreferences.setMockInitialValues({});
    const fileCount = int.fromEnvironment(
      'SIMICHAT_EXPORT_BENCH_FILES',
      defaultValue: 200,
    );
    final tempDir = await Directory.systemTemp.createTemp(
      'simichat_export_bench_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    for (var i = 0; i < fileCount; i++) {
      final file = File('${tempDir.path}/conversations/session-$i.md');
      await file.create(recursive: true);
      await file.writeAsString(
        '# 会话 $i\n\n移动端优先，本地记忆，Dreaming 夜间整理，数据导出。\n' * 8,
      );
    }

    final watch = Stopwatch()..start();
    final result = await DataExportService(
      rootDirectory: tempDir,
      now: () => DateTime.utc(2026, 6, 27),
    ).exportLocalData();
    watch.stop();

    stdout.writeln(
      [
        'data_export_benchmark',
        'files=$fileCount',
        'export_ms=${watch.elapsedMilliseconds}',
        'manifest_files=${result.manifest.fileCount}',
        'uncompressed_bytes=${result.uncompressedBytes}',
        'compressed_bytes=${result.compressedBytes}',
      ].join(' '),
    );

    expect(result.file.existsSync(), isTrue);
    expect(result.manifest.fileCount, fileCount);
    expect(result.compressedBytes, greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
