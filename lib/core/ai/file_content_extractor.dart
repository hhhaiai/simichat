import 'dart:convert';
import 'dart:io';

/// Upper bound for text that is copied into a chat request.
///
/// Attachment storage still uses the larger media limit.  This smaller limit
/// is intentional: a document is expanded into the model context, so its
/// cost must be bounded independently from the size of the original file.
const kMaxExtractableFileBytes = 2 * 1024 * 1024;

/// Upper bound for the number of lines accepted from one text attachment.
const kMaxExtractableFileLines = 20000;

/// Upper bound for one physical line, measured in UTF-8 bytes.
const kMaxExtractableLineBytes = 128 * 1024;

/// Categories are kept stable so callers can provide a retryable UI without
/// parsing the user-facing message.
enum FileContentExtractionFailureKind {
  unsupportedType,
  missing,
  unreadable,
  tooLarge,
  tooManyLines,
  lineTooLong,
  binary,
  invalidUtf8,
  empty,
}

/// A safe, bounded text extraction result.
class FileContentExtractionResult {
  final String text;
  final int byteLength;
  final int lineCount;

  const FileContentExtractionResult({
    required this.text,
    required this.byteLength,
    required this.lineCount,
  });

  /// Alias for callers that use “content” terminology.
  String get content => text;
}

/// Raised when a selected file cannot safely become chat text.
///
/// The exception deliberately contains no OS error, absolute path, or raw
/// provider diagnostic.  A file name is retained only as a sanitized basename
/// for structured logging/tests; [message] is always safe to show to a user.
class FileContentExtractionException implements Exception {
  final FileContentExtractionFailureKind kind;
  final String fileName;
  final String message;

  const FileContentExtractionException({
    required this.kind,
    required this.fileName,
    required this.message,
  });

  @override
  String toString() => message;
}

/// Extracts only bounded UTF-8 text from a `document` attachment.
class FileContentExtractor {
  final int maxBytes;
  final int maxLines;
  final int maxLineBytes;

  const FileContentExtractor({
    this.maxBytes = kMaxExtractableFileBytes,
    this.maxLines = kMaxExtractableFileLines,
    this.maxLineBytes = kMaxExtractableLineBytes,
  });

  Future<FileContentExtractionResult> extract({
    required String path,
    String? fileName,
    String attachmentType = 'document',
    String? mimeType,
  }) async {
    final safeName = sanitizeFileDiagnosticName(fileName ?? path);
    final normalizedType = attachmentType.trim().toLowerCase();
    final extension = _extensionOf(fileName ?? path);
    final normalizedMime = mimeType?.trim().toLowerCase();

    _validateLimits(safeName);
    _rejectKnownUnsupportedType(
      safeName: safeName,
      attachmentType: normalizedType,
      extension: extension,
      mimeType: normalizedMime,
    );

    final file = File(path);
    final FileStat stat;
    try {
      stat = await file.stat();
    } on Object {
      throw _failure(
        kind: FileContentExtractionFailureKind.missing,
        fileName: safeName,
      );
    }
    if (stat.type == FileSystemEntityType.notFound) {
      throw _failure(
        kind: FileContentExtractionFailureKind.missing,
        fileName: safeName,
      );
    }
    if (stat.type != FileSystemEntityType.file) {
      throw _failure(
        kind: FileContentExtractionFailureKind.unreadable,
        fileName: safeName,
      );
    }
    if (stat.size > maxBytes) {
      throw _failure(
        kind: FileContentExtractionFailureKind.tooLarge,
        fileName: safeName,
      );
    }

    final bytes = <int>[];
    try {
      // Reading maxBytes + 1 bytes also catches a file that grows after the
      // stat() call without ever loading an unbounded file into memory.
      await for (final chunk in file.openRead(0, maxBytes + 1)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          throw _failure(
            kind: FileContentExtractionFailureKind.tooLarge,
            fileName: safeName,
          );
        }
      }
    } on FileContentExtractionException {
      rethrow;
    } on Object {
      throw _failure(
        kind: FileContentExtractionFailureKind.unreadable,
        fileName: safeName,
      );
    }

    if (bytes.isEmpty) {
      throw _failure(
        kind: FileContentExtractionFailureKind.empty,
        fileName: safeName,
      );
    }
    _rejectBinaryBytes(bytes, safeName);
    _validateLineBounds(bytes, safeName);

    final String decoded;
    try {
      decoded = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw _failure(
        kind: FileContentExtractionFailureKind.invalidUtf8,
        fileName: safeName,
      );
    }

