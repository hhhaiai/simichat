import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'archive_attachment_path.dart';

const kObsidianVaultExportFormat = 'simichat.obsidian_vault.v1';
const kObsidianVaultSyncStateFormat = 'simichat.obsidian_sync_state.v1';
const _simichatVaultFolderName = 'SimiChat';
const _syncStateFileName = 'SimiChat-Sync-State.json';

typedef ObsidianAttachmentLoader =
    Future<List<ObsidianExportableAttachment>> Function();

class ObsidianVaultExportResult {
  const ObsidianVaultExportResult({
    required this.directory,
    required this.entries,
    required this.conversationCount,
    required this.audioTranscriptCount,
    required this.totalBytes,
  });

  final Directory directory;
  final List<ObsidianVaultEntry> entries;
  final int conversationCount;
  final int audioTranscriptCount;
  final int totalBytes;

  int get fileCount => entries.length;
}

class ObsidianVaultSyncResult {
  const ObsidianVaultSyncResult({
    required this.vaultDirectory,
    required this.simichatDirectory,
    required this.entries,
    required this.conflicts,
    required this.conversationCount,
    required this.audioTranscriptCount,
    required this.createdCount,
    required this.updatedCount,
    required this.unchangedCount,
    required this.deletedCount,
    required this.totalBytes,
  });

  final Directory vaultDirectory;
  final Directory simichatDirectory;
  final List<ObsidianVaultEntry> entries;
  final List<ObsidianVaultSyncConflict> conflicts;
  final int conversationCount;
  final int audioTranscriptCount;
  final int createdCount;
  final int updatedCount;
  final int unchangedCount;
  final int deletedCount;
  final int totalBytes;

  int get conflictCount => conflicts.length;
  int get fileCount => entries.length;
}

class ObsidianVaultSyncConflict {
  const ObsidianVaultSyncConflict({
    required this.path,
    required this.reason,
    required this.incomingSha256Hex,
    this.existingSha256Hex,
  });

  final String path;
  final String reason;
  final String incomingSha256Hex;
  final String? existingSha256Hex;
}

class ObsidianVaultEntry {
  const ObsidianVaultEntry({
    required this.path,
    required this.size,
    required this.sha256Hex,
    required this.kind,
  });

  final String path;
  final int size;
  final String sha256Hex;
  final String kind;
}

class ObsidianExportableAttachment {
  const ObsidianExportableAttachment({
    required this.id,
    required this.messageId,
    required this.fileType,
    required this.localPath,
    required this.fileName,
    required this.fileSize,
  });

  final String id;
  final String messageId;
  final String fileType;
  final String localPath;
  final String fileName;
  final int fileSize;
}

class ObsidianVaultExportService {
  const ObsidianVaultExportService({
    required this.rootDirectory,
    ObsidianAttachmentLoader? listAttachments,
    DateTime Function()? now,
  }) : _listAttachments = listAttachments,
       _now = now;

  final Directory rootDirectory;
  final ObsidianAttachmentLoader? _listAttachments;
  final DateTime Function()? _now;

  Directory get exportsDirectory =>
      Directory(p.join(rootDirectory.path, 'exports'));

