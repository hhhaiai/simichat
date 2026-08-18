import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'structured_data_backup.dart';
import 'local_database_snapshot.dart';

class DataImportException implements Exception {
  const DataImportException(this.message);

  final String message;

  @override
  String toString() => 'DataImportException: $message';
}

class DataImportPreview {
  const DataImportPreview({
    required this.exportFile,
    required this.exportFormat,
    required this.createdAt,
    required this.includeAudioFiles,
    required this.manifestFileCount,
    required this.importableEntries,
    required this.unsupportedEntryCount,
    required this.existingFileCount,
    required this.totalBytes,
    required this.hasStructuredData,
    required this.existingStructuredData,
    required this.structuredKeyCount,
    required this.unsupportedStructuredKeyCount,
  });

  final File exportFile;
  final String exportFormat;
  final DateTime? createdAt;
  final bool includeAudioFiles;
  final int manifestFileCount;
  final List<DataImportEntryPreview> importableEntries;
  final int unsupportedEntryCount;
  final int existingFileCount;
  final int totalBytes;
  final bool hasStructuredData;
  final bool existingStructuredData;
  final int structuredKeyCount;
  final int unsupportedStructuredKeyCount;

  int get importableFileCount =>
      importableEntries.where((entry) => !entry.isStructuredData).length;

  String get summary {
    final structured = hasStructuredData ? '，结构化数据 $structuredKeyCount 项' : '';
    final structuredConflict = existingStructuredData ? '，已有本机结构化数据' : '';
    return '可导入 $importableFileCount 个文件$structured，已存在 $existingFileCount 个'
        '$structuredConflict，跳过 $unsupportedEntryCount 个不支持项';
  }
}

class DataImportEntryPreview {
  const DataImportEntryPreview({
    required this.path,
    required this.size,
    required this.exists,
    this.isStructuredData = false,
  });

  final String path;
  final int size;
  final bool exists;
  final bool isStructuredData;
}

class DataImportResult {
  const DataImportResult({
    required this.importedFiles,
    required this.skippedExistingFiles,
    required this.skippedUnsupportedFiles,
    required this.totalBytes,
    this.restoredStructuredKeys = 0,
    this.skippedExistingStructuredKeys = 0,
    this.skippedUnsupportedStructuredKeys = 0,
  });

  final int importedFiles;
  final int skippedExistingFiles;
  final int skippedUnsupportedFiles;
  final int totalBytes;
  final int restoredStructuredKeys;
  final int skippedExistingStructuredKeys;
  final int skippedUnsupportedStructuredKeys;

  String get summary {
    final structured =
        restoredStructuredKeys > 0 ||
            skippedExistingStructuredKeys > 0 ||
            skippedUnsupportedStructuredKeys > 0
        ? '；恢复结构化数据 $restoredStructuredKeys 项，'
              '跳过已有 $skippedExistingStructuredKeys 项，'
              '跳过不支持 $skippedUnsupportedStructuredKeys 项'
        : '';
    return '已导入 $importedFiles 个文件，跳过已有 $skippedExistingFiles 个，'
        '跳过不支持 $skippedUnsupportedFiles 个$structured';
  }
}

class DataImportService {
  const DataImportService({
    required this.rootDirectory,
    LocalDatabaseSnapshotService? localDatabaseSnapshotService,
  }) : _localDatabaseSnapshotService = localDatabaseSnapshotService;

  final Directory rootDirectory;
  final LocalDatabaseSnapshotService? _localDatabaseSnapshotService;

  Future<DataImportPreview> previewExport(File exportFile) async {
    final archive = await _readArchive(exportFile);
    return _buildPreview(exportFile, archive);
  }

  Future<DataImportResult> importExport(
    File exportFile, {
    bool overwriteExisting = false,
  }) async {
    final archive = await _readArchive(exportFile);
    final manifest = archive.manifest;
    var imported = 0;
    var skippedExisting = 0;
    var skippedUnsupported = 0;
    var totalBytes = 0;
    var restoredStructuredKeys = 0;
    var skippedExistingStructuredKeys = 0;
    var skippedUnsupportedStructuredKeys = 0;
    const structuredService = StructuredDataBackupService();

    for (final entry in archive.entries) {
      if (entry.path == 'manifest.json') continue;
      if (!_isSupportedImportPath(entry.path)) {
        skippedUnsupported++;
        continue;
      }
      _verifyChecksum(entry, manifest);
      if (entry.path == kStructuredDataArchivePath) {
        try {
          final result = await structuredService.restoreSharedPreferences(
            entry.bytes,
            overwriteExisting: overwriteExisting,
          );
          restoredStructuredKeys += result.restoredKeys;
          skippedExistingStructuredKeys += result.skippedExistingKeys;
          skippedUnsupportedStructuredKeys += result.skippedUnsupportedKeys;
          if (result.restoredKeys > 0) totalBytes += entry.bytes.length;
        } on FormatException {
          throw const DataImportException('结构化数据解析失败');
        }
        continue;
      }
      if (entry.path == kLocalDatabaseArchivePath) {
        final service = _localDatabaseSnapshotService;
        if (service == null) {
          skippedUnsupported++;
          continue;
        }
        try {
          final result = await service.restoreSnapshot(
            entry.bytes,
            overwriteExisting: overwriteExisting,
          );
          restoredStructuredKeys += result.restoredRecordCount;
          skippedExistingStructuredKeys += result.skippedExistingRecordCount;
          skippedUnsupportedStructuredKeys += result.skippedInvalidRecordCount;
          if (result.restoredRecordCount > 0) totalBytes += entry.bytes.length;
        } on FormatException {
          throw const DataImportException('本地数据库快照解析失败');
        }
        continue;
      }
      final output = File(p.join(rootDirectory.path, entry.path));
      if (await output.exists() && !overwriteExisting) {
        skippedExisting++;
        continue;
      }
      await output.parent.create(recursive: true);
      await output.writeAsBytes(entry.bytes, flush: true);
      imported++;
      totalBytes += entry.bytes.length;
    }

    return DataImportResult(
      importedFiles: imported,
      skippedExistingFiles: skippedExisting,
      skippedUnsupportedFiles: skippedUnsupported,
      totalBytes: totalBytes,
      restoredStructuredKeys: restoredStructuredKeys,
      skippedExistingStructuredKeys: skippedExistingStructuredKeys,
      skippedUnsupportedStructuredKeys: skippedUnsupportedStructuredKeys,
    );
  }

