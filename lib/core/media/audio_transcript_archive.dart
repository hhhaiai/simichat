import 'dart:io';

import 'package:path/path.dart' as p;

class AudioTranscriptDetails {
  final AudioTranscriptStatus status;
  final String? transcriptText;
  final String? statusMessage;

  const AudioTranscriptDetails({
    required this.status,
    this.transcriptText,
    this.statusMessage,
  });

  bool get hasCopyableTranscript =>
      status == AudioTranscriptStatus.ready &&
      transcriptText != null &&
      transcriptText!.trim().isNotEmpty;

  String get displayText {
    if (hasCopyableTranscript) return transcriptText!.trim();
    if (statusMessage != null && statusMessage!.trim().isNotEmpty) {
      return statusMessage!.trim();
    }
    return switch (status) {
      AudioTranscriptStatus.pending => '等待语音转文字完成。',
      AudioTranscriptStatus.empty => '转写已完成，但未识别到可保存的文字。',
      AudioTranscriptStatus.failed => '转写失败，暂无可用正文。',
      AudioTranscriptStatus.ready => '暂无可复制的转写正文。',
    };
  }
}

enum AudioTranscriptStatus {
  pending('pending', '等待转写'),
  ready('ready', '转写完成'),
  empty('empty', '未识别到文字'),
  failed('failed', '转写失败');

  final String label;
  final String displayLabel;

  const AudioTranscriptStatus(this.label, this.displayLabel);
}

class AudioTranscriptArchive {
  final Directory rootDirectory;

  const AudioTranscriptArchive({required this.rootDirectory});

  Directory get transcriptsDirectory =>
      Directory(p.join(rootDirectory.path, 'audio_transcripts'));

  File transcriptFile({
    required String messageId,
    required String attachmentId,
  }) {
    return File(
      p.join(
        transcriptsDirectory.path,
        sanitizeId(messageId),
        '${sanitizeId(attachmentId)}.md',
      ),
    );
  }

  Future<File> writeDraft({
    required String messageId,
    required String attachmentId,
    required String fileName,
    required int fileSize,
    String? transcript,
    AudioTranscriptStatus? status,
    String? errorMessage,
    DateTime? createdAt,
  }) async {
    final file = transcriptFile(
      messageId: messageId,
      attachmentId: attachmentId,
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      renderTranscript(
        messageId: messageId,
        attachmentId: attachmentId,
        fileName: fileName,
        fileSize: fileSize,
        transcript: transcript,
        status: status,
        errorMessage: errorMessage,
        createdAt: createdAt ?? DateTime.now(),
      ),
      flush: true,
    );
    return file;
  }

  Future<File> writeFailure({
    required String messageId,
    required String attachmentId,
    required String fileName,
    required int fileSize,
    Object? error,
    DateTime? createdAt,
  }) {
    return writeDraft(
      messageId: messageId,
      attachmentId: attachmentId,
      fileName: fileName,
      fileSize: fileSize,
      status: AudioTranscriptStatus.failed,
      errorMessage: sanitizeErrorMessage(error),
      createdAt: createdAt,
    );
  }

