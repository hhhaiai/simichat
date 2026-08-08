import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const kBundledNodeRuntimeChannel = MethodChannel(
  'top.simitalk.aichat/node_runtime',
);
const kBundledNodeRuntimeHealthUrl = 'http://127.0.0.1:37651/health';
const kBundledNodeRuntimeSseUrl =
    'http://127.0.0.1:37651/mcp/sse/simichat-node';
const kBundledNodeRuntimeServerAsset =
    'tools/mcp_runtime/container/runtime-server.mjs';

/// The runtime that is shipped with the application, as opposed to a host
/// `node`, `npx`, Docker, or Podman installation.
class BundledNodeRuntime {
  BundledNodeRuntime._();

  static Process? _desktopProcess;
  static String? _desktopNodePath;
  static Future<Map<String, dynamic>>? _startFuture;

  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  static Future<Map<String, dynamic>> start() {
    final existing = _startFuture;
    if (existing != null) {
      return existing;
    }
    final future = _startInternal();
    _startFuture = future.then(
      (value) {
        _startFuture = null;
        return value;
      },
      onError: (Object error, StackTrace stackTrace) {
        _startFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    return _startFuture!;
  }

  static Future<Map<String, dynamic>> status() async {
    if (isMobile) {
      if (!Platform.isAndroid) {
        return _unsupported(
          'iOS uses App Native MCP; Node runtime is Android/PC only',
        );
      }
      try {
        final response = await kBundledNodeRuntimeChannel
            .invokeMapMethod<String, dynamic>('status');
        return response ??
            _unsupported('Android Node runtime returned no status');
      } on MissingPluginException {
        return _unsupported('Android Node runtime channel is not registered');
      }
    }
    if (!isDesktop) {
      return _unsupported(
        'Bundled Node runtime is unavailable on this platform',
      );
    }
    final process = _desktopProcess;
    if (process == null) {
      return _stopped('Bundled Node runtime is not started');
    }
    return _runningInfo(
      runtime: 'simichat-node-desktop-bundled',
      nodePath: _desktopNodePath ?? 'unknown',
      externalProcess: true,
    );
  }

  static Future<Map<String, dynamic>> stop() async {
    if (isMobile) {
      if (!Platform.isAndroid) {
        return _unsupported(
          'iOS uses App Native MCP; Node runtime is Android/PC only',
        );
      }
      try {
        final response = await kBundledNodeRuntimeChannel
            .invokeMapMethod<String, dynamic>('stop');
        return response ??
            _unsupported('Android Node runtime returned no status');
      } on MissingPluginException {
        return _unsupported('Android Node runtime channel is not registered');
      }
    }
    final process = _desktopProcess;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      _desktopProcess = null;
      _desktopNodePath = null;
    }
    return _stopped('Bundled Node runtime stopped');
  }

  static Future<Map<String, dynamic>> _startInternal() async {
    if (isMobile) {
      if (!Platform.isAndroid) {
        return _unsupported(
          'iOS uses App Native MCP; Node runtime is Android/PC only',
        );
      }
      try {
        final response = await kBundledNodeRuntimeChannel
            .invokeMapMethod<String, dynamic>('start');
        final info =
            response ?? _unsupported('Android Node runtime returned no status');
        if (info['running'] == true) await _waitForHealth();
        return info;
      } on MissingPluginException {
        return _unsupported('Android Node runtime channel is not registered');
      }
    }
    if (!isDesktop) {
      return _unsupported(
        'Bundled Node runtime is unavailable on this platform',
      );
    }

    final existing = _desktopProcess;
    if (existing != null) {
      return _runningInfo(
        runtime: 'simichat-node-desktop-bundled',
        nodePath: _desktopNodePath ?? 'unknown',
        externalProcess: true,
      );
    }

    final runtimeRoot = await _runtimeRoot();
    final serverFile = await _copyServerAsset(runtimeRoot);
    final nodeFile = await _resolveBundledNode(runtimeRoot);
    if (nodeFile == null) {
      throw StateError(
        '找不到随应用分发的 Node runtime。请先运行 scripts/prepare_node_runtime.sh，'
        '不能回退到宿主机 node。',
      );
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['700', nodeFile.path]);
    }

    final process = await Process.start(
      nodeFile.path,
      [serverFile.path],
      workingDirectory: runtimeRoot.path,
      environment: <String, String>{
        ...Platform.environment,
        'MCP_RUNTIME_HOST': '127.0.0.1',
        'MCP_RUNTIME_PORT': '37651',
        'MCP_RUNTIME_WORKSPACE_ROOT': runtimeRoot.path,
        'SIMICHAT_NODE_RUNTIME_KIND': 'desktop-bundled',
        'SIMICHAT_NODE_APP_MANAGED': 'true',
      },
      runInShell: false,
    );
    _desktopProcess = process;
    _desktopNodePath = nodeFile.path;
    unawaited(
      process.exitCode.then((_) {
        if (identical(_desktopProcess, process)) {
          _desktopProcess = null;
          _desktopNodePath = null;
        }
      }),
    );
    unawaited(process.stdout.drain());
    unawaited(process.stderr.drain());
    try {
      await _waitForHealth();
    } catch (_) {
      process.kill(ProcessSignal.sigterm);
      _desktopProcess = null;
      _desktopNodePath = null;
      rethrow;
    }
    return _runningInfo(
      runtime: 'simichat-node-desktop-bundled',
      nodePath: nodeFile.path,
      externalProcess: true,
    );
  }

