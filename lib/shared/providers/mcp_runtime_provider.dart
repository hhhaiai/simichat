import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kMcpRuntimeDefaultHealthUrl = 'http://127.0.0.1:37651/health';
const kMcpRuntimeDefaultSseUrl = 'http://127.0.0.1:37651/mcp/sse/simichat-node';

const kMcpRuntimeScriptPath = 'scripts/mcp_runtime_container.sh';

const _kBundledRuntimeAssets = <String>[
  'scripts/mcp_runtime_container.sh',
  'tools/mcp_runtime/container/Dockerfile',
  'tools/mcp_runtime/container/package.json',
  'tools/mcp_runtime/container/runtime-server.mjs',
];

enum McpRuntimeStatus { unsupported, stopped, running, busy, error }

@immutable
class McpRuntimeState {
  const McpRuntimeState({
    required this.status,
    this.message = '',
    this.lastOutput = '',
    this.healthUrl = kMcpRuntimeDefaultHealthUrl,
    this.sseUrl = kMcpRuntimeDefaultSseUrl,
    this.supportsContainerRuntime = false,
  });

  final McpRuntimeStatus status;
  final String message;
  final String lastOutput;
  final String healthUrl;
  final String sseUrl;
  final bool supportsContainerRuntime;

  bool get isBusy => status == McpRuntimeStatus.busy;
  bool get isRunning => status == McpRuntimeStatus.running;

  McpRuntimeState copyWith({
    McpRuntimeStatus? status,
    String? message,
    String? lastOutput,
    String? healthUrl,
    String? sseUrl,
    bool? supportsContainerRuntime,
  }) {
    return McpRuntimeState(
      status: status ?? this.status,
      message: message ?? this.message,
      lastOutput: lastOutput ?? this.lastOutput,
      healthUrl: healthUrl ?? this.healthUrl,
      sseUrl: sseUrl ?? this.sseUrl,
      supportsContainerRuntime:
          supportsContainerRuntime ?? this.supportsContainerRuntime,
    );
  }
}

@immutable
class McpRuntimeCommandResult {
  const McpRuntimeCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String get combinedOutput => [
    stdout.trim(),
    stderr.trim(),
  ].where((part) => part.isNotEmpty).join('\n');
}

typedef McpRuntimeCommandRunner =
    Future<McpRuntimeCommandResult> Function(
      List<String> args, {
      Map<String, String>? environment,
    });

class McpRuntimeController extends StateNotifier<McpRuntimeState> {
  McpRuntimeController({
    McpRuntimeCommandRunner? runner,
    bool? supportsContainerRuntime,
  }) : _runner = runner ?? _defaultRunner,
       _supportsContainerRuntime =
           supportsContainerRuntime ?? _isDesktopContainerPlatform,
       super(
         McpRuntimeState(
           status: (supportsContainerRuntime ?? _isDesktopContainerPlatform)
               ? McpRuntimeStatus.stopped
               : McpRuntimeStatus.unsupported,
           message: (supportsContainerRuntime ?? _isDesktopContainerPlatform)
               ? 'PC 端 Node MCP 容器 Runtime 未启动'
               : '移动端使用 App 内建 MCP Runtime，无需 Node / npx / Docker',
           supportsContainerRuntime:
               supportsContainerRuntime ?? _isDesktopContainerPlatform,
         ),
       );

  final McpRuntimeCommandRunner _runner;
  final bool _supportsContainerRuntime;

  static bool get _isDesktopContainerPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  Future<void> refreshStatus() async {
    if (!_supportsContainerRuntime) {
      state = const McpRuntimeState(
        status: McpRuntimeStatus.unsupported,
        message: '移动端使用 App 内建 MCP Runtime，无需 Node / npx / Docker',
      );
      return;
    }
    await _runRuntimeCommand(
      const ['status'],
      busyMessage: '正在检查 PC MCP 容器 Runtime 状态...',
      successMessage: _messageFromStatusOutput,
    );
  }

  Future<void> start() async {
    if (!_supportsContainerRuntime) {
      await refreshStatus();
      return;
    }
    await _runRuntimeCommand(
      const ['start'],
      busyMessage: '正在启动 PC MCP 容器 Runtime...',
      successMessage: (_) => 'PC MCP 容器 Runtime 已启动',
    );
  }

