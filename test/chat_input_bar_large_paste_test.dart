import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:ai_chat_app/core/media/attachment_export_service.dart';
import 'package:ai_chat_app/core/media/large_paste_policy.dart';
import 'package:ai_chat_app/core/media/pasted_text_attachment_service.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImmediatePastedTextAttachmentService
    extends PastedTextAttachmentService {
  _ImmediatePastedTextAttachmentService({required this.root})
    : super(
        archive: AttachmentDraftArchive(rootDirectory: root),
        clock: () => DateTime(2026, 8, 19, 14, 58),
      );

  final Directory root;
  final Map<String, String> _contents = <String, String>{};
  var _nextId = 0;

  @override
  Future<PastedTextAttachment> create({
    required String conversationId,
    required String draftId,
    required String text,
    required LargePasteDecision decision,
  }) {
    final id = 'large-paste-${++_nextId}';
    final extension = inferPastedTextExtension(text);
    final name = 'pasted-content-20260819-145800.$extension';
    final file = File('${root.path}/composer_drafts/$conversationId/$id-$name');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text, encoding: utf8, flush: true);
    _contents[file.path] = text;
    return Future<PastedTextAttachment>.value(
      PastedTextAttachment(
        id: id,
        conversationId: conversationId,
        draftId: draftId,
        localPath: file.path,
        displayName: name,
        mimeType: extension == 'md'
            ? 'text/markdown; charset=utf-8'
            : 'text/plain; charset=utf-8',
        source: PastedTextAttachmentSource.largePaste,
        characterCount: decision.characterCount,
        utf8ByteCount: decision.utf8ByteCount,
        estimatedTokens: decision.estimatedTokens,
        sha256: sha256.convert(utf8.encode(text)).toString(),
        createdAt: DateTime(2026, 8, 19, 14, 58),
      ),
    );
  }

  @override
  Future<String> readText(PastedTextAttachment attachment) =>
      Future<String>.value(_contents[attachment.localPath]);
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('simichat-composer-paste-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('large inserted delta becomes a private text attachment only', (
    tester,
  ) async {
    final controller = TextEditingController(text: '请检查下面的内容：\n');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    final archive = AttachmentDraftArchive(rootDirectory: root);
    final drafts = <ChatComposerDraft>[];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            sessionId: 'conversation-1',
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            draftArchive: archive,
            largePastePolicy: const LargePastePolicy(
              characterThreshold: 16,
              utf8ByteThreshold: 4096,
              estimatedTokenThreshold: 4096,
            ),
            pastedTextAttachmentService: _ImmediatePastedTextAttachmentService(
              root: root,
            ),
            onDraftChanged: drafts.add,
            onSend: (_, _) async => true,
          ),
        ),
      ),
    );

    const pasted = '# 标题\n\n```dart\nprint("🙂");\n```\n';
    controller.value = TextEditingValue(
      text: '请检查下面的内容：\n$pasted',
      selection: const TextSelection.collapsed(
        offset: '请检查下面的内容：\n'.length + pasted.length,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(controller.text, '请检查下面的内容：\n');
    expect(drafts, isNotEmpty);
    final attachment = drafts.last.attachments.single;
    expect(attachment.type, 'document');
    expect(attachment.pastedText, isNotNull);
    expect(attachment.name, 'pasted-content-20260819-145800.md');
    expect(File(attachment.path).readAsStringSync(), pasted);
    expect(
      find.textContaining('~${attachment.pastedText!.estimatedTokens} tokens'),
      findsOneWidget,
    );
    expect(find.byTooltip('大粘贴附件操作'), findsOneWidget);
  });

  testWidgets(
    'small edits remain in the composer and do not create attachments',
    (tester) async {
      final controller = TextEditingController(text: '问题：');
      final focusNode = FocusNode();
      final hasText = ValueNotifier(true);
      final drafts = <ChatComposerDraft>[];
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              sessionId: 'conversation-1',
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              largePastePolicy: const LargePastePolicy(characterThreshold: 16),
              onDraftChanged: drafts.add,
              onSend: (_, _) async => true,
            ),
          ),
        ),
      );

      controller.value = const TextEditingValue(
        text: '问题：短文本',
        selection: TextSelection.collapsed(offset: 6),
      );
      await tester.pump();

      expect(controller.text, '问题：短文本');
      expect(drafts.where((draft) => draft.attachments.isNotEmpty), isEmpty);
    },
  );
}
