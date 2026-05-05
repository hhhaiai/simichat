import 'dart:convert';
import 'dart:io';
import 'ai_protocol.dart';

/// 读取附件文件为 base64
Future<List<AttachmentData>> loadAttachments(List<Attachment> attachments) async {
  final result = <AttachmentData>[];
  for (final att in attachments) {
    final bytes = await File(att.path).readAsBytes();
    final base64 = base64Encode(bytes);
    final mimeType = att.mimeType ?? _guessMimeType(att.path, att.type);
    result.add(AttachmentData(
      type: att.type,
      base64: base64,
      mimeType: mimeType,
    ));
  }
  return result;
}

String _guessMimeType(String path, String type) {
  if (type == 'image') {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'bmp': return 'image/bmp';
      default: return 'image/jpeg';
    }
  }
  if (type == 'pdf') return 'application/pdf';
  return 'application/octet-stream';
}

class AttachmentData {
  final String type;
  final String base64;
  final String mimeType;
  const AttachmentData({required this.type, required this.base64, required this.mimeType});
}
