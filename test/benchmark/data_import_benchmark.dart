import 'dart:io';

import 'package:ai_chat_app/core/archive/data_export_service.dart';
import 'package:ai_chat_app/core/archive/data_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('local data import benchmark', () async {
    SharedPreferences.setMockInitialValues({});
    const fileCount = int.fromEnvironment(
      'SIMICHAT_IMPORT_BENCH_FILES',
      defaultValue: 200,
    );
    final sourceDir = await Directory.systemTemp.createTemp(
      'simichat_import_bench_src_',
    );
    final targetDir = await Directory.systemTemp.createTemp(
      'simichat_import_bench_dst_',
    );
    addTearDown(() async {
      for (final dir in [sourceDir, targetDir]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    for (var i = 0; i < fileCount; i++) {
      final file = File('${sourceDir.path}/conversations/session-$i.md');
      await file.create(recursive: true);
      await file.writeAsString(
        '# 会话 $i\n\n移动端优先，本地记忆，Dreaming 夜间整理，数据导入恢复。\n' * 8,
      );
    }

    final export = await DataExportService(
      rootDirectory: sourceDir,
      now: () => DateTime.utc(2026, 6, 27),
    ).exportLocalData();
    final service = DataImportService(rootDirectory: targetDir);

    final previewWatch = Stopwatch()..start();
    final preview = await service.previewExport(export.file);
    previewWatch.stop();

    final importWatch = Stopwatch()..start();
    final result = await service.importExport(export.file);
    importWatch.stop();

    stdout.writeln(
      [
        'data_import_benchmark',
        'files=$fileCount',
        'preview_ms=${previewWatch.elapsedMilliseconds}',
        'import_ms=${importWatch.elapsedMilliseconds}',
        'preview_files=${preview.importableFileCount}',
        'imported_files=${result.importedFiles}',
        'imported_bytes=${result.totalBytes}',
      ].join(' '),
    );

    expect(preview.importableFileCount, fileCount);
    expect(result.importedFiles, fileCount);
    expect(
      await File('${targetDir.path}/conversations/session-0.md').exists(),
      isTrue,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