  Future<void> stop() async {
    if (!_supportsContainerRuntime) {
      await refreshStatus();
      return;
    }
    await _runRuntimeCommand(
      const ['stop'],
      busyMessage: '正在停止 PC MCP 容器 Runtime...',
      successMessage: (_) => 'PC MCP 容器 Runtime 已停止',
    );
  }

  Future<void> smoke() async {
    if (!_supportsContainerRuntime) {
      await refreshStatus();
      return;
    }
    await _runRuntimeCommand(
      const ['smoke'],
      busyMessage: '正在自检 PC MCP 容器 Runtime...',
      successMessage: (_) => 'PC MCP 容器 Runtime 自检通过',
    );
  }

  Future<void> _runRuntimeCommand(
    List<String> args, {
    required String busyMessage,
    required String Function(String output) successMessage,
  }) async {
    final previous = state;
    state = previous.copyWith(
      status: McpRuntimeStatus.busy,
      message: busyMessage,
    );

    try {
      final result = await _runner(args);
      final output = result.combinedOutput;
      if (result.exitCode != 0) {
        state = previous.copyWith(
          status: McpRuntimeStatus.error,
          message: output.isEmpty ? 'PC MCP 容器 Runtime 命令失败' : output,
          lastOutput: output,
        );
        return;
      }

      state = previous.copyWith(
        status: _statusFromOutput(args.first, output),
        message: successMessage(output),
        lastOutput: output,
        supportsContainerRuntime: _supportsContainerRuntime,
      );
    } catch (e) {
      state = previous.copyWith(
        status: McpRuntimeStatus.error,
        message: 'PC MCP 容器 Runtime 命令失败: $e',
        lastOutput: e.toString(),
      );
    }
  }

  static McpRuntimeStatus _statusFromOutput(String command, String output) {
    if (command == 'stop') return McpRuntimeStatus.stopped;
    if (output.contains('not created') || output.contains('not running')) {
      return McpRuntimeStatus.stopped;
    }
    if (output.contains('SMOKE_TOOL_CALL_OK') ||
        output.contains('MCP SSE:') ||
        output.contains('runtime started') ||
        output.contains('already running')) {
      return McpRuntimeStatus.running;
    }
    return command == 'start' || command == 'smoke'
        ? McpRuntimeStatus.running
        : McpRuntimeStatus.stopped;
  }

  static String _messageFromStatusOutput(String output) {
    if (output.contains('not created') || output.contains('not running')) {
      return 'PC MCP 容器 Runtime 未启动';
    }
    if (output.contains('MCP SSE:')) {
      return 'PC MCP 容器 Runtime 已运行';
    }
    return output.isEmpty ? 'PC MCP 容器 Runtime 状态已刷新' : output;
  }

  static Future<McpRuntimeCommandResult> _defaultRunner(
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final script = await _resolveRuntimeScript();
    if (script == null) {
      return const McpRuntimeCommandResult(
        exitCode: 127,
        stderr: '找不到 MCP Runtime 脚本；请确认 PC Runtime 已随应用打包',
      );
    }
    final result = await Process.run(
      'bash',
      [script.path, ...args],
      environment: environment,
      runInShell: Platform.isWindows,
    );
    return McpRuntimeCommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  static Future<File?> _resolveRuntimeScript() async {
    final repoScript = File(kMcpRuntimeScriptPath);
    if (repoScript.existsSync()) return repoScript;

    try {
      final supportDir = await getApplicationSupportDirectory();
      final runtimeRoot = Directory('${supportDir.path}/mcp_runtime');
      for (final assetPath in _kBundledRuntimeAssets) {
        await _copyRuntimeAsset(assetPath, runtimeRoot);
      }
      final bundledScript = File('${runtimeRoot.path}/$kMcpRuntimeScriptPath');
      return bundledScript.existsSync() ? bundledScript : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _copyRuntimeAsset(
    String assetPath,
    Directory runtimeRoot,
  ) async {
    final data = await rootBundle.load(assetPath);
    final target = File('${runtimeRoot.path}/$assetPath');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
}

final mcpRuntimeControllerProvider =
    StateNotifierProvider<McpRuntimeController, McpRuntimeState>(
      (ref) => McpRuntimeController(),
    );
