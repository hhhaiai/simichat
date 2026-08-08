import 'dart:convert';

import '../skills/skill.dart';
import 'mobile_extension_installer.dart';
import 'mobile_extension_manifest.dart';

/// Converts an installed Skill package into the existing Skill database model.
Skill skillFromMobileExtension(MobileExtensionPackage package) {
  final manifest = package.manifest;
  if (manifest.type != MobileExtensionType.skill) {
    throw const MobileExtensionManifestException('扩展不是 Skill package');
  }
  final instructions = _decodeUtf8(
    package.files[manifest.entry]!,
    manifest.entry,
  );
  if (instructions.trim().isEmpty) {
    throw const MobileExtensionManifestException('Skill entry 不能为空');
  }
  return Skill(
    id: manifest.id,
    name: manifest.name ?? manifest.id,
    description: manifest.description ?? '',
    instructions: instructions,
    sourceUrl: 'simichat-extension://${manifest.id}/${manifest.version}',
    sourceSha256: manifest.sha256,
    sha256Verified: true,
    online: false,
    isEnabled: manifest.autoEnable,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
}

/// A portable MCP descriptor that the platform adapter can bind to
/// McpServerConfig without making the package format depend on Flutter UI.
class MobileMcpInstallDescriptor {
  const MobileMcpInstallDescriptor({
    required this.id,
    required this.name,
    required this.version,
    required this.runtime,
    required this.entry,
    required this.installPath,
    required this.sha256,
    this.protocol,
    this.transport,
    this.serverId,
    this.permissions = const <String>[],
  });

  final String id;
  final String name;
  final String version;
  final MobileExtensionRuntime runtime;
  final String entry;
  final String installPath;
  final String sha256;
  final String? protocol;
  final String? transport;
  final String? serverId;
  final List<String> permissions;

  bool get isAppNative => transport == 'app_native';
  bool get isNodeMobile => runtime == MobileExtensionRuntime.nodeMobile;

  factory MobileMcpInstallDescriptor.fromResult(
    MobileExtensionInstallResult result,
  ) {
    final manifest = result.package.manifest;
    if (manifest.type != MobileExtensionType.mcp) {
      throw const MobileExtensionManifestException('扩展不是 MCP package');
    }
    return MobileMcpInstallDescriptor(
      id: manifest.id,
      name: manifest.name ?? manifest.id,
      version: manifest.version,
      runtime: manifest.runtime,
      entry: manifest.entry,
      installPath: result.record.installPath,
      sha256: manifest.sha256,
      protocol: manifest.protocol,
      transport: manifest.mcpTransport,
      serverId: manifest.mcpServerId,
      permissions: manifest.permissions,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'version': version,
    'runtime': runtime.wireName,
    'entry': entry,
    'installPath': installPath,
    'sha256': sha256,
    if (protocol != null) 'protocol': protocol,
    if (transport != null) 'transport': transport,
    if (serverId != null) 'serverId': serverId,
    'permissions': permissions,
  };
}

String _decodeUtf8(List<int> bytes, String fileName) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw MobileExtensionManifestException('$fileName 不是有效 UTF-8 文本');
  }
}
