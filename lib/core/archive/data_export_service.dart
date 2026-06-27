import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'archive_attachment_path.dart' as attachment_path;
import 'structured_data_backup.dart';
import 'local_database_snapshot.dart';

typedef ExportableAttachmentLoader =
    Future<List<ExportableAttachment>> Function();
typedef LocalDatabaseExporter =
    Future<List<int>?> Function({required bool includeAudioFiles});

class ExportableAttachment {
  const ExportableAttachment({
    required this.id,
    required this.messageId,
    required this.fileType,
    required this.localPath,
    required this.fileName,
    required this.fileSize,
  });

  final String id;
  final String messageId;
  final String fileType;
  final String localPath;
  final String fileName;
  final int fileSize;
}

class DataExportResult {
  const DataExportResult({
    required this.file,
    required this.manifest,
    required this.uncompressedBytes,
    required this.compressedBytes,
  });

  final File file;
  final DataExportManifest manifest;
  final int uncompressedBytes;
  final int compressedBytes;
}

class DataExportManifest {
  const DataExportManifest({
    required this.createdAt,
    required this.fileCount,
    required this.uncompressedBytes,
    required this.entries,
    required this.includeAudioFiles,
  });

  final DateTime createdAt;
  final int fileCount;
  final int uncompressedBytes;
  final List<DataExportEntry> entries;
  final bool includeAudioFiles;

  Map<String, Object?> toJson() => {
    'export_format': 'simichat.data_export.v1',
    'created_at': createdAt.toUtc().toIso8601String(),
    'file_count': fileCount,
    'uncompressed_bytes': uncompressedBytes,
    'include_audio_files': includeAudioFiles,
    'privacy': {
      'local_only': true,
      'contains_api_keys': false,
      'note': '该导出包只从本机应用数据目录生成，不包含模型 API Key。请用户自行确认分享目标。',
    },
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };
}

class DataExportEntry {
  const DataExportEntry({
    required this.path,
    required this.size,
    required this.sha256Hex,
  });

  final String path;
  final int size;
  final String sha256Hex;

  Map<String, Object?> toJson() => {
    'path': path,
    'size': size,
    'sha256': sha256Hex,
  };
}

class DataExportService {
  const DataExportService({
    required this.rootDirectory,
    ExportableAttachmentLoader? listAttachments,
    LocalDatabaseExporter? exportLocalDatabase,
    DateTime Function()? now,
  }) : _listAttachments = listAttachments,
       _exportLocalDatabase = exportLocalDatabase,
       _now = now;

  final Directory rootDirectory;
  final ExportableAttachmentLoader? _listAttachments;
  final LocalDatabaseExporter? _exportLocalDatabase;
  final DateTime Function()? _now;

  Directory get exportsDirectory =>
      Directory(p.join(rootDirectory.path, 'exports'));

  Future<DataExportResult> exportLocalData({
    bool includeAudioFiles = true,
    bool includeStructuredData = true,
    Directory? outputDirectory,
  }) async {
    final createdAt = (_now ?? DateTime.now)().toUtc();
    final exportDir = outputDirectory ?? exportsDirectory;
    await exportDir.create(recursive: true);

    final entries = await _collectEntries(
      includeAudioFiles: includeAudioFiles,
      includeStructuredData: includeStructuredData,
      createdAt: createdAt,
    );
    final manifest = DataExportManifest(
      createdAt: createdAt,
      fileCount: entries.length,
      uncompressedBytes: entries.fold<int>(
        0,
        (sum, entry) => sum + entry.bytes.length,
      ),
      entries: entries
          .map(
            (entry) => DataExportEntry(
              path: entry.archivePath,
              size: entry.bytes.length,
              sha256Hex: sha256.convert(entry.bytes).toString(),
            ),
          )
          .toList(growable: false),
      includeAudioFiles: includeAudioFiles,
    );

    final tar = _TarWriter();
    final manifestBytes = utf8.encode(_prettyJson(manifest.toJson()));
    tar.addFile('manifest.json', manifestBytes, modifiedAt: createdAt);
    for (final entry in entries) {
      tar.addFile(entry.archivePath, entry.bytes, modifiedAt: entry.modifiedAt);
    }
    final tarBytes = tar.close();
    final compressedBytes = GZipCodec(level: 6).encode(tarBytes);
    final output = File(p.join(exportDir.path, _exportFileName(createdAt)));
    await output.writeAsBytes(compressedBytes, flush: true);

    return DataExportResult(
      file: output,
      manifest: manifest,
      uncompressedBytes: tarBytes.length,
      compressedBytes: compressedBytes.length,
    );
  }

