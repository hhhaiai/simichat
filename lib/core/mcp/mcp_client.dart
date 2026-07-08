import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  McpClient({required this.name, required McpTransport transport})
    : _transport = transport;

  /// 初始化连接
  Future<void> initialize() async {
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
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final message = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    await _transport.send(message);

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('MCP request timed out: $method');
      },
    );
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    unawaited(
      _transport.send({'jsonrpc': '2.0', 'method': method, 'params': params}),
    );
  }

  void _onMessage(Map<String, dynamic> message) {
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

  Future<void> dispose() async {
    // 清理所有未完成的请求
    for (final entry in _pendingRequests.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(Exception('MCP client disposed'));
      }
    }
    _pendingRequests.clear();
    await _transport.disconnect();
    await _toolsController.close();
    await _resourcesController.close();
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
  AppNativeMcpTransport({this.serverId = kAppNativeMcpServerId});

  final String serverId;
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
    return [
      {
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
      },
      {
        'name': 'simichat.runtime_info',
        'description': '返回当前 SimiChat 内建 MCP Runtime 状态。',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
    ];
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

  Map<String, dynamic> _callTool(Map<String, dynamic> params) {
    final name = params['name'] as String?;
    final arguments =
        (params['arguments'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

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

/// SSE 传输（远程服务）
class SseTransport implements McpTransport {
  final String url;
  final Map<String, String> headers;
  http.Client? _client;
  String? _messageEndpoint;
  StreamSubscription<String>? _sseSubscription;

  SseTransport({required this.url, this.headers = const {}});

  @override
  Future<void> connect(void Function(Map<String, dynamic>) onMessage) async {
    _client = http.Client();
    final endpointCompleter = Completer<void>();

    final request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(headers);

    final response = await _client!.send(request);
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
            _messageEndpoint = dataBuffer;
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
      onError: (e) {
        debugPrint('[MCP SSE] Stream error: $e');
        if (!endpointCompleter.isCompleted) {
          endpointCompleter.completeError(e);
        }
      },
      onDone: () {
        debugPrint('[MCP SSE] Stream closed');
        if (!endpointCompleter.isCompleted) {
          endpointCompleter.completeError(
            Exception('SSE stream closed before endpoint received'),
          );
        }
      },
    );

    return endpointCompleter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException('SSE endpoint not received within 15s');
      },
    );
  }

  @override
  Future<void> disconnect() async {
    await _sseSubscription?.cancel();
    _sseSubscription = null;
    _client?.close();
    _client = null;
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_messageEndpoint == null || _client == null) return;
    final body = jsonEncode(message);
    try {
      final response = await _client!.post(
        Uri.parse(url).resolve(_messageEndpoint!),
        headers: {'Content-Type': 'application/json', ...headers},
        body: body,
      );
      if (response.statusCode >= 400) {
        debugPrint(
          '[MCP SSE] POST failed: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[MCP SSE] POST error: $e');
    }
  }
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