  Future<DataImportPreview> _buildPreview(
    File exportFile,
    _DataImportArchive archive,
  ) async {
    final manifest = archive.manifest;
    final importable = <DataImportEntryPreview>[];
    var unsupported = 0;
    var existing = 0;
    var totalBytes = 0;
    var hasStructuredData = false;
    var existingStructuredData = false;
    var structuredKeyCount = 0;
    var unsupportedStructuredKeyCount = 0;
    const structuredService = StructuredDataBackupService();
    for (final entry in archive.entries) {
      if (entry.path == 'manifest.json') continue;
      if (!_isSupportedImportPath(entry.path)) {
        unsupported++;
        continue;
      }
      _verifyChecksum(entry, manifest);
      if (entry.path == kStructuredDataArchivePath) {
        hasStructuredData = true;
        try {
          final structuredPreview = structuredService.previewSharedPreferences(
            entry.bytes,
          );
          structuredKeyCount += structuredPreview.supportedKeys;
          unsupportedStructuredKeyCount += structuredPreview.unsupportedKeys;
          existingStructuredData = await structuredService
              .hasAnyStoredPreference();
        } on FormatException {
          throw const DataImportException('结构化数据解析失败');
        }
        importable.add(
          DataImportEntryPreview(
            path: entry.path,
            size: entry.bytes.length,
            exists: existingStructuredData,
            isStructuredData: true,
          ),
        );
        totalBytes += entry.bytes.length;
        continue;
      }
      if (entry.path == kLocalDatabaseArchivePath) {
        final service = _localDatabaseSnapshotService;
        if (service == null) {
          unsupported++;
          continue;
        }
        hasStructuredData = true;
        try {
          final snapshotPreview = await service.previewSnapshot(entry.bytes);
          structuredKeyCount += snapshotPreview.totalRecordCount;
          unsupportedStructuredKeyCount += snapshotPreview.invalidMediaJobCount;
          existingStructuredData =
              existingStructuredData || snapshotPreview.existingRecordCount > 0;
          importable.add(
            DataImportEntryPreview(
              path: entry.path,
              size: entry.bytes.length,
              exists: snapshotPreview.existingRecordCount > 0,
              isStructuredData: true,
            ),
          );
          totalBytes += entry.bytes.length;
        } on FormatException {
          throw const DataImportException('本地数据库快照解析失败');
        }
        continue;
      }
      final output = File(p.join(rootDirectory.path, entry.path));
      final exists = output.existsSync();
      if (exists) existing++;
      importable.add(
        DataImportEntryPreview(
          path: entry.path,
          size: entry.bytes.length,
          exists: exists,
        ),
      );
      totalBytes += entry.bytes.length;
    }

    return DataImportPreview(
      exportFile: exportFile,
      exportFormat: manifest.exportFormat,
      createdAt: manifest.createdAt,
      includeAudioFiles: manifest.includeAudioFiles,
      manifestFileCount: manifest.fileCount,
      importableEntries: List.unmodifiable(importable),
      unsupportedEntryCount: unsupported,
      existingFileCount: existing,
      totalBytes: totalBytes,
      hasStructuredData: hasStructuredData,
      existingStructuredData: existingStructuredData,
      structuredKeyCount: structuredKeyCount,
      unsupportedStructuredKeyCount: unsupportedStructuredKeyCount,
    );
  }

