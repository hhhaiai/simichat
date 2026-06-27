import 'dart:io';

import 'package:path/path.dart' as p;

/// 单条消息的 Markdown 原始档案表示。
class ArchivedMessage {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String? thinkingContent;
  final String? channelModelId;
  final DateTime createdAt;
  final List<String> attachmentNames;

  const ArchivedMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.thinkingContent,
    this.channelModelId,
    this.attachmentNames = const [],
  });
}

/// 每个会话一个 Markdown 原始档案。
///
/// SQLite 仍是查询权威源；Markdown 用作本地原始档案、导出和人工审阅格式。
class MarkdownConversationArchive {
  final Directory rootDirectory;

  const MarkdownConversationArchive({required this.rootDirectory});

  Directory get conversationsDirectory =>
      Directory(p.join(rootDirectory.path, 'conversations'));

  File conversationFile(String sessionId) => File(
    p.join(conversationsDirectory.path, '${sanitizeSessionId(sessionId)}.md'),
  );

  /// 追加单条消息。若文件不存在，会先写入会话头。
  Future<File> appendMessage({
    required String sessionId,
    required ArchivedMessage message,
    String? sessionTitle,
  }) async {
    final file = conversationFile(sessionId);
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await file.writeAsString(_renderHeader(sessionId, sessionTitle));
    }
    await file.writeAsString(
      renderMessage(message),
      mode: FileMode.append,
      flush: true,
    );
    return file;
  }

  /// 从消息列表重建完整会话档案，用于修复 Markdown 与 SQLite 不一致。
  Future<File> rebuildSession({
    required String sessionId,
    required Iterable<ArchivedMessage> messages,
    String? sessionTitle,
  }) async {
    final file = conversationFile(sessionId);
    await file.parent.create(recursive: true);
    final buffer = StringBuffer(_renderHeader(sessionId, sessionTitle));
    for (final message in messages) {
      buffer.write(renderMessage(message));
    }
    await file.writeAsString(buffer.toString(), flush: true);
    return file;
  }

  /// 同步会话标题。文件不存在时不创建空档案，避免误生成用户数据文件。
  Future<File?> updateSessionTitle({
    required String sessionId,
    String? sessionTitle,
  }) async {
    final file = conversationFile(sessionId);
    if (!await file.exists()) return null;
    final lines = await file.readAsLines();
    if (lines.isEmpty) return file;
    final title = sessionTitle?.trim().isNotEmpty == true
        ? sessionTitle!.trim()
        : '未命名会话';
    lines[0] = '# $title';
    await file.writeAsString('${lines.join('\n')}\n', flush: true);
    return file;
  }

  Future<List<String>> readArchivedMessageIds(String sessionId) async {
    final file = conversationFile(sessionId);
    if (!await file.exists()) return const [];
    final content = await file.readAsString();
    return RegExp(
      r'<!-- simichat-message-id: ([^ ]+) -->',
    ).allMatches(content).map((match) => match.group(1)!).toList();
  }

  static String sanitizeSessionId(String sessionId) {
    final sanitized = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return sanitized.isEmpty ? 'untitled-session' : sanitized;
  }

  static String renderMessage(ArchivedMessage message) {
    final label = switch (message.role) {
      'user' => '用户',
      'assistant' => '助手',
      'system' => '系统',
      _ => message.role,
    };
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('<!-- simichat-message-id: ${message.id} -->')
      ..writeln('### ${_formatDateTime(message.createdAt)} $label')
      ..writeln()
      ..writeln('- message_id: `${message.id}`')
      ..writeln('- role: `${message.role}`');

    if (message.channelModelId != null && message.channelModelId!.isNotEmpty) {
      buffer.writeln('- channel_model_id: `${message.channelModelId}`');
    }
    if (message.attachmentNames.isNotEmpty) {
      buffer.writeln('- attachments:');
      for (final name in message.attachmentNames) {
        buffer.writeln('  - ${_escapeInline(name)}');
      }
    }

    buffer
      ..writeln()
      ..writeln(message.content.isEmpty ? '_（空消息）_' : message.content.trim())
      ..writeln();

    final thinking = message.thinkingContent?.trim();
    if (thinking != null && thinking.isNotEmpty) {
      buffer
        ..writeln('<details>')
        ..writeln('<summary>思考过程</summary>')
        ..writeln()
        ..writeln(thinking)
        ..writeln()
        ..writeln('</details>')
        ..writeln();
    }

    return buffer.toString();
  }

  static String _renderHeader(String sessionId, String? sessionTitle) {
    final title = sessionTitle?.trim().isNotEmpty == true
        ? sessionTitle!.trim()
        : '未命名会话';
    return '''# $title

- session_id: `$sessionId`
- archive_format: `simichat.markdown.v1`

## 消息
''';
  }

  static String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static String _escapeInline(String value) => value.replaceAll('\n', ' ');
}
