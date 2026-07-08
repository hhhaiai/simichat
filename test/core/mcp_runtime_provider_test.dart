import 'package:ai_chat_app/shared/providers/mcp_runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'runtime controller reports mobile app-native path as unsupported for container',
    () async {
      final calls = <List<String>>[];
      final controller = McpRuntimeController(
        supportsContainerRuntime: false,
        runner: (args, {environment}) async {
          calls.add(args);
          return const McpRuntimeCommandResult(exitCode: 0);
        },
      );
      addTearDown(controller.dispose);

      expect(controller.state.status, McpRuntimeStatus.unsupported);
      expect(controller.state.supportsContainerRuntime, isFalse);
      expect(controller.state.message, contains('移动端使用 App 内建 MCP Runtime'));

      await controller.start();

      expect(calls, isEmpty);
      expect(controller.state.status, McpRuntimeStatus.unsupported);
    },
  );

  test(
    'runtime controller parses PC container lifecycle and smoke output',
    () async {
      final calls = <String>[];
      final controller = McpRuntimeController(
        supportsContainerRuntime: true,
        runner: (args, {environment}) async {
          calls.add(args.single);
          return switch (args.single) {
            'status' => const McpRuntimeCommandResult(
              exitCode: 0,
              stdout: 'SimiChat MCP runtime container not created.',
            ),
            'start' => const McpRuntimeCommandResult(
              exitCode: 0,
              stdout:
                  'SimiChat MCP runtime started: http://127.0.0.1:37651/mcp/sse/simichat-node',
            ),
            'smoke' => const McpRuntimeCommandResult(
              exitCode: 0,
              stdout: 'SMOKE_HEALTH_OK\nSMOKE_TOOL_LIST_OK\nSMOKE_TOOL_CALL_OK',
            ),
            'stop' => const McpRuntimeCommandResult(
              exitCode: 0,
              stdout: 'SimiChat MCP runtime stopped.',
            ),
            _ => const McpRuntimeCommandResult(
              exitCode: 64,
              stderr: 'bad command',
            ),
          };
        },
      );
      addTearDown(controller.dispose);

      await controller.refreshStatus();
      expect(controller.state.status, McpRuntimeStatus.stopped);
      expect(controller.state.message, contains('未启动'));

      await controller.start();
      expect(controller.state.status, McpRuntimeStatus.running);
      expect(controller.state.message, contains('已启动'));

      await controller.smoke();
      expect(controller.state.status, McpRuntimeStatus.running);
      expect(controller.state.message, contains('自检通过'));
      expect(controller.state.lastOutput, contains('SMOKE_TOOL_CALL_OK'));

      await controller.stop();
      expect(controller.state.status, McpRuntimeStatus.stopped);
      expect(calls, ['status', 'start', 'smoke', 'stop']);
    },
  );

  test(
    'runtime controller surfaces command failure without hiding diagnostics',
    () async {
      final controller = McpRuntimeController(
        supportsContainerRuntime: true,
        runner: (args, {environment}) async => const McpRuntimeCommandResult(
          exitCode: 1,
          stderr: 'Docker or Podman is required',
        ),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.state.status, McpRuntimeStatus.error);
      expect(
        controller.state.message,
        contains('Docker or Podman is required'),
      );
    },
  );
}
