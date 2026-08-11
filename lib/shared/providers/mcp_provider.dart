import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mcp/mcp_client.dart';
import '../../core/mcp/bundled_node_runtime.dart';
import '../../core/mcp/mobile_npx_resolver.dart';
import '../../core/database/dao/mcp_dao.dart';
import 'database_provider.dart';

/// MCP 服务器配置
class McpServerConfig {
  final String id;
  final String name;
  final String transport; // 'app_native' | 'stdio' | 'sse'
  final String? command;
  final List<String>? args;
  final String? url;
  final Map<String, String>? headers;
  final bool isEnabled;
  final String source; // 'manual' | 'marketplace'
  final String? marketplaceId;

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.transport,
    this.command,
    this.args,
    this.url,
    this.headers,
    this.isEnabled = true,
    this.source = 'manual',
    this.marketplaceId,
  });

  McpServerConfig copyWith({
    String? id,
    String? name,
    String? transport,
    String? command,
    List<String>? args,
    String? url,
    Map<String, String>? headers,
    bool? isEnabled,
    String? source,
    String? marketplaceId,
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      transport: transport ?? this.transport,
      command: command ?? this.command,
      args: args ?? this.args,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      isEnabled: isEnabled ?? this.isEnabled,
      source: source ?? this.source,
      marketplaceId: marketplaceId ?? this.marketplaceId,
    );
  }
}

// JSON 序列化辅助
String? _listToJson(List<String>? list) =>
    list != null ? jsonEncode(list) : null;

List<String>? _listFromJson(String? json) {
  if (json == null || json.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return null;
    return decoded.whereType<String>().toList(growable: false);
  } on Object {
    // 旧版本或手工修改过的数据库不能阻塞移动端启动。
    return null;
  }
}

String? _mapToJson(Map<String, String>? map) =>
    map != null ? jsonEncode(map) : null;

Map<String, String>? _mapFromJson(String? json) {
  if (json == null || json.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    return decoded.map<String, String>((key, value) {
      return MapEntry(key.toString(), value.toString());
    });
  } on Object {
    // headers 是可选配置；损坏时安全降级为空，而不是让 provider 失败。
    return null;
  }
}

bool get isMobileMcpPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Platforms where SimiChat owns the MCP runtime and can install a verified
/// pure-JS extension without a host `node`/`npx` command.
bool get isAppManagedMcpExtensionPlatform =>
    isMobileMcpPlatform || BundledNodeRuntime.isDesktop;

class McpUnsupportedTransportException implements Exception {
  const McpUnsupportedTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

const kBundledNodeMcpServerId = 'simichat-node-bundled';
const kContainerMcpServerId = 'simichat-node-container';
const kMobileExtensionMarketplacePrefix = 'mobile-extension:';
const kMobileExtensionRootConfigKey = 'x-simichat-extension-root';
const kMobileExtensionEntryConfigKey = 'x-simichat-extension-entry';
const kMobileExtensionProtocolConfigKey = 'x-simichat-extension-protocol';
const kMobileExtensionSha256ConfigKey = 'x-simichat-extension-sha256';
const kMobileExtensionPermissionsConfigKey = 'x-simichat-extension-permissions';

/// Mobile supports the MCP stdio configuration shape through an app-owned
/// JSON-Lines stdio session. It cannot run a host shell command or download an
/// arbitrary npm package. The command is therefore resolved to either an
/// audited bundled mobile package or an installed Node Mobile extension.
const kMobileStdioCompatibilityError =
    '移动端 stdio 需要随 App 分发的移动 Runtime：未知 command 不会执行。';

String? mobileExtensionIdForMcpConfig(McpServerConfig config) {
  final marketplaceId = config.marketplaceId;
  if (marketplaceId == null ||
      !marketplaceId.startsWith(kMobileExtensionMarketplacePrefix)) {
    return null;
  }
  final id = marketplaceId.substring(kMobileExtensionMarketplacePrefix.length);
  return id.isEmpty ? null : id;
}

bool hasMobileExtensionRegistrationMetadata(McpServerConfig config) {
  final headers = config.headers;
  if (mobileExtensionIdForMcpConfig(config) == null || headers == null) {
    return false;
  }
  return [
    headers[kMobileExtensionRootConfigKey],
    headers[kMobileExtensionEntryConfigKey],
    headers[kMobileExtensionProtocolConfigKey],
    headers[kMobileExtensionSha256ConfigKey],
  ].every((value) => value != null && value.isNotEmpty);
}

String mobileStdioDescription(McpServerConfig config) {
  final legacy = MobileNpxResolver.resolve(
    command: config.command ?? '',
    args: config.args ?? const <String>[],
  );
  if (legacy != null) return '移动端 stdio · 内置 Runtime';
  if (hasMobileExtensionRegistrationMetadata(config)) {
    return '移动端 stdio · Node Runtime';
  }
  return 'stdio · 需要移动兼容 Runtime';
}

bool isPcOnlyMcpConfig(McpServerConfig config) {
  return config.marketplaceId == kContainerMcpServerId;
}

/// MCP 管理器：管理多个 MCP 服务器连接，持久化到数据库
class McpManager extends StateNotifier<List<McpServerConfig>> {
  final McpDao _dao;
  final bool _mobilePlatform;
  final Map<String, McpClient> _clients = {};
  final Set<String> _connectedIds = <String>{};
  final Map<String, String> _connectionErrors = <String, String>{};
  late final Future<void> ready;
  bool _disposed = false;

