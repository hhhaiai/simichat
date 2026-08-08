import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// Extension kinds that can be installed into the mobile application.
enum MobileExtensionType { mcp, skill, agent }

extension MobileExtensionTypeJson on MobileExtensionType {
  String get wireName => name;

  static MobileExtensionType parse(Object? value) {
    final wireName = value?.toString().trim().toLowerCase();
    return MobileExtensionType.values.firstWhere(
      (type) => type.wireName == wireName,
      orElse: () =>
          throw MobileExtensionManifestException('type 必须是 mcp、skill 或 agent'),
    );
  }
}

/// Execution models supported by the mobile extension contract.
enum MobileExtensionRuntime { dart, nodeMobile, declarative }

extension MobileExtensionRuntimeJson on MobileExtensionRuntime {
  String get wireName => switch (this) {
    MobileExtensionRuntime.dart => 'dart',
    MobileExtensionRuntime.nodeMobile => 'node-mobile',
    MobileExtensionRuntime.declarative => 'declarative',
  };

  static MobileExtensionRuntime parse(Object? value) {
    final wireName = value?.toString().trim().toLowerCase();
    return MobileExtensionRuntime.values.firstWhere(
      (runtime) => runtime.wireName == wireName,
      orElse: () => throw MobileExtensionManifestException(
        'runtime 必须是 dart、node-mobile 或 declarative',
      ),
    );
  }
}

/// Permissions are capabilities, not arbitrary operating-system privileges.
/// Unknown permissions are rejected so a newly introduced capability cannot
/// silently become available to old application versions.
const kMobileExtensionPermissions = <String>{
  'network',
  'filesystem.app_container',
  'clipboard',
  'photo_picker',
  'calendar',
  'contacts',
  'memory.read',
  'mcp.call',
};

/// Protocol contracts implemented by a JavaScript MCP package.  These are
/// deliberately explicit: a package that only has an npm CLI entry point is
/// not automatically runnable on a phone.  It must be adapted to one of the
/// in-process contracts and ship all of its JavaScript dependencies.
const kMobileMcpProtocols = <String>{'mobile-mcp-v1', 'stdio-compat-v1'};

const kMobileExtensionIdPattern = r'^[a-z0-9][a-z0-9._-]{1,127}$';
final _mobileExtensionIdPattern = RegExp(kMobileExtensionIdPattern);
final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

class MobileExtensionManifestException implements Exception {
  const MobileExtensionManifestException(this.message);

  final String message;

  @override
  String toString() => 'Invalid mobile extension manifest: $message';
}

/// Version 1 of the package manifest shared by MCP, Skill and Agent packages.
///
/// `sha256` and `sizeBytes` describe the entry file. The package envelope also
/// carries a deterministic set of supporting files. This keeps integrity
/// checks independent from JSON key ordering and makes a package easy to
/// inspect before it is installed.
class MobileExtensionManifest {
  const MobileExtensionManifest({
    required this.id,
    required this.version,
    required this.type,
    required this.entry,
    required this.sha256,
    required this.sizeBytes,
    required this.runtime,
    this.name,
    this.description,
    this.nativeAddon = false,
    this.permissions = const <String>[],
    this.protocol,
    this.mcpTransport,
    this.mcpServerId,
    this.autoEnable = false,
  });

  final String id;
  final String version;
  final MobileExtensionType type;
  final String entry;
  final String sha256;
  final int sizeBytes;
  final MobileExtensionRuntime runtime;
  final String? name;
  final String? description;
  final bool nativeAddon;
  final List<String> permissions;

  /// The in-process JavaScript contract used by a node-mobile MCP package.
  /// `stdio-compat-v1` is an adapter contract, not a child-process transport.
  final String? protocol;

  /// For an MCP package this is either `app_native` or `sse`.
  /// `node-mobile` packages use the local bundled runtime and do not set it.
  final String? mcpTransport;

  /// An app-native package may bind to a handler that is already shipped in
  /// the application. It cannot add a native handler at install time.
  final String? mcpServerId;
  final bool autoEnable;

  factory MobileExtensionManifest.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    if (!_mobileExtensionIdPattern.hasMatch(id)) {
      throw const MobileExtensionManifestException(
        'id 只能包含小写字母、数字、点、下划线和连字符，长度 2-128',
      );
    }

    final version = _requiredString(json, 'version');
    final entry = _requiredString(json, 'entry');
    _validateRelativePath(entry, field: 'entry');