  Future<ObsidianVaultExportResult> exportVault({
    Directory? outputDirectory,
    bool includeAudioAttachments = false,
  }) async {
    final createdAt = (_now ?? DateTime.now)().toUtc();
    final parent = outputDirectory ?? exportsDirectory;
    await parent.create(recursive: true);

    final vaultDir = Directory(
      p.join(parent.path, _vaultDirectoryName(createdAt)),
    );
    if (await vaultDir.exists()) {
      await vaultDir.delete(recursive: true);
    }
    await vaultDir.create(recursive: true);

    final attachmentEntries = await _collectAttachmentEntries(
      includeAudioAttachments: includeAudioAttachments,
    );
    final attachmentLinks = _buildAttachmentLinksByMessage(attachmentEntries);
    final pendingEntries = [
      ...await _collectMarkdownEntries(
        attachmentLinksByMessage: attachmentLinks,
      ),
      ...attachmentEntries,
    ]..sort((a, b) => a.path.compareTo(b.path));
    for (final pending in pendingEntries) {
      await _writeVaultFileBytes(vaultDir, pending.path, pending.bytes);
    }
    final copiedEntries =
        pendingEntries
            .map((pending) => pending.toEntry())
            .toList(growable: false)
          ..sort((a, b) => a.path.compareTo(b.path));

    final conversationCount = copiedEntries
        .where((entry) => entry.kind == 'conversation')
        .length;
    final transcriptCount = copiedEntries
        .where((entry) => entry.kind == 'audio_transcript')
        .length;

    final generatedEntries = <ObsidianVaultEntry>[];
    generatedEntries.add(
      await _writeVaultFile(
        vaultDir,
        'README.md',
        _renderReadme(createdAt, mode: 'standalone_export'),
        kind: 'readme',
      ),
    );
    generatedEntries.add(
      await _writeVaultFile(
        vaultDir,
        'SimiChat-Index.md',
        _renderIndex(
          createdAt: createdAt,
          entries: copiedEntries,
          conversationCount: conversationCount,
          audioTranscriptCount: transcriptCount,
          mode: 'standalone_export',
        ),
        kind: 'index',
      ),
    );
    generatedEntries.add(
      await _writeVaultFile(
        vaultDir,
        'SimiChat-Manifest.md',
        _renderManifest(
          createdAt: createdAt,
          entries: copiedEntries,
          conversationCount: conversationCount,
          audioTranscriptCount: transcriptCount,
          mode: 'standalone_export',
        ),
        kind: 'manifest',
      ),
    );

    final allEntries = [...generatedEntries, ...copiedEntries]
      ..sort((a, b) => a.path.compareTo(b.path));
    return ObsidianVaultExportResult(
      directory: vaultDir,
      entries: List.unmodifiable(allEntries),
      conversationCount: conversationCount,
      audioTranscriptCount: transcriptCount,
      totalBytes: allEntries.fold<int>(0, (sum, entry) => sum + entry.size),
    );
  }