  McpManager(this._dao, {bool? mobilePlatform})
    : _mobilePlatform = mobilePlatform ?? isMobileMcpPlatform,
      super([]) {
    ready = _loadFromDb();
  }

  Map<String, McpClient> get clients => _clients;
  bool isConnected(String id) => _connectedIds.contains(id);
  String? connectionErrorFor(String id) => _connectionErrors[id];

  Future<void> _loadFromDb() async {
    final rows = await _dao.getAllServers();
    final configs = rows
        .map(
          (r) => McpServerConfig(
            id: r.id,
            name: r.name,
            transport: r.transport,
            command: r.command,
            args: _listFromJson(r.args),
            url: r.url,
            headers: _mapFromJson(r.headers),
            isEnabled: r.isEnabled,
            source: r.source,
            marketplaceId: r.marketplaceId,
          ),
        )
        .toList();
    state = configs;

    // 自动连接已启用的服务器
    for (final config in configs) {
      if (_mobilePlatform && isPcOnlyMcpConfig(config)) {
        // Older databases may contain the PC container row from before the
        // Marketplace guard was added. Disable it during migration instead
        // of attempting a loopback SSE connection on a phone.
        _connectionErrors[config.id] = 'Node 容器 Runtime 仅支持 PC + Docker/Podman';
        if (config.isEnabled) {
          try {
            await _dao.updateServer(
              id: config.id,
              name: config.name,
              isEnabled: false,
              command: config.command,
              args: _listToJson(config.args),
              url: config.url,
              headers: _mapToJson(config.headers),
            );
          } on Object catch (disableError) {
            debugPrint(
              '[MCP] Failed to disable PC-only server ${config.id}: $disableError',
            );
          }
        }
        state = state
            .map(
              (server) => server.id == config.id
                  ? server.copyWith(isEnabled: false)
                  : server,
            )
            .toList();
        continue;
      }
      if (config.isEnabled) {
        try {
          await connectServer(config);
        } catch (e) {
          // 连接失败不阻塞启动，但记录日志
          _connectionErrors[config.id] = e.toString();
          debugPrint('[MCP] Failed to connect ${config.name}: $e');
          // A stale enabled row must not create a retry loop on every cold
          // start (especially for dead SSE/container endpoints). Keep the
          // failure visible and require an explicit user retry from Settings.
          try {
            await _dao.updateServer(
              id: config.id,
              name: config.name,
              isEnabled: false,
              command: config.command,
              args: _listToJson(config.args),
              url: config.url,
              headers: _mapToJson(config.headers),
            );
            state = state
                .map(
                  (server) => server.id == config.id
                      ? server.copyWith(isEnabled: false)
                      : server,
                )
                .toList();
          } on Object catch (disableError) {
            debugPrint(
              '[MCP] Failed to disable stale server ${config.id}: $disableError',
            );
          }
        }
      }
    }
    state = [...state];
  }

  Future<void> addServer(McpServerConfig config) async {
    await _dao.insertServer(
      id: config.id,
      name: config.name,
      transport: config.transport,
      command: config.command,
      args: _listToJson(config.args),
      url: config.url,
      headers: _mapToJson(config.headers),
      isEnabled: config.isEnabled,
      source: config.source,
      marketplaceId: config.marketplaceId,
    );
    state = [...state, config];
  }

  Future<void> removeServer(String id) async {
    await disconnectServer(id);
    await _dao.deleteServer(id);
    state = state.where((s) => s.id != id).toList();
  }

  Future<void> updateServer(McpServerConfig config) async {
    // 断开旧连接（配置可能已变）
    await disconnectServer(config.id);
    await _dao.updateServer(
      id: config.id,
      name: config.name,
      isEnabled: config.isEnabled,
      command: config.command,
      args: _listToJson(config.args),
      url: config.url,
      headers: _mapToJson(config.headers),
    );
    state = state.map((s) => s.id == config.id ? config : s).toList();
  }

