import 'dart:io';

import 'package:ai_chat_app/core/archive/conversation_archive_service.dart';
import 'package:ai_chat_app/core/archive/markdown_conversation_archive.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConversationArchiveService', () {
    late Directory tempDir;
    late AppDatabase db;
    late ConversationArchiveService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'simichat_archive_service_',
      );
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = ConversationArchiveService(
        archive: MarkdownConversationArchive(rootDirectory: tempDir),
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
        attachmentDao: db.attachmentDao,
      );
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('rebuilds archive from SQLite messages and attachments', () async {
      await db.sessionDao.createSession(id: 's1');
      await db.sessionDao.updateTitle('s1', '数据库标题');
      await db.messageDao.insertMessage(
        id: 'm1',
        sessionId: 's1',
        role: 'user',
        content: '带附件的消息',
      );
      await db.attachmentDao.insertAttachment(
        id: 'a1',
        messageId: 'm1',
        fileType: 'image',
        localPath: '/tmp/photo.png',
        fileName: 'photo.png',
        fileSize: 12,
      );
      await db.messageDao.insertMessage(
        id: 'm2',
        sessionId: 's1',
        role: 'assistant',
        content: '回复',
        thinkingContent: '思考',
        channelModelId: null,
      );

      final file = await service.rebuildSession('s1');
      expect(file, isNotNull);
      final markdown = await file!.readAsString();
      expect(markdown, contains('# 数据库标题'));
      expect(markdown, contains('<!-- simichat-message-id: m1 -->'));
      expect(markdown, contains('photo.png'));
      expect(markdown, contains('<!-- simichat-message-id: m2 -->'));
      expect(markdown, contains('思考'));

      final report = await service.checkConsistency('s1');
      expect(report.isConsistent, true);
    });

    test('detects missing and extra markdown message ids', () async {
      await db.sessionDao.createSession(id: 's2');
      await db.messageDao.insertMessage(
        id: 'db-message',
        sessionId: 's2',
        role: 'user',
        content: '数据库消息',
      );
      await service.archive.rebuildSession(
        sessionId: 's2',
        sessionTitle: '不一致会话',
        messages: [
          ArchivedMessage(
            id: 'extra-message',
            sessionId: 's2',
            role: 'assistant',
            content: '只在 Markdown 中',
            createdAt: DateTime(2026, 6, 27),
          ),
        ],
      );

      final report = await service.checkConsistency('s2');
      expect(report.isConsistent, false);
      expect(report.missingMessageIds, ['db-message']);
      expect(report.extraMessageIds, ['extra-message']);
    });

    test('syncs title without rebuilding message body', () async {
      await db.sessionDao.createSession(id: 's3');
      await db.sessionDao.updateTitle('s3', '旧标题');
      await db.messageDao.insertMessage(
        id: 'm1',
        sessionId: 's3',
        role: 'user',
        content: '正文保留',
      );
      final file = await service.rebuildSession('s3');

      await db.sessionDao.updateTitle('s3', '新标题');
      await service.syncTitle('s3');

      final markdown = await file!.readAsString();
      expect(markdown, startsWith('# 新标题'));
      expect(markdown, contains('正文保留'));
    });
  });
}
