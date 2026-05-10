import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mcp/mcp_client.dart';
import '../../core/database/dao/mcp_dao.dart';
import 'database_provider.dart';

/// MCP 服务器配置
class McpServerConfig {
  final String id;
  final String name;
  final String transport; // 'stdio' | 'sse'
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
List<String>? _listFromJson(String? json) =>
    json != null ? List<String>.from(jsonDecode(json) as List) : null;
String? _mapToJson(Map<String, String>? map) =>
    map != null ? jsonEncode(map) : null;
Map<String, String>? _mapFromJson(String? json) =>
    json != null ? Map<String, String>.from(jsonDecode(json) as Map) : null;

/// MCP 管理器：管理多个 MCP 服务器连接，持久化到数据库
class McpManager extends StateNotifier<List<McpServerConfig>> {
  final McpDao _dao;
  final Map<String, McpClient> _clients = {};
  final Set<String> _connectedIds = <String>{};
  final Map<String, String> _connectionErrors = <String, String>{};

  McpManager(this._dao) : super([]) {
    _loadFromDb();
  }

  Map<String, McpClient> get clients => _clients;
  bool isConnected(String id) => _connectedIds.contains(id);
  String? connectionErrorFor(String id) => _connectionErrors[id];

  Future<void> _loadFromDb() async {
    final rows = await _dao.getAllServers();
    final configs = rows.map((r) => McpServerConfig(
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
    )).toList();
    state = configs;

    // 自动连接已启用的服务器
    for (final config in configs) {
      if (config.isEnabled) {
        try {
          await connectServer(config);
        } catch (e) {
          // 连接失败不阻塞启动，但记录日志
          _connectionErrors[config.id] = e.toString();
          debugPrint('[MCP] Failed to connect ${config.name}: $e');
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
    _clients[id]?.dispose();
    _clients.remove(id);
    _connectedIds.remove(id);
    _connectionErrors.remove(id);
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

  Future<void> connectServer(McpServerConfig config) async {
    // 断开已有连接（避免资源泄漏）
    await disconnectServer(config.id);

    McpTransport transport;
    if (config.transport == 'stdio') {
      if (config.command == null || config.command!.isEmpty) {
        throw Exception('MCP stdio server requires a command');
      }
      transport = StdioTransport(
        command: config.command!,
        args: config.args ?? [],
      );
    } else {
      if (config.url == null || config.url!.isEmpty) {
        throw Exception('MCP SSE server requires a URL');
      }
      transport = SseTransport(
        url: config.url!,
        headers: config.headers ?? {},
      );
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
      state = [...state];
      rethrow;
    }
  }

  Future<void> disconnectServer(String id) async {
    await _clients[id]?.dispose();
    _clients.remove(id);
    _connectedIds.remove(id);
    _connectionErrors.remove(id);
    state = [...state];
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
        result.add(McpToolWithServer(
          serverId: serverId,
          serverName: serverName,
          tool: tool,
        ));
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
    for (final client in _clients.values) {
      client.dispose();
    }
    _clients.clear();
    super.dispose();
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