  static Future<void> _waitForHealth({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1);
      try {
        final request = await client.getUrl(
          Uri.parse(kBundledNodeRuntimeHealthUrl),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        final body = await utf8.decoder.bind(response).join();
        if (response.statusCode == 200 && body.isNotEmpty) return;
        lastError = 'health status ${response.statusCode}';
      } on Object catch (error) {
        lastError = error;
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException(
      'Bundled Node runtime health check failed: $lastError',
    );
  }

  static Future<Directory> _runtimeRoot() async {
    final override = Platform.environment['SIMICHAT_RUNTIME_ROOT'];
    if (override != null && override.isNotEmpty) {
      final root = Directory(override);
      await root.create(recursive: true);
      return root;
    }
    Directory support;
    try {
      support = await getApplicationSupportDirectory();
    } on MissingPluginException {
      // Pure Dart/host smoke tests do not register path_provider. Production
      // Android, macOS, Windows, and Linux builds always use app-private
      // support storage through the plugin.
      support = Directory(
        '${Directory.current.path}/.dart_tool/simichat_runtime',
      );
    }
    final root = Directory('${support.path}/simichat_bundled_node');
    await root.create(recursive: true);
    return root;
  }

  static Future<File> _copyServerAsset(Directory root) async {
    final target = File('${root.path}/runtime-server.mjs');
    try {
      final data = await rootBundle.load(kBundledNodeRuntimeServerAsset);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return target;
    } catch (_) {
      final repoFile = File(kBundledNodeRuntimeServerAsset);
      if (!repoFile.existsSync()) rethrow;
      await repoFile.copy(target.path);
      return target;
    }
  }

  static Future<File?> _resolveBundledNode(Directory root) async {
    final id = _runtimePlatformId();
    final fileName = Platform.isWindows ? 'node.exe' : 'node';
    final explicit = Platform.environment['SIMICHAT_BUNDLED_NODE_PATH'];
    final candidates = <String>[
      if (explicit != null && explicit.isNotEmpty) explicit,
      'tools/node_runtime/bundled/$id/$fileName',
      '${root.path}/$id/$fileName',
      ..._applicationBundleCandidates(id, fileName),
    ];
    for (final path in candidates) {
      final file = File(path).absolute;
      if (file.existsSync() && file.lengthSync() > 1024 * 1024) return file;
    }

    // A prepared binary is also a Flutter asset in release builds. Copying it
    // to app-private storage gives it an executable mode on Unix platforms.
    final assetPath = 'tools/node_runtime/bundled/$id/$fileName';
    try {
      final data = await rootBundle.load(assetPath);
      final target = File('${root.path}/$id/$fileName');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return target;
    } catch (_) {
      return null;
    }
  }

  static List<String> _applicationBundleCandidates(String id, String fileName) {
    final executable = File(Platform.resolvedExecutable);
    final bin = executable.parent.path;
    if (Platform.isMacOS) {
      final contents = executable.parent.parent;
      return [
        '${contents.path}/Resources/node_runtime/$id/$fileName',
        '${contents.path}/Resources/tools/node_runtime/bundled/$id/$fileName',
      ];
    }
    return [
      '$bin/node_runtime/$id/$fileName',
      '$bin/data/node_runtime/$id/$fileName',
      '$bin/data/flutter_assets/tools/node_runtime/bundled/$id/$fileName',
    ];
  }

  static String _runtimePlatformId() {
    final arch =
        Platform.version.toLowerCase().contains('arm64') ||
            Platform.environment['PROCESSOR_ARCHITECTURE']?.contains('ARM64') ==
                true
        ? 'arm64'
        : 'x64';
    if (Platform.isMacOS) return 'macos-$arch';
    if (Platform.isLinux) return 'linux-$arch';
    if (Platform.isWindows) return 'windows-$arch';
    return 'unsupported';
  }

  static Map<String, dynamic> _runningInfo({
    required String runtime,
    required String nodePath,
    required bool externalProcess,
  }) => {
    'running': true,
    'runtime': runtime,
    'dependencyMode': 'bundled_node',
    'nodePath': nodePath,
    'externalProcess': externalProcess,
    'appManaged': true,
    'requiresHostNode': false,
    'requiresHostNpx': false,
    'requiresDocker': false,
    'healthUrl': kBundledNodeRuntimeHealthUrl,
    'sseUrl': kBundledNodeRuntimeSseUrl,
  };

  static Map<String, dynamic> _stopped(String message) => {
    'running': false,
    'runtime': 'simichat-node-bundled',
    'message': message,
    'requiresHostNode': false,
    'requiresHostNpx': false,
    'requiresDocker': false,
  };

  static Map<String, dynamic> _unsupported(String message) => {
    'running': false,
    'supported': false,
    'runtime': 'unsupported',
    'message': message,
  };
}
