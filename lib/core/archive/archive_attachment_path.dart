import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

String buildAttachmentArchivePath({
  required String attachmentId,
  required String messageId,
  required String fileName,
}) {
  final safeMessageId = safeArchiveSegment(
    messageId,
    fallbackPrefix: 'message',
  );
  final safeAttachmentId = safeArchiveSegment(
    attachmentId,
    fallbackPrefix: 'attachment',
  );
  final safeFileName = safeAttachmentFileName(fileName);
  return 'attachments/$safeMessageId/$safeAttachmentId-$safeFileName';
}

String safeArchiveSegment(String raw, {required String fallbackPrefix}) {
  final sanitized = raw
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
  if (sanitized.isEmpty) {
    return '$fallbackPrefix-${sha256.convert(utf8.encode(raw)).toString().substring(0, 12)}';
  }
  return sanitized.length <= 48 ? sanitized : sanitized.substring(0, 48);
}

String safeAttachmentFileName(String raw) {
  final normalized = raw.replaceAll('\\', '/').trim();
  final basename = p.posix.basename(normalized.isEmpty ? 'file' : normalized);
  final extension = p
      .extension(basename)
      .replaceAll(RegExp(r'[^A-Za-z0-9.]'), '')
      .toLowerCase();
  final stem = p
      .basenameWithoutExtension(basename)
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
  final safeStem = stem.isEmpty ? 'file' : stem;
  final limitedStem = safeStem.length <= 64
      ? safeStem
      : safeStem.substring(0, 64);
  final limitedExtension = extension.length <= 16
      ? extension
      : extension.substring(0, 16);
  return '$limitedStem$limitedExtension';
}
