import 'dart:io';

import 'package:ai_chat_app/core/archive/markdown_conversation_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownConversationArchive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_archive_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('sanitizes session id for file names', () {
      expect(
        MarkdownConversationArchive.sanitizeSessionId('session/with spaces'),
        'session_with_spaces',
      );
      expect(
        MarkdownConversationArchive.sanitizeSessionId(''),
        'untitled-session',
      );
    });

    test('appends messages to one markdown file per session', () async {
      final archive = MarkdownConversationArchive(rootDirectory: tempDir);
      await archive.appendMessage(
        sessionId: 'session-1',
        sessionTitle: '测试会话',
        message: ArchivedMessage(
          id: 'm1',
          sessionId: 'session-1',
          role: 'user',
          content: '你好',
          attachmentNames: const ['photo.png'],
          createdAt: DateTime(2026, 6, 27, 8, 30),
        ),
      );
      final file = await archive.appendMessage(
        sessionId: 'session-1',
        sessionTitle: '测试会话',
        message: ArchivedMessage(
          id: 'm2',
          sessionId: 'session-1',
          role: 'assistant',
          content: '你好，我在。',
          thinkingContent: '需要友好回应。',
          channelModelId: 'model-1',
          createdAt: DateTime(2026, 6, 27, 8, 31),
        ),
      );

      expect(file.path.endsWith('conversations/session-1.md'), true);
      final markdown = await file.readAsString();
      expect(markdown, contains('# 测试会话'));
      expect(markdown, contains('session_id: `session-1`'));
      expect(markdown, contains('<!-- simichat-message-id: m1 -->'));
      expect(markdown, contains('### 2026-06-27 08:30:00 用户'));
      expect(markdown, contains('你好'));
      expect(markdown, contains('photo.png'));
      expect(markdown, contains('<!-- simichat-message-id: m2 -->'));
      expect(markdown, contains('channel_model_id: `model-1`'));
      expect(markdown, contains('<summary>思考过程</summary>'));
      expect(markdown, contains('需要友好回应。'));

      await archive.updateSessionTitle(
        sessionId: 'session-1',
        sessionTitle: '新标题',
      );
      final updated = await file.readAsString();
      expect(updated, startsWith('# 新标题'));
      expect(await archive.readArchivedMessageIds('session-1'), ['m1', 'm2']);
    });

    test('rebuilds a session archive deterministically', () async {
      final archive = MarkdownConversationArchive(rootDirectory: tempDir);
      final file = await archive.rebuildSession(
        sessionId: 'session-2',
        sessionTitle: '重建会话',
        messages: [
          ArchivedMessage(
            id: 'm1',
            sessionId: 'session-2',
            role: 'user',
            content: '第一条',
            createdAt: DateTime(2026, 6, 27, 9),
          ),
          ArchivedMessage(
            id: 'm2',
            sessionId: 'session-2',
            role: 'assistant',
            content: '第二条',
            createdAt: DateTime(2026, 6, 27, 9, 1),
          ),
        ],
      );

      final markdown = await file.readAsString();
      expect(markdown.indexOf('第一条') < markdown.indexOf('第二条'), true);
      expect('simichat-message-id'.allMatches(markdown), hasLength(2));
    });
  });
}
