import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bundled_node_runtime.dart';
import '../search/web_search_service.dart';

const kMcpTransportAppNative = 'app_native';
const kMcpTransportStdio = 'stdio';
const kMcpTransportSse = 'sse';

const kAppNativeMcpServerId = 'simichat-local';

/// MCP (Model Context Protocol) 客户端
/// 支持 App 内建、stdio 和 SSE 传输方式
class McpClient {
  final String name;
  final McpTransport _transport;
  int _nextId = 1;
  final _pendingRequests = <int, Completer<Map<String, dynamic>>>{};
  final _toolsController = StreamController<List<McpTool>>.broadcast();
  final _resourcesController = StreamController<List<McpResource>>.broadcast();

  Stream<List<McpTool>> get toolsStream => _toolsController.stream;
  Stream<List<McpResource>> get resourcesStream => _resourcesController.stream;

  List<McpTool> _tools = [];
  List<McpResource> _resources = [];
  List<McpTool> get tools => _tools;
  List<McpResource> get resources => _resources;

  bool _initialized = false;
  bool get isInitialized => _initialized;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  McpClient({required this.name, required McpTransport transport})
    : _transport = transport;

  /// 初始化连接
  Future<void> initialize() async {
    if (_disposed) throw StateError('MCP client has been disposed');
    try {
      await _transport.connect(_onMessage);

      // 发送 initialize 请求
      await _sendRequest('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': {}, 'resources': {}},
        'clientInfo': {'name': 'ai_chat_app', 'version': '1.0.0'},
      });

      _initialized = true;

      // 通知服务端初始化完成
      _sendNotification('notifications/initialized', {});

      // 获取工具列表
      await refreshTools();
      await refreshResources();
    } catch (_) {
      _initialized = false;
      // initialize 失败时也必须释放已经建立的 transport，避免移动端
      // 页面返回 / 重试后留下旧的 SSE 或 stdio 资源。
      try {
        await _transport.disconnect();
      } catch (disconnectError) {
        debugPrint('[MCP] Failed to cleanup initialization: $disconnectError');
      }
      rethrow;
    }
  }

  /// 刷新工具列表
  Future<List<McpTool>> refreshTools() async {
    final result = await _sendRequest('tools/list', {});
    final toolsList = result['tools'] as List? ?? [];
    _tools = toolsList.map((t) => McpTool.fromJson(t)).toList();
    _toolsController.add(_tools);
    return _tools;
  }

  /// 刷新资源列表
  Future<List<McpResource>> refreshResources() async {
    try {
      final result = await _sendRequest('resources/list', {});
      final resourcesList = result['resources'] as List? ?? [];
      _resources = resourcesList.map((r) => McpResource.fromJson(r)).toList();
      _resourcesController.add(_resources);
    } catch (e) {
      debugPrint('[MCP] Failed to list resources: $e');
    }
    return _resources;
  }

  /// 调用工具
  Future<McpToolResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final result = await _sendRequest('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    return McpToolResult.fromJson(result);
  }

  /// 读取资源
  Future<McpResourceContent> readResource(String uri) async {
    final result = await _sendRequest('resources/read', {'uri': uri});
    final contents = result['contents'] as List? ?? [];
    if (contents.isEmpty) {
      return McpResourceContent(text: '', mimeType: 'text/plain');
    }
    return McpResourceContent.fromJson(contents.first);
  }

  Future<Map<String, dynamic>> _sendRequest(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_disposed) throw StateError('MCP client has been disposed');
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final message = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    try {
      await _transport.send(message);
    } catch (_) {
      // 传输层失败时不能把永远不会完成的 request 留在 pending map 中。
      _pendingRequests.remove(id);
      rethrow;
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('MCP request timed out: $method');
      },
    );
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    if (_disposed) return;
    unawaited(_sendNotificationSafely(method, params));
  }

  Future<void> _sendNotificationSafely(
    String method,
    Map<String, dynamic> params,
  ) async {
    try {
      await _transport.send({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
      });
    } catch (error) {
      debugPrint('[MCP] Notification failed: $error');
    }
  }

  void _onMessage(Map<String, dynamic> message) {
    if (_disposed) return;
    // JSON-RPC 2.0: id 可以是 int 或 String
    final rawId = message['id'];
    final id = rawId is int
        ? rawId
        : (rawId is String ? int.tryParse(rawId) : null);
    if (id != null && _pendingRequests.containsKey(id)) {
      final error = message['error'];
      if (error != null) {
        _pendingRequests[id]!.completeError(
          Exception('MCP error: ${error['message']}'),
        );
      } else {
        _pendingRequests[id]!.complete(
          message['result'] as Map<String, dynamic>? ?? {},
        );
      }
      _pendingRequests.remove(id);
    }
  }

  Future<void> dispose() {
    return _disposeFuture ??= _disposeInternal();
  }

  Future<void> _disposeInternal() async {
    _disposed = true;
    _initialized = false;
    // 清理所有未完成的请求
    for (final entry in _pendingRequests.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(Exception('MCP client disposed'));
      }
    }
    _pendingRequests.clear();
    try {
      await _transport.disconnect();
    } finally {
      await _toolsController.close();
      await _resourcesController.close();
    }
  }
}