  /// Persist only the enabled flag without tearing down an active connection.
  ///
  /// Extension toggles use this instead of `updateServer`: the latter always
  /// disconnects first, which makes it impossible to atomically enable a
  /// previously disabled MCP and then connect it. Keeping the flag in the
  /// Drift row aligned with the extension registry also prevents a disabled
  /// extension from being auto-connected again on the next cold start.
  Future<void> setServerEnabled(String id, bool enabled) async {
    final current = state.where((server) => server.id == id).firstOrNull;
    if (current == null) {
      throw StateError('MCP server not found: $id');
    }
    await _dao.updateServer(
      id: current.id,
      name: current.name,
      isEnabled: enabled,
      command: current.command,
      args: _listToJson(current.args),
      url: current.url,
      headers: _mapToJson(current.headers),
    );
    state = state
        .map((server) => server.id == id
            ? server.copyWith(isEnabled: enabled)
            : server)
        .toList();
  }

  Future<void> connectServer(McpServerConfig config) async {
    if (_disposed) {
      throw StateError('MCP manager has been disposed');
    }

    // 断开已有连接（避免资源泄漏）
    await disconnectServer(config.id);

    McpTransport transport;
    String? registeredMobileExtensionId;
    if (config.transport == kMcpTransportAppNative) {
      transport = AppNativeMcpTransport(
        serverId: config.marketplaceId ?? config.id,
      );
    } else if (config.transport == kMcpTransportStdio) {
      final extensionId = mobileExtensionIdForMcpConfig(config);
      if (extensionId != null &&
          hasMobileExtensionRegistrationMetadata(config)) {
        // A verified pure-JS extension can use the same app-owned JSONL
        // bridge on mobile and desktop. Desktop never falls back to a host
        // command for this path.
        await _registerMobileExtension(config, extensionId);
        registeredMobileExtensionId = extensionId;
        transport = MobileStdioTransport(
          command: config.command ?? '',
          args: config.args ?? const <String>[],
          serverId: extensionId,
        );
      } else if (_mobilePlatform) {
        final resolution = MobileNpxResolver.resolve(
          command: config.command ?? '',
          args: config.args ?? const <String>[],
        );
        // Unit tests can inject mobilePlatform=true while running on a host
        // Dart VM. Do not start the real local Runtime in that synthetic
        // environment; production Android/iOS always takes MobileStdioTransport.
        if (!BundledNodeRuntime.isMobile && resolution != null) {
          transport = AppNativeMcpTransport(
            serverId: 'test-mobile-npx:${resolution.packageName}',
            profile: resolution.profile,
          );
          final client = McpClient(name: config.name, transport: transport);
          try {
            await client.initialize();
            _clients[config.id] = client;
            _connectedIds.add(config.id);
            _connectionErrors.remove(config.id);
            state = [...state];
          } catch (e) {
            _connectedIds.remove(config.id);
            _connectionErrors[config.id] = e.toString();
            await client.dispose();
            state = [...state];
            rethrow;
          }
          return;
        }
        if (resolution == null &&
            (!hasMobileExtensionRegistrationMetadata(config) ||
                extensionId == null)) {
          throw const McpUnsupportedTransportException(
            kMobileStdioCompatibilityError,
          );
        }
        transport = MobileStdioTransport(
          command: config.command ?? '',
          args: config.args ?? const <String>[],
          // Bundled audited profiles are resolved from command + args by the
          // Runtime itself. `serverId` is reserved for a registered package;
          // passing a synthetic mobile-npx id would make the Runtime look for
          // a non-existent extension instead of selecting its built-in profile.
          serverId: extensionId,
        );
      } else if (BundledNodeRuntime.isDesktop) {
        // The same audited profiles can run on desktop without falling back
        // to a host `npx`. Unknown commands retain the normal desktop stdio
        // escape hatch for manually configured, user-owned processes.
        final resolution = MobileNpxResolver.resolve(
          command: config.command ?? '',
          args: config.args ?? const <String>[],
        );
        if (resolution != null) {
          transport = MobileStdioTransport(
            command: config.command ?? '',
            args: config.args ?? const <String>[],
          );
        } else {
          if (config.command == null || config.command!.isEmpty) {
            throw Exception('MCP stdio server requires a command');
          }
          transport = StdioTransport(
            command: config.command!,
            args: config.args ?? [],
          );
        }
      } else {
        if (config.command == null || config.command!.isEmpty) {
          throw Exception('MCP stdio server requires a command');
        }
        transport = StdioTransport(
          command: config.command!,
          args: config.args ?? [],
        );
      }
    } else if (config.transport == kMcpTransportSse) {
      if (config.url == null || config.url!.isEmpty) {
        throw Exception('MCP SSE server requires a URL');
      }
      if (config.marketplaceId == kBundledNodeMcpServerId) {
        final runtime = await BundledNodeRuntime.start();
        if (runtime['running'] != true) {
          throw Exception(
            '随应用分发的 Node Runtime 未运行: ${runtime['message'] ?? runtime}',
          );
        }
      }
      final extensionId =
          config.marketplaceId != null &&
              config.marketplaceId!.startsWith(
                kMobileExtensionMarketplacePrefix,
              )
          ? config.marketplaceId!.substring(
              kMobileExtensionMarketplacePrefix.length,
            )
          : null;
      if (extensionId != null) {
        await _registerMobileExtension(config, extensionId);
        registeredMobileExtensionId = extensionId;
      }
      transport = SseTransport(url: config.url!, headers: config.headers ?? {});
    } else {
      throw Exception('Unsupported MCP transport: ${config.transport}');
    }

    final client = McpClient(name: config.name, transport: transport);
    try {
      await client.initialize();
      _clients[config.id] = client;
      _connectedIds.add(config.id);
      _connectionErrors.remove(config.id);
      state = [...state];
    } catch (e) {
      _connectedIds.remove(config.id);
      _connectionErrors[config.id] = e.toString();
      await client.dispose();
      if (registeredMobileExtensionId != null) {
        await _unregisterMobileExtension(registeredMobileExtensionId);
      }
      state = [...state];
      rethrow;
    }
  }

