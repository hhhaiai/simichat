import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../archive/archive_attachment_path.dart';
import '../attachments/attachment_policy.dart';
import '../storage/atomic_file_writer.dart';

const _attachmentArchiveUuid = Uuid();

/// Composer 选择后的附件副本。
///
/// picker 返回的路径可能位于系统 cache、外部相册 provider 或录音插件的
/// 临时目录。这个对象只描述已经复制到应用私有 draft 目录的文件，发送前
/// 始终使用 [path]，不会再回读 picker 的原始路径。
class ArchivedDraftAttachment {
  final String id;
  final String path;
  final String fileName;
  final int fileSize;

  const ArchivedDraftAttachment({
    required this.id,
    required this.path,
    required this.fileName,
    required this.fileSize,
  });
}

/// 将 composer 附件复制到应用私有的、按会话分隔的 draft 目录。
///
/// 这里不使用 temporary directory：系统可以随时清理 cache，而 draft 必须
/// 在用户切换会话、等待发送或应用被系统回收后仍然可读。所有写入都走原子
/// copy，避免把半写文件交给聊天请求。
class AttachmentDraftArchive {
  final Directory? rootDirectory;

  const AttachmentDraftArchive({this.rootDirectory});

  Future<Directory> _root() async {
    final root = rootDirectory ?? await getApplicationSupportDirectory();
    final drafts = Directory(p.join(root.path, 'composer_drafts'));
    await drafts.create(recursive: true);
    return drafts;
  }

  Future<ArchivedDraftAttachment> archiveFile({
    required String sourcePath,
    required String fileName,
    String? sessionId,
  }) async {
    final source = File(sourcePath);
    final type = await FileSystemEntity.type(source.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const FileSystemException('附件文件不存在或不可读');
    }
    final fileSize = await source.length();
    if (fileSize > kMaxAttachmentBytes) {
      throw ArgumentError.value(fileSize, 'sourcePath', '附件超过允许大小');
    }
    final safeName = safeAttachmentFileName(fileName);
    final id = _attachmentArchiveUuid.v4();
    final root = await _root();
    final sessionSegment = safeArchiveSegment(
      sessionId?.trim() ?? 'default',
      fallbackPrefix: 'session',
    );
    final target = File(p.join(root.path, sessionSegment, '$id-$safeName'));
    final archived = await copyFileAtomically(
      source,
      target,
      maxBytes: kMaxAttachmentBytes,
    );
    return ArchivedDraftAttachment(
      id: id,
      path: archived.path,
      fileName: safeName,
      fileSize: fileSize,
    );
  }

  Future<ArchivedDraftAttachment> archiveBytes({
    required List<int> bytes,
    required String fileName,
    String? sessionId,
  }) async {
    if (bytes.length > kMaxAttachmentBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', '附件超过允许大小');
    }
    final safeName = safeAttachmentFileName(fileName);
    final id = _attachmentArchiveUuid.v4();
    final root = await _root();
    final sessionSegment = safeArchiveSegment(
      sessionId?.trim() ?? 'default',
      fallbackPrefix: 'session',
    );
    final target = File(p.join(root.path, sessionSegment, '$id-$safeName'));
    final archived = await writeBytesAtomically(
      target,
      bytes,
      maxBytes: kMaxAttachmentBytes,
    );
    return ArchivedDraftAttachment(
      id: id,
      path: archived.path,
      fileName: safeName,
      fileSize: bytes.length,
    );
  }

  /// 只删除明确传入的 draft 文件，且拒绝删除 draft 根目录以外的路径。
  /// 调用方应以实际被消费的附件列表调用此方法，不要用整个目录清理代替。
  Future<void> deleteFile(String path) async {
    final root = await _root();
    final normalizedRoot = p.normalize(File(root.path).absolute.path);
    final normalizedPath = p.normalize(File(path).absolute.path);
    final prefix = '$normalizedRoot${Platform.pathSeparator}';
    if (!normalizedPath.startsWith(prefix)) return;
    final file = File(normalizedPath);
    if (await file.exists()) await file.delete();
  }
}

class ArchivedMessageAttachment {
  final String localPath;
  final int fileSize;

  const ArchivedMessageAttachment({
    required this.localPath,
    required this.fileSize,
  });
}

/// 消息附件归档。与 composer draft 分开，发送成功后消息只引用这里的路径，
/// 因而 picker/cache 清理不会让历史消息失效。
class MessageAttachmentArchive {
  final Directory rootDirectory;

  const MessageAttachmentArchive({required this.rootDirectory});

  Future<ArchivedMessageAttachment> archive({
    required String sourcePath,
    required String messageId,
    required String attachmentId,
    required String fileName,
  }) async {
    final source = File(sourcePath);
    final type = await FileSystemEntity.type(source.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const FileSystemException('附件文件不存在或已移动');
    }
    final size = await source.length();
    if (size > kMaxAttachmentBytes) {
      throw ArgumentError.value(size, 'sourcePath', '附件超过允许大小');
    }
    final target = File(
      p.join(
        rootDirectory.path,
        buildAttachmentArchivePath(
          messageId: messageId,
          attachmentId: attachmentId,
          fileName: fileName,
        ),
      ),
    );
    final archived = await copyFileAtomically(
      source,
      target,
      maxBytes: kMaxAttachmentBytes,
    );
    return ArchivedMessageAttachment(localPath: archived.path, fileSize: size);
  }
}

typedef SaveAttachmentFile =
    Future<String?> Function({
      String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type,
      List<String>? allowedExtensions,
      Uint8List? bytes,
    });

/// 将会话中的本地媒体通过系统保存对话框导出。
///
/// Android / iOS 的 FilePicker 需要直接传入 bytes；桌面端先返回用户选择的
/// 目标路径，再由应用使用 `.part -> rename` 写入，避免目标文件出现半成品。
class AttachmentExportService {
  AttachmentExportService({SaveAttachmentFile? saveFile})
    : saveFile = saveFile ?? FilePicker.platform.saveFile;

  final SaveAttachmentFile saveFile;

  Future<File?> export({
    required String localPath,
    required String fileName,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('当前平台暂不支持保存本地附件');
    }
    final source = File(localPath);
    final sourceType = await FileSystemEntity.type(
      source.path,
      followLinks: false,
    );
    if (sourceType != FileSystemEntityType.file) {
      throw const FileSystemException('附件文件不存在');
    }
    final bytes = await source.readAsBytes();
    if (bytes.isEmpty) throw const FileSystemException('附件文件为空');

    final safeName = safeAttachmentFileName(fileName);
    final extension = _extensionOf(safeName);
    final isMobile = Platform.isAndroid || Platform.isIOS;
    Directory? downloadsDirectory;
    try {
      downloadsDirectory = await getDownloadsDirectory();
    } catch (_) {
      downloadsDirectory = null;
    }
    final selected = await saveFile(
      dialogTitle: '保存附件',
      fileName: safeName,
      initialDirectory: downloadsDirectory?.path,
      type: extension == null ? FileType.any : FileType.custom,
      allowedExtensions: extension == null ? null : [extension],
      bytes: isMobile ? Uint8List.fromList(bytes) : null,
    );
    if (selected == null || selected.trim().isEmpty) return null;

    final destination = File(selected);
    if (!isMobile) {
      await writeBytesAtomically(destination, bytes);
    }
    return destination;
  }
}

String? _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return null;
  final extension = fileName.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,16}$').hasMatch(extension) ? extension : null;
}