  Future<_DataImportArchive> _readArchive(File exportFile) async {
    if (!await exportFile.exists()) {
      throw const DataImportException('导入文件不存在');
    }
    final fileName = p.basename(exportFile.path);
    if (!fileName.endsWith('.tar.gz') && !fileName.endsWith('.tgz')) {
      throw const DataImportException('只支持 .tar.gz / .tgz 导出包');
    }

    late List<int> tarBytes;
    try {
      tarBytes = gzip.decode(await exportFile.readAsBytes());
    } catch (_) {
      throw const DataImportException('导出包解压失败');
    }

    final entries = _readTarEntries(tarBytes);
    final manifestEntry = entries.where(
      (entry) => entry.path == 'manifest.json',
    );
    if (manifestEntry.isEmpty) {
      throw const DataImportException('导出包缺少 manifest.json');
    }
    final manifest = _ImportManifest.fromJsonBytes(manifestEntry.first.bytes);
    if (manifest.exportFormat != 'simichat.data_export.v1') {
      throw const DataImportException('导出包格式不受支持');
    }
    return _DataImportArchive(entries: entries, manifest: manifest);
  }
}

class _DataImportArchive {
  const _DataImportArchive({required this.entries, required this.manifest});

  final List<_TarEntry> entries;
  final _ImportManifest manifest;
}

class _ImportManifest {
  _ImportManifest({
    required this.exportFormat,
    required this.createdAt,
    required this.fileCount,
    required this.includeAudioFiles,
    required this.checksums,
  });

  final String exportFormat;
  final DateTime? createdAt;
  final int fileCount;
  final bool includeAudioFiles;
  final Map<String, String> checksums;

  static _ImportManifest fromJsonBytes(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, Object?>) {
        throw const DataImportException('manifest 格式错误');
      }
      final entries = json['entries'];
      final checksums = <String, String>{};
      if (entries is List) {
        for (final entry in entries) {
          if (entry is! Map) continue;
          final path = entry['path'];
          final sha = entry['sha256'];
          if (path is String && sha is String) {
            checksums[_normalizeImportPath(path)] = sha;
          }
        }
      }
      final createdAtText = json['created_at'];
      return _ImportManifest(
        exportFormat: json['export_format'] as String? ?? '',
        createdAt: createdAtText is String
            ? DateTime.tryParse(createdAtText)?.toLocal()
            : null,
        fileCount: json['file_count'] is int ? json['file_count'] as int : 0,
        includeAudioFiles: json['include_audio_files'] == true,
        checksums: checksums,
      );
    } on DataImportException {
      rethrow;
    } catch (_) {
      throw const DataImportException('manifest 解析失败');
    }
  }
}

class _TarEntry {
  const _TarEntry({required this.path, required this.bytes});

  final String path;
  final List<int> bytes;
}

List<_TarEntry> _readTarEntries(List<int> tarBytes) {
  final entries = <_TarEntry>[];
  var offset = 0;
  while (offset + 512 <= tarBytes.length) {
    final header = tarBytes.sublist(offset, offset + 512);
    if (header.every((byte) => byte == 0)) break;

    final typeFlag = header[156];
    final isRegularFile = typeFlag == 0 || typeFlag == 0x30;
    final rawName = _readTarString(header, 0, 100);
    final rawPrefix = _readTarString(header, 345, 155);
    final fullName = rawPrefix.isEmpty ? rawName : '$rawPrefix/$rawName';
    final path = _normalizeImportPath(fullName);
    final sizeText = _readTarString(header, 124, 12).trim();
    final size = int.tryParse(sizeText, radix: 8);
    if (size == null || size < 0) {
      throw const DataImportException('tar 文件大小字段无效');
    }

    offset += 512;
    if (offset + size > tarBytes.length) {
      throw const DataImportException('tar 文件内容不完整');
    }
    final bytes = tarBytes.sublist(offset, offset + size);
    if (isRegularFile && path.isNotEmpty) {
      entries.add(_TarEntry(path: path, bytes: bytes));
    }
    offset += size;
    offset += (512 - (size % 512)) % 512;
  }
  return entries;
}

String _readTarString(List<int> bytes, int offset, int length) {
  final slice = bytes.sublist(offset, offset + length);
  final end = slice.indexOf(0);
  return ascii.decode(end == -1 ? slice : slice.sublist(0, end));
}

String _normalizeImportPath(String rawPath) {
  if (rawPath.startsWith('/') || rawPath.contains('\\')) {
    throw const DataImportException('导出包包含非法路径');
  }
  final parts = p.posix
      .split(rawPath)
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.any((part) => part == '.' || part == '..')) {
    throw const DataImportException('导出包包含路径穿越');
  }
  return parts.join('/');
}

bool _isSupportedImportPath(String path) {
  return path == kStructuredDataArchivePath ||
      path == kLocalDatabaseArchivePath ||
      path.startsWith('conversations/') ||
      path.startsWith('audio_transcripts/') ||
      path.startsWith('audio_files/') ||
      path.startsWith('attachments/');
}

void _verifyChecksum(_TarEntry entry, _ImportManifest manifest) {
  final expected = manifest.checksums[entry.path];
  if (expected == null) {
    throw DataImportException('manifest 缺少 ${entry.path} 的校验信息');
  }
  final actual = sha256.convert(entry.bytes).toString();
  if (actual != expected) {
    throw DataImportException('${entry.path} 校验失败');
  }
}
