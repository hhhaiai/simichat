import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// MCP (Model Context Protocol) 客户端
/// 支持 stdio 和 SSE 两种传输方式
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
      'capabilities': {
        'tools': {},
        'resources': {},
      },
      'clientInfo': {
        'name': 'ai_chat_app',
        'version': '1.0.0',
      },
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
  Future<McpToolResult> callTool(String name, Map<String, dynamic> arguments) async {
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
    if (contents.isEmpty) return McpResourceContent(text: '', mimeType: 'text/plain');
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

    return completer.future.timeout(timeout, onTimeout: () {
      _pendingRequests.remove(id);
      throw TimeoutException('MCP request timed out: $method');
    });
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    unawaited(_transport.send({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    }));
  }

  void _onMessage(Map<String, dynamic> message) {
    // JSON-RPC 2.0: id 可以是 int 或 String
    final rawId = message['id'];
    final id = rawId is int ? rawId : (rawId is String ? int.tryParse(rawId) : null);
    if (id != null && _pendingRequests.containsKey(id)) {
      final error = message['error'];
      if (error != null) {
        _pendingRequests[id]!.completeError(
          Exception('MCP error: ${error['message']}'),
        );
      } else {
        _pendingRequests[id]!.complete(message['result'] as Map<String, dynamic>? ?? {});
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
    _process = await Process.start(command, args);
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
          endpointCompleter.completeError(Exception('SSE stream closed before endpoint received'));
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
        Uri.parse(_messageEndpoint!),
        headers: {'Content-Type': 'application/json', ...headers},
        body: body,
      );
      if (response.statusCode >= 400) {
        debugPrint('[MCP SSE] POST failed: ${response.statusCode} ${response.body}');
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

  const McpResource({required this.uri, this.name, this.description, this.mimeType});

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

  const McpToolContent({required this.type, this.text, this.mimeType, this.data});

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
