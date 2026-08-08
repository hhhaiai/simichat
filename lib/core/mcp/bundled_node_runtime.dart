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
  static final Set<Process> _desktopIntentionalStops = <Process>{};
  static const int _maxStartAttempts = 2;
  static const Duration _startRetryDelay = Duration(milliseconds: 350);
  static String _desktopState = 'stopped';
  static int _desktopRestartCount = 0;
  static String? _lastError;
  static DateTime? _lastHealthyAt;

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
      return _stopped(
        _lastError == null
            ? 'Bundled Node runtime is not started'
            : 'Bundled Node runtime is not running: $_lastError',
      );
    }
    return _runningInfo(
      runtime: 'simichat-node-desktop-bundled',
      nodePath: _desktopNodePath ?? 'unknown',
      externalProcess: true,
      state: _desktopState,
    );
  }

  static Future<Map<String, dynamic>> stop() async {
    if (isMobile) {
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
      _desktopIntentionalStops.add(process);
      process.kill(ProcessSignal.sigterm);
      _desktopProcess = null;
      _desktopNodePath = null;
    }
    _desktopState = 'stopped';
    _lastError = null;
    return _stopped('Bundled Node runtime stopped');
  }

  static Future<Map<String, dynamic>> _startInternal() async {
    if (isMobile) {
      Object? lastError;
      Map<String, dynamic>? lastInfo;
      for (var attempt = 1; attempt <= _maxStartAttempts; attempt++) {
        try {
          final response = await kBundledNodeRuntimeChannel
              .invokeMapMethod<String, dynamic>('start');
          final info =
              response ??
              _unsupported('Android Node runtime returned no status');
          lastInfo = info;
          if (info['running'] == true) {
            await _waitForHealth();
            return <String, dynamic>{
              ...info,
              'state': 'running',
              'healthVerified': true,
            };
          }
          lastError = info['lastError'] ?? info['message'] ?? 'not running';
        } on MissingPluginException {
          return _unsupported('Android Node runtime channel is not registered');
        } on Object catch (error) {
          lastError = error;
        }
        if (attempt < _maxStartAttempts) {
          await Future<void>.delayed(_startRetryDelay);
        }
      }
      throw StateError(
        'Android bundled Node runtime failed after $_maxStartAttempts '
        'attempts: ${lastError ?? lastInfo}',
      );
    }
    if (!isDesktop) {
      return _unsupported(
        'Bundled Node runtime is unavailable on this platform',
      );
    }

    final existing = _desktopProcess;
    if (existing != null) {
      await _waitForHealth();
      _desktopState = 'running';
      _lastHealthyAt = DateTime.now();
      return _runningInfo(
        runtime: 'simichat-node-desktop-bundled',
        nodePath: _desktopNodePath ?? 'unknown',
        externalProcess: true,
        state: _desktopState,
      );
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _maxStartAttempts; attempt++) {
      try {
        return await _startDesktopOnce();
      } on Object catch (error) {
        lastError = error;
        _lastError = error.toString();
        await _terminateDesktopProcess();
        if (attempt < _maxStartAttempts) {
          _desktopRestartCount++;
          await Future<void>.delayed(_startRetryDelay);
        }
      }
    }
    _desktopState = 'crashed';
    throw StateError(
      'Bundled Node runtime failed after $_maxStartAttempts attempts: '
      '$lastError',
    );
  }

  static Future<Map<String, dynamic>> _startDesktopOnce() async {
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
        'MCP_RUNTIME_EXTENSION_ROOT': runtimeRoot.parent.path,
        'SIMICHAT_NODE_RUNTIME_KIND': 'desktop-bundled',
        'SIMICHAT_NODE_APP_MANAGED': 'true',
      },
      runInShell: false,
    );
    _desktopProcess = process;
    _desktopNodePath = nodeFile.path;
    _desktopState = 'starting';
    _lastError = null;
    unawaited(
      process.exitCode.then((exitCode) {
        final intentional = _desktopIntentionalStops.remove(process);
        if (identical(_desktopProcess, process)) {
          _desktopProcess = null;
          _desktopNodePath = null;
          _desktopState = intentional || exitCode == 0 ? 'stopped' : 'crashed';
          if (!intentional && exitCode != 0) {
            _lastError = 'bundled Node exited with code $exitCode';
          }
        }
      }),
    );
    unawaited(process.stdout.drain());
    unawaited(process.stderr.drain());
    await _waitForHealth();
    _desktopState = 'running';
    _lastHealthyAt = DateTime.now();
    return _runningInfo(
      runtime: 'simichat-node-desktop-bundled',
      nodePath: nodeFile.path,
      externalProcess: true,
      state: _desktopState,
    );
  }

  static Future<void> _terminateDesktopProcess() async {
    final process = _desktopProcess;
    if (process == null) return;
    _desktopIntentionalStops.add(process);
    process.kill(ProcessSignal.sigterm);
    _desktopProcess = null;
    _desktopNodePath = null;
    _desktopState = 'stopped';
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

  /// Loads one verified, pure-JavaScript MCP package into the already running
  /// Node Mobile/desktop runtime. Registration is an in-process adapter; it
  /// never starts `node`, `npm`, `npx`, a shell, or a child process.
  static Future<Map<String, dynamic>> registerExtension({
    required String id,
    required String root,
    required String entry,
    required String protocol,
    required String sha256,
    List<String> permissions = const <String>[],
  }) async {
    final runtime = await start();
    if (runtime['running'] != true) {
      throw StateError('Bundled Node runtime is not running: $runtime');
    }
    return _postRuntimeJson('/runtime/extensions/register', <String, dynamic>{
      'id': id,
      'root': root,
      'entry': entry,
      'protocol': protocol,
      'sha256': sha256,
      'permissions': permissions,
    });
  }

  static String extensionSseUrl(String id) =>
      'http://127.0.0.1:37651/mcp/sse/$id';

  static Future<Map<String, dynamic>> unregisterExtension(String id) {
    return _postRuntimeJson('/runtime/extensions/unregister', <String, dynamic>{
      'id': id,
    });
  }

  static Future<List<Map<String, dynamic>>> extensionStatus() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:37651/runtime/extensions/status'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw StateError(
          'Node runtime extension status failed: HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(body);
      final raw = decoded is Map ? decoded['extensions'] : null;
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(growable: false);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _postRuntimeJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:37651$path'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await utf8.decoder.bind(response).join();
      final decoded = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map ? decoded['error'] : decoded;
        throw StateError('Node runtime extension request failed: $message');
      }
      return decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{'value': decoded};
    } finally {
      client.close(force: true);
    }
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
    required String state,
  }) => {
    'running': true,
    'state': state,
    'runtime': runtime,
    'dependencyMode': 'bundled_node',
    'nodePath': nodePath,
    'externalProcess': externalProcess,
    'appManaged': true,
    'requiresHostNode': false,
    'requiresHostNpx': false,
    'requiresDocker': false,
    'restartCount': _desktopRestartCount,
    'lastError': _lastError ?? '',
    'lastHealthyAt': _lastHealthyAt?.toIso8601String() ?? '',
    'healthVerified': _lastHealthyAt != null,
    'healthUrl': kBundledNodeRuntimeHealthUrl,
    'sseUrl': kBundledNodeRuntimeSseUrl,
  };

  static Map<String, dynamic> _stopped(String message) => {
    'running': false,
    'state': _desktopState,
    'runtime': 'simichat-node-bundled',
    'message': message,
    'restartCount': _desktopRestartCount,
    'lastError': _lastError ?? '',
    'lastHealthyAt': _lastHealthyAt?.toIso8601String() ?? '',
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