/// MCP 传输接口
abstract class McpTransport {
  Future<void> connect(void Function(Map<String, dynamic>) onMessage);
  Future<void> disconnect();
  Future<void> send(Map<String, dynamic> message);
}

/// App 内建传输：不启动外部进程，不依赖宿主机 node / npx / python。
///
/// 这是移动端默认可用的 MCP Runtime 基线；PC 端也可用同一套能力。
class AppNativeMcpTransport implements McpTransport {
  AppNativeMcpTransport({
    this.serverId = kAppNativeMcpServerId,
    this.profile = 'default',
    WebSearchService? webSearch,
  }) : _webSearch = webSearch;

  final String serverId;

  /// Legacy npm MCP compatibility profile.  It is an in-app adapter, not a
  /// stdio process, and is only selected by MobileNpxResolver.
  final String profile;
  final WebSearchService? _webSearch;
  void Function(Map<String, dynamic>)? _onMessage;
  bool _connected = false;

  @override
  Future<void> connect(void Function(Map<String, dynamic>) onMessage) async {
    _onMessage = onMessage;
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _onMessage = null;
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (!_connected || _onMessage == null) return;

    final id = message['id'];
    if (id == null) return; // notifications/initialized 等通知无需响应

    final method = message['method'] as String?;
    final params =
        (message['params'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    try {
      final result = await _handleRequest(method, params);
      _onMessage!({'jsonrpc': '2.0', 'id': id, 'result': result});
    } catch (e) {
      _onMessage!({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32603, 'message': e.toString()},
      });
    }
  }

  Future<Map<String, dynamic>> _handleRequest(
    String? method,
    Map<String, dynamic> params,
  ) async {
    switch (method) {
      case 'initialize':
        return {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': {}, 'resources': {}},
          'serverInfo': {'name': 'SimiChat App Native MCP', 'version': '1.0.0'},
        };
      case 'tools/list':
        return {'tools': _tools()};
      case 'tools/call':
        return _callTool(params);
      case 'resources/list':
        return {'resources': _resources()};
      case 'resources/read':
        return _readResource(params);
      default:
        throw UnsupportedError('Unsupported app-native MCP method: $method');
    }
  }

  List<Map<String, dynamic>> _tools() {
    final tools = <Map<String, dynamic>>[];
    if (profile == 'default' || profile == 'time') {
      tools.add({
        'name': 'simichat.now',
        'description': '返回当前设备时间。无需 Node、npx 或外部 MCP 进程。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'timezoneOffsetMinutes': {
              'type': 'integer',
              'description': '可选。按指定 UTC 偏移分钟数换算时间。',
            },
          },
        },
      });
      tools.add({
        'name': 'simichat.runtime_info',
        'description': '返回当前 SimiChat 内建 MCP Runtime 状态。',
        'inputSchema': {'type': 'object', 'properties': {}},
      });
    }
    if (profile == 'default') {
      tools.add({
        'name': 'simichat.web_search',
        'description':
            '搜索互联网（DuckDuckGo Instant Answer，无需 API Key），返回相关摘要与链接，可用于检索增强回答。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': '搜索关键词'},
          },
          'required': ['query'],
        },
      });
    }
    if (profile == 'memory') {
      tools.addAll([
        {
          'name': 'simichat.memory_search',
          'description': '在 App 本地记忆中搜索文本。只读，不启动 npx。',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string'},
              'maxResults': {'type': 'integer'},
            },
            'required': ['query'],
          },
        },
        {
          'name': 'simichat.memory_list',
          'description': '列出 App 本地记忆摘要。',
          'inputSchema': {'type': 'object', 'properties': {}},
        },
      ]);
    }
    if (profile == 'fetch') {
      tools.add({
        'name': 'simichat.fetch',
        'description': '在 App 内发起受限 HTTP(S) GET 请求。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
            'maxBytes': {'type': 'integer'},
          },
          'required': ['url'],
        },
      });
    }
    if (profile == 'filesystem') {
      tools.addAll([
        {
          'name': 'simichat.fs_list',
          'description': '列出 App 私有 Application Support 目录。',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
            },
          },
        },
        {
          'name': 'simichat.fs_read_text',
          'description': '读取 App 私有 Application Support 目录中的文本文件。',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'maxBytes': {'type': 'integer'},
            },
            'required': ['path'],
          },
        },
      ]);
    }
    return tools;
  }

  List<Map<String, dynamic>> _resources() {
    return [
      {
        'uri': 'simichat://runtime/info',
        'name': 'SimiChat 内建 MCP Runtime',
        'description': 'App 内建、自依赖 MCP Runtime 基线说明。',
        'mimeType': 'application/json',
      },
    ];
  }

  Future<Map<String, dynamic>> _callTool(Map<String, dynamic> params) async {
    final name = params['name'] as String?;
    final arguments =
        (params['arguments'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    if (!_tools().any((tool) => tool['name'] == name)) {
      return {
        'content': [
          {'type': 'text', 'text': '当前 MCP profile 未暴露工具: $name'},
        ],
        'isError': true,
      };
    }

    switch (name) {
      case 'simichat.now':
        final now = DateTime.now();
        final offset = arguments['timezoneOffsetMinutes'];
        final converted = offset is int
            ? now.toUtc().add(Duration(minutes: offset))
            : now;
        final iso8601 = offset is int
            ? '${converted.toIso8601String().replaceFirst(RegExp(r'Z$'), '')}${_formatOffset(offset)}'
            : converted.toIso8601String();
        return _textResult({
          'iso8601': iso8601,
          'timezoneName': offset is int
              ? 'UTC${_formatOffset(offset)}'
              : now.timeZoneName,
          'timezoneOffsetMinutes': offset is int
              ? offset
              : now.timeZoneOffset.inMinutes,
          'runtime': kMcpTransportAppNative,
        });
      case 'simichat.runtime_info':
        return _textResult(_runtimeInfo());
      case 'simichat.web_search':
        final query = (arguments['query'] as String? ?? '').trim();
        if (query.isEmpty) {
          return {
            'content': [
              {'type': 'text', 'text': 'web_search 需要非空 query 参数'},
            ],
            'isError': true,
          };
        }
        try {
          final results = await (_webSearch ?? const WebSearchService()).search(
            query,
          );
          return _textResult({
            'query': query,
            'resultCount': results.length,
            'results': results.map((r) => r.toJson()).toList(),
            'searchEngine': 'duckduckgo',
          });
        } on WebSearchException catch (e) {
          return {
            'content': [
              {'type': 'text', 'text': '搜索失败：${e.message}'},
            ],
            'isError': true,
          };
        }
      case 'simichat.memory_search':
        return _memorySearch(arguments);
      case 'simichat.memory_list':
        return _memoryList();
      case 'simichat.fetch':
        return _fetch(arguments);
      case 'simichat.fs_list':
        return _filesystemList(arguments);
      case 'simichat.fs_read_text':
        return _filesystemRead(arguments);
      default:
        return {
          'content': [
            {'type': 'text', 'text': '未知内建 MCP 工具: $name'},
          ],
          'isError': true,
        };
    }
  }

  Map<String, dynamic> _readResource(Map<String, dynamic> params) {
    final uri = params['uri'] as String?;
    if (uri != 'simichat://runtime/info') {
      return {
        'contents': [
          {
            'uri': uri ?? '',
            'mimeType': 'text/plain',
            'text': '未知内建 MCP 资源: $uri',
          },
        ],
      };
    }

    return {
      'contents': [
        {
          'uri': uri,
          'mimeType': 'application/json',
          'text': const JsonEncoder.withIndent('  ').convert(_runtimeInfo()),
        },
      ],
    };
  }

  Map<String, dynamic> _runtimeInfo() {
    return {
      'serverId': serverId,
      'profile': profile,
      'transport': kMcpTransportAppNative,
      'dependencyMode': 'in_app',
      'externalProcess': false,
      'requiresNode': false,
      'requiresNpx': false,
      'requiresPython': false,
      'mobileReady': true,
      'desktopReady': true,
      'tools': _tools().map((tool) => tool['name']).toList(),
    };
  }

  Map<String, dynamic> _textResult(Object payload) {
    return {
      'content': [
        {
          'type': 'text',
          'text': const JsonEncoder.withIndent('  ').convert(payload),
        },
      ],
      'isError': false,
    };
  }

  String _formatOffset(int minutes) {
    final sign = minutes >= 0 ? '+' : '-';
    final absMinutes = minutes.abs();
    final hours = (absMinutes ~/ 60).toString().padLeft(2, '0');
    final mins = (absMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hours:$mins';
  }

  Future<Map<String, dynamic>> _memoryList() async {
    final items = await _loadMemoryItems();
    return _textResult({'count': items.length, 'items': items});
  }

  Future<Map<String, dynamic>> _memorySearch(
    Map<String, dynamic> arguments,
  ) async {
    final query = (arguments['query'] as String? ?? '').trim().toLowerCase();
    if (query.isEmpty) {
      return {
        'content': [
          {'type': 'text', 'text': 'query 不能为空'},
        ],
        'isError': true,
      };
    }
    final maxResults = (arguments['maxResults'] is int)
        ? (arguments['maxResults'] as int).clamp(1, 50).toInt()
        : 10;
    final items = await _loadMemoryItems();
    final matches = items
        .where((item) => jsonEncode(item).toLowerCase().contains(query))
        .take(maxResults)
        .toList(growable: false);
    return _textResult({
      'query': query,
      'count': matches.length,
      'items': matches,
    });
  }

  Future<List<Map<String, dynamic>>> _loadMemoryItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('key_point_memory_v1');
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<Map<String, dynamic>> _fetch(Map<String, dynamic> arguments) async {
    final uri = Uri.tryParse((arguments['url'] as String? ?? '').trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return {
        'content': [
          {'type': 'text', 'text': '只支持 HTTP(S) URL'},
        ],
        'isError': true,
      };
    }
    final maxBytes = (arguments['maxBytes'] is int)
        ? (arguments['maxBytes'] as int).clamp(1, 65536).toInt()
        : 65536;
    final client = http.Client();
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      final bytes = response.bodyBytes;
      return _textResult({
        'url': uri.toString(),
        'status': response.statusCode,
        'ok': response.statusCode >= 200 && response.statusCode < 300,
        'text': utf8.decode(
          bytes.take(maxBytes).toList(),
          allowMalformed: true,
        ),
        'truncated': bytes.length > maxBytes,
      });
    } finally {
      client.close();
    }
  }

  Future<Directory> _filesystemRoot() => getApplicationSupportDirectory();

  Future<FileSystemEntity> _filesystemPath(String rawPath) async {
    final root = p.normalize((await _filesystemRoot()).absolute.path);
    final candidate = p.normalize(
      p.join(root, rawPath.trim().isEmpty ? '.' : rawPath),
    );
    if (candidate != root && !p.isWithin(root, candidate)) {
      throw StateError('filesystem path escapes the app container');
    }
    return FileSystemEntity.typeSync(candidate) ==
            FileSystemEntityType.directory
        ? Directory(candidate)
        : File(candidate);
  }

  Future<Map<String, dynamic>> _filesystemList(
    Map<String, dynamic> arguments,
  ) async {
    final directory = await _filesystemPath(
      arguments['path'] as String? ?? '.',
    );
    if (directory is! Directory) throw StateError('path is not a directory');
    final entries = <Map<String, dynamic>>[];
    await for (final item in directory.list()) {
      final type = await FileSystemEntity.type(item.path);
      entries.add(<String, dynamic>{
        'name': p.basename(item.path),
        'type': type == FileSystemEntityType.directory
            ? 'directory'
            : type == FileSystemEntityType.file
            ? 'file'
            : 'other',
      });
      if (entries.length >= 200) break;
    }
    return _textResult({'entries': entries});
  }

  Future<Map<String, dynamic>> _filesystemRead(
    Map<String, dynamic> arguments,
  ) async {
    final file = await _filesystemPath(arguments['path'] as String? ?? '');
    if (file is! File) throw StateError('path is not a file');
    final maxBytes = (arguments['maxBytes'] is int)
        ? (arguments['maxBytes'] as int).clamp(1, 65536).toInt()
        : 65536;
    final bytes = await file.readAsBytes();
    return _textResult({
      'path': p.basename(file.path),
      'text': utf8.decode(bytes.take(maxBytes).toList(), allowMalformed: true),
      'truncated': bytes.length > maxBytes,
    });
  }
}

/// stdio 传输（本地进程）
class StdioTransport implements McpTransport {
  final String command;
  final List<String> args;
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  StdioTransport({required this.command, this.args = const []});

  @override
  Future<void> connect(void Function(Map<String, dynamic>) onMessage) async {
    final resolvedCommand = _resolveCommand(command);
    final environment = _buildProcessEnvironment();
    _process = await Process.start(
      resolvedCommand,
      args,
      runInShell: Platform.isWindows,
      environment: environment,
    );
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isEmpty) return;
          try {
            final message = jsonDecode(line) as Map<String, dynamic>;
            onMessage(message);
          } catch (e) {
            debugPrint('[MCP Stdio] Parse error: $e');
          }
        });
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isNotEmpty) {
            debugPrint('[MCP Stdio stderr] $line');
          }
        });
  }

  @override
  Future<void> disconnect() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process?.kill();
    _process = null;
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    _process?.stdin.writeln(jsonEncode(message));
  }

  String _resolveCommand(String rawCommand) {
    if (Platform.isWindows) return rawCommand;
    if (rawCommand.contains(Platform.pathSeparator)) return rawCommand;

    final searchDirs = _candidateSearchDirs();

    for (final dir in searchDirs) {
      final candidate = File('$dir/$rawCommand');
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }

    return rawCommand;
  }

  Map<String, String> _buildProcessEnvironment() {
    final env = Map<String, String>.from(Platform.environment);
    final pathKey = Platform.isWindows ? 'Path' : 'PATH';
    final separator = Platform.isWindows ? ';' : ':';
    final existing = env[pathKey] ?? '';

    final merged = {
      ..._candidateSearchDirs(),
      ...existing.split(separator).where((entry) => entry.trim().isNotEmpty),
    }.join(separator);

    env[pathKey] = merged;
    return env;
  }

  List<String> _candidateSearchDirs() {
    final separator = Platform.isWindows ? ';' : ':';
    final pathEnv =
        Platform.environment[Platform.isWindows ? 'Path' : 'PATH'] ?? '';
    final searchDirs = <String>{
      ...pathEnv.split(separator).where((p) => p.trim().isNotEmpty),
    };

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      searchDirs.add('$home/.local/bin');
      searchDirs.add('$home/bin');

      final nvmRoot = Directory('$home/.nvm/versions/node');
      if (nvmRoot.existsSync()) {
        for (final nodeVersionDir in nvmRoot.listSync()) {
          if (nodeVersionDir is Directory) {
            searchDirs.add('${nodeVersionDir.path}/bin');
          }
        }
      }
    }

    if (Platform.isMacOS || Platform.isLinux) {
      searchDirs.addAll({
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/usr/bin',
        '/bin',
        '/opt/local/bin',
      });
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (appData != null && appData.isNotEmpty) {
        searchDirs.add('$appData\\npm');
      }
      if (localAppData != null && localAppData.isNotEmpty) {
        searchDirs.add('$localAppData\\Microsoft\\WindowsApps');
        searchDirs.add('$localAppData\\Programs\\nodejs');
      }
    }

    return searchDirs.toList();
  }
}

