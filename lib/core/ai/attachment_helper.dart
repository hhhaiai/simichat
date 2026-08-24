import 'dart:convert';
import 'dart:io';
import 'ai_protocol.dart';
import '../attachments/attachment_policy.dart' show kMaxAttachmentBytes;

const kAttachmentImageDataUrlMaxBytes = 1024 * 1024;
const kAttachmentAudioDataUrlMaxBytes = kMaxAttachmentBytes;
const kAttachmentFileDataMaxBytes = kMaxAttachmentBytes;

enum AttachmentLoadFailureKind {
  invalidSource,
  missing,
  unreadable,
  tooLarge,
  empty,
}

/// Raised when a native adapter cannot safely read a local attachment.
///
/// The message intentionally contains neither the source path nor the raw
/// filesystem diagnostic. Attachment paths can include private directories,
/// provider URIs, or accidentally pasted credentials.
class AttachmentLoadException implements Exception {
  final String attachmentType;
  final AttachmentLoadFailureKind kind;
  final String message;

  const AttachmentLoadException({
    required this.attachmentType,
    required this.kind,
    required this.message,
  });

  @override
  String toString() => message;
}

/// Raised when a protocol cannot represent an attachment natively.
class UnsupportedAttachmentException implements Exception {
  final String attachmentType;
  final String protocol;
  final String message;

  const UnsupportedAttachmentException({
    required this.attachmentType,
    required this.protocol,
    required this.message,
  });

  @override
  String toString() => message;
}

/// `document` remains a text fallback for protocols that do not declare a
/// native file part. A protocol with a declared native `document` transport
/// is allowed to receive the original attachment instead.
const _chatTextFallbackAttachmentTypes = {'document'};
const _chatUnsupportedAttachmentTypes = {'pdf', 'video'};

String attachmentTypeLabel(String type) {
  return switch (type.trim().toLowerCase()) {
    'pdf' => 'PDF',
    'video' => 'video',
    'document' => 'document',
    'audio' => 'audio',
    'image' => 'image',
    final other when other.isNotEmpty => other,
    _ => 'document',
  };
}

/// Checks the transport boundary before persistence.
///
/// `document` is allowed here because [sendMessage] performs the real,
/// bounded UTF-8 extraction and binds the resulting text to the current model
/// request.  The document is not passed to an adapter as a placeholder or
/// filename-only part. Audio is intentionally excluded because the chat
/// provider keeps its existing STT -> ordinary text fallback, while protocol
/// adapters may separately opt into native audio parts.
UnsupportedAttachmentException? preflightChatAttachmentTransport({
  required String protocol,
  required Iterable<String> attachmentTypes,
  Set<String>? nativeAttachmentTypes,
}) {
  final nativeTypes = (nativeAttachmentTypes ?? const <String>{})
      .map((type) => type.trim().toLowerCase())
      .toSet();
  for (final rawType in attachmentTypes) {
    final type = rawType.trim().toLowerCase();
    if (type == 'image' ||
        type == 'audio' ||
        _chatTextFallbackAttachmentTypes.contains(type) ||
        nativeTypes.contains(type)) {
      continue;
    }
    final normalizedType = _chatUnsupportedAttachmentTypes.contains(type)
        ? type
        : (type.isEmpty ? 'document' : type);
    final message = switch (normalizedType) {
      'pdf' => '当前 $protocol 未配置 PDF 的真实 File API / 解析通道，消息未发送；已保留输入和附件。',
      'video' => '当前 $protocol 没有视频附件的真实上传 / 理解通道，消息未发送；已保留输入和附件。',
      _ =>
        '当前 $protocol 没有 ${attachmentTypeLabel(normalizedType)} 附件的真实上传通道，消息未发送；已保留输入和附件。',
    };
    return UnsupportedAttachmentException(
      attachmentType: normalizedType,
      protocol: protocol,
      message: message,
    );
  }
  return null;
}

