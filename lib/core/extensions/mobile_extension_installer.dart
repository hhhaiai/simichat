import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'mobile_extension_manifest.dart';
import 'mobile_extension_registry.dart';
import 'mobile_extension_store.dart';

const kMobileExtensionMaxDownloadBytes = 20 * 1024 * 1024;
final _packageSha256Pattern = RegExp(r'^[a-f0-9]{64}$');

class MobileExtensionInstallException implements Exception {
  const MobileExtensionInstallException(this.message, {this.quarantinePath});

  final String message;
  final String? quarantinePath;

  @override
  String toString() =>
      quarantinePath == null ? message : '$message (已隔离: $quarantinePath)';
}

class MobileExtensionInstallResult {
  const MobileExtensionInstallResult({
    required this.package,
    required this.record,
  });

  final MobileExtensionPackage package;
  final MobileExtensionRecord record;
}

/// Installs hash-checked, data-only mobile extension packages.
///
/// The entry hash proves package self-consistency.  Unless the caller also
/// supplies an expected package hash, it is not a publisher signature or a
/// trust decision; marketplace callers must pin that value before installing.
///
/// This installer never invokes npm, npx, a shell, Docker, Podman or a
/// downloaded executable. Node MCP packages are copied as JavaScript files and
/// are consumed only by the app-owned Node Mobile runtime contract.
class MobileExtensionInstaller {
  MobileExtensionInstaller({
    Directory? storageDirectory,
    http.Client? client,
    MobileExtensionStore? store,
    MobileExtensionRegistry? registry,
    this.maxDownloadBytes = kMobileExtensionMaxDownloadBytes,
  }) : _storageDirectory = storageDirectory,
       _client = client ?? http.Client(),
       _store = store,
       _registry = registry;

  final Directory? _storageDirectory;
  final http.Client _client;
  final MobileExtensionStore? _store;
  final MobileExtensionRegistry? _registry;
  final int maxDownloadBytes;
  static const _uuid = Uuid();
  Future<MobileExtensionStore>? _storeFuture;
  Future<MobileExtensionRegistry>? _registryFuture;

  void dispose() => _client.close();

  Future<MobileExtensionStore> get store async {
    final existing = _storeFuture;
    if (existing != null) return existing;
    final future = _createStore();
    _storeFuture = future;
    return future;
  }

  Future<MobileExtensionRegistry> get registry async {
    final existing = _registryFuture;
    if (existing != null) return existing;
    final extensionStore = await store;
    final future = Future<MobileExtensionRegistry>.value(
      _registry ?? MobileExtensionRegistry(root: extensionStore.root),
    );
    _registryFuture = future;
    return future;
  }

  Future<List<MobileExtensionRecord>> installed() async {
    return (await registry).load();
  }

