const kMaxAttachmentsPerMessage = 8;
const kMaxAttachmentBytes = 25 * 1024 * 1024;

const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
const _audioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'wav',
  'flac',
  'ogg',
  'opus',
  'amr',
};
const _allowedAttachmentTypes = {'image', 'pdf', 'audio', 'document'};

String inferAttachmentType(String? extensionOrName) {
  if (extensionOrName == null || extensionOrName.trim().isEmpty) {
    return 'document';
  }
  var ext = extensionOrName.trim().toLowerCase();
  final dotIndex = ext.lastIndexOf('.');
  if (dotIndex >= 0 && dotIndex < ext.length - 1) {
    ext = ext.substring(dotIndex + 1);
  }
  if (_imageExtensions.contains(ext)) return 'image';
  if (_audioExtensions.contains(ext)) return 'audio';
  if (ext == 'pdf') return 'pdf';
  return 'document';
}

String formatAttachmentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

String? validateAttachmentMetadata({
  required String fileName,
  required String fileType,
  required int fileSize,
  required int currentCount,
  int maxCount = kMaxAttachmentsPerMessage,
  int maxBytes = kMaxAttachmentBytes,
}) {
  final displayName = fileName.trim().isEmpty ? '未命名附件' : fileName.trim();
  if (currentCount >= maxCount) {
    return '每条消息最多添加 $maxCount 个附件';
  }
  if (!_allowedAttachmentTypes.contains(fileType)) {
    return '不支持的附件类型：$fileType';
  }
  if (fileSize < 0) {
    return '无法读取附件大小：$displayName';
  }
  if (fileSize > maxBytes) {
    return '附件过大：$displayName（${formatAttachmentSize(fileSize)}），单个附件上限 ${formatAttachmentSize(maxBytes)}';
  }
  return null;
}
