import 'dart:convert';

import 'package:ai_chat_app/core/media/pasted_text_attachment_service.dart';
import 'package:ai_chat_app/shared/providers/chat_composer_draft_store.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'persists a session draft without storing large pasted-text content',
    () async {
      final createdAt = DateTime.utc(2026, 8, 19, 8, 30);
      final store = ChatComposerDraftStore(now: () => createdAt);
      final attachment = PendingAttachment(
        id: 'pasted-1',
        path: '/private/composer_drafts/pasted-content.md',
        name: 'pasted-content.md',
        type: 'document',
        fileSize: 4096,
        pastedText: PastedTextAttachment(
          id: 'pasted-1',
          conversationId: 'session-a',
          draftId: 'draft-a',
          localPath: '/private/composer_drafts/pasted-content.md',
          displayName: 'pasted-content.md',
          mimeType: 'text/markdown; charset=utf-8',
          source: PastedTextAttachmentSource.largePaste,
          characterCount: 2000,
          utf8ByteCount: 4096,
          estimatedTokens: 1000,
          sha256: 'a' * 64,
          createdAt: createdAt,
        ),
      );

      await store.save(
        'session-a',
        ChatComposerDraft(
          text: '下次继续优化多模态工具',
          attachments: [attachment],
          deepThink: true,
        ),
      );
      await store.flush();

      final raw = SharedPreferences.getInstance().then(
        (preferences) => preferences.getString(kChatComposerDraftStorageKey),
      );
      final encoded = await raw;
      expect(encoded, isNotNull);
      expect(encoded, contains('pasted-content.md'));
      expect(encoded, isNot(contains('不应写入偏好设置的大粘贴原文')));

      final restored = await ChatComposerDraftStore().read('session-a');
      expect(restored, isNotNull);
      expect(restored!.text, '下次继续优化多模态工具');
      expect(restored.deepThink, isTrue);
      expect(restored.attachments, hasLength(1));
      final restoredAttachment = restored.attachments.single;
      expect(restoredAttachment.path, attachment.path);
      expect(restoredAttachment.name, attachment.name);
      expect(restoredAttachment.pastedText, isNotNull);
      expect(restoredAttachment.pastedText!.id, 'pasted-1');
      expect(restoredAttachment.pastedText!.localPath, attachment.path);
      expect(restoredAttachment.pastedText!.displayName, attachment.name);
      expect(restoredAttachment.pastedText!.sha256, 'a' * 64);
    },
  );

  test('serializes successive updates and keeps sessions isolated', () async {
    var clock = DateTime.utc(2026, 8, 19, 9);
    final store = ChatComposerDraftStore(now: () => clock);

    final first = store.save(
      'session-a',
      const ChatComposerDraft(text: '旧版本', deepThink: false),
    );
    clock = clock.add(const Duration(seconds: 1));
    final second = store.save(
      'session-a',
      const ChatComposerDraft(text: '最新版本', deepThink: true),
    );
    clock = clock.add(const Duration(seconds: 1));
    final third = store.save(
      'session-b',
      const ChatComposerDraft(text: 'B 会话草稿'),
    );
    await Future.wait([first, second, third]);

    final reloaded = ChatComposerDraftStore();
    expect((await reloaded.read('session-a'))?.text, '最新版本');
    expect((await reloaded.read('session-a'))?.deepThink, isTrue);
    expect((await reloaded.read('session-b'))?.text, 'B 会话草稿');
  });

  test('removes drafts and evicts the least recently saved entries', () async {
    var clock = DateTime.utc(2026, 8, 19, 10);
    final store = ChatComposerDraftStore(now: () => clock, maxEntries: 2);

    await store.save('oldest', const ChatComposerDraft(text: '一'));
    clock = clock.add(const Duration(seconds: 1));
    await store.save('middle', const ChatComposerDraft(text: '二'));
    clock = clock.add(const Duration(seconds: 1));
    await store.save('latest', const ChatComposerDraft(text: '三'));

    final reloaded = ChatComposerDraftStore(maxEntries: 2);
    expect(await reloaded.read('oldest'), isNull);
    expect((await reloaded.read('middle'))?.text, '二');
    expect((await reloaded.read('latest'))?.text, '三');

    await reloaded.remove('middle');
    expect(await ChatComposerDraftStore().read('middle'), isNull);
    expect((await ChatComposerDraftStore().read('latest'))?.text, '三');
  });

  test(
    'ignores malformed persisted entries without blocking valid recovery',
    () async {
      final createdAt = DateTime.utc(2026, 8, 19, 11);
      SharedPreferences.setMockInitialValues({
        kChatComposerDraftStorageKey: jsonEncode({
          'version': 1,
          'drafts': [
            {'session_id': 42, 'draft': 'not a map'},
            {
              'session_id': 'valid-session',
              'updated_at': createdAt.toIso8601String(),
              'draft': {
                'text': '可以恢复',
                'deep_think': true,
                'attachments': [
                  {'path': '', 'name': 'bad', 'type': 'image'},
                ],
              },
            },
          ],
        }),
      });

      final restored = await ChatComposerDraftStore().read('valid-session');
      expect(restored, isNotNull);
      expect(restored!.text, '可以恢复');
      expect(restored.deepThink, isTrue);
      expect(restored.attachments, isEmpty);
      expect(await ChatComposerDraftStore().read('missing'), isNull);
    },
  );
}
