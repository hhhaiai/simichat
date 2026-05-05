import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mcp/mcp_client.dart';

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

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.transport,
    this.command,
    this.args,
    this.url,
    this.headers,
    this.isEnabled = true,
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
    );
  }
}

/// MCP 管理器：管理多个 MCP 服务器连接
class McpManager extends StateNotifier<List<McpServerConfig>> {
  final Map<String, McpClient> _clients = {};

  McpManager() : super([]);

  Map<String, McpClient> get clients => _clients;

  void addServer(McpServerConfig config) {
    state = [...state, config];
  }

  void removeServer(String id) {
    _clients[id]?.dispose();
    _clients.remove(id);
    state = state.where((s) => s.id != id).toList();
  }

  void updateServer(McpServerConfig config) {
    state = state.map((s) => s.id == config.id ? config : s).toList();
  }

  Future<void> connectServer(McpServerConfig config) async {
    McpTransport transport;
    if (config.transport == 'stdio') {
      transport = StdioTransport(
        command: config.command!,
        args: config.args ?? [],
      );
    } else {
      transport = SseTransport(
        url: config.url!,
        headers: config.headers ?? {},
      );
    }

    final client = McpClient(name: config.name, transport: transport);
    await client.initialize();
    _clients[config.id] = client;
  }

  Future<void> disconnectServer(String id) async {
    await _clients[id]?.dispose();
    _clients.remove(id);
  }

  /// 获取所有已连接服务器的工具
  List<McpToolWithServer> getAllTools() {
    final result = <McpToolWithServer>[];
    for (final entry in _clients.entries) {
      final serverId = entry.key;
      final client = entry.value;
      final serverName = state.firstWhere((s) => s.id == serverId).name;
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
  return McpManager();
});