Never throwUnsupportedAttachment(String protocol, String attachmentType) {
  final normalizedType = attachmentType.trim().toLowerCase();
  if (normalizedType == 'audio') {
    throwUnsupportedAudioAttachment(protocol);
  }
  throw UnsupportedAttachmentException(
    attachmentType: normalizedType.isEmpty ? 'document' : normalizedType,
    protocol: protocol,
    message: '当前 $protocol 适配器不支持原生 ${attachmentTypeLabel(normalizedType)} 输入。',
  );
}

Never throwUnsupportedAudioAttachment(String protocol) {
  throw UnsupportedAttachmentException(
    attachmentType: 'audio',
    protocol: protocol,
    message: '当前 $protocol 适配器不支持原生 audio 输入，请先通过 STT 转写后发送。',
  );
}

/// 读取可直接传给多模态模型的附件为 base64。
Future<List<AttachmentData>> loadAttachments(
  List<Attachment> attachments, {
  int maxBytes = kAttachmentFileDataMaxBytes,
}) async {
  if (maxBytes <= 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
  }
  final result = <AttachmentData>[];
  for (final att in attachments) {
    final normalizedType = att.type.trim().toLowerCase();
    final mimeType = _mimeTypeForAttachment(att, normalizedType);
    if (normalizedType == 'image' || normalizedType == 'audio') {
      final dataUrl = parseAttachmentImageDataUrl(att.path);
      if (normalizedType == 'image' && dataUrl != null) {
        result.add(
          AttachmentData(
            type: normalizedType,
            base64: dataUrl.base64,
            mimeType: dataUrl.mimeType,
          ),
        );
        continue;
      }
      if (normalizedType == 'audio') {
        final dataUrl = parseAttachmentAudioDataUrl(att.path);
        if (dataUrl != null) {
          result.add(
            AttachmentData(
              type: normalizedType,
              base64: dataUrl.base64,
              mimeType: dataUrl.mimeType,
              audioFormat: _guessAudioFormat('', dataUrl.mimeType),
            ),
          );
          continue;
        }
      }
    }

    final bytes = await _readLocalAttachmentBytes(att, maxBytes: maxBytes);
    result.add(
      AttachmentData(
        type: normalizedType,
        base64: base64Encode(bytes),
        mimeType: mimeType,
        fileName:
            _safeAttachmentFileName(att.fileName) ??
            _attachmentBasename(att.path),
        audioFormat: normalizedType == 'audio'
            ? _guessAudioFormat(att.path, mimeType)
            : null,
      ),
    );
  }
  return result;
}

Future<List<int>> _readLocalAttachmentBytes(
  Attachment attachment, {
  required int maxBytes,
}) async {
  final source = attachment.path.trim();
  final type = attachment.type.trim().toLowerCase();
  if (source.isEmpty || _isNonLocalAttachmentSource(source)) {
    throw AttachmentLoadException(
      attachmentType: type,
      kind: AttachmentLoadFailureKind.invalidSource,
      message: '附件来源不是可读取的本地文件，未发送；已保留输入和附件。',
    );
  }

  final file = File(source);
  final FileStat stat;
  try {
    stat = await file.stat();
  } on Object {
    throw _attachmentLoadException(type, AttachmentLoadFailureKind.unreadable);
  }
  if (stat.type == FileSystemEntityType.notFound) {
    throw _attachmentLoadException(type, AttachmentLoadFailureKind.missing);
  }
  if (stat.type != FileSystemEntityType.file) {
    throw _attachmentLoadException(type, AttachmentLoadFailureKind.unreadable);
  }
  if (stat.size <= 0) {
    throw _attachmentLoadException(type, AttachmentLoadFailureKind.empty);
  }
  if (stat.size > maxBytes) {
    throw _attachmentLoadException(type, AttachmentLoadFailureKind.tooLarge);
  }

  final bytes = <int>[];
  try {
    // Read one byte beyond the limit so a file that grows after stat() is
    // rejected without ever loading an unbounded payload.
    await for (final chunk in file.openRead(0, maxBytes + 1)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw _attachmentLoadException(
          type,
          AttachmentLoadFailureKind.tooLarge,
        );
      }
    }
  } on AttachmentLoadException {
    rethrow;
  } on Object {
    throw _attachmentLoadException(type, AttachmentLoadFailureKind.unreadable);
  }
  if (bytes.isEmpty) {
    throw _attachmentLoadException(type, AttachmentLoadFailureKind.empty);
  }
  return bytes;
}