  Future<ObsidianVaultSyncResult> syncToExistingVault({
    required Directory targetVaultDirectory,
    bool overwriteConflicts = false,
    bool includeAudioAttachments = false,
  }) async {
    final createdAt = (_now ?? DateTime.now)().toUtc();
    await _ensureSafeSyncTarget(targetVaultDirectory);
    await targetVaultDirectory.create(recursive: true);
    final simichatDir = Directory(
      p.join(targetVaultDirectory.path, _simichatVaultFolderName),
    );
    await simichatDir.create(recursive: true);

    final previousHashes = await _readPreviousSyncHashes(simichatDir);
    final attachmentEntries = await _collectAttachmentEntries(
      includeAudioAttachments: includeAudioAttachments,
    );
    final attachmentLinks = _buildAttachmentLinksByMessage(attachmentEntries);
    final pendingEntries = [
      ...await _collectMarkdownEntries(
        attachmentLinksByMessage: attachmentLinks,
      ),
      ...attachmentEntries,
    ]..sort((a, b) => a.path.compareTo(b.path));
    final sourceConversationCount = pendingEntries
        .where((entry) => entry.kind == 'conversation')
        .length;
    final sourceTranscriptCount = pendingEntries
        .where((entry) => entry.kind == 'audio_transcript')
        .length;

    final syncedEntries = <ObsidianVaultEntry>[];
    final conflicts = <ObsidianVaultSyncConflict>[];
    var createdCount = 0;
    var updatedCount = 0;
    var unchangedCount = 0;
    var deletedCount = 0;

    for (final pending in pendingEntries) {
      final outcome = await _syncPendingEntry(
        simichatDir,
        pending,
        previousSha256Hex: previousHashes[pending.path],
        overwriteConflicts: overwriteConflicts,
      );
      switch (outcome.status) {
        case _SyncWriteStatus.created:
          createdCount++;
          syncedEntries.add(pending.toEntry());
        case _SyncWriteStatus.updated:
          updatedCount++;
          syncedEntries.add(pending.toEntry());
        case _SyncWriteStatus.unchanged:
          unchangedCount++;
          syncedEntries.add(pending.toEntry());
        case _SyncWriteStatus.conflict:
          conflicts.add(
            ObsidianVaultSyncConflict(
              path: pending.path,
              reason: outcome.conflictReason ?? 'conflict',
              incomingSha256Hex: pending.sha256Hex,
              existingSha256Hex: outcome.existingSha256Hex,
            ),
          );
      }
    }

    deletedCount = await _deleteStaleSyncedEntries(
      simichatDir,
      previousHashes: previousHashes,
      currentPaths: pendingEntries.map((entry) => entry.path).toSet(),
      conflicts: conflicts,
    );

    syncedEntries.sort((a, b) => a.path.compareTo(b.path));
    final generatedEntries = <ObsidianVaultEntry>[];
    generatedEntries.add(
      await _writeVaultFile(
        simichatDir,
        'README.md',
        _renderReadme(createdAt, mode: 'existing_vault_sync'),
        kind: 'readme',
      ),
    );
    generatedEntries.add(
      await _writeVaultFile(
        simichatDir,
        'SimiChat-Index.md',
        _renderIndex(
          createdAt: createdAt,
          entries: syncedEntries,
          conversationCount: sourceConversationCount,
          audioTranscriptCount: sourceTranscriptCount,
          mode: 'existing_vault_sync',
          conflictCount: conflicts.length,
          deletedCount: deletedCount,
        ),
        kind: 'index',
      ),
    );
    generatedEntries.add(
      await _writeVaultFile(
        simichatDir,
        'SimiChat-Manifest.md',
        _renderManifest(
          createdAt: createdAt,
          entries: syncedEntries,
          conversationCount: sourceConversationCount,
          audioTranscriptCount: sourceTranscriptCount,
          mode: 'existing_vault_sync',
          conflictCount: conflicts.length,
          deletedCount: deletedCount,
        ),
        kind: 'manifest',
      ),
    );
    generatedEntries.add(
      await _writeVaultFile(
        simichatDir,
        _syncStateFileName,
        _renderSyncStateJson(
          createdAt: createdAt,
          entries: syncedEntries,
          conflicts: conflicts,
          deletedCount: deletedCount,
        ),
        kind: 'sync_state',
      ),
    );

    final allEntries = [...generatedEntries, ...syncedEntries]
      ..sort((a, b) => a.path.compareTo(b.path));
    return ObsidianVaultSyncResult(
      vaultDirectory: targetVaultDirectory,
      simichatDirectory: simichatDir,
      entries: List.unmodifiable(allEntries),
      conflicts: List.unmodifiable(conflicts),
      conversationCount: sourceConversationCount,
      audioTranscriptCount: sourceTranscriptCount,
      createdCount: createdCount,
      updatedCount: updatedCount,
      unchangedCount: unchangedCount,
      deletedCount: deletedCount,
      totalBytes: allEntries.fold<int>(0, (sum, entry) => sum + entry.size),
    );
  }

  Future<List<_PendingObsidianVaultFile>> _collectMarkdownEntries({
    required _AttachmentLinksByMessage attachmentLinksByMessage,
  }) async {
    final entries = <_PendingObsidianVaultFile>[];
    entries.addAll(
      await _collectMarkdownDirectory(
        sourceDir: Directory(p.join(rootDirectory.path, 'conversations')),
        targetPrefix: 'Conversations',
        kind: 'conversation',
        attachmentLinksByMessage: attachmentLinksByMessage,
      ),
    );
    entries.addAll(
      await _collectMarkdownDirectory(
        sourceDir: Directory(p.join(rootDirectory.path, 'audio_transcripts')),
        targetPrefix: 'Audio Transcripts',
        kind: 'audio_transcript',
        attachmentLinksByMessage: const {},
      ),
    );
    return entries;
  }

  Future<List<_PendingObsidianVaultFile>> _collectMarkdownDirectory({
    required Directory sourceDir,
    required String targetPrefix,
    required String kind,
    required _AttachmentLinksByMessage attachmentLinksByMessage,
  }) async {
    if (!await sourceDir.exists()) return const [];
    final entries = <_PendingObsidianVaultFile>[];
    await for (final entity in sourceDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final entityType = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (entityType != FileSystemEntityType.file) continue;
      if (p.extension(entity.path).toLowerCase() != '.md') continue;

      final relativePath = p.relative(entity.path, from: sourceDir.path);
      final normalizedRelativePath = _normalizeRelativePath(relativePath);
      if (normalizedRelativePath == null) continue;

      final vaultPath = _normalizeRelativePath(
        p.posix.join(targetPrefix, normalizedRelativePath),
      );
      if (vaultPath == null) continue;

      var bytes = await entity.readAsBytes();
      if (attachmentLinksByMessage.isNotEmpty) {
        bytes = utf8.encode(
          _rewriteAttachmentLinks(
            utf8.decode(bytes, allowMalformed: true),
            attachmentLinksByMessage,
          ),
        );
      }
      entries.add(
        _PendingObsidianVaultFile(path: vaultPath, bytes: bytes, kind: kind),
      );
    }
    return entries;
  }

