import 'dart:io';

import 'package:ai_chat_app/core/archive/obsidian_vault_export_service.dart';
import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObsidianVaultExportService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_obsidian_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test(
      'exports conversations and audio transcripts as an Obsidian vault',
      () async {
        await File('${tempDir.path}/conversations/s1.md')
            .create(recursive: true)
            .then((file) => file.writeAsString('# 会话一\n\n正文'));
        await File(
          '${tempDir.path}/conversations/nested/s2.md',
        ).create(recursive: true).then((file) => file.writeAsString('# 会话二'));
        await File('${tempDir.path}/audio_transcripts/m1/a1.md')
            .create(recursive: true)
            .then((file) => file.writeAsString('# 转写\n\n文本'));
        await File('${tempDir.path}/audio_transcripts/m1/raw.txt')
            .create(recursive: true)
            .then((file) => file.writeAsString('不应进入 vault'));
        await File('${tempDir.path}/exports/old.md')
            .create(recursive: true)
            .then((file) => file.writeAsString('旧导出不应进入 vault'));

        final result = await ObsidianVaultExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27, 1, 2, 3),
        ).exportVault();

        expect(
          result.directory.path,
          endsWith('obsidian-vault-20260627-010203'),
        );
        expect(result.conversationCount, 2);
        expect(result.audioTranscriptCount, 1);
        expect(result.fileCount, 6);
        expect(result.totalBytes, greaterThan(0));

        expect(
          File(
            '${result.directory.path}/Conversations/s1.md',
          ).readAsStringSync(),
          contains('正文'),
        );
        expect(
          File(
            '${result.directory.path}/Conversations/nested/s2.md',
          ).existsSync(),
          isTrue,
        );
        expect(
          File(
            '${result.directory.path}/Audio Transcripts/m1/a1.md',
          ).readAsStringSync(),
          contains('文本'),
        );
        expect(
          File(
            '${result.directory.path}/Audio Transcripts/m1/raw.txt',
          ).existsSync(),
          isFalse,
        );
        expect(
          File('${result.directory.path}/exports/old.md').existsSync(),
          isFalse,
        );

        final readme = File(
          '${result.directory.path}/README.md',
        ).readAsStringSync();
        expect(readme, contains(kObsidianVaultExportFormat));
        expect(readme, contains('[[SimiChat-Index]]'));

        final index = File(
          '${result.directory.path}/SimiChat-Index.md',
        ).readAsStringSync();
        expect(index, contains('[[Conversations/s1|s1]]'));
        expect(index, contains('[[Conversations/nested/s2|s2]]'));
        expect(index, contains('[[Audio Transcripts/m1/a1|a1]]'));
        expect(index, contains('contains_api_keys: `false`'));
        expect(index, isNot(contains(tempDir.path)));

        final manifest = File(
          '${result.directory.path}/SimiChat-Manifest.md',
        ).readAsStringSync();
        expect(manifest, contains('| `Conversations/s1.md` |'));
        expect(manifest, contains('contains_absolute_paths: `false`'));
        expect(manifest, isNot(contains(tempDir.path)));
      },
    );

    test('creates an auditable empty vault without absolute paths', () async {
      final result = await ObsidianVaultExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27),
      ).exportVault();

      expect(result.conversationCount, 0);
      expect(result.audioTranscriptCount, 0);
      expect(result.fileCount, 3);
      final index = File(
        '${result.directory.path}/SimiChat-Index.md',
      ).readAsStringSync();
      expect(index, contains('_暂无会话 Markdown。_'));
      expect(index, contains('_暂无语音转写 Markdown。_'));
      expect(index, isNot(contains(tempDir.path)));
    });

    test('keeps transcript failure status sanitized in Obsidian export', () async {
      await AudioTranscriptArchive(rootDirectory: tempDir).writeFailure(
        messageId: 'message:fail',
        attachmentId: 'attachment:fail',
        fileName: 'voice.m4a',
        fileSize: 2048,
        error:
            'STT failed sk-secret-token at /Users/sanbo/audio/voice.m4a https://example.com/stt?token=raw',
        createdAt: DateTime.utc(2026, 6, 27, 1, 2, 3),
      );

      final result = await ObsidianVaultExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27, 1, 3, 4),
      ).exportVault();

      final transcript = File(
        '${result.directory.path}/Audio Transcripts/message_fail/attachment_fail.md',
      ).readAsStringSync();
      expect(transcript, contains('- status: `failed`'));
      expect(transcript, contains('[已隐藏密钥]'));
      expect(transcript, contains('[已隐藏路径]'));
      expect(transcript, contains('[已隐藏链接]'));
      expect(transcript, isNot(contains('sk-secret-token')));
      expect(transcript, isNot(contains('/Users/sanbo')));
      expect(transcript, isNot(contains('token=raw')));
    });

    test(
      'copies non-audio attachments and rewrites conversation markdown links',
      () async {
        await File('${tempDir.path}/conversations/s1.md')
            .create(recursive: true)
            .then(
              (file) => file.writeAsString(
                '# 会话一\n\n'
                '<!-- simichat-message-id: m1 -->\n'
                '### 2026-06-27 12:00:00 用户\n\n'
                '- message_id: `m1`\n'
                '- role: `user`\n'
                '- attachments:\n'
                '  - 图 片.png\n'
                '  - voice.m4a\n\n'
                '看图。\n',
              ),
            );
        final image = File('${tempDir.path}/source/图 片.png');
        await image.create(recursive: true);
        await image.writeAsBytes([1, 2, 3, 4]);
        final audio = File('${tempDir.path}/source/voice.m4a');
        await audio.create(recursive: true);
        await audio.writeAsBytes([5, 6, 7]);

        final result = await ObsidianVaultExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27, 5),
          listAttachments: () async => [
            ObsidianExportableAttachment(
              id: 'att/1',
              messageId: 'm1',
              fileType: 'image',
              localPath: image.path,
              fileName: '图 片.png',
              fileSize: 4,
            ),
            ObsidianExportableAttachment(
              id: 'audio/1',
              messageId: 'm1',
              fileType: 'audio',
              localPath: audio.path,
              fileName: 'voice.m4a',
              fileSize: 3,
            ),
          ],
        ).exportVault();

        expect(
          result.entries.where((entry) => entry.kind == 'attachment'),
          hasLength(1),
        );
        final attachmentPath =
            '${result.directory.path}/Attachments/m1/att_1-file.png';
        expect(File(attachmentPath).readAsBytesSync(), [1, 2, 3, 4]);
        expect(
          File(
            '${result.directory.path}/Attachments/m1/audio_1-voice.m4a',
          ).existsSync(),
          isFalse,
        );

        final conversation = File(
          '${result.directory.path}/Conversations/s1.md',
        ).readAsStringSync();
        expect(
          conversation,
          contains('[[Attachments/m1/att_1-file.png|图 片.png]]'),
        );
        expect(conversation, contains('  - voice.m4a'));
        expect(conversation, isNot(contains(tempDir.path)));

        final index = File(
          '${result.directory.path}/SimiChat-Index.md',
        ).readAsStringSync();
        expect(index, contains('attachments: `1`'));
        expect(
          index,
          contains('[[Attachments/m1/att_1-file.png|att_1-file.png]]'),
        );
      },
    );

    test('rewrites same-name attachment links in message order', () async {
      await File('${tempDir.path}/conversations/s1.md')
          .create(recursive: true)
          .then(
            (file) => file.writeAsString(
              '# 会话一\n\n'
              '<!-- simichat-message-id: m1 -->\n'
              '- attachments:\n'
              '  - duplicate.png\n'
              '  - duplicate.png\n\n',
            ),
          );
      final first = File('${tempDir.path}/source/first.png');
      await first.create(recursive: true);
      await first.writeAsBytes([1, 1, 1]);
      final second = File('${tempDir.path}/source/second.png');
      await second.create(recursive: true);
      await second.writeAsBytes([2, 2, 2]);

      final result = await ObsidianVaultExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27, 5, 15),
        listAttachments: () async => [
          ObsidianExportableAttachment(
            id: 'att/1',
            messageId: 'm1',
            fileType: 'image',
            localPath: first.path,
            fileName: 'duplicate.png',
            fileSize: 3,
          ),
          ObsidianExportableAttachment(
            id: 'att/2',
            messageId: 'm1',
            fileType: 'image',
            localPath: second.path,
            fileName: 'duplicate.png',
            fileSize: 3,
          ),
        ],
      ).exportVault();

      expect(
        File(
          '${result.directory.path}/Attachments/m1/att_1-duplicate.png',
        ).readAsBytesSync(),
        [1, 1, 1],
      );
      expect(
        File(
          '${result.directory.path}/Attachments/m1/att_2-duplicate.png',
        ).readAsBytesSync(),
        [2, 2, 2],
      );

      final conversation = File(
        '${result.directory.path}/Conversations/s1.md',
      ).readAsStringSync();
      expect(
        conversation,
        contains(
          '  - [[Attachments/m1/att_1-duplicate.png|duplicate.png]]\n'
          '  - [[Attachments/m1/att_2-duplicate.png|duplicate.png]]',
        ),
      );
      expect(conversation, isNot(contains(tempDir.path)));
    });

    test('can include audio attachments when explicitly requested', () async {
      await File('${tempDir.path}/conversations/s1.md')
          .create(recursive: true)
          .then(
            (file) => file.writeAsString(
              '# 会话一\n\n'
              '<!-- simichat-message-id: m1 -->\n'
              '- attachments:\n'
              '  - voice.m4a\n\n',
            ),
          );
      final audio = File('${tempDir.path}/source/voice.m4a');
      await audio.create(recursive: true);
      await audio.writeAsBytes([9, 8, 7]);

      final result = await ObsidianVaultExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27, 5, 30),
        listAttachments: () async => [
          ObsidianExportableAttachment(
            id: 'audio/1',
            messageId: 'm1',
            fileType: 'audio',
            localPath: audio.path,
            fileName: 'voice.m4a',
            fileSize: 3,
          ),
        ],
      ).exportVault(includeAudioAttachments: true);

      expect(
        result.entries.where((entry) => entry.kind == 'attachment'),
        hasLength(1),
      );
      final audioPath =
          '${result.directory.path}/Attachments/m1/audio_1-voice.m4a';
      expect(File(audioPath).readAsBytesSync(), [9, 8, 7]);

      final conversation = File(
        '${result.directory.path}/Conversations/s1.md',
      ).readAsStringSync();
      expect(
        conversation,
        contains('[[Attachments/m1/audio_1-voice.m4a|voice.m4a]]'),
      );
      expect(conversation, isNot(contains(tempDir.path)));

      final manifest = File(
        '${result.directory.path}/SimiChat-Manifest.md',
      ).readAsStringSync();
      expect(manifest, contains('Attachments/m1/audio_1-voice.m4a'));
      expect(manifest, isNot(contains(tempDir.path)));
    });

    test('syncs incrementally into an existing Obsidian vault', () async {
      final conversation = File('${tempDir.path}/conversations/s1.md');
      await conversation.create(recursive: true);
      await conversation.writeAsString('# 会话一\n\n第一版');
      final transcript = File('${tempDir.path}/audio_transcripts/m1/a1.md');
      await transcript.create(recursive: true);
      await transcript.writeAsString('# 转写\n\n第一版');

      final targetVault = Directory('${tempDir.path}/target-vault');
      final service = ObsidianVaultExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27, 2),
      );

      final first = await service.syncToExistingVault(
        targetVaultDirectory: targetVault,
      );

      expect(first.createdCount, 2);
      expect(first.updatedCount, 0);
      expect(first.unchangedCount, 0);
      expect(first.deletedCount, 0);
      expect(first.conflictCount, 0);
      expect(first.conversationCount, 1);
      expect(first.audioTranscriptCount, 1);
      expect(first.fileCount, 6);
      expect(
        File(
          '${targetVault.path}/SimiChat/Conversations/s1.md',
        ).readAsStringSync(),
        contains('第一版'),
      );
      expect(
        File(
          '${targetVault.path}/SimiChat/Audio Transcripts/m1/a1.md',
        ).readAsStringSync(),
        contains('第一版'),
      );
      final firstState = File(
        '${targetVault.path}/SimiChat/SimiChat-Sync-State.json',
      ).readAsStringSync();
      expect(firstState, contains(kObsidianVaultSyncStateFormat));
      expect(firstState, isNot(contains(tempDir.path)));

      await conversation.writeAsString('# 会话一\n\n第二版');
      final second = await service.syncToExistingVault(
        targetVaultDirectory: targetVault,
      );

      expect(second.createdCount, 0);
      expect(second.updatedCount, 1);
      expect(second.unchangedCount, 1);
      expect(second.deletedCount, 0);
      expect(second.conflictCount, 0);
      expect(
        File(
          '${targetVault.path}/SimiChat/Conversations/s1.md',
        ).readAsStringSync(),
        contains('第二版'),
      );
    });

    test('deletes stale synced files when source is removed', () async {
      final conversation = File('${tempDir.path}/conversations/s1.md');
      await conversation.create(recursive: true);
      await conversation.writeAsString('# 会话一\n\n第一版');

      final targetVault = Directory('${tempDir.path}/target-vault');
      final service = ObsidianVaultExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27, 2, 30),
      );
      await service.syncToExistingVault(targetVaultDirectory: targetVault);
      final targetConversation = File(
        '${targetVault.path}/SimiChat/Conversations/s1.md',
      );
      expect(targetConversation.existsSync(), isTrue);

      await conversation.delete();
      final result = await service.syncToExistingVault(
        targetVaultDirectory: targetVault,
      );

      expect(result.createdCount, 0);
      expect(result.updatedCount, 0);
      expect(result.unchangedCount, 0);
      expect(result.deletedCount, 1);
      expect(result.conflictCount, 0);
      expect(targetConversation.existsSync(), isFalse);

      final index = File(
        '${targetVault.path}/SimiChat/SimiChat-Index.md',
      ).readAsStringSync();
      expect(index, contains('sync_deleted: `1`'));
      expect(index, isNot(contains('Conversations/s1.md')));

      final state = File(
        '${targetVault.path}/SimiChat/SimiChat-Sync-State.json',
      ).readAsStringSync();
      expect(state, contains('"deleted_count": 1'));
      expect(state, isNot(contains('Conversations/s1.md')));
      expect(state, isNot(contains(tempDir.path)));
    });

    test(
      'does not delete stale files that were modified in target vault',
      () async {
        final conversation = File('${tempDir.path}/conversations/s1.md');
        await conversation.create(recursive: true);
        await conversation.writeAsString('# 会话一\n\n第一版');

        final targetVault = Directory('${tempDir.path}/target-vault');
        final service = ObsidianVaultExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27, 2, 45),
        );
        await service.syncToExistingVault(targetVaultDirectory: targetVault);

        final targetConversation = File(
          '${targetVault.path}/SimiChat/Conversations/s1.md',
        );
        await targetConversation.writeAsString('# 用户保留\n\n不要删除');
        await conversation.delete();

        final result = await service.syncToExistingVault(
          targetVaultDirectory: targetVault,
        );

        expect(result.deletedCount, 0);
        expect(result.conflictCount, 1);
        expect(result.conflicts.single.path, 'Conversations/s1.md');
        expect(
          result.conflicts.single.reason,
          'source_removed_target_modified',
        );
        expect(targetConversation.readAsStringSync(), contains('不要删除'));

        final state = File(
          '${targetVault.path}/SimiChat/SimiChat-Sync-State.json',
        ).readAsStringSync();
        expect(state, contains('"reason": "source_removed_target_modified"'));
        expect(state, isNot(contains(tempDir.path)));
      },
    );

    test('detects target edits and does not overwrite conflicts', () async {
      final conversation = File('${tempDir.path}/conversations/s1.md');
      await conversation.create(recursive: true);
      await conversation.writeAsString('# 会话一\n\n第一版');

      final targetVault = Directory('${tempDir.path}/target-vault');
      final service = ObsidianVaultExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27, 3),
      );
      await service.syncToExistingVault(targetVaultDirectory: targetVault);

      final targetConversation = File(
        '${targetVault.path}/SimiChat/Conversations/s1.md',
      );
      await targetConversation.writeAsString('# 用户修改\n\n不要覆盖');
      await conversation.writeAsString('# 会话一\n\n第二版');

      final result = await service.syncToExistingVault(
        targetVaultDirectory: targetVault,
      );

      expect(result.createdCount, 0);
      expect(result.updatedCount, 0);
      expect(result.unchangedCount, 0);
      expect(result.conflictCount, 1);
      expect(result.conflicts.single.path, 'Conversations/s1.md');
      expect(result.conflicts.single.reason, 'target_modified');
      expect(targetConversation.readAsStringSync(), contains('不要覆盖'));

      final index = File(
        '${targetVault.path}/SimiChat/SimiChat-Index.md',
      ).readAsStringSync();
      expect(index, contains('sync_conflicts: `1`'));
      expect(index, isNot(contains(tempDir.path)));
    });

    test('can overwrite target edits only when explicitly requested', () async {
      final conversation = File('${tempDir.path}/conversations/s1.md');
      await conversation.create(recursive: true);
      await conversation.writeAsString('# 会话一\n\n第一版');

      final targetVault = Directory('${tempDir.path}/target-vault');
      final service = ObsidianVaultExportService(
        rootDirectory: tempDir,
        now: () => DateTime.utc(2026, 6, 27, 3, 30),
      );
      await service.syncToExistingVault(targetVaultDirectory: targetVault);

      final targetConversation = File(
        '${targetVault.path}/SimiChat/Conversations/s1.md',
      );
      await targetConversation.writeAsString('# 用户修改\n\n允许覆盖前的内容');
      await conversation.writeAsString('# 会话一\n\n第二版');

      final result = await service.syncToExistingVault(
        targetVaultDirectory: targetVault,
        overwriteConflicts: true,
      );

      expect(result.createdCount, 0);
      expect(result.updatedCount, 1);
      expect(result.conflictCount, 0);
      expect(targetConversation.readAsStringSync(), contains('第二版'));
      expect(
        targetConversation.readAsStringSync(),
        isNot(contains('允许覆盖前的内容')),
      );
      final state = File(
        '${targetVault.path}/SimiChat/SimiChat-Sync-State.json',
      ).readAsStringSync();
      expect(state, contains('Conversations/s1.md'));
      expect(state, isNot(contains(tempDir.path)));
    });

    test(
      'does not write through unsafe existing symlinks during sync',
      () async {
        final conversation = File('${tempDir.path}/conversations/s1.md');
        await conversation.create(recursive: true);
        await conversation.writeAsString('# 会话一\n\n正文');

        final targetVault = Directory('${tempDir.path}/target-vault');
        final unsafeTarget = Link(
          '${targetVault.path}/SimiChat/Conversations/s1.md',
        );
        await unsafeTarget.parent.create(recursive: true);
        final outside = File('${tempDir.path}/outside.md');
        await outside.writeAsString('外部文件');
        await unsafeTarget.create(outside.path);

        final result = await ObsidianVaultExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27, 4),
        ).syncToExistingVault(targetVaultDirectory: targetVault);

        expect(result.createdCount, 0);
        expect(result.conflictCount, 1);
        expect(result.conflicts.single.reason, 'unsafe_existing_entity');
        expect(outside.readAsStringSync(), '外部文件');
      },
    );

    test('rejects sync targets inside SimiChat source archives', () async {
      final conversation = File('${tempDir.path}/conversations/s1.md');
      await conversation.create(recursive: true);
      await conversation.writeAsString('# 会话一');

      await expectLater(
        ObsidianVaultExportService(
          rootDirectory: tempDir,
          now: () => DateTime.utc(2026, 6, 27),
        ).syncToExistingVault(
          targetVaultDirectory: Directory(
            '${tempDir.path}/conversations/vault',
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