/// 移动端标准 MCP stdio 传输。
///
/// 移动系统不能像桌面端一样启动用户的宿主机 shell 命令，但可以把
/// `command + args` 交给随 App 分发的 Node Runtime。Runtime 为每个配置
/// 建立独立 session，并只暴露 JSON Lines 的 stdin / stdout 语义：这里写入
/// 的每一行就是 MCP server stdin 的一行，这里读出的每一行就是 server
/// stdout 的一行。它不经过 SSE，也不把请求直接改写成 Dart 对象调用。
class MobileStdioTransport implements McpTransport {
  MobileStdioTransport({
    required this.command,
    this.args = const <String>[],
    this.serverId,
    this.baseUrl,
    this.ensureRuntime = true,
  });

  final String command;
  final List<String> args;
  final String? serverId;

  /// Only used by protocol-level tests. Production uses the app-owned local
  /// Node Runtime endpoint.
  final String? baseUrl;
  final bool ensureRuntime;

  void Function(Map<String, dynamic>)? _onMessage;
  String? _sessionId;
  Future<void>? _pollFuture;
  bool _closed = true;

  @override
  Future<void> connect(void Function(Map<String, dynamic>) onMessage) async {
    await disconnect();
    final session = await BundledNodeRuntime.startStdioSession(
      command: command,
      args: args,
      serverId: serverId,
      baseUrl: baseUrl,
      ensureRuntime: ensureRuntime,
    );
    final id = session['sessionId'];
    if (id is! String || id.isEmpty) {
      throw const McpMobileStdioException('移动 stdio Runtime 未返回 sessionId');
    }
    _onMessage = onMessage;
    _sessionId = id;
    _closed = false;
    _pollFuture = _pollStdout(id);
  }