  Future<List<_PendingObsidianVaultFile>> _collectAttachmentEntries({
    required bool includeAudioAttachments,
  }) async {
    final loader = _listAttachments;
    if (loader == null) return const [];

    final rootCanonical = _canonicalPath(rootDirectory.path);
    final exportsCanonical = _canonicalPath(
      p.join(rootDirectory.path, 'exports'),
    );
    final attachments = await loader();
    final usedPaths = <String>{};
    final entries = <_PendingObsidianVaultFile>[];

    for (final attachment in attachments) {
      if (!includeAudioAttachments &&
          attachment.fileType.toLowerCase() == 'audio') {
        continue;
      }

      final source = File(attachment.localPath);
      final entityType = await FileSystemEntity.type(
        source.path,
        followLinks: false,
      );
      if (entityType != FileSystemEntityType.file) continue;

      late final String sourceCanonical;
      try {
        sourceCanonical = source.resolveSymbolicLinksSync();
      } catch (_) {
        continue;
      }
      if (_isWithinOrSame(sourceCanonical, exportsCanonical)) continue;
      if (p.equals(sourceCanonical, rootCanonical)) continue;

      final bytes = await source.readAsBytes();
      final archivePath = _dedupeObsidianPath(
        _obsidianAttachmentPath(attachment),
        usedPaths,
      );
      entries.add(
        _PendingObsidianVaultFile(
          path: archivePath,
          bytes: bytes,
          kind: 'attachment',
          messageId: attachment.messageId,
          fileName: _escapeInlineAttachmentName(attachment.fileName),
        ),
      );
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Future<_SyncWriteOutcome> _syncPendingEntry(
    Directory targetRoot,
    _PendingObsidianVaultFile pending, {
    required String? previousSha256Hex,
    required bool overwriteConflicts,
  }) async {
    final output = _resolveVaultFile(targetRoot, pending.path);
    await output.parent.create(recursive: true);
    final existingType = await FileSystemEntity.type(
      output.path,
      followLinks: false,
    );
    if (existingType == FileSystemEntityType.notFound) {
      await _writeVaultFileBytes(targetRoot, pending.path, pending.bytes);
      return const _SyncWriteOutcome(_SyncWriteStatus.created);
    }
    if (existingType != FileSystemEntityType.file) {
      return _SyncWriteOutcome(
        _SyncWriteStatus.conflict,
        conflictReason: 'unsafe_existing_entity',
      );
    }

    final existingBytes = await output.readAsBytes();
    final existingHash = sha256.convert(existingBytes).toString();
    if (existingHash == pending.sha256Hex) {
      return _SyncWriteOutcome(
        _SyncWriteStatus.unchanged,
        existingSha256Hex: existingHash,
      );
    }

    final canSafelyUpdate =
        overwriteConflicts ||
        (previousSha256Hex != null && existingHash == previousSha256Hex);
    if (!canSafelyUpdate) {
      return _SyncWriteOutcome(
        _SyncWriteStatus.conflict,
        conflictReason: 'target_modified',
        existingSha256Hex: existingHash,
      );
    }

    await _writeVaultFileBytes(targetRoot, pending.path, pending.bytes);
    return _SyncWriteOutcome(
      _SyncWriteStatus.updated,
      existingSha256Hex: existingHash,
    );
  }

  Future<int> _deleteStaleSyncedEntries(
    Directory targetRoot, {
    required Map<String, String> previousHashes,
    required Set<String> currentPaths,
    required List<ObsidianVaultSyncConflict> conflicts,
  }) async {
    var deletedCount = 0;
    final stalePaths =
        previousHashes.keys
            .where((path) => !currentPaths.contains(path))
            .toList(growable: false)
          ..sort();

    for (final stalePath in stalePaths) {
      final previousSha256Hex = previousHashes[stalePath];
      if (previousSha256Hex == null) continue;
      final output = _resolveVaultFile(targetRoot, stalePath);
      final existingType = await FileSystemEntity.type(
        output.path,
        followLinks: false,
      );
      if (existingType == FileSystemEntityType.notFound) continue;
      if (existingType != FileSystemEntityType.file) {
        conflicts.add(
          ObsidianVaultSyncConflict(
            path: stalePath,
            reason: 'stale_unsafe_existing_entity',
            incomingSha256Hex: previousSha256Hex,
          ),
        );
        continue;
      }

      final existingBytes = await output.readAsBytes();
      final existingSha256Hex = sha256.convert(existingBytes).toString();
      if (existingSha256Hex != previousSha256Hex) {
        conflicts.add(
          ObsidianVaultSyncConflict(
            path: stalePath,
            reason: 'source_removed_target_modified',
            incomingSha256Hex: previousSha256Hex,
            existingSha256Hex: existingSha256Hex,
          ),
        );
        continue;
      }

      await output.delete();
      deletedCount++;
    }

    return deletedCount;
  }

  Future<ObsidianVaultEntry> _writeVaultFile(
    Directory vaultDir,
    String relativePath,
    String content, {
    required String kind,
  }) async {
    final bytes = utf8.encode(content);
    await _writeVaultFileBytes(vaultDir, relativePath, bytes);
    final normalized = _normalizeRelativePath(relativePath)!;
    return ObsidianVaultEntry(
      path: normalized,
      size: bytes.length,
      sha256Hex: sha256.convert(bytes).toString(),
      kind: kind,
    );
  }

  Future<void> _writeVaultFileBytes(
    Directory vaultDir,
    String relativePath,
    List<int> bytes,
  ) async {
    final output = _resolveVaultFile(vaultDir, relativePath);
    await output.parent.create(recursive: true);
    final existingType = await FileSystemEntity.type(
      output.path,
      followLinks: false,
    );
    if (existingType != FileSystemEntityType.notFound &&
        existingType != FileSystemEntityType.file) {
      throw StateError('Unsafe Obsidian target path: $relativePath');
    }
    await output.writeAsBytes(bytes, flush: true);
  }

  File _resolveVaultFile(Directory vaultDir, String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Unsafe path');
    }
    return File(p.joinAll([vaultDir.path, ...p.posix.split(normalized)]));
  }

  Future<Map<String, String>> _readPreviousSyncHashes(
    Directory simichatDir,
  ) async {
    final file = File(p.join(simichatDir.path, _syncStateFileName));
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file) return const {};
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['format'] != kObsidianVaultSyncStateFormat) {
        return const {};
      }
      final entries = raw['entries'];
      if (entries is! List) return const {};
      final result = <String, String>{};
      for (final entry in entries) {
        if (entry is! Map) continue;
        final path = entry['path'];
        final sha = entry['sha256'];
        if (path is! String || sha is! String) continue;
        final normalized = _normalizeRelativePath(path);
        if (normalized == null) continue;
        result[normalized] = sha;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _ensureSafeSyncTarget(Directory targetVaultDirectory) async {
    final targetPath = _canonicalPath(targetVaultDirectory.path);
    final sourceDirs = [
      Directory(p.join(rootDirectory.path, 'conversations')),
      Directory(p.join(rootDirectory.path, 'audio_transcripts')),
    ];
    for (final source in sourceDirs) {
      if (!await source.exists()) continue;
      final sourcePath = _canonicalPath(source.path);
      if (_isWithinOrSame(targetPath, sourcePath)) {
        throw ArgumentError.value(
          targetVaultDirectory.path,
          'targetVaultDirectory',
          'Target vault must not be inside SimiChat source archives',
        );
      }
    }
  }
}

class _PendingObsidianVaultFile {
  _PendingObsidianVaultFile({
    required this.path,
    required this.bytes,
    required this.kind,
    this.messageId,
    this.fileName,
  }) : sha256Hex = sha256.convert(bytes).toString();

