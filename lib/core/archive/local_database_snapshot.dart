import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import 'archive_attachment_path.dart';

const kLocalDatabaseArchivePath = 'structured_data/local_database.json';
const kLocalDatabaseSnapshotFormat = 'simichat.local_database.v1';

class LocalDatabaseSnapshotPreview {
  const LocalDatabaseSnapshotPreview({
    required this.sessionCount,
    required this.messageCount,
    required this.attachmentCount,
    required this.folderCount,
    required this.promptCount,
    required this.skillCount,
    required this.mcpServerCount,
    required this.modelChannelCount,
    required this.channelModelCount,
    required this.existingSessionCount,
    required this.existingMessageCount,
    required this.existingAttachmentCount,
    required this.existingFolderCount,
    required this.existingPromptCount,
    required this.existingSkillCount,
    required this.existingMcpServerCount,
    required this.existingModelChannelCount,
    required this.existingChannelModelCount,
  });

  final int sessionCount;
  final int messageCount;
  final int attachmentCount;
  final int folderCount;
  final int promptCount;
  final int skillCount;
  final int mcpServerCount;
  final int modelChannelCount;
  final int channelModelCount;
  final int existingSessionCount;
  final int existingMessageCount;
  final int existingAttachmentCount;
  final int existingFolderCount;
  final int existingPromptCount;
  final int existingSkillCount;
  final int existingMcpServerCount;
  final int existingModelChannelCount;
  final int existingChannelModelCount;

  int get configurationRecordCount =>
      folderCount +
      promptCount +
      skillCount +
      mcpServerCount +
      modelChannelCount +
      channelModelCount;

  int get totalRecordCount =>
      sessionCount + messageCount + attachmentCount + configurationRecordCount;

  int get existingConfigurationRecordCount =>
      existingFolderCount +
      existingPromptCount +
      existingSkillCount +
      existingMcpServerCount +
      existingModelChannelCount +
      existingChannelModelCount;

  int get existingRecordCount =>
      existingSessionCount +
      existingMessageCount +
      existingAttachmentCount +
      existingConfigurationRecordCount;
}

class LocalDatabaseRestoreResult {
  const LocalDatabaseRestoreResult({
    required this.restoredSessions,
    required this.restoredMessages,
    required this.restoredAttachments,
    required this.restoredFolders,
    required this.restoredPrompts,
    required this.restoredSkills,
    required this.restoredMcpServers,
    required this.restoredModelChannels,
    required this.restoredChannelModels,
    required this.skippedExistingSessions,
    required this.skippedExistingMessages,
    required this.skippedExistingAttachments,
    required this.skippedExistingFolders,
    required this.skippedExistingPrompts,
    required this.skippedExistingSkills,
    required this.skippedExistingMcpServers,
    required this.skippedExistingModelChannels,
    required this.skippedExistingChannelModels,
    required this.skippedInvalidMessages,
    required this.skippedInvalidAttachments,
    required this.skippedInvalidChannelModels,
  });

  final int restoredSessions;
  final int restoredMessages;
  final int restoredAttachments;
  final int restoredFolders;
  final int restoredPrompts;
  final int restoredSkills;
  final int restoredMcpServers;
  final int restoredModelChannels;
  final int restoredChannelModels;
  final int skippedExistingSessions;
  final int skippedExistingMessages;
  final int skippedExistingAttachments;
  final int skippedExistingFolders;
  final int skippedExistingPrompts;
  final int skippedExistingSkills;
  final int skippedExistingMcpServers;
  final int skippedExistingModelChannels;
  final int skippedExistingChannelModels;
  final int skippedInvalidMessages;
  final int skippedInvalidAttachments;
  final int skippedInvalidChannelModels;

  int get restoredConfigurationRecords =>
      restoredFolders +
      restoredPrompts +
      restoredSkills +
      restoredMcpServers +
      restoredModelChannels +
      restoredChannelModels;

  int get restoredRecordCount =>
      restoredSessions +
      restoredMessages +
      restoredAttachments +
      restoredConfigurationRecords;

  int get skippedExistingConfigurationRecords =>
      skippedExistingFolders +
      skippedExistingPrompts +
      skippedExistingSkills +
      skippedExistingMcpServers +
      skippedExistingModelChannels +
      skippedExistingChannelModels;

