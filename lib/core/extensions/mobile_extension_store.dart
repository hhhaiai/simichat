import 'dart:io';

import 'package:path/path.dart' as p;

import 'mobile_extension_manifest.dart';

/// Filesystem layout for mobile extensions.
///
/// ```text
/// <app support>/simichat_extensions/
///   registry.json
///   installed/<type>/<id>/<version>/manifest.json
///   quarantine/*.package
///   downloads/*.part
/// ```
class MobileExtensionStore {
  MobileExtensionStore({required Directory root}) : _root = root;

  final Directory _root;

  Directory get root => _root;
  Directory get installedRoot => Directory(p.join(_root.path, 'installed'));
  Directory get downloadsRoot => Directory(p.join(_root.path, 'downloads'));
  Directory get quarantineRoot => Directory(p.join(_root.path, 'quarantine'));

  Directory installationDirectory(MobileExtensionManifest manifest) {
    MobileExtensionManifest.validateRelativePath(manifest.id, field: 'id');
    MobileExtensionManifest.validateRelativePath(
      manifest.version,
      field: 'version',
    );
    return Directory(
      p.join(
        installedRoot.path,
        manifest.type.wireName,
        manifest.id,
        manifest.version,
      ),
    );
  }

  File fileIn(Directory directory, String relativePath) {
    MobileExtensionManifest.validateRelativePath(relativePath);
    final file = File(p.normalize(p.join(directory.path, relativePath)));
    final normalizedRoot = p.normalize(directory.absolute.path);
    final normalizedFile = p.normalize(file.absolute.path);
    if (normalizedFile != normalizedRoot &&
        !p.isWithin(normalizedRoot, normalizedFile)) {
      throw const MobileExtensionManifestException('文件路径逃逸安装目录');
    }
    return file;
  }

  Future<void> prepare() async {
    await installedRoot.create(recursive: true);
    await downloadsRoot.create(recursive: true);
    await quarantineRoot.create(recursive: true);
  }
}