AttachmentLoadException _attachmentLoadException(
  String type,
  AttachmentLoadFailureKind kind,
) {
  final message = switch (kind) {
    AttachmentLoadFailureKind.invalidSource => '附件来源不是可读取的本地文件，未发送；已保留输入和附件。',
    AttachmentLoadFailureKind.missing => '附件文件不存在或已被移动，未发送；已保留输入和附件。',
    AttachmentLoadFailureKind.unreadable => '无法读取附件内容，未发送；已保留输入和附件。',
    AttachmentLoadFailureKind.tooLarge => '附件超过 25 MiB 安全上限，未发送；已保留输入和附件。',
    AttachmentLoadFailureKind.empty => '附件文件为空，未发送；已保留输入和附件。',
  };
  return AttachmentLoadException(
    attachmentType: type.isEmpty ? 'document' : type,
    kind: kind,
    message: message,
  );
}

bool _isNonLocalAttachmentSource(String value) {
  final lower = value.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('data:') ||
      lower.startsWith('file://') ||
      lower.contains('://')) {
    return true;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.isEmpty) return false;
  // Keep Windows drive paths as local paths.
  return !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
}

String _attachmentBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  var basename = slash < 0 ? normalized : normalized.substring(slash + 1);
  basename = basename.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '_');
  if (basename.isEmpty || basename == '.' || basename == '..') {
    return 'attachment';
  }
  return basename;
}

String? _safeAttachmentFileName(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  // Filename 是协议元数据，不是路径；移除目录和控制字符，防止把私有归档
  // 路径、Windows 路径或 CRLF 直接带进上游请求。
  final basename = normalized
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '_')
      .trim();
  if (basename.isEmpty || basename == '.' || basename == '..') return null;
  return basename.length <= 255 ? basename : basename.substring(0, 255);
}

String _mimeTypeForAttachment(Attachment attachment, String type) {
  if (type == 'pdf') return 'application/pdf';
  final supplied = attachment.mimeType?.trim().toLowerCase();
  if (type == 'document' && _safeDocumentMimeTypes.contains(supplied)) {
    return supplied!;
  }
  if (type != 'document' && supplied != null && supplied.isNotEmpty) {
    return supplied;
  }
  return _guessMimeType(attachment.path, type);
}