  @override
  Future<void> disconnect() async {
    _closed = true;
    final id = _sessionId;
    _sessionId = null;
    _onMessage = null;
    if (id != null) {
      try {
        await BundledNodeRuntime.closeStdioSession(id, baseUrl: baseUrl);
      } catch (error) {
        debugPrint('[MCP Mobile stdio] close failed: $error');
      }
    }
    final poll = _pollFuture;
    _pollFuture = null;
    await poll;
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    final id = _sessionId;
    if (_closed || id == null) {
      throw const McpMobileStdioException('移动 stdio session 未连接');
    }
    await BundledNodeRuntime.writeStdioLine(
      id,
      jsonEncode(message),
      baseUrl: baseUrl,
    );
  }

  Future<void> _pollStdout(String id) async {
    while (!_closed && identical(_sessionId, id)) {
      try {
        final result = await BundledNodeRuntime.readStdioLines(
          id,
          baseUrl: baseUrl,
        );
        final lines = result['lines'];
        if (lines is List) {
          for (final rawLine in lines) {
            if (rawLine is! String || rawLine.trim().isEmpty) continue;
            try {
              final decoded = jsonDecode(rawLine);
              if (decoded is Map) {
                _onMessage?.call(decoded.cast<String, dynamic>());
              } else {
                debugPrint(
                  '[MCP Mobile stdio] stdout line is not a JSON object',
                );
              }
            } on Object catch (error) {
              debugPrint('[MCP Mobile stdio] stdout parse error: $error');
            }
          }
        }
        if (result['closed'] == true) break;
      } on Object catch (error) {
        if (!_closed) {
          debugPrint('[MCP Mobile stdio] stdout polling failed: $error');
        }
        break;
      }
    }
  }
}

