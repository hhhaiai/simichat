import 'dart:convert';
import 'dart:io';
import 'ai_protocol.dart';

const kAttachmentImageDataUrlMaxBytes = 1024 * 1024;

/// 读取附件文件为 base64
Future<List<AttachmentData>> loadAttachments(
  List<Attachment> attachments,
) async {
  final result = <AttachmentData>[];
  for (final att in attachments) {
    final mimeType = att.mimeType ?? _guessMimeType(att.path, att.type);
    if (att.type == 'image') {
      final dataUrl = parseAttachmentImageDataUrl(att.path);
      if (dataUrl != null) {
        result.add(
          AttachmentData(
            type: att.type,
            base64: dataUrl.base64,
            mimeType: dataUrl.mimeType,
          ),
        );
        continue;
      }
      final bytes = await File(att.path).readAsBytes();
      final base64 = base64Encode(bytes);
      result.add(
        AttachmentData(type: att.type, base64: base64, mimeType: mimeType),
      );
    } else {
      result.add(
        AttachmentData(type: att.type, base64: '', mimeType: mimeType),
      );
    }
  }
  return result;
}

AttachmentImageDataUrl? parseAttachmentImageDataUrl(
  String value, {
  int maxBytes = kAttachmentImageDataUrlMaxBytes,
}) {
  final trimmed = value.trim();
  final match = RegExp(
    r'^data:(image/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=_-]+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match == null) return null;

  final mimeType = _normalizeImageDataUrlMimeType(match.group(1)!);
  if (mimeType == null) return null;

  final normalizedBase64 = _normalizeBase64(match.group(2)!);
  if (normalizedBase64 == null) return null;

  try {
    final bytes = base64Decode(normalizedBase64);
    if (bytes.isEmpty || bytes.length > maxBytes) return null;
    return AttachmentImageDataUrl(
      mimeType: mimeType,
      base64: normalizedBase64,
      byteLength: bytes.length,
    );
  } catch (_) {
    return null;
  }
}

String? _normalizeImageDataUrlMimeType(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'image/jpg' => 'image/jpeg',
    'image/jpeg' ||
    'image/png' ||
    'image/gif' ||
    'image/webp' ||
    'image/bmp' => normalized,
    _ => null,
  };
}

String? _normalizeBase64(String value) {
  final normalized = value.trim().replaceAll('-', '+').replaceAll('_', '/');
  final remainder = normalized.length % 4;
  if (remainder == 1) return null;
  if (remainder == 2) return '$normalized==';
  if (remainder == 3) return '$normalized=';
  return normalized;
}

String _guessMimeType(String path, String type) {
  if (type == 'image') {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }
  if (type == 'pdf') return 'application/pdf';
  if (type == 'audio') {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'opus':
        return 'audio/opus';
      case 'amr':
        return 'audio/amr';
      default:
        return 'audio/mpeg';
    }
  }
  return 'application/octet-stream';
}

class AttachmentData {
  final String type;
  final String base64;
  final String mimeType;
  const AttachmentData({
    required this.type,
    required this.base64,
    required this.mimeType,
  });
}

class AttachmentImageDataUrl {
  final String mimeType;
  final String base64;
  final int byteLength;

  const AttachmentImageDataUrl({
    required this.mimeType,
    required this.base64,
    required this.byteLength,
  });
}