AttachmentAudioDataUrl? parseAttachmentAudioDataUrl(
  String value, {
  int maxBytes = kAttachmentAudioDataUrlMaxBytes,
}) {
  final trimmed = value.trim();
  final match = RegExp(
    r'^data:(audio/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=_-]+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match == null) return null;

  final mimeType = _normalizeAudioDataUrlMimeType(match.group(1)!);
  if (mimeType == null) return null;
  final normalizedBase64 = _normalizeBase64(match.group(2)!);
  if (normalizedBase64 == null) return null;
  try {
    final bytes = base64Decode(normalizedBase64);
    if (bytes.isEmpty || bytes.length > maxBytes) return null;
    return AttachmentAudioDataUrl(
      mimeType: mimeType,
      base64: normalizedBase64,
      byteLength: bytes.length,
    );
  } catch (_) {
    return null;
  }
}

String? _normalizeAudioDataUrlMimeType(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'audio/x-m4a' => 'audio/mp4',
    'audio/mpeg' ||
    'audio/mp4' ||
    'audio/aac' ||
    'audio/wav' ||
    'audio/x-wav' ||
    'audio/flac' ||
    'audio/ogg' ||
    'audio/opus' ||
    'audio/amr' => normalized == 'audio/x-wav' ? 'audio/wav' : normalized,
    _ => null,
  };
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

const _safeDocumentMimeTypes = {
  'application/octet-stream',
  'application/json',
  'application/pdf',
  'application/rtf',
  'application/vnd.ms-excel',
  'application/vnd.ms-powerpoint',
  'application/vnd.ms-word',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/xml',
  'application/yaml',
  'text/csv',
  'text/html',
  'text/markdown',
  'text/plain',
  'text/tab-separated-values',
};

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
  if (type == 'document') {
    final normalizedPath = path.replaceAll('\\', '/');
    final slash = normalizedPath.lastIndexOf('/');
    final basename = slash < 0
        ? normalizedPath
        : normalizedPath.substring(slash + 1);
    final dot = basename.lastIndexOf('.');
    final ext = dot <= 0 || dot == basename.length - 1
        ? ''
        : basename.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'txt' || 'log' => 'text/plain',
      'md' || 'markdown' => 'text/markdown',
      'csv' => 'text/csv',
      'tsv' => 'text/tab-separated-values',
      'html' || 'htm' => 'text/html',
      'json' => 'application/json',
      'xml' => 'application/xml',
      'yaml' || 'yml' => 'application/yaml',
      'rtf' => 'application/rtf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      _ => 'application/octet-stream',
    };
  }
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

String _guessAudioFormat(String path, String mimeType) {
  final ext = path.split('.').last.toLowerCase();
  switch (ext) {
    case 'mp3':
    case 'm4a':
    case 'mp4':
    case 'aac':
    case 'wav':
    case 'flac':
    case 'ogg':
    case 'opus':
    case 'amr':
      return ext;
  }
  switch (mimeType.toLowerCase()) {
    case 'audio/mpeg':
      return 'mp3';
    case 'audio/mp4':
      return 'm4a';
    case 'audio/aac':
      return 'aac';
    case 'audio/wav':
    case 'audio/x-wav':
      return 'wav';
    case 'audio/flac':
      return 'flac';
    case 'audio/ogg':
      return 'ogg';
    case 'audio/opus':
      return 'opus';
    case 'audio/amr':
      return 'amr';
  }
  return 'mp3';
}

class AttachmentData {
  final String type;
  final String base64;
  final String mimeType;
  final String? fileName;
  final String? audioFormat;

  const AttachmentData({
    required this.type,
    required this.base64,
    required this.mimeType,
    this.fileName,
    this.audioFormat,
  });
}

class AttachmentAudioDataUrl {
  final String mimeType;
  final String base64;
  final int byteLength;

  const AttachmentAudioDataUrl({
    required this.mimeType,
    required this.base64,
    required this.byteLength,
  });
}

/// Native OpenAI Chat Completions audio input. This is intentionally not a
/// text fallback: callers can inspect the typed attachment exception when a
/// different OpenAI-compatible endpoint cannot support this shape.
Map<String, dynamic> buildOpenAiChatAudioPart(AttachmentData attachment) {
  if (attachment.base64.isEmpty) {
    throwUnsupportedAudioAttachment('openai_chat');
  }
  return {
    'type': 'input_audio',
    'input_audio': {
      'data': attachment.base64,
      'format': attachment.audioFormat ?? 'mp3',
    },
  };
}

/// Legacy diagnostic formatter retained for non-protocol callers. Protocol
/// adapters must use a native audio part or [throwUnsupportedAudioAttachment].
String buildAudioAttachmentText(AttachmentData attachment) {
  final format = attachment.audioFormat ?? 'mp3';
  return '[附件: audio]\n'
      'mime_type: ${attachment.mimeType}\n'
      'format: $format\n'
      'base64:\n${attachment.base64}';
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
