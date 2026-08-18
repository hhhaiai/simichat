import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../database/dao/channel_dao.dart' show decodeModelCapabilities;
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
    required this.dreamingJobCount,
    required this.dreamingReportCount,
    this.mediaJobCount = 0,
    this.invalidMediaJobCount = 0,
    required this.existingSessionCount,
    required this.existingMessageCount,
    required this.existingAttachmentCount,
    required this.existingFolderCount,
    required this.existingPromptCount,
    required this.existingSkillCount,
    required this.existingMcpServerCount,
    required this.existingModelChannelCount,
    required this.existingChannelModelCount,
    required this.existingDreamingJobCount,
    required this.existingDreamingReportCount,
    this.existingMediaJobCount = 0,
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
  final int dreamingJobCount;
  final int dreamingReportCount;
  final int mediaJobCount;
  final int invalidMediaJobCount;
  final int existingSessionCount;
  final int existingMessageCount;
  final int existingAttachmentCount;
  final int existingFolderCount;
  final int existingPromptCount;
  final int existingSkillCount;
  final int existingMcpServerCount;
  final int existingModelChannelCount;
  final int existingChannelModelCount;
  final int existingDreamingJobCount;
  final int existingDreamingReportCount;
  final int existingMediaJobCount;

  int get configurationRecordCount =>
      folderCount +
      promptCount +
      skillCount +
      mcpServerCount +
      modelChannelCount +
      channelModelCount +
      dreamingJobCount +
      dreamingReportCount +
      mediaJobCount;

  int get totalRecordCount =>
      sessionCount + messageCount + attachmentCount + configurationRecordCount;

  int get existingConfigurationRecordCount =>
      existingFolderCount +
      existingPromptCount +
      existingSkillCount +
      existingMcpServerCount +
      existingModelChannelCount +
      existingChannelModelCount +
      existingDreamingJobCount +
      existingDreamingReportCount +
      existingMediaJobCount;

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
    required this.restoredDreamingJobs,
    required this.restoredDreamingReports,
    required this.skippedExistingSessions,
    required this.skippedExistingMessages,
    required this.skippedExistingAttachments,
    required this.skippedExistingFolders,
    required this.skippedExistingPrompts,
    required this.skippedExistingSkills,
    required this.skippedExistingMcpServers,
    required this.skippedExistingModelChannels,
    required this.skippedExistingChannelModels,
    required this.skippedExistingDreamingJobs,
    required this.skippedExistingDreamingReports,
    required this.skippedInvalidMessages,
    required this.skippedInvalidAttachments,
    required this.skippedInvalidChannelModels,
    this.restoredMediaJobs = 0,
    this.skippedExistingMediaJobs = 0,
    this.skippedInvalidMediaJobs = 0,
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
  final int restoredDreamingJobs;
  final int restoredDreamingReports;
  final int skippedExistingSessions;
  final int skippedExistingMessages;
  final int skippedExistingAttachments;
  final int skippedExistingFolders;
  final int skippedExistingPrompts;
  final int skippedExistingSkills;
  final int skippedExistingMcpServers;
  final int skippedExistingModelChannels;
  final int skippedExistingChannelModels;
  final int skippedExistingDreamingJobs;
  final int skippedExistingDreamingReports;
  final int skippedInvalidMessages;
  final int skippedInvalidAttachments;
  final int skippedInvalidChannelModels;
  final int restoredMediaJobs;
  final int skippedExistingMediaJobs;
  final int skippedInvalidMediaJobs;

  int get restoredConfigurationRecords =>
      restoredFolders +
      restoredPrompts +
      restoredSkills +
      restoredMcpServers +
      restoredModelChannels +
      restoredChannelModels +
      restoredDreamingJobs +
      restoredDreamingReports +
      restoredMediaJobs;

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
      skippedExistingChannelModels +
      skippedExistingDreamingJobs +
      skippedExistingDreamingReports +
      skippedExistingMediaJobs;

  int get skippedExistingRecordCount =>
      skippedExistingSessions +
      skippedExistingMessages +
      skippedExistingAttachments +
      skippedExistingConfigurationRecords;
  int get skippedInvalidRecordCount =>
      skippedInvalidMessages +
      skippedInvalidAttachments +
      skippedInvalidChannelModels +
      skippedInvalidMediaJobs;
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
    final dreamingJobs = await (database.select(
      database.dreamingJobs,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    final dreamingReports = await (database.select(
      database.dreamingReports,
    )..orderBy([(t) => OrderingTerm.asc(t.generatedAt)])).get();
    final mediaJobs = await (database.select(
      database.mediaJobs,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
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
        dreamingJobs.isEmpty &&
        dreamingReports.isEmpty &&
        mediaJobs.isEmpty &&
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
        'contains_media_job_secrets': false,
        'contains_media_binaries': false,
        'contains_absolute_paths': false,
        'note':
            '导出本地会话、消息、附件元数据、媒体任务元数据和非密钥配置；不包含模型渠道密钥、MCP headers、媒体二进制或本机绝对路径。',
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
              'capabilities': decodeModelCapabilities(
                model.capability,
                model.capabilities,
              ).toList(growable: false),
              'is_default': model.isDefault,
            },
          )
          .toList(growable: false),
      'dreaming_jobs': dreamingJobs
          .map(
            (job) => {
              'id': job.id,
              'day_key': job.dayKey,
              'scheduled_for': job.scheduledFor,
              'status': job.status,
              'trigger': job.trigger,
              'message_limit': job.messageLimit,
              'started_at': job.startedAt,
              'finished_at': job.finishedAt,
              'error': _safeDiagnosticString(job.error),
              'created_at': job.createdAt,
              'updated_at': job.updatedAt,
            },
          )
          .toList(growable: false),
      'dreaming_reports': dreamingReports
          .map(
            (report) => {
              'id': report.id,
              'day_key': report.dayKey,
              'job_id': report.jobId,
              'generated_at': report.generatedAt,
              'markdown': report.markdown,
              'digest_json': report.digestJson,
              'session_count': report.sessionCount,
              'original_message_count': report.originalMessageCount,
              'total_original_message_count': report.totalOriginalMessageCount,
              'memory_candidate_count': report.memoryCandidateCount,
              'is_truncated': report.isTruncated,
              'created_at': report.createdAt,
            },
          )
          .toList(growable: false),
      'media_jobs': mediaJobs
          .map(_exportMediaJob)
          .whereType<Map<String, Object?>>()
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
              'is_pinned': session.isPinned,
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
      dreamingJobCount: snapshot.dreamingJobs.length,
      dreamingReportCount: snapshot.dreamingReports.length,
      mediaJobCount: snapshot.mediaJobs.length,
      invalidMediaJobCount: snapshot.invalidMediaJobCount,
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
      existingDreamingJobCount: await _countExistingIds(
        'dreaming_jobs',
        snapshot.dreamingJobs.map((row) => row.id),
      ),
      existingDreamingReportCount: await _countExistingDreamingReports(
        snapshot.dreamingReports,
      ),
      existingMediaJobCount: await _countExistingIds(
        'media_jobs',
        snapshot.mediaJobs.map((row) => row.id),
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
    var restoredDreamingJobs = 0;
    var restoredDreamingReports = 0;
    var restoredMediaJobs = 0;
    var skippedExistingSessions = 0;
    var skippedExistingMessages = 0;
    var skippedExistingAttachments = 0;
    var skippedExistingFolders = 0;
    var skippedExistingPrompts = 0;
    var skippedExistingSkills = 0;
    var skippedExistingMcpServers = 0;
    var skippedExistingModelChannels = 0;
    var skippedExistingChannelModels = 0;
    var skippedExistingDreamingJobs = 0;
    var skippedExistingDreamingReports = 0;
    var skippedExistingMediaJobs = 0;
    var skippedInvalidMessages = 0;
    var skippedInvalidAttachments = 0;
    var skippedInvalidChannelModels = 0;
    var skippedInvalidMediaJobs = snapshot.invalidMediaJobCount;

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
          capabilities: Value(jsonEncode(row.capabilities)),
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

      for (final row in snapshot.dreamingJobs) {
        final exists = await _recordExists('dreaming_jobs', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingDreamingJobs++;
          continue;
        }
        final companion = DreamingJobsCompanion.insert(
          id: row.id,
          dayKey: row.dayKey,
          scheduledFor: row.scheduledFor,
          status: Value(row.status),
          trigger: Value(row.trigger),
          messageLimit: Value(row.messageLimit),
          startedAt: Value(row.startedAt),
          finishedAt: Value(row.finishedAt),
          error: Value(_safeDiagnosticString(row.error)),
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
        );
        if (overwriteExisting) {
          await database
              .into(database.dreamingJobs)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.dreamingJobs)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredDreamingJobs++;
      }

      for (final row in snapshot.dreamingReports) {
        final exists =
            await _recordExists('dreaming_reports', row.id) ||
            await _recordExistsByText(
              'dreaming_reports',
              'day_key',
              row.dayKey,
            );
        if (exists && !overwriteExisting) {
          skippedExistingDreamingReports++;
          continue;
        }
        final jobId = await _existingReferenceOrNull(
          'dreaming_jobs',
          row.jobId,
        );
        final companion = DreamingReportsCompanion.insert(
          id: row.id,
          dayKey: row.dayKey,
          jobId: Value(jobId),
          generatedAt: row.generatedAt,
          markdown: row.markdown,
          digestJson: row.digestJson,
          sessionCount: row.sessionCount,
          originalMessageCount: row.originalMessageCount,
          totalOriginalMessageCount: row.totalOriginalMessageCount,
          memoryCandidateCount: row.memoryCandidateCount,
          isTruncated: Value(row.isTruncated),
          createdAt: row.createdAt,
        );
        await database
            .into(database.dreamingReports)
            .insert(
              companion,
              mode: overwriteExisting
                  ? InsertMode.insertOrReplace
                  : InsertMode.insertOrIgnore,
            );
        restoredDreamingReports++;
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
          isPinned: Value(row.isPinned),
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

      for (final row in snapshot.mediaJobs) {
        final exists = await _recordExists('media_jobs', row.id);
        if (exists && !overwriteExisting) {
          skippedExistingMediaJobs++;
          continue;
        }
        final sessionId = await _existingReferenceOrNull(
          'sessions',
          row.sessionId,
        );
        final companion = MediaJobsCompanion.insert(
          id: row.id,
          sessionId: Value(sessionId),
          kind: row.kind,
          provider: Value(row.provider),
          model: Value(row.model),
          endpoint: Value(row.endpoint),
          status: row.status,
          progress: Value(row.progress),
          phase: Value(row.phase),
          requestUrl: Value(row.requestUrl),
          providerJobId: Value(row.providerJobId),
          requestId: Value(row.requestId),
          pollUrl: Value(row.pollUrl),
          cancelUrl: Value(row.cancelUrl),
          contentUrl: Value(row.contentUrl),
          assetPath: Value(_restoreMediaAssetPath(row.assetPath)),
          assetMime: Value(row.assetMime),
          assetExtension: Value(row.assetExtension),
          prompt: Value(_safeDiagnosticString(row.prompt, maxLength: 4000)),
          error: Value(_safeDiagnosticString(row.error)),
          attempts: Value(row.attempts),
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          deadline: Value(row.deadline),
          endpointStyle: Value(row.endpointStyle),
          channelModelId: Value(row.channelModelId),
          deliveryUserMessageId: Value(row.deliveryUserMessageId),
          deliveryAssistantMessageId: Value(row.deliveryAssistantMessageId),
          deliveryAttachmentId: Value(row.deliveryAttachmentId),
          deliverySourceAttachmentId: Value(row.deliverySourceAttachmentId),
          deliveryPhase: Value(row.deliveryPhase),
          deliveryUserContent: Value(
            _safeDiagnosticString(row.deliveryUserContent, maxLength: 4000),
          ),
          deliveryAssistantContent: Value(
            _safeDiagnosticString(
              row.deliveryAssistantContent,
              maxLength: 4000,
            ),
          ),
          deliveryFileType: Value(row.deliveryFileType),
          deliverySourcePath: Value(
            _restoreMediaAssetPath(row.deliverySourcePath),
          ),
          deliverySourceFileName: Value(
            _safeDiagnosticString(row.deliverySourceFileName, maxLength: 256),
          ),
          deliverySourceFileType: Value(row.deliverySourceFileType),
        );
        if (overwriteExisting) {
          await database
              .into(database.mediaJobs)
              .insertOnConflictUpdate(companion);
        } else {
          await database
              .into(database.mediaJobs)
              .insert(companion, mode: InsertMode.insertOrIgnore);
        }
        restoredMediaJobs++;
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
      restoredDreamingJobs: restoredDreamingJobs,
      restoredDreamingReports: restoredDreamingReports,
      skippedExistingSessions: skippedExistingSessions,
      skippedExistingMessages: skippedExistingMessages,
      skippedExistingAttachments: skippedExistingAttachments,
      skippedExistingFolders: skippedExistingFolders,
      skippedExistingPrompts: skippedExistingPrompts,
      skippedExistingSkills: skippedExistingSkills,
      skippedExistingMcpServers: skippedExistingMcpServers,
      skippedExistingModelChannels: skippedExistingModelChannels,
      skippedExistingChannelModels: skippedExistingChannelModels,
      skippedExistingDreamingJobs: skippedExistingDreamingJobs,
      skippedExistingDreamingReports: skippedExistingDreamingReports,
      skippedInvalidMessages: skippedInvalidMessages,
      skippedInvalidAttachments: skippedInvalidAttachments,
      skippedInvalidChannelModels: skippedInvalidChannelModels,
      restoredMediaJobs: restoredMediaJobs,
      skippedExistingMediaJobs: skippedExistingMediaJobs,
      skippedInvalidMediaJobs: skippedInvalidMediaJobs,
    );
  }

  Map<String, Object?>? _exportMediaJob(MediaJob job) {
    final id = _safeMediaJobIdentifier(job.id);
    final kind = _safeMediaJobKind(job.kind);
    final status = _safeMediaJobStatus(job.status);
    if (id == null || kind == null || status == null) return null;

    return <String, Object?>{
      'id': id,
      'session_id': _safeConfigString(job.sessionId, maxLength: 256),
      'kind': kind,
      'provider': _safeConfigString(job.provider, maxLength: 256),
      'model': _safeConfigString(job.model, maxLength: 256),
      'endpoint': _safeConfigString(job.endpoint, maxLength: 512),
      'status': status,
      'progress': _safeMediaJobProgress(job.progress),
      'phase': _safeConfigString(job.phase, maxLength: 64),
      'request_url': _safeUrlString(job.requestUrl),
      'provider_job_id': _safeConfigString(job.providerJobId, maxLength: 512),
      'request_id': _safeConfigString(job.requestId, maxLength: 512),
      'poll_url': _safeUrlString(job.pollUrl),
      'cancel_url': _safeUrlString(job.cancelUrl),
      'content_url': _safeUrlString(job.contentUrl),
      'asset_path': _exportMediaAssetPath(job.assetPath),
      'asset_mime': _safeConfigString(job.assetMime, maxLength: 128),
      'asset_extension': _safeConfigString(job.assetExtension, maxLength: 32),
      'prompt': _safeDiagnosticString(job.prompt, maxLength: 4000),
      'error': _safeDiagnosticString(job.error),
      'attempts': job.attempts < 0 ? 0 : job.attempts,
      'created_at': _safeMediaJobTimestamp(job.createdAt),
      'updated_at': _safeMediaJobTimestamp(job.updatedAt),
      'deadline': _safeMediaJobOptionalTimestamp(job.deadline),
      'endpoint_style': _safeConfigString(job.endpointStyle, maxLength: 32),
      'channel_model_id': _safeDiagnosticString(
        job.channelModelId,
        maxLength: 256,
      ),
      'delivery_user_message_id': _safeDiagnosticString(
        job.deliveryUserMessageId,
        maxLength: 256,
      ),
      'delivery_assistant_message_id': _safeDiagnosticString(
        job.deliveryAssistantMessageId,
        maxLength: 256,
      ),
      'delivery_attachment_id': _safeDiagnosticString(
        job.deliveryAttachmentId,
        maxLength: 256,
      ),
      'delivery_source_attachment_id': _safeDiagnosticString(
        job.deliverySourceAttachmentId,
        maxLength: 256,
      ),
      'delivery_phase': _safeConfigString(job.deliveryPhase, maxLength: 64),
      'delivery_user_content': _safeDiagnosticString(
        job.deliveryUserContent,
        maxLength: 4000,
      ),
      'delivery_assistant_content': _safeDiagnosticString(
        job.deliveryAssistantContent,
        maxLength: 4000,
      ),
      'delivery_file_type': _safeConfigString(
        job.deliveryFileType,
        maxLength: 32,
      ),
      'delivery_source_path': _exportMediaAssetPath(job.deliverySourcePath),
      'delivery_source_file_name': _safeDiagnosticString(
        job.deliverySourceFileName,
        maxLength: 256,
      ),
      'delivery_source_file_type': _safeConfigString(
        job.deliverySourceFileType,
        maxLength: 32,
      ),
    };
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

  String? _exportMediaAssetPath(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) return null;
    final normalized = rawPath.trim();
    if (normalized.contains('\u0000') ||
        normalized.contains('?') ||
        normalized.contains('#')) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    final path = uri?.scheme == 'file' ? uri!.path : normalized;
    if (uri != null && uri.scheme.isNotEmpty && uri.scheme != 'file') {
      return null;
    }

    if (p.isAbsolute(path)) {
      final relative = p.relative(path, from: rootDirectory.path);
      return _normalizeRelativeMediaAssetPath(relative);
    }
    return _normalizeRelativeMediaAssetPath(path);
  }

  String? _restoreMediaAssetPath(String? relativePath) {
    final normalized = relativePath == null
        ? null
        : _normalizeRelativeMediaAssetPath(relativePath);
    if (normalized == null) return null;
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

  Future<bool> _recordExistsByText(
    String table,
    String column,
    String value,
  ) async {
    final row = await database
        .customSelect(
          'SELECT 1 FROM $table WHERE $column = ? LIMIT 1',
          variables: [Variable.withString(value)],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<int> _countExistingDreamingReports(
    Iterable<_SnapshotDreamingReport> reports,
  ) async {
    var count = 0;
    for (final report in reports) {
      if (await _recordExists('dreaming_reports', report.id) ||
          await _recordExistsByText(
            'dreaming_reports',
            'day_key',
            report.dayKey,
          )) {
        count++;
      }
    }
    return count;
  }

  Future<String?> _existingReferenceOrNull(String table, String? id) async {
    if (id == null || id.isEmpty) return null;
    return await _recordExists(table, id) ? id : null;
  }
}

String? _normalizeRelativeMediaAssetPath(String rawPath) {
  if (rawPath.startsWith('/') ||
      rawPath.contains('\\') ||
      rawPath.contains('\u0000') ||
      rawPath.contains('?') ||
      rawPath.contains('#')) {
    return null;
  }
  final uri = Uri.tryParse(rawPath);
  if (uri != null && uri.scheme.isNotEmpty) return null;
  final parts = p.posix
      .split(rawPath)
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty || parts.any((part) => part == '.' || part == '..')) {
    return null;
  }
  return parts.join('/');
}

String? _safeMediaJobIdentifier(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 256) return null;
  return _safeConfigString(normalized, maxLength: 256);
}

String? _safeMediaJobKind(String value) {
  final normalized = value.trim().toLowerCase();
  return _mediaJobKinds.contains(normalized) ? normalized : null;
}

String? _safeMediaJobStatus(String value) {
  final normalized = value.trim().toLowerCase();
  return _mediaJobStatuses.contains(normalized) ? normalized : null;
}

int? _safeMediaJobProgress(int? value) {
  if (value == null) return null;
  return value.clamp(0, 100).toInt();
}

int _safeMediaJobTimestamp(int value) => value < 0 ? 0 : value;

int? _safeMediaJobOptionalTimestamp(int? value) {
  if (value == null || value < 0) return null;
  return value;
}

const _mediaJobKinds = <String>{'image', 'video', 'music'};
const _mediaJobStatuses = <String>{
  'pending',
  'running',
  'completed',
  'failed',
  'expired',
  'cancelled',
};

_LocalDatabaseSnapshot _parseSnapshot(List<int> bytes) {
  final json = jsonDecode(utf8.decode(bytes));
  if (json is! Map<String, Object?> ||
      json['format'] != kLocalDatabaseSnapshotFormat) {
    throw const FormatException('本地数据库快照格式不受支持');
  }
  final mediaJobParse = _parseMediaJobs(_listOfMaps(json['media_jobs']));
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
    dreamingJobs: _listOfMaps(
      json['dreaming_jobs'],
    ).map(_SnapshotDreamingJob.fromJson).toList(growable: false),
    dreamingReports: _listOfMaps(
      json['dreaming_reports'],
    ).map(_SnapshotDreamingReport.fromJson).toList(growable: false),
    mediaJobs: mediaJobParse.jobs,
    invalidMediaJobCount: mediaJobParse.invalidCount,
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

_MediaJobParseResult _parseMediaJobs(List<Map<String, Object?>> values) {
  final jobs = <_SnapshotMediaJob>[];
  var invalidCount = 0;
  for (final value in values) {
    try {
      jobs.add(_SnapshotMediaJob.fromJson(value));
    } on FormatException {
      // 单条媒体任务损坏时跳过该条，保留同一快照中的其他数据。
      invalidCount++;
    }
  }
  return _MediaJobParseResult(jobs: jobs, invalidCount: invalidCount);
}

class _MediaJobParseResult {
  const _MediaJobParseResult({required this.jobs, required this.invalidCount});

  final List<_SnapshotMediaJob> jobs;
  final int invalidCount;
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

List<String> _stringListValue(
  Map<String, Object?> json,
  String key, {
  List<String> defaultValue = const <String>[],
}) {
  final value = json[key];
  if (value == null) return defaultValue;
  if (value is! List) throw FormatException('快照字段 $key 类型错误');
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int _intValue(Map<String, Object?> json, String key, {int defaultValue = 0}) {
  final value = json[key];
  if (value == null) return defaultValue;
  if (value is int) return value;
  throw FormatException('快照字段 $key 类型错误');
}

int? _nullableInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw FormatException('快照字段 $key 类型错误');
}

int _nonNegativeIntValue(
  Map<String, Object?> json,
  String key, {
  int defaultValue = 0,
}) {
  final value = _intValue(json, key, defaultValue: defaultValue);
  return value < 0 ? 0 : value;
}

int? _nullableNonNegativeIntValue(Map<String, Object?> json, String key) {
  final value = _nullableInt(json, key);
  if (value == null || value < 0) return null;
  return value;
}

String? _safeMediaJobNullableText(String? value, {required int maxLength}) {
  return _safeConfigString(value, maxLength: maxLength);
}

String? _safeMediaJobUrl(Map<String, Object?> json, String key) {
  return _safeUrlString(_nullableString(json, key));
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

String? _safeDiagnosticString(String? value, {int maxLength = 512}) {
  if (value == null) return null;
  var sanitized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (sanitized.isEmpty) return sanitized;
  sanitized = sanitized
      .replaceAll(
        RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        'Bearer ***',
      )
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{6,}'), 'sk-***')
      .replaceAll(RegExp(r'AIza[0-9A-Za-z_-]{10,}'), 'AIza***')
      .replaceAll(RegExp(r'xox[baprs]-[A-Za-z0-9-]+'), 'xox***')
      .replaceAll(
        RegExp(r'https?://[^\s，。；,;)]+', caseSensitive: false),
        '[链接]',
      )
      .replaceAll(RegExp(r'(/Users/|/var/|/private/)[^\s，。；,;)]+'), '[本机路径]');
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'([?&]?)(authorization|x-api-key|api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password|passwd|token)=([^&\s]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1) ?? ''}${match.group(2)}=***',
  );
  return sanitized.length <= maxLength
      ? sanitized
      : '${sanitized.substring(0, maxLength)}...';
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
    required this.dreamingJobs,
    required this.dreamingReports,
    required this.mediaJobs,
    required this.invalidMediaJobCount,
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
  final List<_SnapshotDreamingJob> dreamingJobs;
  final List<_SnapshotDreamingReport> dreamingReports;
  final List<_SnapshotMediaJob> mediaJobs;
  final int invalidMediaJobCount;
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
    required this.capabilities,
    required this.isDefault,
  });

  final String id;
  final String channelId;
  final String modelName;
  final String capability;
  final List<String> capabilities;
  final bool isDefault;

  factory _SnapshotChannelModel.fromJson(Map<String, Object?> json) {
    return _SnapshotChannelModel(
      id: _requiredString(json, 'id'),
      channelId: _requiredString(json, 'channel_id'),
      modelName: _requiredString(json, 'model_name'),
      capability: _nullableString(json, 'capability') ?? 'chat',
      capabilities: _stringListValue(json, 'capabilities'),
      isDefault: _boolValue(json, 'is_default'),
    );
  }
}

class _SnapshotDreamingJob {
  const _SnapshotDreamingJob({
    required this.id,
    required this.dayKey,
    required this.scheduledFor,
    required this.status,
    required this.trigger,
    required this.messageLimit,
    required this.startedAt,
    required this.finishedAt,
    required this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String dayKey;
  final int scheduledFor;
  final String status;
  final String trigger;
  final int messageLimit;
  final int? startedAt;
  final int? finishedAt;
  final String? error;
  final int createdAt;
  final int updatedAt;

  factory _SnapshotDreamingJob.fromJson(Map<String, Object?> json) {
    return _SnapshotDreamingJob(
      id: _requiredString(json, 'id'),
      dayKey: _requiredString(json, 'day_key'),
      scheduledFor: _intValue(json, 'scheduled_for'),
      status: _nullableString(json, 'status') ?? 'pending',
      trigger: _nullableString(json, 'trigger') ?? 'foreground',
      messageLimit: _intValue(json, 'message_limit', defaultValue: 5000),
      startedAt: json['started_at'] == null
          ? null
          : _intValue(json, 'started_at'),
      finishedAt: json['finished_at'] == null
          ? null
          : _intValue(json, 'finished_at'),
      error: _nullableString(json, 'error'),
      createdAt: _intValue(json, 'created_at'),
      updatedAt: _intValue(json, 'updated_at'),
    );
  }
}

class _SnapshotDreamingReport {
  const _SnapshotDreamingReport({
    required this.id,
    required this.dayKey,
    required this.jobId,
    required this.generatedAt,
    required this.markdown,
    required this.digestJson,
    required this.sessionCount,
    required this.originalMessageCount,
    required this.totalOriginalMessageCount,
    required this.memoryCandidateCount,
    required this.isTruncated,
    required this.createdAt,
  });

  final String id;
  final String dayKey;
  final String? jobId;
  final int generatedAt;
  final String markdown;
  final String digestJson;
  final int sessionCount;
  final int originalMessageCount;
  final int totalOriginalMessageCount;
  final int memoryCandidateCount;
  final bool isTruncated;
  final int createdAt;

  factory _SnapshotDreamingReport.fromJson(Map<String, Object?> json) {
    return _SnapshotDreamingReport(
      id: _requiredString(json, 'id'),
      dayKey: _requiredString(json, 'day_key'),
      jobId: _nullableString(json, 'job_id'),
      generatedAt: _intValue(json, 'generated_at'),
      markdown: _nullableString(json, 'markdown') ?? '',
      digestJson: _nullableString(json, 'digest_json') ?? '{}',
      sessionCount: _intValue(json, 'session_count'),
      originalMessageCount: _intValue(json, 'original_message_count'),
      totalOriginalMessageCount: _intValue(
        json,
        'total_original_message_count',
      ),
      memoryCandidateCount: _intValue(json, 'memory_candidate_count'),
      isTruncated: _boolValue(json, 'is_truncated'),
      createdAt: _intValue(json, 'created_at'),
    );
  }
}

class _SnapshotMediaJob {
  const _SnapshotMediaJob({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.provider,
    required this.model,
    required this.endpoint,
    required this.status,
    required this.progress,
    required this.phase,
    required this.requestUrl,
    required this.providerJobId,
    required this.requestId,
    required this.pollUrl,
    required this.cancelUrl,
    required this.contentUrl,
    required this.assetPath,
    required this.assetMime,
    required this.assetExtension,
    required this.prompt,
    required this.error,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    required this.deadline,
    required this.endpointStyle,
    required this.channelModelId,
    required this.deliveryUserMessageId,
    required this.deliveryAssistantMessageId,
    required this.deliveryAttachmentId,
    required this.deliverySourceAttachmentId,
    required this.deliveryPhase,
    required this.deliveryUserContent,
    required this.deliveryAssistantContent,
    required this.deliveryFileType,
    required this.deliverySourcePath,
    required this.deliverySourceFileName,
    required this.deliverySourceFileType,
  });

  final String id;
  final String? sessionId;
  final String kind;
  final String? provider;
  final String? model;
  final String? endpoint;
  final String status;
  final int? progress;
  final String? phase;
  final String? requestUrl;
  final String? providerJobId;
  final String? requestId;
  final String? pollUrl;
  final String? cancelUrl;
  final String? contentUrl;
  final String? assetPath;
  final String? assetMime;
  final String? assetExtension;
  final String? prompt;
  final String? error;
  final int attempts;
  final int createdAt;
  final int updatedAt;
  final int? deadline;
  final String? endpointStyle;
  final String? channelModelId;
  final String? deliveryUserMessageId;
  final String? deliveryAssistantMessageId;
  final String? deliveryAttachmentId;
  final String? deliverySourceAttachmentId;
  final String? deliveryPhase;
  final String? deliveryUserContent;
  final String? deliveryAssistantContent;
  final String? deliveryFileType;
  final String? deliverySourcePath;
  final String? deliverySourceFileName;
  final String? deliverySourceFileType;

  factory _SnapshotMediaJob.fromJson(Map<String, Object?> json) {
    final id = _safeMediaJobIdentifier(_requiredString(json, 'id'));
    if (id == null) {
      throw const FormatException('媒体任务 id 无效');
    }

    final kind = (_nullableString(json, 'kind') ?? 'image')
        .trim()
        .toLowerCase();
    if (!_mediaJobKinds.contains(kind)) {
      throw const FormatException('媒体任务类型不受支持');
    }
    final status = (_nullableString(json, 'status') ?? 'pending')
        .trim()
        .toLowerCase();
    if (!_mediaJobStatuses.contains(status)) {
      throw const FormatException('媒体任务状态不受支持');
    }

    final rawAssetPath = _nullableString(json, 'asset_path');
    final assetPath = rawAssetPath == null
        ? null
        : _normalizeRelativeMediaAssetPath(rawAssetPath);
    if (rawAssetPath != null && assetPath == null) {
      throw const FormatException('媒体任务资源路径不安全');
    }
    final rawDeliverySourcePath = _nullableString(json, 'delivery_source_path');
    final deliverySourcePath = rawDeliverySourcePath == null
        ? null
        : _normalizeRelativeMediaAssetPath(rawDeliverySourcePath);
    if (rawDeliverySourcePath != null && deliverySourcePath == null) {
      throw const FormatException('媒体任务交付源路径不安全');
    }

    return _SnapshotMediaJob(
      id: id,
      sessionId: _safeMediaJobNullableText(
        _nullableString(json, 'session_id'),
        maxLength: 256,
      ),
      kind: kind,
      provider: _safeMediaJobNullableText(
        _nullableString(json, 'provider'),
        maxLength: 256,
      ),
      model: _safeMediaJobNullableText(
        _nullableString(json, 'model'),
        maxLength: 256,
      ),
      endpoint: _safeMediaJobNullableText(
        _nullableString(json, 'endpoint'),
        maxLength: 512,
      ),
      status: status,
      progress: _safeMediaJobProgress(_nullableInt(json, 'progress')),
      phase: _safeMediaJobNullableText(
        _nullableString(json, 'phase'),
        maxLength: 64,
      ),
      requestUrl: _safeMediaJobUrl(json, 'request_url'),
      providerJobId: _safeMediaJobNullableText(
        _nullableString(json, 'provider_job_id'),
        maxLength: 512,
      ),
      requestId: _safeMediaJobNullableText(
        _nullableString(json, 'request_id'),
        maxLength: 512,
      ),
      pollUrl: _safeMediaJobUrl(json, 'poll_url'),
      cancelUrl: _safeMediaJobUrl(json, 'cancel_url'),
      contentUrl: _safeMediaJobUrl(json, 'content_url'),
      assetPath: assetPath,
      assetMime: _safeMediaJobNullableText(
        _nullableString(json, 'asset_mime'),
        maxLength: 128,
      ),
      assetExtension: _safeMediaJobNullableText(
        _nullableString(json, 'asset_extension'),
        maxLength: 32,
      ),
      prompt: _safeDiagnosticString(
        _nullableString(json, 'prompt'),
        maxLength: 4000,
      ),
      error: _safeDiagnosticString(_nullableString(json, 'error')),
      attempts: _nonNegativeIntValue(json, 'attempts'),
      createdAt: _nonNegativeIntValue(json, 'created_at'),
      updatedAt: _nonNegativeIntValue(json, 'updated_at'),
      deadline: _nullableNonNegativeIntValue(json, 'deadline'),
      endpointStyle: _safeMediaJobNullableText(
        _nullableString(json, 'endpoint_style') ?? 'auto',
        maxLength: 32,
      ),
      channelModelId: _safeDiagnosticString(
        _nullableString(json, 'channel_model_id'),
        maxLength: 256,
      ),
      deliveryUserMessageId: _safeDiagnosticString(
        _nullableString(json, 'delivery_user_message_id'),
        maxLength: 256,
      ),
      deliveryAssistantMessageId: _safeDiagnosticString(
        _nullableString(json, 'delivery_assistant_message_id'),
        maxLength: 256,
      ),
      deliveryAttachmentId: _safeDiagnosticString(
        _nullableString(json, 'delivery_attachment_id'),
        maxLength: 256,
      ),
      deliverySourceAttachmentId: _safeDiagnosticString(
        _nullableString(json, 'delivery_source_attachment_id'),
        maxLength: 256,
      ),
      deliveryPhase: _safeMediaJobNullableText(
        _nullableString(json, 'delivery_phase'),
        maxLength: 64,
      ),
      deliveryUserContent: _safeDiagnosticString(
        _nullableString(json, 'delivery_user_content'),
        maxLength: 4000,
      ),
      deliveryAssistantContent: _safeDiagnosticString(
        _nullableString(json, 'delivery_assistant_content'),
        maxLength: 4000,
      ),
      deliveryFileType: _safeMediaJobNullableText(
        _nullableString(json, 'delivery_file_type'),
        maxLength: 32,
      ),
      deliverySourcePath: deliverySourcePath,
      deliverySourceFileName: _safeDiagnosticString(
        _nullableString(json, 'delivery_source_file_name'),
        maxLength: 256,
      ),
      deliverySourceFileType: _safeMediaJobNullableText(
        _nullableString(json, 'delivery_source_file_type'),
        maxLength: 32,
      ),
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
    required this.isPinned,
  });

  final String id;
  final String userId;
  final String? title;
  final String? folderId;
  final int totalTokens;
  final int createdAt;
  final int lastMessageAt;
  final bool isPinned;

  factory _SnapshotSession.fromJson(Map<String, Object?> json) {
    return _SnapshotSession(
      id: _requiredString(json, 'id'),
      userId: _nullableString(json, 'user_id') ?? 'local',
      title: _nullableString(json, 'title'),
      folderId: _nullableString(json, 'folder_id'),
      totalTokens: _intValue(json, 'total_tokens'),
      createdAt: _intValue(json, 'created_at'),
      lastMessageAt: _intValue(json, 'last_message_at'),
      // 旧快照没有该字段，默认 false。
      isPinned: _boolValue(json, 'is_pinned'),
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