  Future<AudioTranscriptStatus?> readStatus({
    required String messageId,
    required String attachmentId,
  }) async {
    final file = transcriptFile(
      messageId: messageId,
      attachmentId: attachmentId,
    );
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file) return null;
    return parseStatus(await file.readAsString());
  }

  Future<AudioTranscriptDetails?> readDetails({
    required String messageId,
    required String attachmentId,
  }) async {
    final file = transcriptFile(
      messageId: messageId,
      attachmentId: attachmentId,
    );
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file) return null;
    final markdown = await file.readAsString();
    final status = parseStatus(markdown) ?? AudioTranscriptStatus.pending;
    final transcriptText = _extractTranscriptText(markdown, status);
    final statusMessage = _extractSection(markdown, '转写状态');
    return AudioTranscriptDetails(
      status: status,
      transcriptText: transcriptText,
      statusMessage: statusMessage,
    );
  }

  static String renderTranscript({
    required String messageId,
    required String attachmentId,
    required String fileName,
    required int fileSize,
    required DateTime createdAt,
    String? transcript,
    AudioTranscriptStatus? status,
    String? errorMessage,
  }) {
    final normalizedTranscript = transcript?.trim();
    final resolvedStatus =
        status ??
        (normalizedTranscript == null
            ? AudioTranscriptStatus.pending
            : normalizedTranscript.isEmpty
            ? AudioTranscriptStatus.empty
            : AudioTranscriptStatus.ready);
    final buffer = StringBuffer()
      ..writeln('# 语音转写稿件')
      ..writeln()
      ..writeln('- message_id: `${_escapeInline(messageId)}`')
      ..writeln('- attachment_id: `${_escapeInline(attachmentId)}`')
      ..writeln('- file_name: `${_escapeInline(fileName)}`')
      ..writeln('- file_size: `$fileSize`')
      ..writeln('- status: `${resolvedStatus.label}`')
      ..writeln('- created_at: `${_formatDateTime(createdAt)}`')
      ..writeln();
    if (resolvedStatus == AudioTranscriptStatus.failed) {
      buffer
        ..writeln('## 转写状态')
        ..writeln()
        ..writeln(
          sanitizeErrorMessage(errorMessage ?? '语音转文字失败，请检查 STT 配置或稍后重试。'),
        )
        ..writeln()
        ..writeln('## 转写正文')
        ..writeln()
        ..writeln('_转写失败，暂无可用正文_')
        ..writeln();
      return buffer.toString();
    }
    if (resolvedStatus == AudioTranscriptStatus.empty) {
      buffer
        ..writeln('## 转写状态')
        ..writeln()
        ..writeln('转写已完成，但未识别到可保存的文字。')
        ..writeln()
        ..writeln('## 转写正文')
        ..writeln()
        ..writeln('_未识别到文字_')
        ..writeln();
      return buffer.toString();
    }

    final hasTranscript =
        normalizedTranscript != null && normalizedTranscript.isNotEmpty;
    buffer
      ..writeln('## 转写正文')
      ..writeln()
      ..writeln(hasTranscript ? normalizedTranscript : '_等待语音转文字完成_')
      ..writeln();
    return buffer.toString();
  }

  static String sanitizeErrorMessage(Object? error) {
    const fallback = '语音转文字失败，请检查 STT 配置或稍后重试。';
    if (error == null) return fallback;

    var text = error.toString().trim();
    if (text.isEmpty) return fallback;
    if (text.startsWith('Exception: ')) {
      text = text.substring('Exception: '.length).trim();
    }
    text = text
        .replaceAll(
          RegExp(r'sk-[A-Za-z0-9_-]{8,}', caseSensitive: false),
          '[已隐藏密钥]',
        )
        .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
          'Bearer [已隐藏]',
        )
        .replaceAllMapped(
          RegExp(
            r'(api[_-]?key|token|secret|authorization)\s*[:=]\s*[^,\s)]+',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}=[已隐藏]',
        )
        .replaceAll(
          RegExp(r'https?://[^\s)]+', caseSensitive: false),
          '[已隐藏链接]',
        )
        .replaceAll(RegExp(r'(/[^\s`]+)+'), '[已隐藏路径]')
        .replaceAll(RegExp(r'[A-Za-z]:\\[^\s`]+'), '[已隐藏路径]')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty || text == '[已隐藏路径]') return fallback;
    if (text.length > 120) {
      text = '${text.substring(0, 120)}…';
    }
    return text;
  }

  static AudioTranscriptStatus? parseStatus(String markdown) {
    final match = RegExp(
      r'^\s*-\s*status:\s*`?([a-zA-Z_ -]+)`?\s*$',
      multiLine: true,
    ).firstMatch(markdown);
    final raw = match?.group(1)?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    for (final status in AudioTranscriptStatus.values) {
      if (status.label == raw) return status;
    }
    return null;
  }

  static String sanitizeId(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  static String? _extractTranscriptText(
    String markdown,
    AudioTranscriptStatus status,
  ) {
    if (status != AudioTranscriptStatus.ready) return null;
    final section = _extractSection(markdown, '转写正文');
    if (section == null || section.isEmpty) return null;
    const placeholders = {'_等待语音转文字完成_', '_未识别到文字_', '_转写失败，暂无可用正文_'};
    if (placeholders.contains(section.trim())) return null;
    return section.trim();
  }

  static String? _extractSection(String markdown, String heading) {
    final lines = markdown.split('\n');
    final target = '## $heading';
    final buffer = StringBuffer();
    var inSection = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (!inSection) {
        if (trimmed == target) inSection = true;
        continue;
      }
      if (trimmed.startsWith('## ')) break;
      buffer.writeln(line);
    }
    final value = buffer.toString().trim();
    return value.isEmpty ? null : value;
  }

  static String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static String _escapeInline(String value) => value.replaceAll('\n', ' ');
}