class McpMobileStdioException implements Exception {
  const McpMobileStdioException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// SSE 传输（远程服务）
class SseTransport implements McpTransport {
  final String url;
  final Map<String, String> headers;
  final Duration connectTimeout;
  final Duration endpointTimeout;
  final Duration requestTimeout;
  http.Client? _client;
  String? _messageEndpoint;
  StreamSubscription<String>? _sseSubscription;

  SseTransport({
    required this.url,
    this.headers = const {},
    this.connectTimeout = const Duration(seconds: 15),
    this.endpointTimeout = const Duration(seconds: 15),
    this.requestTimeout = const Duration(seconds: 15),
  });

  @override
  Future<void> connect(void Function(Map<String, dynamic>) onMessage) async {
    await disconnect();
    final client = http.Client();
    _client = client;
    _messageEndpoint = null;
    final endpointCompleter = Completer<void>();

    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);

      final response = await client.send(request).timeout(connectTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw McpSseException('SSE 连接失败：HTTP ${response.statusCode}');
      }
      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      String? eventType;
      String dataBuffer = '';

      _sseSubscription = stream.listen(
        (line) {
          if (line.startsWith('event:')) {
            eventType = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            if (dataBuffer.isNotEmpty) dataBuffer += '\n';
            dataBuffer += line.substring(5).trim();
          } else if (line.isEmpty && dataBuffer.isNotEmpty) {
            if (eventType == 'endpoint') {
              _messageEndpoint = dataBuffer.trim();
              if (!endpointCompleter.isCompleted) endpointCompleter.complete();
            } else if (eventType == 'message') {
              try {
                final message = jsonDecode(dataBuffer) as Map<String, dynamic>;
                onMessage(message);
              } catch (e) {
                debugPrint('[MCP SSE] Parse error: $e');
              }
            }
            eventType = null;
            dataBuffer = '';
          }
        },
        onError: (Object error) {
          debugPrint('[MCP SSE] Stream error: $error');
          if (!endpointCompleter.isCompleted) {
            endpointCompleter.completeError(error);
          }
        },
        onDone: () {
          debugPrint('[MCP SSE] Stream closed');
          if (!endpointCompleter.isCompleted) {
            endpointCompleter.completeError(
              const McpSseException(
                'SSE stream closed before endpoint received',
              ),
            );
          }
        },
      );