    // A UTF-8 BOM is an encoding marker, not user document content.
    final text = decoded.startsWith('\uFEFF') ? decoded.substring(1) : decoded;
    if (text.trim().isEmpty) {
      throw _failure(
        kind: FileContentExtractionFailureKind.empty,
        fileName: safeName,
      );
    }

    return FileContentExtractionResult(
      text: text,
      byteLength: bytes.length,
      lineCount: _lineCount(bytes),
    );
  }

  void _validateLimits(String safeName) {
    if (maxBytes <= 0 || maxLines <= 0 || maxLineBytes <= 0) {
      throw ArgumentError('FileContentExtractor limits must be positive');
    }
    // Keep the argument in the error path so a malformed extractor cannot
    // accidentally produce an unlabelled diagnostic.
    if (safeName.isEmpty) return;
  }

  void _rejectKnownUnsupportedType({
    required String safeName,
    required String attachmentType,
    required String extension,
    required String? mimeType,
  }) {
    if (attachmentType == 'pdf' ||
        extension == 'pdf' ||
        mimeType == 'application/pdf') {
      throw _failure(
        kind: FileContentExtractionFailureKind.unsupportedType,
        fileName: safeName,
        message:
            '当前聊天未配置可用的 PDF File API，暂不支持把 PDF 内容读入模型；已保留附件，请改用纯文本或 Markdown 后重试。',
      );
    }
    if (attachmentType == 'video' ||
        _videoExtensions.contains(extension) ||
        (mimeType?.startsWith('video/') ?? false)) {
      throw _failure(
        kind: FileContentExtractionFailureKind.unsupportedType,
        fileName: safeName,
        message: '当前聊天不支持视频文件直接进入模型上下文；已保留附件，请改用视频理解接口或先提取文字后重试。',
      );
    }
    if (attachmentType != 'document' && attachmentType != 'text') {
      throw _failure(
        kind: FileContentExtractionFailureKind.unsupportedType,
        fileName: safeName,
      );
    }
    if (_knownBinaryExtensions.contains(extension) ||
        _officeExtensions.contains(extension)) {
      throw _failure(
        kind: FileContentExtractionFailureKind.unsupportedType,
        fileName: safeName,
      );
    }
  }

  void _rejectBinaryBytes(List<int> bytes, String safeName) {
    // NUL is not valid in the text formats supported here and is a high-signal
    // binary marker.  Other C0 controls are rejected except common whitespace.
    for (final byte in bytes) {
      if (byte == 0 ||
          (byte < 0x20 &&
              byte != 0x09 &&
              byte != 0x0A &&
              byte != 0x0C &&
              byte != 0x0D)) {
        throw _failure(
          kind: FileContentExtractionFailureKind.binary,
          fileName: safeName,
        );
      }
    }

    // Catch common container/media signatures even if a user-facing extension
    // was lost during import.  This prevents a binary blob with an accidental
    // UTF-8-looking prefix from being sent as document text.
    if (_looksLikePdf(bytes) ||
        _looksLikeVideo(bytes) ||
        _looksLikeContainer(bytes)) {
      throw _failure(
        kind: FileContentExtractionFailureKind.binary,
        fileName: safeName,
      );
    }
  }

  void _validateLineBounds(List<int> bytes, String safeName) {
    var lines = bytes.isEmpty ? 0 : 1;
    var currentLineBytes = 0;
    for (final byte in bytes) {
      if (byte == 0x0A) {
        if (currentLineBytes > maxLineBytes) {
          throw _failure(
            kind: FileContentExtractionFailureKind.lineTooLong,
            fileName: safeName,
          );
        }
        lines++;
        currentLineBytes = 0;
        if (lines > maxLines) {
          throw _failure(
            kind: FileContentExtractionFailureKind.tooManyLines,
            fileName: safeName,
          );
        }
      } else {
        currentLineBytes++;
        if (currentLineBytes > maxLineBytes) {
          throw _failure(
            kind: FileContentExtractionFailureKind.lineTooLong,
            fileName: safeName,
          );
        }
      }
    }
    if (currentLineBytes > maxLineBytes) {
      throw _failure(
        kind: FileContentExtractionFailureKind.lineTooLong,
        fileName: safeName,
      );
    }
    if (lines > maxLines) {
      throw _failure(
        kind: FileContentExtractionFailureKind.tooManyLines,
        fileName: safeName,
      );
    }
  }

  int _lineCount(List<int> bytes) {
    if (bytes.isEmpty) return 0;
    return 1 + bytes.where((byte) => byte == 0x0A).length;
  }

  FileContentExtractionException _failure({
    required FileContentExtractionFailureKind kind,
    required String fileName,
    String? message,
  }) {
    return FileContentExtractionException(
      kind: kind,
      fileName: sanitizeFileDiagnosticName(fileName),
      message: message ?? _defaultMessage(kind),
    );
  }

  String _defaultMessage(FileContentExtractionFailureKind kind) {
    return switch (kind) {
      FileContentExtractionFailureKind.missing =>
        '附件文件不存在或已被移动；已保留输入和附件，请重新选择文件后重试。',
      FileContentExtractionFailureKind.unreadable =>
        '无法读取附件内容；已保留输入和附件，请检查文件后重试。',
      FileContentExtractionFailureKind.tooLarge => '文本附件过大，未写入模型上下文；请缩小文件后重试。',
      FileContentExtractionFailureKind.tooManyLines =>
        '文本附件行数超出安全上限，未写入模型上下文；请拆分文件后重试。',
      FileContentExtractionFailureKind.lineTooLong =>
        '文本附件包含过长行，未写入模型上下文；请拆分或格式化文件后重试。',
      FileContentExtractionFailureKind.binary =>
        '附件不是可安全读取的 UTF-8 文本，未写入模型上下文；已保留附件，请改用纯文本文件后重试。',
      FileContentExtractionFailureKind.invalidUtf8 =>
        '附件不是有效的 UTF-8 文本，未写入模型上下文；已保留附件，请另存为 UTF-8 后重试。',
      FileContentExtractionFailureKind.empty =>
        '文本附件没有可用内容，未写入模型上下文；已保留附件，请选择非空文件后重试。',
      FileContentExtractionFailureKind.unsupportedType =>
        '当前聊天不支持把该附件类型读入模型上下文；已保留附件，请改用纯文本或已配置的文件接口后重试。',
    };
  }
}

