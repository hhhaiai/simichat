import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'mobile_extension_manifest.dart';

enum MobileExtensionStatus {
  available,
  downloading,
  downloaded,
  verifying,
  installing,
  installed,
  enabled,
  disabled,
  failed,
  quarantined,
}

extension MobileExtensionStatusJson on MobileExtensionStatus {
  String get wireName => name;

  static MobileExtensionStatus parse(Object? value) {
    final name = value?.toString();
    return MobileExtensionStatus.values.firstWhere(
      (status) => status.wireName == name,
      orElse: () => MobileExtensionStatus.failed,
    );
  }
}

class MobileExtensionRecord {
  const MobileExtensionRecord({
    required this.manifest,
    required this.installPath,
    required this.status,
    required this.enabled,
    required this.installedAt,
    this.lastError,
  });

  final MobileExtensionManifest manifest;
  final String installPath;
  final MobileExtensionStatus status;
  final bool enabled;
  final int installedAt;
  final String? lastError;

  MobileExtensionRecord copyWith({
    String? installPath,
    MobileExtensionStatus? status,
    bool? enabled,
    int? installedAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return MobileExtensionRecord(
      manifest: manifest,
      installPath: installPath ?? this.installPath,
      status: status ?? this.status,
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'manifest': manifest.toJson(),
    'installPath': installPath,
    'status': status.wireName,
    'enabled': enabled,
    'installedAt': installedAt,
    if (lastError != null) 'lastError': lastError,
  };

  factory MobileExtensionRecord.fromJson(Map<String, dynamic> json) {
    final rawManifest = json['manifest'];
    if (rawManifest is! Map) {
      throw const FormatException('registry record 缺少 manifest');
    }
    final installPath = json['installPath'];
    if (installPath is! String || installPath.trim().isEmpty) {
      throw const FormatException('registry record 缺少 installPath');
    }
    final installedAt = json['installedAt'];
    if (installedAt is! int) {
      throw const FormatException('registry record 缺少 installedAt');
    }
    return MobileExtensionRecord(
      manifest: MobileExtensionManifest.fromJson(
        rawManifest.cast<String, dynamic>(),
      ),
      installPath: installPath,
      status: MobileExtensionStatusJson.parse(json['status']),
      enabled: json['enabled'] == true,
      installedAt: installedAt,
      lastError: json['lastError']?.toString(),
    );
  }
}

/// Crash-safe registry for installed extensions.
///
/// The registry is intentionally separate from the Drift database: extension
/// packages can be installed before the main database is opened, and a
/// corrupted registry must not prevent chat history from loading.
class MobileExtensionRegistry {
  MobileExtensionRegistry({required Directory root}) : _root = root;

  final Directory _root;
  static const _fileName = 'registry.json';

  File get file => File(p.join(_root.path, _fileName));
  Directory get root => _root;

  Future<List<MobileExtensionRecord>> load() async {
    final registryFile = file;
    if (!await registryFile.exists()) return const [];
    try {
      final decoded = jsonDecode(await registryFile.readAsString());
      if (decoded is! List) throw const FormatException('registry 顶层必须是数组');
      final records = <MobileExtensionRecord>[];
      for (final item in decoded) {
        if (item is! Map) {
          throw const FormatException('registry record 必须是 object');
        }
        records.add(
          MobileExtensionRecord.fromJson(item.cast<String, dynamic>()),
        );
      }
      return records;
    } on Object {
      await _quarantineCorruptRegistry(registryFile);
      return const [];
    }
  }

  Future<MobileExtensionRecord?> get(String id) async {
    final records = await load();
    for (final record in records) {
      if (record.manifest.id == id) return record;
    }
    return null;
  }

  Future<void> upsert(MobileExtensionRecord record) async {
    final records = await load();
    final next = <MobileExtensionRecord>[
      for (final item in records)
        if (item.manifest.id != record.manifest.id) item,
      record,
    ]..sort((a, b) => a.manifest.id.compareTo(b.manifest.id));
    await _save(next);
  }

  Future<MobileExtensionRecord?> setEnabled(String id, bool enabled) async {
    final records = await load();
    final index = records.indexWhere((item) => item.manifest.id == id);
    if (index < 0) return null;
    final current = records[index];
    final next = current.copyWith(
      enabled: enabled,
      status: enabled
          ? MobileExtensionStatus.enabled
          : MobileExtensionStatus.disabled,
    );
    records[index] = next;
    await _save(records);
    return next;
  }

  Future<void> remove(String id) async {
    final records = await load();
    await _save(
      records.where((item) => item.manifest.id != id).toList(growable: false),
    );
  }

  Future<void> _save(List<MobileExtensionRecord> records) async {
    await _root.create(recursive: true);
    final temp = File(p.join(_root.path, '.$_fileName.tmp'));
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        records.map((record) => record.toJson()).toList(growable: false),
      ),
      flush: true,
    );
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _quarantineCorruptRegistry(File source) async {
    var target = File('${source.path}.corrupt');
    for (var index = 1; await target.exists(); index++) {
      target = File('${source.path}.corrupt.$index');
    }
    try {
      await source.rename(target.path);
    } on FileSystemException {
      // Loading the registry is best-effort; never turn recovery into a boot
      // blocker when the filesystem refuses a rename.
    }
  }
}
