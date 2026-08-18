import 'dart:io';

import 'package:path/path.dart' as p;

import '../storage/atomic_file_writer.dart';

class ArchivedAudioFile {
  final String localPath;
  final int fileSize;

  const ArchivedAudioFile({required this.localPath, required this.fileSize});
}

class AudioFileArchive {
  final Directory rootDirectory;

  const AudioFileArchive({required this.rootDirectory});

  Directory get audioDirectory =>
      Directory(p.join(rootDirectory.path, 'audio_files'));

  File archivedFile({
    required String messageId,
    required String attachmentId,
    required String fileName,
  }) {
    return File(
      p.join(
        audioDirectory.path,
        sanitizeId(messageId),
        '${sanitizeId(attachmentId)}${_safeExtension(fileName)}',
      ),
    );
  }

  Future<ArchivedAudioFile> archive({
    required String sourcePath,
    required String messageId,
    required String attachmentId,
    required String fileName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('语音文件不存在或已移动');
    }

    final destination = archivedFile(
      messageId: messageId,
      attachmentId: attachmentId,
      fileName: fileName,
    );
    await destination.parent.create(recursive: true);

    final sourcePathNormalized = p.normalize(source.absolute.path);
    final destinationPathNormalized = p.normalize(destination.absolute.path);
    if (sourcePathNormalized != destinationPathNormalized) {
      await copyFileAtomically(source, destination);
    }

    return ArchivedAudioFile(
      localPath: destination.path,
      fileSize: await destination.length(),
    );
  }

  static String sanitizeId(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  static String _safeExtension(String fileName) {
    final extension = p.extension(fileName).toLowerCase();
    if (extension.isEmpty) return '';
    if (!RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension)) return '';
    return extension;
  }
}