  final String path;
  final List<int> bytes;
  final String kind;
  final String? messageId;
  final String? fileName;
  final String sha256Hex;

  ObsidianVaultEntry toEntry() {
    return ObsidianVaultEntry(
      path: path,
      size: bytes.length,
      sha256Hex: sha256Hex,
      kind: kind,
    );
  }
}

enum _SyncWriteStatus { created, updated, unchanged, conflict }

class _SyncWriteOutcome {
  const _SyncWriteOutcome(
    this.status, {
    this.conflictReason,
    this.existingSha256Hex,
  });

  final _SyncWriteStatus status;
  final String? conflictReason;
  final String? existingSha256Hex;
}

typedef _AttachmentLinksByMessage = Map<String, Map<String, List<String>>>;

_AttachmentLinksByMessage _buildAttachmentLinksByMessage(
  List<_PendingObsidianVaultFile> attachmentEntries,
) {
  final result = <String, Map<String, List<String>>>{};
  for (final entry in attachmentEntries) {
    if (entry.kind != 'attachment') continue;
    final messageId = entry.messageId;
    final fileName = entry.fileName;
    if (messageId == null || fileName == null) continue;
    final byName = result.putIfAbsent(
      messageId,
      () => <String, List<String>>{},
    );
    byName.putIfAbsent(fileName, () => <String>[]).add(entry.path);
  }
  return result;
}

String _rewriteAttachmentLinks(
  String content,
  _AttachmentLinksByMessage attachmentLinksByMessage,
) {
  if (attachmentLinksByMessage.isEmpty) return content;

  final lines = content.split('\n');
  final output = <String>[];
  final consumedLinksByMessage = <String, Map<String, int>>{};
  final messageIdPattern = RegExp(r'^<!-- simichat-message-id: ([^ ]+) -->$');
  final attachmentItemPattern = RegExp(r'^(\s{2}- )(.*)$');
  String? currentMessageId;
  var inAttachmentList = false;

  for (final line in lines) {
    final messageMatch = messageIdPattern.firstMatch(line);
    if (messageMatch != null) {
      currentMessageId = messageMatch.group(1);
      inAttachmentList = false;
      output.add(line);
      continue;
    }

    if (line == '- attachments:') {
      inAttachmentList = true;
      output.add(line);
      continue;
    }

    if (inAttachmentList) {
      final itemMatch = attachmentItemPattern.firstMatch(line);
      if (itemMatch != null && currentMessageId != null) {
        final prefix = itemMatch.group(1)!;
        final fileName = itemMatch.group(2)!;
        final links = attachmentLinksByMessage[currentMessageId]?[fileName];
        if (links != null && links.isNotEmpty) {
          final consumedByName = consumedLinksByMessage.putIfAbsent(
            currentMessageId,
            () => <String, int>{},
          );
          final linkIndex = consumedByName[fileName] ?? 0;
          if (linkIndex >= links.length) {
            output.add(line);
            continue;
          }
          consumedByName[fileName] = linkIndex + 1;
          final linkTarget = links[linkIndex];
          output.add('$prefix${_obsidianFileLink(linkTarget, fileName)}');
          continue;
        }
      } else if (!line.startsWith('  ')) {
        inAttachmentList = false;
      }
    }

    output.add(line);
  }

  return output.join('\n');
}

String _obsidianAttachmentPath(ObsidianExportableAttachment attachment) {
  final archivePath = buildAttachmentArchivePath(
    attachmentId: attachment.id,
    messageId: attachment.messageId,
    fileName: attachment.fileName,
  );
  final withoutRoot = archivePath.startsWith('attachments/')
      ? archivePath.substring('attachments/'.length)
      : archivePath;
  final normalized = _normalizeRelativePath(
    p.posix.join('Attachments', withoutRoot),
  );
  if (normalized == null) {
    throw ArgumentError.value(archivePath, 'attachment', 'Unsafe path');
  }
  return normalized;
}

String _dedupeObsidianPath(String path, Set<String> usedPaths) {
  var candidate = path;
  if (usedPaths.add(candidate)) return candidate;
  final dir = p.posix.dirname(path);
  final extension = p.posix.extension(path);
  final stem = p.posix.basenameWithoutExtension(path);
  for (var i = 2; ; i++) {
    candidate = p.posix.join(dir, '$stem-$i$extension');
    if (usedPaths.add(candidate)) return candidate;
  }
}

String _renderReadme(DateTime createdAt, {required String mode}) {
  return '''# SimiChat Obsidian Vault

- format: `$kObsidianVaultExportFormat`
- generated_at: `${createdAt.toIso8601String()}`
- mode: `$mode`
- privacy: `local_only`

这是从 SimiChat 本机数据生成的 Obsidian 兼容 Markdown Vault。它复制会话 Markdown、语音转写 Markdown 和可安全读取的非语音附件原文件，不包含模型 API Key、渠道密钥、MCP headers、数据库原始文件或本机绝对路径。

> 注意：Vault 中包含用户主动导出的聊天正文和转写正文；分享给外部应用或他人前，请自行确认内容是否适合外发。

入口：[[SimiChat-Index]]
''';
}

String _renderIndex({
  required DateTime createdAt,
  required List<ObsidianVaultEntry> entries,
  required int conversationCount,
  required int audioTranscriptCount,
  required String mode,
  int conflictCount = 0,
  int deletedCount = 0,
}) {
  final conversations = entries
      .where((entry) => entry.kind == 'conversation')
      .toList(growable: false);
  final transcripts = entries
      .where((entry) => entry.kind == 'audio_transcript')
      .toList(growable: false);
  final attachments = entries
      .where((entry) => entry.kind == 'attachment')
      .toList(growable: false);
  final buffer = StringBuffer()
    ..writeln('# SimiChat 导出索引')
    ..writeln()
    ..writeln('- format: `$kObsidianVaultExportFormat`')
    ..writeln('- generated_at: `${createdAt.toIso8601String()}`')
    ..writeln('- mode: `$mode`')
    ..writeln('- conversations: `$conversationCount`')
    ..writeln('- audio_transcripts: `$audioTranscriptCount`')
    ..writeln('- attachments: `${attachments.length}`')
    ..writeln('- sync_conflicts: `$conflictCount`')
    ..writeln('- sync_deleted: `$deletedCount`')
    ..writeln('- contains_api_keys: `false`')
    ..writeln('- contains_absolute_paths: `false`')
    ..writeln()
    ..writeln('## 会话')
    ..writeln();
  if (conversations.isEmpty) {
    buffer.writeln('_暂无会话 Markdown。_');
  } else {
    for (final entry in conversations) {
      buffer.writeln('- ${_obsidianLink(entry.path)}');
    }
  }
  buffer
    ..writeln()
    ..writeln('## 语音转写')
    ..writeln();
  if (transcripts.isEmpty) {
    buffer.writeln('_暂无语音转写 Markdown。_');
  } else {
    for (final entry in transcripts) {
      buffer.writeln('- ${_obsidianLink(entry.path)}');
    }
  }
  buffer
    ..writeln()
    ..writeln('## 附件')
    ..writeln();
  if (attachments.isEmpty) {
    buffer.writeln('_暂无可同步附件。_');
  } else {
    for (final entry in attachments) {
      buffer.writeln(
        '- ${_obsidianFileLink(entry.path, p.posix.basename(entry.path))}',
      );
    }
  }
  return buffer.toString();
}

String _renderManifest({
  required DateTime createdAt,
  required List<ObsidianVaultEntry> entries,
  required int conversationCount,
  required int audioTranscriptCount,
  required String mode,
  int conflictCount = 0,
  int deletedCount = 0,
}) {
  final attachmentCount = entries
      .where((entry) => entry.kind == 'attachment')
      .length;
  final buffer = StringBuffer()
    ..writeln('# SimiChat Vault Manifest')
    ..writeln()
    ..writeln('- format: `$kObsidianVaultExportFormat`')
    ..writeln('- generated_at: `${createdAt.toIso8601String()}`')
    ..writeln('- mode: `$mode`')
    ..writeln('- conversations: `$conversationCount`')
    ..writeln('- audio_transcripts: `$audioTranscriptCount`')
    ..writeln('- attachments: `$attachmentCount`')
    ..writeln('- sync_conflicts: `$conflictCount`')
    ..writeln('- sync_deleted: `$deletedCount`')
    ..writeln('- contains_api_keys: `false`')
    ..writeln('- contains_absolute_paths: `false`')
    ..writeln()
    ..writeln('| Path | Kind | Bytes | SHA-256 |')
    ..writeln('| --- | --- | ---: | --- |');
  for (final entry in entries) {
    buffer.writeln(
      '| `${_escapeTableCell(entry.path)}` | `${entry.kind}` | ${entry.size} | `${entry.sha256Hex}` |',
    );
  }
  return buffer.toString();
}

String _renderSyncStateJson({
  required DateTime createdAt,
  required List<ObsidianVaultEntry> entries,
  required List<ObsidianVaultSyncConflict> conflicts,
  required int deletedCount,
}) {
  final payload = <String, Object?>{
    'format': kObsidianVaultSyncStateFormat,
    'generated_at': createdAt.toIso8601String(),
    'contains_api_keys': false,
    'contains_absolute_paths': false,
    'deleted_count': deletedCount,
    'entries': entries
        .where(
          (entry) =>
              entry.kind == 'conversation' ||
              entry.kind == 'audio_transcript' ||
              entry.kind == 'attachment',
        )
        .map(
          (entry) => <String, Object?>{
            'path': entry.path,
            'kind': entry.kind,
            'bytes': entry.size,
            'sha256': entry.sha256Hex,
          },
        )
        .toList(growable: false),
    'conflicts': conflicts
        .map(
          (conflict) => <String, Object?>{
            'path': conflict.path,
            'reason': conflict.reason,
            'incoming_sha256': conflict.incomingSha256Hex,
            'existing_sha256': conflict.existingSha256Hex,
          },
        )
        .toList(growable: false),
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

String _vaultDirectoryName(DateTime createdAt) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'obsidian-vault-${createdAt.year}'
      '${two(createdAt.month)}${two(createdAt.day)}-'
      '${two(createdAt.hour)}${two(createdAt.minute)}${two(createdAt.second)}';
}

String? _normalizeRelativePath(String rawPath) {
  if (rawPath.startsWith('/') || rawPath.contains('\\')) return null;
  final parts = p.posix
      .split(rawPath.replaceAll(p.separator, '/'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.any((part) => part == '.' || part == '..')) return null;
  return parts.join('/');
}

String _obsidianLink(String markdownPath) {
  final withoutExtension = markdownPath.toLowerCase().endsWith('.md')
      ? markdownPath.substring(0, markdownPath.length - 3)
      : markdownPath;
  final label = p.posix.basenameWithoutExtension(markdownPath);
  return '[[${_escapeWikiLinkTarget(withoutExtension)}|${_escapeWikiLinkLabel(label)}]]';
}

String _obsidianFileLink(String relativePath, String label) {
  return '[[${_escapeWikiLinkTarget(relativePath)}|${_escapeWikiLinkLabel(label)}]]';
}

String _escapeInlineAttachmentName(String value) => value.replaceAll('\n', ' ');

String _escapeWikiLinkTarget(String value) {
  return value.replaceAll('|', '｜').replaceAll(']', '］');
}

String _escapeWikiLinkLabel(String value) {
  return value.replaceAll('|', '｜').replaceAll(']', '］');
}

String _escapeTableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

String _canonicalPath(String rawPath) {
  final absolute = p.normalize(p.absolute(rawPath));
  try {
    return Directory(absolute).resolveSymbolicLinksSync();
  } catch (_) {
    final parts = p.split(absolute);
    for (var i = parts.length - 1; i > 0; i--) {
      final existingPrefix = p.joinAll(parts.take(i));
      if (!Directory(existingPrefix).existsSync()) continue;
      try {
        final resolvedPrefix = Directory(
          existingPrefix,
        ).resolveSymbolicLinksSync();
        return p.normalize(p.joinAll([resolvedPrefix, ...parts.skip(i)]));
      } catch (_) {
        break;
      }
    }
    // The target vault may not exist yet and no parent could be resolved. Fall
    // back to a normalized absolute path; callers still create the directory
    // before writing any file.
  }
  return absolute;
}

bool _isWithinOrSame(String childPath, String parentPath) {
  final relative = p.relative(childPath, from: parentPath);
  return relative == '.' ||
      (!relative.startsWith('..${p.separator}') && relative != '..');
}