  Future<List<_CollectedExportEntry>> _collectEntries({
    required bool includeAudioFiles,
    required bool includeStructuredData,
    required DateTime createdAt,
  }) async {
    final directories = <String>[
      'conversations',
      'audio_transcripts',
      if (includeAudioFiles) 'audio_files',
    ];
    final entries = <_CollectedExportEntry>[];
    for (final directoryName in directories) {
      final dir = Directory(p.join(rootDirectory.path, directoryName));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relativePath = p.relative(entity.path, from: rootDirectory.path);
        final archivePath = _normalizeArchivePath(relativePath);
        if (archivePath.isEmpty || archivePath.startsWith('exports/')) continue;
        final bytes = await entity.readAsBytes();
        final stat = await entity.stat();
        entries.add(
          _CollectedExportEntry(
            archivePath: archivePath,
            bytes: bytes,
            modifiedAt: stat.modified.toUtc(),
          ),
        );
      }
    }
    if (includeStructuredData) {
      final structuredBytes = await StructuredDataBackupService(
        now: () => createdAt,
      ).exportSharedPreferences();
      if (structuredBytes != null) {
        entries.add(
          _CollectedExportEntry(
            archivePath: kStructuredDataArchivePath,
            bytes: structuredBytes,
            modifiedAt: createdAt,
          ),
        );
      }
      final localDatabaseBytes = await _exportLocalDatabase?.call(
        includeAudioFiles: includeAudioFiles,
      );
      if (localDatabaseBytes != null) {
        entries.add(
          _CollectedExportEntry(
            archivePath: kLocalDatabaseArchivePath,
            bytes: localDatabaseBytes,
            modifiedAt: createdAt,
          ),
        );
      }
    }
    entries.addAll(await _collectAttachmentEntries(existingEntries: entries));
    entries.sort((a, b) => a.archivePath.compareTo(b.archivePath));
    return entries;
  }

  Future<List<_CollectedExportEntry>> _collectAttachmentEntries({
    required List<_CollectedExportEntry> existingEntries,
  }) async {
    final loader = _listAttachments;
    if (loader == null) return const [];

    final rootCanonical = await _resolveCanonicalDirectory(rootDirectory);
    final exportsCanonical = rootCanonical == null
        ? null
        : p.join(rootCanonical, 'exports');
    final usedPaths = existingEntries.map((entry) => entry.archivePath).toSet();
    final entries = <_CollectedExportEntry>[];
    final attachments = await loader();

    for (final attachment in attachments) {
      if (attachment.fileType.toLowerCase() == 'audio') continue;

      final source = File(attachment.localPath);
      final entityType = await FileSystemEntity.type(
        source.path,
        followLinks: false,
      );
      if (entityType != FileSystemEntityType.file) continue;

      late final String sourceCanonical;
      try {
        sourceCanonical = await source.resolveSymbolicLinks();
      } catch (_) {
        continue;
      }
      if (exportsCanonical != null &&
          (p.equals(sourceCanonical, exportsCanonical) ||
              p.isWithin(exportsCanonical, sourceCanonical))) {
        continue;
      }

      final stat = await source.stat();
      final archivePath = _dedupeArchivePath(
        buildAttachmentArchivePath(attachment),
        usedPaths,
      );
      final bytes = await source.readAsBytes();
      entries.add(
        _CollectedExportEntry(
          archivePath: archivePath,
          bytes: bytes,
          modifiedAt: stat.modified.toUtc(),
        ),
      );
    }

    return entries;
  }
}

String _prettyJson(Object? value) {
  return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
}

String _exportFileName(DateTime createdAt) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'simichat-export-${createdAt.year}'
      '${two(createdAt.month)}${two(createdAt.day)}-'
      '${two(createdAt.hour)}${two(createdAt.minute)}${two(createdAt.second)}.tar.gz';
}

String _normalizeArchivePath(String relativePath) {
  final parts = p
      .split(relativePath)
      .where((part) {
        return part.isNotEmpty && part != '.' && part != '..';
      })
      .toList(growable: false);
  return parts.join('/');
}