  int get skippedExistingRecordCount =>
      skippedExistingSessions +
      skippedExistingMessages +
      skippedExistingAttachments +
      skippedExistingConfigurationRecords;
  int get skippedInvalidRecordCount =>
      skippedInvalidMessages +
      skippedInvalidAttachments +
      skippedInvalidChannelModels;
}

class LocalDatabaseSnapshotService {
  const LocalDatabaseSnapshotService({
    required this.database,
    required this.rootDirectory,
    DateTime Function()? now,
  }) : _now = now;

  final AppDatabase database;
  final Directory rootDirectory;
  final DateTime Function()? _now;

  Future<List<int>?> exportSnapshot({bool includeAudioFiles = true}) async {
    final folders = await (database.select(
      database.folders,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    final prompts = await (database.select(
      database.prompts,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    final skills = await (database.select(
      database.skills,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    final mcpServers = await (database.select(
      database.mcpServers,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    final modelChannels = await (database.select(
      database.modelChannels,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    final channelModels = await (database.select(
      database.channelModels,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    final sessions = await (database.select(
      database.sessions,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    final messages = await (database.select(
      database.messages,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    final attachments = await (database.select(
      database.attachments,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

    if (folders.isEmpty &&
        prompts.isEmpty &&
        skills.isEmpty &&
        mcpServers.isEmpty &&
        modelChannels.isEmpty &&
        channelModels.isEmpty &&
        sessions.isEmpty &&
        messages.isEmpty &&
        attachments.isEmpty) {
      return null;
    }

    final exportableAttachments = <Map<String, Object?>>[];
    for (final attachment in attachments) {
      final archivePath = await _archivePathForAttachment(
        attachment,
        includeAudioFiles: includeAudioFiles,
      );
      if (archivePath == null) continue;
      exportableAttachments.add({
        'id': attachment.id,
        'message_id': attachment.messageId,
        'file_type': attachment.fileType,
        'archive_path': archivePath,
        'file_name': attachment.fileName,
        'file_size': attachment.fileSize,
        'created_at': attachment.createdAt,
      });
    }

    final json = {
      'format': kLocalDatabaseSnapshotFormat,
      'exported_at': (_now ?? DateTime.now)().toUtc().toIso8601String(),
      'privacy': {
        'contains_model_api_keys': false,
        'contains_mcp_headers': false,
        'contains_absolute_paths': false,
        'note': '导出本地会话、消息、附件元数据和非密钥配置；不包含模型渠道密钥、MCP headers 或本机绝对路径。',
      },
      'folders': folders
          .map(
            (folder) => {
              'id': folder.id,
              'user_id': folder.userId,
              'name': folder.name,
              'ai_summary': folder.aiSummary,
              'last_summarized_at': folder.lastSummarizedAt,
              'created_at': folder.createdAt,
              'updated_at': folder.updatedAt,
            },
          )
          .toList(growable: false),
      'prompts': prompts
          .map(
            (prompt) => {
              'id': prompt.id,
              'name': prompt.name,
              'content': prompt.content,
              'category': prompt.category,
              'is_default': prompt.isDefault,
              'created_at': prompt.createdAt,
              'updated_at': prompt.updatedAt,
            },
          )
          .toList(growable: false),
      'skills': skills
          .map(
            (skill) => {
              'id': skill.id,
              'name': skill.name,
              'description': skill.description,
              'instructions': skill.instructions,
              'source_url': skill.sourceUrl,
              'source_sha256': skill.sourceSha256,
              'sha256_verified': skill.sha256Verified,
              'online': skill.online,
              'is_enabled': skill.isEnabled,
              'created_at': skill.createdAt,
            },
          )
          .toList(growable: false),
      'mcp_servers': mcpServers
          .map(
            (server) => {
              'id': server.id,
              'name': server.name,
              'transport': server.transport,
              'command': _safeConfigString(server.command, maxLength: 1024),
              'args': _safeConfigString(server.args, maxLength: 8192),
              'url': _safeUrlString(server.url),
              'headers_exported': false,
              'is_enabled': server.isEnabled,
              'source': server.source,
              'marketplace_id': server.marketplaceId,
              'created_at': server.createdAt,
            },
          )
          .toList(growable: false),
      'model_channels': modelChannels
          .map(
            (channel) => {
              'id': channel.id,
              'name': channel.name,
              'base_url': _safeUrlString(channel.baseUrl) ?? '',
              'api_key_exported': false,
              'protocol': channel.protocol,
              'is_enabled': channel.isEnabled,
              'is_default': channel.isDefault,
              'created_at': channel.createdAt,
            },
          )
          .toList(growable: false),
      'channel_models': channelModels
          .map(
            (model) => {
              'id': model.id,
              'channel_id': model.channelId,
              'model_name': model.modelName,
              'capability': model.capability,
              'is_default': model.isDefault,
            },
          )
          .toList(growable: false),
      'sessions': sessions
          .map(
            (session) => {
              'id': session.id,
              'user_id': session.userId,
              'title': session.title,
              'folder_id': session.folderId,
              'total_tokens': session.totalTokens,
              'created_at': session.createdAt,
              'last_message_at': session.lastMessageAt,
            },
          )
          .toList(growable: false),
      'messages': messages
          .map(
            (message) => {
              'id': message.id,
              'session_id': message.sessionId,
              'role': message.role,
              'content': message.content,
              'thinking_content': message.thinkingContent,
              'message_type': message.messageType,
              'summary_start_id': message.summaryStartId,
              'summary_end_id': message.summaryEndId,
              'is_summarized': message.isSummarized,
              'tokens': message.tokens,
              'response_ms': message.responseMs,
              'created_at': message.createdAt,
            },
          )
          .toList(growable: false),
      'attachments': exportableAttachments,
    };

    return utf8.encode('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  }

  Future<LocalDatabaseSnapshotPreview> previewSnapshot(List<int> bytes) async {
    final snapshot = _parseSnapshot(bytes);
    return LocalDatabaseSnapshotPreview(
      sessionCount: snapshot.sessions.length,
      messageCount: snapshot.messages.length,
      attachmentCount: snapshot.attachments.length,
      folderCount: snapshot.folders.length,
      promptCount: snapshot.prompts.length,
      skillCount: snapshot.skills.length,
      mcpServerCount: snapshot.mcpServers.length,
      modelChannelCount: snapshot.modelChannels.length,
      channelModelCount: snapshot.channelModels.length,
      existingSessionCount: await _countExistingIds(
        'sessions',
        snapshot.sessions.map((row) => row.id),
      ),
      existingMessageCount: await _countExistingIds(
        'messages',
        snapshot.messages.map((row) => row.id),
      ),
      existingAttachmentCount: await _countExistingIds(
        'attachments',
        snapshot.attachments.map((row) => row.id),
      ),
      existingFolderCount: await _countExistingIds(
        'folders',
        snapshot.folders.map((row) => row.id),
      ),
      existingPromptCount: await _countExistingIds(
        'prompts',
        snapshot.prompts.map((row) => row.id),
      ),
      existingSkillCount: await _countExistingIds(
        'skills',
        snapshot.skills.map((row) => row.id),
      ),
      existingMcpServerCount: await _countExistingIds(
        'mcp_servers',
        snapshot.mcpServers.map((row) => row.id),
      ),
      existingModelChannelCount: await _countExistingIds(
        'model_channels',
        snapshot.modelChannels.map((row) => row.id),
      ),
      existingChannelModelCount: await _countExistingIds(
        'channel_models',
        snapshot.channelModels.map((row) => row.id),
      ),
    );
  }

  Future<LocalDatabaseRestoreResult> restoreSnapshot(
    List<int> bytes, {
    bool overwriteExisting = false,
  }) async {
    final snapshot = _parseSnapshot(bytes);

    var restoredSessions = 0;
    var restoredMessages = 0;
    var restoredAttachments = 0;
    var restoredFolders = 0;
    var restoredPrompts = 0;
    var restoredSkills = 0;
    var restoredMcpServers = 0;
    var restoredModelChannels = 0;
    var restoredChannelModels = 0;
    var skippedExistingSessions = 0;
    var skippedExistingMessages = 0;
    var skippedExistingAttachments = 0;
    var skippedExistingFolders = 0;
    var skippedExistingPrompts = 0;
    var skippedExistingSkills = 0;
    var skippedExistingMcpServers = 0;
    var skippedExistingModelChannels = 0;
    var skippedExistingChannelModels = 0;
    var skippedInvalidMessages = 0;
    var skippedInvalidAttachments = 0;
    var skippedInvalidChannelModels = 0;

    await database.transaction(() async {
      for (final row in snapshot.folders) {
        final exists = await _recordExists('folders', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingFolders++;
          continue;
        }
        final companion = FoldersCompanion.insert(
          id: row.id,
          userId: Value(row.userId),
          name: row.name,
          aiSummary: Value(row.aiSummary),
          lastSummarizedAt: Value(row.lastSummarizedAt),
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
        );
        if (overwriteExisting) {
          await database
              .into(database.folders)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.folders)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredFolders++;
      }

      for (final row in snapshot.prompts) {
        final exists = await _recordExists('prompts', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingPrompts++;
          continue;
        }
        final companion = PromptsCompanion.insert(
          id: row.id,
          name: row.name,
          content: row.content,
          category: Value(row.category),
          isDefault: Value(row.isDefault),
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
        );
        if (overwriteExisting) {
          await database
              .into(database.prompts)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.prompts)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredPrompts++;
      }

      for (final row in snapshot.skills) {
        final exists = await _recordExists('skills', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingSkills++;
          continue;
        }
        final companion = SkillsCompanion.insert(
          id: row.id,
          name: row.name,
          description: Value(row.description),
          instructions: row.instructions,
          sourceUrl: Value(row.sourceUrl),
          sourceSha256: Value(row.sourceSha256),
          sha256Verified: Value(row.sha256Verified),
          online: Value(row.online),
          isEnabled: Value(row.isEnabled),
          createdAt: row.createdAt,
        );
        if (overwriteExisting) {
          await database
              .into(database.skills)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.skills)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredSkills++;
      }

      for (final row in snapshot.mcpServers) {
        final exists = await _recordExists('mcp_servers', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingMcpServers++;
          continue;
        }
        final companion = McpServersCompanion.insert(
          id: row.id,
          name: row.name,
          transport: row.transport,
          command: Value(row.command),
          args: Value(row.args),
          url: Value(row.url),
          headers: const Value(null),
          isEnabled: const Value(false),
          source: Value(row.source),
          marketplaceId: Value(row.marketplaceId),
          createdAt: row.createdAt,
        );
        if (overwriteExisting) {
          await database
              .into(database.mcpServers)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.mcpServers)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredMcpServers++;
      }

      for (final row in snapshot.modelChannels) {
        final exists = await _recordExists('model_channels', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingModelChannels++;
          continue;
        }
        final companion = ModelChannelsCompanion.insert(
          id: row.id,
          name: row.name,
          baseUrl: row.baseUrl,
          apiKeyEncrypted: '',
          protocol: row.protocol,
          isEnabled: const Value(false),
          isDefault: const Value(false),
          createdAt: row.createdAt,
        );
        if (overwriteExisting) {
          await database
              .into(database.modelChannels)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.modelChannels)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredModelChannels++;
      }

      for (final row in snapshot.channelModels) {
        final exists = await _recordExists('channel_models', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingChannelModels++;
          continue;
        }
        final channelExists = await _recordExists(
          'model_channels',
          row.channelId,
        );
        if (!channelExists) {
          skippedInvalidChannelModels++;
          continue;
        }
        final companion = ChannelModelsCompanion.insert(
          id: row.id,
          channelId: row.channelId,
          modelName: row.modelName,
          capability: Value(row.capability),
          isDefault: Value(row.isDefault),
        );
        if (overwriteExisting) {
          await database
              .into(database.channelModels)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.channelModels)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredChannelModels++;
      }

      for (final row in snapshot.sessions) {
        final exists = await _recordExists('sessions', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingSessions++;
          continue;
        }
        final folderId = await _existingReferenceOrNull(
          'folders',
          row.folderId,
        );
        final companion = SessionsCompanion.insert(
          id: row.id,
          userId: Value(row.userId),
          title: Value(row.title),
          folderId: Value(folderId),
          defaultChannelModelId: const Value(null),
          totalTokens: Value(row.totalTokens),
          createdAt: row.createdAt,
          lastMessageAt: row.lastMessageAt,
        );
        if (overwriteExisting) {
          await database
              .into(database.sessions)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.sessions)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredSessions++;
      }

      for (final row in snapshot.messages) {
        final sessionExists = await _recordExists('sessions', row.sessionId);
        if (!sessionExists) {
          skippedInvalidMessages++;
          continue;
        }
        final exists = await _recordExists('messages', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingMessages++;
          continue;
        }
        final companion = MessagesCompanion.insert(
          id: row.id,
          sessionId: row.sessionId,
          role: row.role,
          content: row.content,
          thinkingContent: Value(row.thinkingContent),
          messageType: Value(row.messageType),
          summaryStartId: Value(row.summaryStartId),
          summaryEndId: Value(row.summaryEndId),
          isSummarized: Value(row.isSummarized),
          channelModelId: const Value(null),
          tokens: Value(row.tokens),
          responseMs: Value(row.responseMs),
          createdAt: row.createdAt,
        );
        if (overwriteExisting) {
          await database
              .into(database.messages)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.messages)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredMessages++;
      }

      for (final row in snapshot.attachments) {
        final messageExists = await _recordExists('messages', row.messageId);
        if (!messageExists) {
          skippedInvalidAttachments++;
          continue;
        }
        final exists = await _recordExists('attachments', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingAttachments++;
          continue;
        }
        final localPath = _restoreLocalPath(row.archivePath);
        if (localPath == null) {
          skippedInvalidAttachments++;
          continue;
        }
        final companion = AttachmentsCompanion.insert(
          id: row.id,
          messageId: row.messageId,
          fileType: row.fileType,
          localPath: localPath,
          fileName: row.fileName,
          fileSize: row.fileSize,
          createdAt: row.createdAt,
        );
        if (overwriteExisting) {
          await database
              .into(database.attachments)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.attachments)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredAttachments++;
      }
    });

    return LocalDatabaseRestoreResult(
      restoredSessions: restoredSessions,
      restoredMessages: restoredMessages,
      restoredAttachments: restoredAttachments,
      restoredFolders: restoredFolders,
      restoredPrompts: restoredPrompts,
      restoredSkills: restoredSkills,
      restoredMcpServers: restoredMcpServers,
      restoredModelChannels: restoredModelChannels,
      restoredChannelModels: restoredChannelModels,
      skippedExistingSessions: skippedExistingSessions,
      skippedExistingMessages: skippedExistingMessages,
      skippedExistingAttachments: skippedExistingAttachments,
      skippedExistingFolders: skippedExistingFolders,
      skippedExistingPrompts: skippedExistingPrompts,
      skippedExistingSkills: skippedExistingSkills,
      skippedExistingMcpServers: skippedExistingMcpServers,
      skippedExistingModelChannels: skippedExistingModelChannels,
      skippedExistingChannelModels: skippedExistingChannelModels,
      skippedInvalidMessages: skippedInvalidMessages,
      skippedInvalidAttachments: skippedInvalidAttachments,
      skippedInvalidChannelModels: skippedInvalidChannelModels,
    );
  }

  Future<String?> _archivePathForAttachment(
    Attachment attachment, {
    required bool includeAudioFiles,
  }) async {
    final type = attachment.fileType.toLowerCase();
    final source = File(attachment.localPath);
    final entityType = await FileSystemEntity.type(
      source.path,
      followLinks: false,
    );
    if (entityType != FileSystemEntityType.file) return null;

    if (type == 'audio') {
      if (!includeAudioFiles) return null;
      final relative = _relativeRootArchivePath(source.path);
      if (relative == null || !relative.startsWith('audio_files/')) {
        return null;
      }
      return relative;
    }

    final exportsDir = p.join(rootDirectory.path, 'exports');
    late final String sourceCanonical;
    try {
      sourceCanonical = await source.resolveSymbolicLinks();
    } catch (_) {
      return null;
    }
    if (p.equals(sourceCanonical, exportsDir) ||
        p.isWithin(exportsDir, sourceCanonical)) {
      return null;
    }
    return buildAttachmentArchivePath(
      attachmentId: attachment.id,
      messageId: attachment.messageId,
      fileName: attachment.fileName,
    );
  }

  String? _relativeRootArchivePath(String path) {
    final relative = p.relative(path, from: rootDirectory.path);
    final parts = p.split(relative);
    if (parts.any((part) => part == '..' || part == '.' || part.isEmpty)) {
      return null;
    }
    return parts.join('/');
  }

  String? _restoreLocalPath(String archivePath) {
    final normalized = _normalizeSnapshotPath(archivePath);
    if (normalized == null) return null;
    if (!normalized.startsWith('attachments/') &&
        !normalized.startsWith('audio_files/')) {
      return null;
    }
    return p.joinAll([rootDirectory.path, ...p.posix.split(normalized)]);
  }

  Future<int> _countExistingIds(String table, Iterable<String> ids) async {
    var count = 0;
    for (final id in ids) {
      if (await _recordExists(table, id)) count++;
    }
    return count;
  }

  Future<bool> _recordExists(String table, String id) async {
    final row = await database
        .customSelect(
          'SELECT 1 FROM $table WHERE id = ? LIMIT 1',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<String?> _existingReferenceOrNull(String table, String? id) async {
    if (id == null || id.isEmpty) return null;
    return await _recordExists(table, id) ? id : null;
  }
}

_LocalDatabaseSnapshot _parseSnapshot(List<int> bytes) {
  final json = jsonDecode(utf8.decode(bytes));
  if (json is! Map<String, Object?> ||
      json['format'] != kLocalDatabaseSnapshotFormat) {
    throw const FormatException('本地数据库快照格式不受支持');
  }
  return _LocalDatabaseSnapshot(
    folders: _listOfMaps(
      json['folders'],
    ).map(_SnapshotFolder.fromJson).toList(growable: false),
    prompts: _listOfMaps(
      json['prompts'],
    ).map(_SnapshotPrompt.fromJson).toList(growable: false),
    skills: _listOfMaps(
      json['skills'],
    ).map(_SnapshotSkill.fromJson).toList(growable: false),
    mcpServers: _listOfMaps(
      json['mcp_servers'],
    ).map(_SnapshotMcpServer.fromJson).toList(growable: false),
    modelChannels: _listOfMaps(
      json['model_channels'],
    ).map(_SnapshotModelChannel.fromJson).toList(growable: false),
    channelModels: _listOfMaps(
      json['channel_models'],
    ).map(_SnapshotChannelModel.fromJson).toList(growable: false),
    sessions: _listOfMaps(
      json['sessions'],
    ).map(_SnapshotSession.fromJson).toList(growable: false),
    messages: _listOfMaps(
      json['messages'],
    ).map(_SnapshotMessage.fromJson).toList(growable: false),
    attachments: _listOfMaps(
      json['attachments'],
    ).map(_SnapshotAttachment.fromJson).toList(growable: false),
  );
}

List<Map<String, Object?>> _listOfMaps(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('快照列表格式错误');
  return value
      .map((item) {
        if (item is! Map) throw const FormatException('快照条目格式错误');
        return item.cast<String, Object?>();
      })
      .toList(growable: false);
}

String? _normalizeSnapshotPath(String rawPath) {
  if (rawPath.startsWith('/') || rawPath.contains('\\')) return null;
  final parts = p.posix
      .split(rawPath)
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.any((part) => part == '.' || part == '..')) return null;
  return parts.join('/');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('快照缺少 $key');
  }
  return value;
}

String _stringValue(
  Map<String, Object?> json,
  String key, {
  String defaultValue = '',
}) {
  final value = json[key];
  if (value == null) return defaultValue;
  if (value is String) return value;
  throw FormatException('快照字段 $key 类型错误');
}

int _intValue(Map<String, Object?> json, String key, {int defaultValue = 0}) {
  final value = json[key];
  if (value == null) return defaultValue;
  if (value is int) return value;
  throw FormatException('快照字段 $key 类型错误');
}

bool _boolValue(
  Map<String, Object?> json,
  String key, {
  bool defaultValue = false,
}) {
  final value = json[key];
  if (value == null) return defaultValue;
  if (value is bool) return value;
  throw FormatException('快照字段 $key 类型错误');
}

String? _nullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('快照字段 $key 类型错误');
}

String? _safeConfigString(String? value, {required int maxLength}) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > maxLength) return null;
  if (_containsSensitiveConfigText(trimmed)) return null;
  return trimmed;
}

String? _safeUrlString(String? value) {
  final safe = _safeConfigString(value, maxLength: 2048);
  if (safe == null) return null;
  final uri = Uri.tryParse(safe);
  if (uri != null && uri.hasAuthority && uri.userInfo.isNotEmpty) {
    return null;
  }
  return safe;
}

bool _containsSensitiveConfigText(String value) {
  return _sensitiveAssignmentPattern.hasMatch(value) ||
      _sensitiveBearerPattern.hasMatch(value) ||
      _sensitiveFlagPattern.hasMatch(value);
}

final _sensitiveAssignmentPattern = RegExp(
  r'''(authorization|x-api-key|api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password|passwd|token)["'\s]*[:=]''',
  caseSensitive: false,
);
final _sensitiveBearerPattern = RegExp(
  r'''\bbearer\s+[a-z0-9._~+/=-]{6,}''',
  caseSensitive: false,
);
final _sensitiveFlagPattern = RegExp(
  r'''--?(api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password|passwd|token)\b''',
  caseSensitive: false,
);

class _LocalDatabaseSnapshot {
  const _LocalDatabaseSnapshot({
    required this.folders,
    required this.prompts,
    required this.skills,
    required this.mcpServers,
    required this.modelChannels,
    required this.channelModels,
    required this.sessions,
    required this.messages,
    required this.attachments,
  });

  final List<_SnapshotFolder> folders;
  final List<_SnapshotPrompt> prompts;
  final List<_SnapshotSkill> skills;
  final List<_SnapshotMcpServer> mcpServers;
  final List<_SnapshotModelChannel> modelChannels;
  final List<_SnapshotChannelModel> channelModels;
  final List<_SnapshotSession> sessions;
  final List<_SnapshotMessage> messages;
  final List<_SnapshotAttachment> attachments;
}

class _SnapshotFolder {
  const _SnapshotFolder({
    required this.id,
    required this.userId,
    required this.name,
    required this.aiSummary,
    required this.lastSummarizedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String? aiSummary;
  final int? lastSummarizedAt;
  final int createdAt;
  final int updatedAt;

  factory _SnapshotFolder.fromJson(Map<String, Object?> json) {
    return _SnapshotFolder(
      id: _requiredString(json, 'id'),
      userId: _nullableString(json, 'user_id') ?? 'local',
      name: _requiredString(json, 'name'),
      aiSummary: _nullableString(json, 'ai_summary'),
      lastSummarizedAt: json['last_summarized_at'] == null
          ? null
          : _intValue(json, 'last_summarized_at'),
      createdAt: _intValue(json, 'created_at'),
      updatedAt: _intValue(json, 'updated_at'),
    );
  }
}

class _SnapshotPrompt {
  const _SnapshotPrompt({
    required this.id,
    required this.name,
    required this.content,
    required this.category,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String content;
  final String category;
  final bool isDefault;
  final int createdAt;
  final int updatedAt;

  factory _SnapshotPrompt.fromJson(Map<String, Object?> json) {
    return _SnapshotPrompt(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      content: _nullableString(json, 'content') ?? '',
      category: _nullableString(json, 'category') ?? 'general',
      isDefault: _boolValue(json, 'is_default'),
      createdAt: _intValue(json, 'created_at'),
      updatedAt: _intValue(json, 'updated_at'),
    );
  }
}

class _SnapshotSkill {
  const _SnapshotSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions,
    required this.sourceUrl,
    required this.sourceSha256,
    required this.sha256Verified,
    required this.online,
    required this.isEnabled,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String instructions;
  final String? sourceUrl;
  final String? sourceSha256;
  final bool sha256Verified;
  final bool online;
  final bool isEnabled;
  final int createdAt;

  factory _SnapshotSkill.fromJson(Map<String, Object?> json) {
    return _SnapshotSkill(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      description: _nullableString(json, 'description') ?? '',
      instructions: _nullableString(json, 'instructions') ?? '',
      sourceUrl: _nullableString(json, 'source_url'),
      sourceSha256: _nullableString(json, 'source_sha256'),
      sha256Verified: _boolValue(json, 'sha256_verified'),
      online: _boolValue(json, 'online'),
      isEnabled: _boolValue(json, 'is_enabled', defaultValue: true),
      createdAt: _intValue(json, 'created_at'),
    );
  }
}

class _SnapshotMcpServer {
  const _SnapshotMcpServer({
    required this.id,
    required this.name,
    required this.transport,
    required this.command,
    required this.args,
    required this.url,
    required this.isEnabled,
    required this.source,
    required this.marketplaceId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String transport;
  final String? command;
  final String? args;
  final String? url;
  final bool isEnabled;
  final String source;
  final String? marketplaceId;
  final int createdAt;

  factory _SnapshotMcpServer.fromJson(Map<String, Object?> json) {
    return _SnapshotMcpServer(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      transport: _nullableString(json, 'transport') ?? 'stdio',
      command: _nullableString(json, 'command'),
      args: _nullableString(json, 'args'),
      url: _nullableString(json, 'url'),
      isEnabled: _boolValue(json, 'is_enabled'),
      source: _nullableString(json, 'source') ?? 'manual',
      marketplaceId: _nullableString(json, 'marketplace_id'),
      createdAt: _intValue(json, 'created_at'),
    );
  }
}

class _SnapshotModelChannel {
  const _SnapshotModelChannel({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.protocol,
    required this.isEnabled,
    required this.isDefault,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String protocol;
  final bool isEnabled;
  final bool isDefault;
  final int createdAt;

  factory _SnapshotModelChannel.fromJson(Map<String, Object?> json) {
    return _SnapshotModelChannel(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      baseUrl: _stringValue(json, 'base_url'),
      protocol: _nullableString(json, 'protocol') ?? 'openai_chat',
      isEnabled: _boolValue(json, 'is_enabled'),
      isDefault: _boolValue(json, 'is_default'),
      createdAt: _intValue(json, 'created_at'),
    );
  }
}

class _SnapshotChannelModel {
  const _SnapshotChannelModel({
    required this.id,
    required this.channelId,
    required this.modelName,
    required this.capability,
    required this.isDefault,
  });

  final String id;
  final String channelId;
  final String modelName;
  final String capability;
  final bool isDefault;

  factory _SnapshotChannelModel.fromJson(Map<String, Object?> json) {
    return _SnapshotChannelModel(
      id: _requiredString(json, 'id'),
      channelId: _requiredString(json, 'channel_id'),
      modelName: _requiredString(json, 'model_name'),
      capability: _nullableString(json, 'capability') ?? 'chat',
      isDefault: _boolValue(json, 'is_default'),
    );
  }
}

class _SnapshotSession {
  const _SnapshotSession({
    required this.id,
    required this.userId,
    required this.title,
    required this.folderId,
    required this.totalTokens,
    required this.createdAt,
    required this.lastMessageAt,
  });

  final String id;
  final String userId;
  final String? title;
  final String? folderId;
  final int totalTokens;
  final int createdAt;
  final int lastMessageAt;

  factory _SnapshotSession.fromJson(Map<String, Object?> json) {
    return _SnapshotSession(
      id: _requiredString(json, 'id'),
      userId: _nullableString(json, 'user_id') ?? 'local',
      title: _nullableString(json, 'title'),
      folderId: _nullableString(json, 'folder_id'),
      totalTokens: _intValue(json, 'total_tokens'),
      createdAt: _intValue(json, 'created_at'),
      lastMessageAt: _intValue(json, 'last_message_at'),
    );
  }
}

class _SnapshotMessage {
  const _SnapshotMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.thinkingContent,
    required this.messageType,
    required this.summaryStartId,
    required this.summaryEndId,
    required this.isSummarized,
    required this.tokens,
    required this.responseMs,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String? thinkingContent;
  final String messageType;
  final String? summaryStartId;
  final String? summaryEndId;
  final bool isSummarized;
  final int tokens;
  final int? responseMs;
  final int createdAt;

  factory _SnapshotMessage.fromJson(Map<String, Object?> json) {
    return _SnapshotMessage(
      id: _requiredString(json, 'id'),
      sessionId: _requiredString(json, 'session_id'),
      role: _requiredString(json, 'role'),
      content: _nullableString(json, 'content') ?? '',
      thinkingContent: _nullableString(json, 'thinking_content'),
      messageType: _nullableString(json, 'message_type') ?? 'original',
      summaryStartId: _nullableString(json, 'summary_start_id'),
      summaryEndId: _nullableString(json, 'summary_end_id'),
      isSummarized: _boolValue(json, 'is_summarized'),
      tokens: _intValue(json, 'tokens'),
      responseMs: json['response_ms'] == null
          ? null
          : _intValue(json, 'response_ms'),
      createdAt: _intValue(json, 'created_at'),
    );
  }
}

class _SnapshotAttachment {
  const _SnapshotAttachment({
    required this.id,
    required this.messageId,
    required this.fileType,
    required this.archivePath,
    required this.fileName,
    required this.fileSize,
    required this.createdAt,
  });

  final String id;
  final String messageId;
  final String fileType;
  final String archivePath;
  final String fileName;
  final int fileSize;
  final int createdAt;

  factory _SnapshotAttachment.fromJson(Map<String, Object?> json) {
    final archivePath = _requiredString(json, 'archive_path');
    final normalized = _normalizeSnapshotPath(archivePath);
    if (normalized == null) {
      throw const FormatException('附件归档路径不安全');
    }
    return _SnapshotAttachment(
      id: _requiredString(json, 'id'),
      messageId: _requiredString(json, 'message_id'),
      fileType: _requiredString(json, 'file_type'),
      archivePath: normalized,
      fileName: _requiredString(json, 'file_name'),
      fileSize: _intValue(json, 'file_size'),
      createdAt: _intValue(json, 'created_at'),
    );
  }
}