/// Convenience wrapper for callers that do not need a configured extractor.
Future<FileContentExtractionResult> extractFileContent({
  required String path,
  String? fileName,
  String attachmentType = 'document',
  String? mimeType,
  int maxBytes = kMaxExtractableFileBytes,
  int maxLines = kMaxExtractableFileLines,
  int maxLineBytes = kMaxExtractableLineBytes,
}) {
  return FileContentExtractor(
    maxBytes: maxBytes,
    maxLines: maxLines,
    maxLineBytes: maxLineBytes,
  ).extract(
    path: path,
    fileName: fileName,
    attachmentType: attachmentType,
    mimeType: mimeType,
  );
}

/// Sanitizes only a diagnostic basename; it is never used as extracted text.
String sanitizeFileDiagnosticName(String value) {
  var name = value.trim().replaceAll(RegExp(r'^.*[\\/]'), '');
  if (name.isEmpty) return '附件';
  name = name.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '_');
  name = name.replaceAllMapped(
    RegExp(r'(bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    (match) => '${match.group(1)}***',
  );
  name = name.replaceAllMapped(
    RegExp(
      r'((?:api[_-]?key|token|secret|password)\s*[=:]\s*)[^\s]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}***',
  );
  if (name.length > 160) name = name.substring(0, 160);
  return name;
}

String _extensionOf(String value) {
  final name = value.replaceAll(RegExp(r'^.*[\\/]'), '').toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1);
}

const _videoExtensions = {
  '3gp',
  'avi',
  'm4v',
  'mkv',
  'mov',
  'mp4',
  'ogv',
  'webm',
};

const _knownBinaryExtensions = {
  '7z',
  'bin',
  'bz2',
  'dmg',
  'gif',
  'gz',
  'iso',
  'jpeg',
  'jpg',
  'png',
  'tar',
  'webp',
  'xz',
  'zip',
};

const _officeExtensions = {
  'doc',
  'docm',
  'docx',
  'odp',
  'ods',
  'odt',
  'ppt',
  'pptm',
  'pptx',
  'xls',
  'xlsm',
  'xlsx',
};

bool _looksLikePdf(List<int> bytes) {
  if (bytes.length < 5) return false;
  return String.fromCharCodes(bytes.take(5)) == '%PDF-';
}

bool _looksLikeVideo(List<int> bytes) {
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
    return true;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'AVI ') {
    return true;
  }
  return bytes.length >= 4 &&
      bytes[0] == 0x1A &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xDF &&
      bytes[3] == 0xA3;
}

bool _looksLikeContainer(List<int> bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08)) {
    return true;
  }
  return bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x21 &&
      bytes[2] == 0x50 &&
      bytes[3] == 0x53;
}