      await endpointCompleter.future.timeout(endpointTimeout);
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    final subscription = _sseSubscription;
    final client = _client;
    _sseSubscription = null;
    _client = null;
    _messageEndpoint = null;
    await subscription?.cancel();
    client?.close();
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    final endpoint = _messageEndpoint;
    final client = _client;
    if (endpoint == null || client == null) {
      throw const McpSseException('SSE 未连接或尚未收到 message endpoint');
    }
    final body = jsonEncode(message);
    final response = await client
        .post(
          Uri.parse(url).resolve(endpoint),
          headers: {'Content-Type': 'application/json', ...headers},
          body: body,
        )
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpSseException('SSE 消息发送失败：HTTP ${response.statusCode}');
    }
  }
}

class McpSseException implements Exception {
  const McpSseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// MCP 工具定义
class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;

  const McpTool({required this.name, this.description, this.inputSchema});

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] as Map<String, dynamic>?,
    );
  }
}

/// MCP 资源定义
class McpResource {
  final String uri;
  final String? name;
  final String? description;
  final String? mimeType;

  const McpResource({
    required this.uri,
    this.name,
    this.description,
    this.mimeType,
  });

  factory McpResource.fromJson(Map<String, dynamic> json) {
    return McpResource(
      uri: json['uri'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }
}

/// MCP 工具调用结果
class McpToolResult {
  final List<McpToolContent> content;
  final bool isError;

  const McpToolResult({required this.content, this.isError = false});

  factory McpToolResult.fromJson(Map<String, dynamic> json) {
    final contentList = json['content'] as List? ?? [];
    return McpToolResult(
      content: contentList.map((c) => McpToolContent.fromJson(c)).toList(),
      isError: json['isError'] as bool? ?? false,
    );
  }
}

class McpToolContent {
  final String type;
  final String? text;
  final String? mimeType;
  final String? data;

  const McpToolContent({
    required this.type,
    this.text,
    this.mimeType,
    this.data,
  });

  factory McpToolContent.fromJson(Map<String, dynamic> json) {
    return McpToolContent(
      type: json['type'] as String,
      text: json['text'] as String?,
      mimeType: json['mimeType'] as String?,
      data: json['data'] as String?,
    );
  }
}

/// MCP 资源内容
class McpResourceContent {
  final String text;
  final String mimeType;

  const McpResourceContent({required this.text, required this.mimeType});

  factory McpResourceContent.fromJson(Map<String, dynamic> json) {
    return McpResourceContent(
      text: json['text'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'text/plain',
    );
  }
}
