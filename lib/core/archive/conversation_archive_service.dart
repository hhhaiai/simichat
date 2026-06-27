import 'dart:io';

import '../database/app_database.dart';
import '../database/dao/attachment_dao.dart';
import '../database/dao/message_dao.dart';
import '../database/dao/session_dao.dart';
import 'markdown_conversation_archive.dart';

class ConversationArchiveService {
  final MarkdownConversationArchive archive;
  final SessionDao sessionDao;
  final MessageDao messageDao;
  final AttachmentDao attachmentDao;

  const ConversationArchiveService({
    required this.archive,
    required this.sessionDao,
    required this.messageDao,
    required this.attachmentDao,
  });

  Future<File?> rebuildSession(String sessionId) async {
    final session = await sessionDao.getSession(sessionId);
    if (session == null) return null;
    final messages = await messageDao.getMessagesBySession(sessionId);
    final archivedMessages = <ArchivedMessage>[];
    for (final message in messages) {
      archivedMessages.add(await _toArchivedMessage(message));
    }
    return archive.rebuildSession(
      sessionId: sessionId,
      sessionTitle: session.title,
      messages: archivedMessages,
    );
  }

  Future<File?> syncTitle(String sessionId) async {
    final session = await sessionDao.getSession(sessionId);
    if (session == null) return null;
    return archive.updateSessionTitle(
      sessionId: sessionId,
      sessionTitle: session.title,
    );
  }

  Future<ArchiveConsistencyReport> checkConsistency(String sessionId) async {
    final session = await sessionDao.getSession(sessionId);
    if (session == null) {
      return ArchiveConsistencyReport(
        sessionId: sessionId,
        fileExists: false,
        missingMessageIds: const [],
        extraMessageIds: const [],
        problem: '会话不存在',
      );
    }

    final messages = await messageDao.getMessagesBySession(sessionId);
    final expectedIds = messages.map((m) => m.id).toSet();
    final archivedIds = (await archive.readArchivedMessageIds(
      sessionId,
    )).toSet();
    return ArchiveConsistencyReport(
      sessionId: sessionId,
      fileExists: await archive.conversationFile(sessionId).exists(),
      missingMessageIds: expectedIds.difference(archivedIds).toList()..sort(),
      extraMessageIds: archivedIds.difference(expectedIds).toList()..sort(),
    );
  }

  Future<ArchivedMessage> _toArchivedMessage(Message message) async {
    final attachments = await attachmentDao.getAttachmentsByMessage(message.id);
    return ArchivedMessage(
      id: message.id,
      sessionId: message.sessionId,
      role: message.role,
      content: message.content,
      thinkingContent: message.thinkingContent,
      channelModelId: message.channelModelId,
      attachmentNames: attachments.map((a) => a.fileName).toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(message.createdAt),
    );
  }
}

class ArchiveConsistencyReport {
  final String sessionId;
  final bool fileExists;
  final List<String> missingMessageIds;
  final List<String> extraMessageIds;
  final String? problem;

  const ArchiveConsistencyReport({
    required this.sessionId,
    required this.fileExists,
    required this.missingMessageIds,
    required this.extraMessageIds,
    this.problem,
  });

  bool get isConsistent =>
      problem == null &&
      fileExists &&
      missingMessageIds.isEmpty &&
      extraMessageIds.isEmpty;
}
