import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'attachment_export_service.dart';
import 'large_paste_policy.dart';

/// 文本附件的来源。首版只自动创建 [largePaste]，保留 enum 是为了未来区分
/// “用户手动从文件选择器添加”与“Composer 自动归档”的展示和降级策略。
enum PastedTextAttachmentSource { largePaste }

/// 绑定某个会话草稿的大粘贴文本附件。
///
/// 这是 UI/网络层共用的本地元数据；原始内容永远只存在 [localPath] 指向的
/// 应用私有 UTF-8 文件，既不存入 SharedPreferences，也不会写进日志。
class PastedTextAttachment {
  const PastedTextAttachment({
    required this.id,
    required this.conversationId,
    required this.draftId,
    required this.localPath,
    required this.displayName,
    required this.mimeType,
    required this.source,
    required this.characterCount,
    required this.utf8ByteCount,
    required this.estimatedTokens,
    required this.sha256,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String draftId;
  final String localPath;
  final String displayName;
  final String mimeType;
  final PastedTextAttachmentSource source;
  final int characterCount;
  final int utf8ByteCount;
  final int estimatedTokens;
  final String sha256;
  final DateTime createdAt;

  PastedTextAttachment copyWith({String? localPath, String? displayName}) =>
      PastedTextAttachment(
        id: id,
        conversationId: conversationId,
        draftId: draftId,
        localPath: localPath ?? this.localPath,
        displayName: displayName ?? this.displayName,
        mimeType: mimeType,
        source: source,
        characterCount: characterCount,
        utf8ByteCount: utf8ByteCount,
        estimatedTokens: estimatedTokens,
        sha256: sha256,
        createdAt: createdAt,
      );
}

/// 把单次大粘贴按 UTF-8 原样落到 [AttachmentDraftArchive] 的小型服务。
///
/// 文件名生成、hash、计数和删除都集中于此，让 Widget 只处理插入区间、提示
/// 和附件卡片。可注入 [clock] 以保证文件名与测试可复现。
class PastedTextAttachmentService {
  PastedTextAttachmentService({
    required AttachmentDraftArchive archive,
    DateTime Function()? clock,
  }) : _archive = archive,
       _clock = clock ?? DateTime.now;

  final AttachmentDraftArchive _archive;
  final DateTime Function() _clock;
  final Map<String, int> _sameSecondNameCounts = <String, int>{};

  Future<PastedTextAttachment> create({
    required String conversationId,
    required String draftId,
    required String text,
    required LargePasteDecision decision,
  }) async {
    final now = _clock();
    final extension = inferPastedTextExtension(text);
    final displayName = _nextDisplayName(now, extension);
    final bytes = utf8.encode(text);
    final archived = await _archive.archiveBytes(
      bytes: bytes,
      fileName: displayName,
      sessionId: conversationId,
    );
    return PastedTextAttachment(
      id: archived.id,
      conversationId: conversationId,
      draftId: draftId,
      localPath: archived.path,
      displayName: displayName,
      mimeType: extension == 'md'
          ? 'text/markdown; charset=utf-8'
          : 'text/plain; charset=utf-8',
      source: PastedTextAttachmentSource.largePaste,
      characterCount: decision.characterCount,
      utf8ByteCount: decision.utf8ByteCount,
      estimatedTokens: decision.estimatedTokens,
      sha256: sha256.convert(bytes).toString(),
      createdAt: now,
    );
  }

  Future<String> readText(PastedTextAttachment attachment) async {
    final file = File(attachment.localPath);
    if (!await file.exists()) {
      throw const FileSystemException('大粘贴附件不存在或已被清理');
    }
    // UTF-8 文件是本服务唯一的写入格式。allowMalformed=false 避免把损坏的
    // 草稿悄悄替换为 U+FFFD 并随后发送给模型。
    return file.readAsString(encoding: utf8);
  }

  Future<PastedTextAttachment> rename(
    PastedTextAttachment attachment,
    String requestedName,
  ) async {
    final displayName = _normalizeDisplayName(
      requestedName,
      fallbackExtension: _extensionForMimeType(attachment.mimeType),
    );
    final localPath = await _archive.renameFile(
      path: attachment.localPath,
      fileName: displayName,
    );
    return attachment.copyWith(localPath: localPath, displayName: displayName);
  }

  Future<void> delete(PastedTextAttachment attachment) =>
      _archive.deleteFile(attachment.localPath);

  String _nextDisplayName(DateTime now, String extension) {
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final base = 'pasted-content-$timestamp';
    final key = '$base.$extension';
    final sequence = (_sameSecondNameCounts[key] ?? 0) + 1;
    _sameSecondNameCounts[key] = sequence;
    return sequence == 1 ? key : '$base-$sequence.$extension';
  }

  String _normalizeDisplayName(
    String requestedName, {
    required String fallbackExtension,
  }) {
    final slashNormalized = requestedName.replaceAll('\\', '/').trim();
    final basename = slashNormalized
        .split('/')
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .lastOrNull;
    final normalized = basename?.trim() ?? '';
    if (normalized.isEmpty) return 'pasted-content.$fallbackExtension';
    // 不允许显示名中携带路径或控制字符；Unicode 文本保留为用户可见名称。
    final cleaned = normalized.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '_');
    if (cleaned.contains('.')) return cleaned;
    return '$cleaned.$fallbackExtension';
  }

  String _extensionForMimeType(String mimeType) =>
      mimeType.toLowerCase().contains('markdown') ? 'md' : 'txt';
}