    final sha256 = _requiredString(json, 'sha256').toLowerCase();
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw const MobileExtensionManifestException('sha256 必须是 64 位小写 hex');
    }

    final sizeBytes = _requiredInt(json, 'sizeBytes');
    if (sizeBytes <= 0) {
      throw const MobileExtensionManifestException('sizeBytes 必须大于 0');
    }
    if (sizeBytes > 10 * 1024 * 1024) {
      throw const MobileExtensionManifestException('entry 文件不能超过 10MB');
    }

    final type = MobileExtensionTypeJson.parse(json['type']);
    final runtime = MobileExtensionRuntimeJson.parse(json['runtime']);
    final nativeAddon = json['nativeAddon'] == true;
    if (nativeAddon) {
      throw const MobileExtensionManifestException('移动端扩展不允许携带 nativeAddon');
    }

    final permissions = _stringList(json['permissions'], field: 'permissions');
    final unknownPermissions = permissions
        .where(
          (permission) => !kMobileExtensionPermissions.contains(permission),
        )
        .toList(growable: false);
    if (unknownPermissions.isNotEmpty) {
      throw MobileExtensionManifestException(
        'permissions 包含未知 capability: ${unknownPermissions.join(', ')}',
      );
    }

    _validateTypeRuntime(type, runtime, entry);

    final protocol = _optionalString(json['protocol']);
    final mcpTransport = _optionalString(json['mcpTransport']);
    final mcpServerId = _optionalString(json['mcpServerId']);
    if (type == MobileExtensionType.mcp && mcpTransport != null) {
      if (mcpTransport != 'app_native' && mcpTransport != 'sse') {
        throw const MobileExtensionManifestException(
          'mcpTransport 只支持 app_native 或 sse',
        );
      }
      if (mcpTransport == 'app_native' &&
          (mcpServerId == null || mcpServerId.isEmpty)) {
        throw const MobileExtensionManifestException(
          'app_native MCP 必须声明 mcpServerId',
        );
      }
    }

    if (type == MobileExtensionType.mcp &&
        runtime == MobileExtensionRuntime.nodeMobile &&
        protocol != null &&
        !kMobileMcpProtocols.contains(protocol)) {
      throw MobileExtensionManifestException(
        'node-mobile MCP protocol 只支持: ${kMobileMcpProtocols.join(', ')}',
      );
    }

    return MobileExtensionManifest(
      id: id,
      version: version,
      type: type,
      entry: entry,
      sha256: sha256,
      sizeBytes: sizeBytes,
      runtime: runtime,
      name: _optionalString(json['name']),
      description: _optionalString(json['description']),
      nativeAddon: nativeAddon,
      permissions: List.unmodifiable(permissions),
      protocol: runtime == MobileExtensionRuntime.nodeMobile
          ? protocol ?? 'mobile-mcp-v1'
          : protocol,
      mcpTransport: mcpTransport,
      mcpServerId: mcpServerId,
      autoEnable: json['autoEnable'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'version': version,
    'type': type.wireName,
    'entry': entry,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'runtime': runtime.wireName,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    'nativeAddon': nativeAddon,
    'permissions': permissions,
    if (protocol != null) 'protocol': protocol,
    if (mcpTransport != null) 'mcpTransport': mcpTransport,
    if (mcpServerId != null) 'mcpServerId': mcpServerId,
    'autoEnable': autoEnable,
  };

  String encode() => jsonEncode(toJson());

  static void _validateTypeRuntime(
    MobileExtensionType type,
    MobileExtensionRuntime runtime,
    String entry,
  ) {
    switch (type) {
      case MobileExtensionType.mcp:
        if (runtime != MobileExtensionRuntime.nodeMobile &&
            runtime != MobileExtensionRuntime.dart) {
          throw const MobileExtensionManifestException(
            'MCP runtime 必须是 node-mobile 或 dart',
          );
        }
        if (runtime == MobileExtensionRuntime.nodeMobile &&
            !entry.toLowerCase().endsWith('.js') &&
            !entry.toLowerCase().endsWith('.mjs')) {
          throw const MobileExtensionManifestException(
            'node-mobile MCP entry 必须是 .js 或 .mjs',
          );
        }
        if (runtime == MobileExtensionRuntime.nodeMobile &&
            entry.toLowerCase().endsWith('.cjs')) {
          throw const MobileExtensionManifestException(
            'node-mobile MCP 不支持 CommonJS entry，请使用 .js 或 .mjs',
          );
        }
      case MobileExtensionType.skill:
        if (runtime != MobileExtensionRuntime.dart ||
            !entry.toLowerCase().endsWith('.md')) {
          throw const MobileExtensionManifestException(
            'Skill 必须使用 dart runtime 且 entry 为 Markdown',
          );
        }
      case MobileExtensionType.agent:
        if (runtime != MobileExtensionRuntime.declarative ||
            !entry.toLowerCase().endsWith('.json')) {
          throw const MobileExtensionManifestException(
            'Agent 必须使用 declarative runtime 且 entry 为 JSON',
          );
        }
    }
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    final string = value is String ? value.trim() : '';
    if (string.isEmpty) {
      throw MobileExtensionManifestException('$key 必填且不能为空');
    }
    return string;
  }

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final string = value.trim();
    return string.isEmpty ? null : string;
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    throw MobileExtensionManifestException('$key 必须是整数');
  }

  static List<String> _stringList(Object? value, {required String field}) {
    if (value == null) return const <String>[];
    if (value is! List) {
      throw MobileExtensionManifestException('$field 必须是字符串数组');
    }
    final result = <String>[];
    for (final item in value) {
      if (item is! String || item.trim().isEmpty) {
        throw MobileExtensionManifestException('$field 只能包含非空字符串');
      }
      result.add(item.trim());
    }
    return result.toSet().toList(growable: false);
  }

  static void _validateRelativePath(String value, {required String field}) {
    if (value.isEmpty || value.startsWith('/') || value.startsWith('\\')) {
      throw MobileExtensionManifestException('$field 不能是绝对路径');
    }
    final normalized = value.replaceAll('\\', '/');
    final segments = normalized.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw MobileExtensionManifestException('$field 包含不安全路径');
    }
    if (normalized.contains(':')) {
      throw MobileExtensionManifestException('$field 不能包含盘符');
    }
  }

  static void validateRelativePath(String value, {String field = 'path'}) {
    _validateRelativePath(value, field: field);
  }
}

