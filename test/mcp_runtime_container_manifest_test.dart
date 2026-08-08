import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/marketplace/marketplace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const runtimeDir = 'tools/mcp_runtime/container';

  test('PC MCP runtime container carries Node and avoids host npx', () {
    final dockerfile = File('$runtimeDir/Dockerfile').readAsStringSync();
    final packageJson = File('$runtimeDir/package.json').readAsStringSync();
    final server = File('$runtimeDir/runtime-server.mjs').readAsStringSync();

    expect(
      dockerfile,
      contains('ARG SIMICHAT_MCP_RUNTIME_BASE_IMAGE=node:22-alpine'),
    );
    expect(dockerfile, contains(r'FROM ${SIMICHAT_MCP_RUNTIME_BASE_IMAGE}'));
    expect(dockerfile, contains('ENTRYPOINT []'));
    expect(dockerfile, contains('CMD ["node", "runtime-server.mjs"]'));
    expect(dockerfile, isNot(contains(' npx ')));
    expect(dockerfile, isNot(contains(' npm ')));

    final package = jsonDecode(packageJson) as Map<String, dynamic>;
    expect(package['type'], 'module');
    expect(package['dependencies'], isEmpty);
    expect(packageJson, isNot(contains('npx')));

    expect(server, contains('mcp\\/sse'));
    expect(server, contains('mcp/messages/'));
    expect(server, contains('tools/list'));
    expect(server, contains('tools/call'));
    expect(server, contains("typeof payload === 'string'"));
    expect(server, contains('simichat.node_runtime_info'));
    expect(server, contains('simichat.fs_list'));
    expect(server, contains('simichat.fs_read_text'));
    expect(server, contains('simichat.fetch_text'));
    expect(server, contains('MCP_RUNTIME_WORKSPACE_ROOT'));
    expect(
      server,
      contains('Only paths relative to MCP_RUNTIME_WORKSPACE_ROOT'),
    );
    expect(server, contains('Only HTTP(S) URLs are allowed'));
    expect(server, isNot(contains('child_process')));
    expect(server, isNot(contains('spawn(')));
    expect(server, isNot(contains('exec(')));
  });

  test(
    'container helper script is shell-valid and does not call host node',
    () async {
      final script = File('scripts/mcp_runtime_container.sh');
      expect(script.existsSync(), isTrue);
      final source = script.readAsStringSync();

      expect(source, contains('docker'));
      expect(source, contains('podman'));
      expect(source, contains('This script never calls host node/npm/npx.'));
      expect(source, contains('SIMICHAT_MCP_RUNTIME_BASE_IMAGE'));
      expect(source, contains('--build-arg'));
      expect(source, contains('smoke)'));
      expect(source, contains('SMOKE_TOOL_CALL_OK'));
      expect(source, contains('SMOKE_FS_TOOL_OK'));
      expect(source, contains('SMOKE_FETCH_TOOL_OK'));
      expect(source, contains('simichat.node_runtime_info'));
      expect(source, contains('container smoke'));
      expect(source, isNot(contains('\nnode ')));
      expect(source, isNot(contains('\nnpm ')));
      expect(source, isNot(contains('\nnpx ')));

      final result = await Process.run('bash', ['-n', script.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    },
  );

  test('marketplace does not auto-enable legacy stdio npx entries', () {
    final pageSource = File(
      'lib/features/marketplace/marketplace_page.dart',
    ).readAsStringSync();

    expect(pageSource, contains('final usesExternalRuntime = item.isStdio;'));
    expect(pageSource, contains('isEnabled: !usesExternalRuntime'));
    expect(pageSource, contains('connected || usesExternalRuntime'));
    expect(pageSource, contains('优先使用 SimiChat Node 容器 Runtime'));
  });

  test(
    'runtime files are bundled as Flutter assets for desktop app extraction',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final provider = File(
        'lib/shared/providers/mcp_runtime_provider.dart',
      ).readAsStringSync();

      expect(pubspec, contains('scripts/mcp_runtime_container.sh'));
      expect(pubspec, contains('tools/mcp_runtime/container/Dockerfile'));
      expect(pubspec, contains('tools/mcp_runtime/container/package.json'));
      expect(
        pubspec,
        contains('tools/mcp_runtime/container/runtime-server.mjs'),
      );
      expect(provider, contains('rootBundle.load'));
      expect(provider, contains('getApplicationSupportDirectory'));
      expect(provider, contains('/mcp_runtime'));
    },
  );

  test('marketplace exposes PC Node container runtime over local SSE', () {
    final item = builtinMcpServers.firstWhere(
      (server) => server.id == 'simichat-node-container',
    );

    expect(item.transport, 'sse');
    expect(item.command, isNull);
    expect(item.args, isEmpty);
    expect(item.url, 'http://127.0.0.1:37651/mcp/sse/simichat-node');
    expect(item.description, contains('不依赖宿主机 npx'));
  });

  test('runtime manifest documents mobile and PC self-dependent paths', () {
    final manifestFile = File('docs/runtime-manifest.example.json');
    expect(manifestFile.existsSync(), isTrue);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final servers = (manifest['servers'] as List).cast<Map<String, dynamic>>();

    final appNative = servers.singleWhere(
      (server) => server['id'] == 'simichat-local',
    );
    expect(appNative['runtime'], 'app_native');
    expect(appNative['mobileReady'], isTrue);
    expect(appNative['requiresHostNode'], isFalse);
    expect(appNative['requiresHostNpx'], isFalse);

    final nodeContainer = servers.singleWhere(
      (server) => server['id'] == 'simichat-node-container',
    );
    expect(nodeContainer['runtime'], 'node-container');
    expect(nodeContainer['desktopReady'], isTrue);
    expect(nodeContainer['requiresHostNode'], isFalse);
    expect(nodeContainer['requiresHostNpx'], isFalse);
    final container = nodeContainer['container'] as Map<String, dynamic>;
    expect(container['startScript'], 'scripts/mcp_runtime_container.sh start');
    expect(container['smokeScript'], 'scripts/mcp_runtime_container.sh smoke');
    expect(container['baseImage'], 'node:22-alpine');
    expect(nodeContainer['tools'], contains('simichat.fs_list'));
    expect(nodeContainer['tools'], contains('simichat.fs_read_text'));
    expect(nodeContainer['tools'], contains('simichat.fetch_text'));
    expect(
      (nodeContainer['permissions']
          as Map<String, dynamic>)['filesystemRootEnv'],
      'MCP_RUNTIME_WORKSPACE_ROOT',
    );
    expect(
      container['baseImageOverrideEnv'],
      'SIMICHAT_MCP_RUNTIME_BASE_IMAGE',
    );
  });
}