  Future<MobileExtensionInstallResult> installBytes(
    List<int> bytes, {
    String? expectedPackageSha256,
  }) async {
    if (bytes.isEmpty) {
      throw const MobileExtensionInstallException('扩展包不能为空');
    }
    if (bytes.length > maxDownloadBytes) {
      throw const MobileExtensionInstallException('扩展包超过移动端大小限制');
    }
    final actualPackageSha256 = crypto.sha256.convert(bytes).toString();
    final expectedSha256 = expectedPackageSha256?.trim().toLowerCase();
    if (expectedSha256 != null &&
        (!_packageSha256Pattern.hasMatch(expectedSha256) ||
            actualPackageSha256 != expectedSha256)) {
      final quarantinePath = await _quarantine(bytes, 'package-sha-mismatch');
      throw MobileExtensionInstallException(
        '扩展包 SHA-256 校验失败',
        quarantinePath: quarantinePath,
      );
    }

    MobileExtensionPackage package;
    try {
      package = MobileExtensionPackage.fromBytes(bytes);
    } on Object catch (error) {
      final quarantinePath = await _quarantine(bytes, 'invalid-package');
      throw MobileExtensionInstallException(
        error.toString(),
        quarantinePath: quarantinePath,
      );
    }

    final extensionStore = await store;
    final extensionRegistry = await registry;
    await extensionStore.prepare();
    final manifest = package.manifest;
    final target = extensionStore.installationDirectory(manifest);
    final parent = target.parent;
    await parent.create(recursive: true);
    final stage = Directory(
      p.join(parent.path, '.${manifest.version}.installing-${_uuid.v4()}'),
    );
    Directory? backup;
    try {
      await stage.create(recursive: true);
      final manifestFile = extensionStore.fileIn(stage, 'manifest.json');
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
        flush: true,
      );
      for (final entry in package.files.entries) {
        final file = extensionStore.fileIn(stage, entry.key);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }

      if (await target.exists()) {
        backup = Directory(
          p.join(parent.path, '.${manifest.version}.backup-${_uuid.v4()}'),
        );
        await target.rename(backup.path);
      }
      await stage.rename(target.path);
      if (backup != null && await backup.exists()) {
        await backup.delete(recursive: true);
      }

      final record = MobileExtensionRecord(
        manifest: manifest,
        installPath: target.path,
        status: manifest.autoEnable
            ? MobileExtensionStatus.enabled
            : MobileExtensionStatus.installed,
        enabled: manifest.autoEnable,
        installedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await extensionRegistry.upsert(record);
      return MobileExtensionInstallResult(package: package, record: record);
    } on Object catch (error) {
      if (await stage.exists()) await stage.delete(recursive: true);
      if (backup != null && await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      throw MobileExtensionInstallException('安装扩展失败: $error');
    }
  }

  Future<MobileExtensionInstallResult> installFromUrl(
    Uri uri, {
    String? expectedPackageSha256,
  }) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const MobileExtensionInstallException('扩展包地址仅支持 HTTP(S)');
    }
    final extensionStore = await store;
    await extensionStore.prepare();
    final part = File(
      p.join(extensionStore.downloadsRoot.path, '${_uuid.v4()}.part'),
    );
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MobileExtensionInstallException(
          '扩展包下载失败: HTTP ${response.statusCode}',
        );
      }
      if (response.bodyBytes.length > maxDownloadBytes) {
        throw const MobileExtensionInstallException('扩展包超过移动端大小限制');
      }
      await part.writeAsBytes(response.bodyBytes, flush: true);
      final result = await installBytes(
        response.bodyBytes,
        expectedPackageSha256: expectedPackageSha256,
      );
      if (await part.exists()) await part.delete();
      return result;
    } on MobileExtensionInstallException catch (error) {
      if (error.quarantinePath != null) rethrow;
      final quarantinePath = await _movePartToQuarantine(part);
      if (quarantinePath == null) rethrow;
      throw MobileExtensionInstallException(
        error.message,
        quarantinePath: quarantinePath,
      );
    } on Object catch (error) {
      final quarantinePath = await _movePartToQuarantine(part);
      throw MobileExtensionInstallException(
        '扩展包下载或安装失败: $error',
        quarantinePath: quarantinePath,
      );
    } finally {
      if (await part.exists()) await part.delete();
    }
  }

  Future<MobileExtensionRecord?> enable(String id, {bool enabled = true}) {
    return registry.then((value) => value.setEnabled(id, enabled));
  }

  Future<void> uninstall(String id) async {
    final extensionRegistry = await registry;
    final record = await extensionRegistry.get(id);
    if (record == null) return;
    final extensionStore = await store;
    final root = p.normalize(extensionStore.installedRoot.absolute.path);
    final candidate = p.normalize(File(record.installPath).absolute.path);
    if (candidate != root && !p.isWithin(root, candidate)) {
      throw const MobileExtensionInstallException('拒绝删除安装目录之外的路径');
    }
    final directory = Directory(record.installPath);
    if (await directory.exists()) await directory.delete(recursive: true);
    await extensionRegistry.remove(id);
  }

  Future<MobileExtensionStore> _createStore() async {
    if (_store != null) return _store;
    final base =
        _storageDirectory ??
        Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'simichat_extensions',
          ),
        );
    return MobileExtensionStore(root: base);
  }

  Future<String> _quarantine(List<int> bytes, String reason) async {
    final extensionStore = await store;
    await extensionStore.prepare();
    final target = File(
      p.join(
        extensionStore.quarantineRoot.path,
        '${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}-$reason.package',
      ),
    );
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<String?> _movePartToQuarantine(File part) async {
    if (!await part.exists()) return null;
    final extensionStore = await store;
    final target = File(
      p.join(
        extensionStore.quarantineRoot.path,
        '${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}-download.part',
      ),
    );
    try {
      await part.rename(target.path);
      return target.path;
    } on FileSystemException {
      return null;
    }
  }
}