/// JSON envelope used for mobile downloads. It is intentionally not an npm
/// archive: a package contains only a manifest and base64-encoded files.
class MobileExtensionPackage {
  const MobileExtensionPackage({
    required this.manifest,
    required this.files,
    this.packageFormat = 1,
  });

  final int packageFormat;
  final MobileExtensionManifest manifest;
  final Map<String, List<int>> files;

  factory MobileExtensionPackage.fromBytes(List<int> bytes) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on Object {
      throw const MobileExtensionManifestException('扩展包不是有效 UTF-8 JSON');
    }
    if (decoded is! Map) {
      throw const MobileExtensionManifestException('扩展包顶层必须是 JSON object');
    }
    final map = decoded.cast<String, dynamic>();
    final packageFormat = map['packageFormat'];
    if (packageFormat != 1) {
      throw MobileExtensionManifestException(
        '不支持的 packageFormat: ${packageFormat ?? '(missing)'}',
      );
    }
    final rawManifest = map['manifest'];
    if (rawManifest is! Map) {
      throw const MobileExtensionManifestException('扩展包缺少 manifest object');
    }
    final manifest = MobileExtensionManifest.fromJson(
      rawManifest.cast<String, dynamic>(),
    );
    final rawFiles = map['files'];
    if (rawFiles is! Map) {
      throw const MobileExtensionManifestException('扩展包缺少 files object');
    }
    final files = <String, List<int>>{};
    for (final entry in rawFiles.entries) {
      final name = entry.key.toString();
      MobileExtensionManifest.validateRelativePath(name);
      if (name == 'manifest.json') {
        throw const MobileExtensionManifestException(
          '扩展包不能覆盖安装器生成的 manifest.json',
        );
      }
      final encoded = entry.value;
      if (encoded is! String) {
        throw MobileExtensionManifestException('文件 $name 必须是 base64 字符串');
      }
      try {
        files[name] = List.unmodifiable(base64.decode(encoded));
      } on Object {
        throw MobileExtensionManifestException('文件 $name 不是有效 base64');
      }
    }
    if (!files.containsKey(manifest.entry)) {
      throw MobileExtensionManifestException(
        '扩展包缺少 entry 文件: ${manifest.entry}',
      );
    }
    final entryBytes = files[manifest.entry]!;
    if (entryBytes.length != manifest.sizeBytes) {
      throw MobileExtensionManifestException(
        'entry sizeBytes 不匹配: manifest=${manifest.sizeBytes}, actual=${entryBytes.length}',
      );
    }
    final actualSha256 = _sha256(entryBytes);
    if (actualSha256 != manifest.sha256) {
      throw MobileExtensionManifestException(
        'entry SHA-256 校验失败: expected=${manifest.sha256}, actual=$actualSha256',
      );
    }
    final totalBytes = files.values.fold<int>(
      0,
      (sum, item) => sum + item.length,
    );
    if (totalBytes > 20 * 1024 * 1024) {
      throw const MobileExtensionManifestException('扩展包总大小不能超过 20MB');
    }
    return MobileExtensionPackage(
      manifest: manifest,
      files: Map.unmodifiable(files),
      packageFormat: packageFormat,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'packageFormat': packageFormat,
    'manifest': manifest.toJson(),
    'files': <String, String>{
      for (final entry in files.entries) entry.key: base64.encode(entry.value),
    },
  };

  List<int> toBytes() => utf8.encode(jsonEncode(toJson()));

  static String _sha256(List<int> bytes) {
    return crypto.sha256.convert(bytes).toString();
  }
}
