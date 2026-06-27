import 'dart:io';

import 'package:ai_chat_app/core/archive/obsidian_vault_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Obsidian vault sync benchmark', () async {
    const fileCount = int.fromEnvironment(
      'SIMICHAT_OBSIDIAN_SYNC_BENCH_FILES',
      defaultValue: 200,
    );
    final tempDir = await Directory.systemTemp.createTemp(
      'simichat_obsidian_sync_bench_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final attachments = <ObsidianExportableAttachment>[];
    for (var i = 0; i < fileCount; i++) {
      final messageId = 'message-$i';
      final attachmentId = 'attachment-$i';
      final attachmentName = 'image-$i.png';
      final file = File('${tempDir.path}/conversations/session-$i.md');
      await file.create(recursive: true);
      await file.writeAsString(
        '# 会话 $i\n\n'
        '<!-- simichat-message-id: $messageId -->\n'
        '### 2026-06-27 12:00:00 用户\n\n'
        '- message_id: `$messageId`\n'
        '- role: `user`\n'
        '- attachments:\n'
        '  - $attachmentName\n\n'
        '${'移动端优先，本地记忆，Dreaming 夜间整理，Obsidian 增量同步。\n' * 8}',
      );
      final attachmentFile = File('${tempDir.path}/source/$attachmentName');
      await attachmentFile.create(recursive: true);
      await attachmentFile.writeAsBytes(List<int>.filled(256, i % 251));
      attachments.add(
        ObsidianExportableAttachment(
          id: attachmentId,
          messageId: messageId,
          fileType: 'image',
          localPath: attachmentFile.path,
          fileName: attachmentName,
          fileSize: 256,
        ),
      );
    }

    final targetVault = Directory('${tempDir.path}/existing-vault');
    final service = ObsidianVaultExportService(
      rootDirectory: tempDir,
      now: () => DateTime.utc(2026, 6, 27),
      listAttachments: () async => attachments,
    );

    final firstWatch = Stopwatch()..start();
    final first = await service.syncToExistingVault(
      targetVaultDirectory: targetVault,
    );
    firstWatch.stop();

    final secondWatch = Stopwatch()..start();
    final second = await service.syncToExistingVault(
      targetVaultDirectory: targetVault,
    );
    secondWatch.stop();

    stdout.writeln(
      [
        'obsidian_vault_sync_benchmark',
        'files=$fileCount',
        'attachments=${attachments.length}',
        'first_sync_ms=${firstWatch.elapsedMilliseconds}',
        'second_sync_ms=${secondWatch.elapsedMilliseconds}',
        'created=${first.createdCount}',
        'unchanged=${second.unchangedCount}',
        'conflicts=${second.conflictCount}',
        'vault_files=${second.fileCount}',
        'bytes=${second.totalBytes}',
      ].join(' '),
    );

    expect(first.createdCount, fileCount * 2);
    expect(first.conflictCount, 0);
    expect(second.createdCount, 0);
    expect(second.unchangedCount, fileCount * 2);
    expect(second.conflictCount, 0);
    expect(second.fileCount, fileCount * 2 + 4);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
