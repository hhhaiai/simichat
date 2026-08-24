import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/media/attachment_export_service.dart';
import 'package:ai_chat_app/core/media/large_paste_policy.dart';
import 'package:ai_chat_app/core/media/pasted_text_attachment_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late PastedTextAttachmentService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('simichat-pasted-text-test-');
    service = PastedTextAttachmentService(
      archive: AttachmentDraftArchive(rootDirectory: root),
      clock: () => DateTime(2026, 8, 19, 14, 58),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'stores original UTF-8 text in the private composer draft archive',
    () async {
      const source = '# 标题\r\n\r\n🙂\t```dart\r\nprint("保真");\r\n```\r\n';
      final attachment = await service.create(
        conversationId: 'conversation-1',
        draftId: 'draft-1',
        text: source,
        decision: const LargePastePolicy(
          characterThreshold: 1,
        ).evaluate(source),
      );

      expect(attachment.source, PastedTextAttachmentSource.largePaste);
      expect(attachment.mimeType, 'text/markdown; charset=utf-8');
      expect(attachment.displayName, 'pasted-content-20260819-145800.md');
      expect(attachment.characterCount, source.length);
      expect(attachment.utf8ByteCount, utf8.encode(source).length);
      expect(attachment.estimatedTokens, greaterThan(0));
      expect(attachment.sha256, sha256.convert(utf8.encode(source)).toString());
      expect(await File(attachment.localPath).readAsString(), source);
      expect(attachment.localPath, contains('composer_drafts'));
    },
  );

  test(
    'uses .txt for normal text and prevents same-second display-name collisions',
    () async {
      const source = '普通文本\n保留末尾\n';
      final first = await service.create(
        conversationId: 'conversation-1',
        draftId: 'draft-1',
        text: source,
        decision: const LargePastePolicy(
          characterThreshold: 1,
        ).evaluate(source),
      );
      final second = await service.create(
        conversationId: 'conversation-1',
        draftId: 'draft-1',
        text: source,
        decision: const LargePastePolicy(
          characterThreshold: 1,
        ).evaluate(source),
      );

      expect(first.displayName, 'pasted-content-20260819-145800.txt');
      expect(second.displayName, 'pasted-content-20260819-145800-2.txt');
      expect(first.localPath, isNot(second.localPath));
    },
  );

  test(
    'rename updates the display name without changing bytes and delete clears private file',
    () async {
      const source = 'hello\n';
      final created = await service.create(
        conversationId: 'conversation-1',
        draftId: 'draft-1',
        text: source,
        decision: const LargePastePolicy(
          characterThreshold: 1,
        ).evaluate(source),
      );

      final renamed = await service.rename(created, '用户笔记.md');

      expect(renamed.displayName, '用户笔记.md');
      expect(await File(renamed.localPath).readAsString(), source);
      expect(await File(created.localPath).exists(), isFalse);
      await service.delete(renamed);
      expect(await File(renamed.localPath).exists(), isFalse);
    },
  );
}
