import 'dart:io';

import 'package:ai_chat_app/core/archive/obsidian_vault_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Obsidian vault export benchmark',
    () async {
      const fileCount = int.fromEnvironment(
        'SIMICHAT_OBSIDIAN_BENCH_FILES',
        defaultValue: 200,
      );
      final tempDir = await Directory.systemTemp.createTemp(
        'simichat_obsidian_bench_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      for (var i = 0; i < fileCount; i++) {
        final file = File('${tempDir.path}/conversations/session-$i.md');
        await file.create(recursive: true);
        await file.writeAsString(
          '# 会话 $i\n\n移动端优先，本地记忆，Dreaming 夜间整理，Obsidian Vault 导出。\n' * 8,
        );
      }

      final watch = Stopwatch()..start();
      final result = await ObsidianVaultExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27),
      ).exportVault();
      watch.stop();

      stdout.writeln(
        [
          'obsidian_vault_export_benchmark',
          'files=$fileCount',
          'export_ms=${watch.elapsedMilliseconds}',
          'vault_files=${result.fileCount}',
          'conversations=${result.conversationCount}',
          'audio_transcripts=${result.audioTranscriptCount}',
          'bytes=${result.totalBytes}',
        ].join(' '),
      );

      expect(result.directory.existsSync(), isTrue);
      expect(result.conversationCount, fileCount);
      expect(result.fileCount, fileCount + 3);
      expect(result.totalBytes, greaterThan(0));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