  Future<void> _registerMobileExtension(
    McpServerConfig config,
    String extensionId,
  ) async {
    final headers = config.headers ?? const <String, String>{};
    final root = headers[kMobileExtensionRootConfigKey];
    final entry = headers[kMobileExtensionEntryConfigKey];
    final protocol = headers[kMobileExtensionProtocolConfigKey];
    final sha256 = headers[kMobileExtensionSha256ConfigKey];
    if ([
      root,
      entry,
      protocol,
      sha256,
    ].any((value) => value == null || value.isEmpty)) {
      throw const McpUnsupportedTransportException(
        '移动端 Node MCP 配置缺少已安装包的注册元数据。',
      );
    }
    final permissions = (headers[kMobileExtensionPermissionsConfigKey] ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    await BundledNodeRuntime.registerExtension(
      id: extensionId,
      root: root!,
      entry: entry!,
      protocol: protocol!,
      sha256: sha256!,
      permissions: permissions,
    );
  }

  Future<void> disconnectServer(String id) async {
    final config = state.where((server) => server.id == id).firstOrNull;
    await _clients[id]?.dispose();
    _clients.remove(id);
    _connectedIds.remove(id);
    _connectionErrors.remove(id);
    final extensionId = config == null
        ? null
        : mobileExtensionIdForMcpConfig(config);
    if (extensionId != null) {
      await _unregisterMobileExtension(extensionId);
    }
    state = [...state];
  }

  Future<void> _unregisterMobileExtension(String extensionId) async {
    try {
      await BundledNodeRuntime.unregisterExtension(extensionId);
    } on Object catch (error) {
      // Disconnect / uninstall remains best-effort when the embedded runtime
      // has already stopped; the persisted extension row is still removed.
      debugPrint(
        '[MCP] Failed to unregister mobile extension $extensionId: $error',
      );
    }
  }

  /// 获取所有已连接服务器的工具
  List<McpToolWithServer> getAllTools() {
    final result = <McpToolWithServer>[];
    for (final entry in _clients.entries) {
      final serverId = entry.key;
      final client = entry.value;
      final matching = state.where((s) => s.id == serverId);
      if (matching.isEmpty) continue;
      final serverName = matching.first.name;
      for (final tool in client.tools) {
        result.add(
          McpToolWithServer(
            serverId: serverId,
            serverName: serverName,
            tool: tool,
          ),
        );
      }
    }
    return result;
  }

  /// 调用工具
  Future<McpToolResult> callTool(
    String serverId,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final client = _clients[serverId];
    if (client == null) throw Exception('MCP server not connected: $serverId');
    return client.callTool(toolName, arguments);
  }

  @override
  void dispose() {
    _disposed = true;
    final clients = _clients.values.toList(growable: false);
    _clients.clear();
    _connectedIds.clear();
    _connectionErrors.clear();
    unawaited(_disposeClients(clients));
    super.dispose();
  }

  Future<void> _disposeClients(Iterable<McpClient> clients) async {
    for (final client in clients) {
      try {
        await client.dispose();
      } on Object catch (error) {
        debugPrint('[MCP] Client dispose failed: $error');
      }
    }
  }
}

class McpToolWithServer {
  final String serverId;
  final String serverName;
  final McpTool tool;

  const McpToolWithServer({
    required this.serverId,
    required this.serverName,
    required this.tool,
  });
}

final mcpManagerProvider =
    StateNotifierProvider<McpManager, List<McpServerConfig>>((ref) {
      final dao = ref.watch(mcpDaoProvider);
      return McpManager(dao);
    });