Future<String?> _resolveCanonicalDirectory(Directory directory) async {
  try {
    return await directory.resolveSymbolicLinks();
  } catch (_) {
    return null;
  }
}

String buildAttachmentArchivePath(ExportableAttachment attachment) {
  return attachment_path.buildAttachmentArchivePath(
    attachmentId: attachment.id,
    messageId: attachment.messageId,
    fileName: attachment.fileName,
  );
}

String _dedupeArchivePath(String archivePath, Set<String> usedPaths) {
  var candidate = _normalizeArchivePath(archivePath);
  if (usedPaths.add(candidate)) return candidate;

  final extension = p.extension(candidate);
  final withoutExtension = extension.isEmpty
      ? candidate
      : candidate.substring(0, candidate.length - extension.length);
  var index = 2;
  do {
    candidate = '$withoutExtension-$index$extension';
    index++;
  } while (!usedPaths.add(candidate));
  return candidate;
}

class _CollectedExportEntry {
  const _CollectedExportEntry({
    required this.archivePath,
    required this.bytes,
    required this.modifiedAt,
  });

  final String archivePath;
  final List<int> bytes;
  final DateTime modifiedAt;
}

class _TarWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void addFile(String name, List<int> bytes, {required DateTime modifiedAt}) {
    final normalizedName = _normalizeArchivePath(name);
    if (normalizedName.isEmpty || normalizedName.startsWith('/')) {
      throw ArgumentError.value(
        name,
        'name',
        'Tar entry path must be relative',
      );
    }
    final header = Uint8List(512);
    final splitName = _splitUstarName(normalizedName);
    _writeAscii(header, 0, 100, splitName.name);
    _writeOctal(header, 100, 8, 0x1a4); // 0644
    _writeOctal(header, 108, 8, 0);
    _writeOctal(header, 116, 8, 0);
    _writeOctal(header, 124, 12, bytes.length);
    _writeOctal(
      header,
      136,
      12,
      modifiedAt.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
    );
    for (var i = 148; i < 156; i++) {
      header[i] = 0x20;
    }
    header[156] = 0x30; // regular file
    _writeAscii(header, 257, 6, 'ustar');
    _writeAscii(header, 263, 2, '00');
    if (splitName.prefix.isNotEmpty) {
      _writeAscii(header, 345, 155, splitName.prefix);
    }
    final checksum = header.fold<int>(0, (sum, byte) => sum + byte);
    _writeChecksum(header, checksum);

    _builder.add(header);
    _builder.add(bytes);
    final padding = (512 - (bytes.length % 512)) % 512;
    if (padding > 0) _builder.add(Uint8List(padding));
  }

  List<int> close() {
    _builder.add(Uint8List(1024));
    return _builder.takeBytes();
  }
}

({String name, String prefix}) _splitUstarName(String path) {
  final encoded = utf8.encode(path);
  if (encoded.length <= 100) return (name: path, prefix: '');
  final parts = path.split('/');
  for (var i = 1; i < parts.length; i++) {
    final prefix = parts.take(i).join('/');
    final name = parts.skip(i).join('/');
    if (utf8.encode(prefix).length <= 155 && utf8.encode(name).length <= 100) {
      return (name: name, prefix: prefix);
    }
  }
  throw ArgumentError.value(path, 'path', 'Path is too long for ustar');
}

void _writeAscii(Uint8List header, int offset, int length, String value) {
  final bytes = ascii.encode(value);
  if (bytes.length > length) {
    throw ArgumentError.value(value, 'value', 'ASCII field is too long');
  }
  header.setRange(offset, offset + bytes.length, bytes);
}

void _writeOctal(Uint8List header, int offset, int length, int value) {
  final octal = value.toRadixString(8).padLeft(length - 1, '0');
  final bytes = ascii.encode(octal);
  header.setRange(offset, offset + bytes.length, bytes);
  header[offset + length - 1] = 0;
}

void _writeChecksum(Uint8List header, int checksum) {
  final octal = checksum.toRadixString(8).padLeft(6, '0');
  final bytes = ascii.encode(octal);
  header.setRange(148, 148 + bytes.length, bytes);
  header[154] = 0;
  header[155] = 0x20;
}
