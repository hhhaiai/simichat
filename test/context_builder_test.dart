import 'package:ai_chat_app/core/ai/ai_protocol.dart' as ai;
import 'package:ai_chat_app/core/context/context_builder.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'upToMessageId truncates after the target and binds request-only data',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      const sessionId = 'context-target-session';
      await db.sessionDao.createSession(id: sessionId);
      await db.messageDao.insertMessage(
        id: 'context-user-before',
        sessionId: sessionId,
        role: 'user',
        content: '前一轮问题',
      );
      await db.messageDao.insertMessage(
        id: 'context-assistant-before',
        sessionId: sessionId,
        role: 'assistant',
        content: '前一轮回答',
      );
      await db.messageDao.insertMessage(
        id: 'context-target-user',
        sessionId: sessionId,
        role: 'user',
        content: '请读取文件',
      );
      await db.messageDao.insertMessage(
        id: 'context-old-assistant',
        sessionId: sessionId,
        role: 'assistant',
        content: '被重试的旧回答',
      );
      await db.messageDao.insertMessage(
        id: 'context-following-user',
        sessionId: sessionId,
        role: 'user',
        content: '后续问题',
      );
      await db.messageDao.insertMessage(
        id: 'context-following-assistant',
        sessionId: sessionId,
        role: 'assistant',
        content: '后续回答',
      );

      const extracted = '# notes\n真实文件正文：context-file-body';
      final effectiveContent = fileAwareMessageContent(
        content: '请读取文件',
        extractedContents: const [extracted],
      );
      const targetAttachment = ai.Attachment(
        type: 'image',
        path: '/private/target-image.png',
      );

      final (_, context) = await ContextBuilder(db.messageDao).buildContext(
        sessionId,
        upToMessageId: 'context-target-user',
        targetMessageContent: effectiveContent,
        targetMessageAttachments: [targetAttachment],
      );

      expect(
        context.map((message) => message.content),
        contains(effectiveContent),
      );
      expect(
        context.map((message) => message.content),
        isNot(contains('被重试的旧回答')),
      );
      expect(
        context.map((message) => message.content),
        isNot(contains('后续回答')),
      );
      final target = context.lastWhere(
        (message) => message.content == effectiveContent,
      );
      expect(target.role, 'user');
      expect(target.attachments, hasLength(1));
      expect(target.attachments!.single.path, targetAttachment.path);

      final persisted = await db.messageDao.getMessagesBySession(sessionId);
      expect(
        persisted
            .firstWhere((message) => message.id == 'context-target-user')
            .content,
        '请读取文件',
      );
      expect(effectiveContent, contains(extracted));
    },
  );
}
