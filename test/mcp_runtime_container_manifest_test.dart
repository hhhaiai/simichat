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

  test('marketplace exposes bundled Node runtime for Android and PC', () {
    final item = builtinMcpServers.firstWhere(
      (server) => server.id == 'simichat-node-bundled',
    );

    expect(item.transport, 'sse');
    expect(item.url, 'http://127.0.0.1:37651/mcp/sse/simichat-node');
    expect(item.description, contains('Android / PC App 随包提供 Node.js Runtime'));
    expect(item.description, contains('不依赖宿主机 node'));
  });

  test('Android bundled Node runtime is a pinned arm64 native asset', () async {
    final library = File('android/app/src/main/jniLibs/arm64-v8a/libnode.so');
    final bridge = File('android/app/src/main/cpp/simichat_node_bridge.cpp');
    final cmake = File('android/app/src/main/cpp/CMakeLists.txt');
    final auditScript = File('scripts/verify_android_native_16k.sh');
    final manifest =
        jsonDecode(File('tools/node_runtime/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final android = manifest['android'] as Map<String, dynamic>;

    expect(library.existsSync(), isTrue);
    expect(library.lengthSync(), greaterThan(50 * 1024 * 1024));
    expect(bridge.readAsStringSync(), contains('node::Start'));
    expect(bridge.readAsStringSync(), contains('nativeState'));
    expect(bridge.readAsStringSync(), contains('nativeExitCode'));
    expect(cmake.readAsStringSync(), contains('max-page-size=16384'));
    expect(cmake.readAsStringSync(), contains('common-page-size=16384'));
    expect(auditScript.existsSync(), isTrue);
    expect(
      await Process.run('bash', [
        '-n',
        auditScript.path,
      ]).then((result) => result.exitCode),
      0,
    );
    expect(android['runtime'], 'nodejs-mobile');
    expect(android['version'], '18.20.4');
    expect(android['sourceRevision'], hasLength(40));
    expect(android['minimumAndroidApi'], 24);
    expect(android['supportedAbis'], ['arm64-v8a']);
    final pageSize = android['pageSize'] as Map<String, dynamic>;
    expect(pageSize['requiredBytes'], 16384);
    expect(pageSize['elfLoadAlignment'], 'verified');
    expect(pageSize['apkZipAlignment'], 'verified');
    final libraries = android['libraries'] as Map<String, dynamic>;
    expect(libraries['arm64-v8a'], isA<Map<String, dynamic>>());
    expect(
      android['arm64Library'],
      'android/app/src/main/jniLibs/arm64-v8a/libnode.so',
    );
    expect(android['arm64Sha256'], hasLength(64));
    expect(
      (libraries['arm64-v8a'] as Map<String, dynamic>)['elfLoadAlignmentBytes'],
      16384,
    );
    expect(
      (android['libnodeBuild'] as Map<String, dynamic>)['ndk'],
      '27.1.12297006',
    );
  });

  test(
    'desktop preparation pins official Node archives and does not use host node',
    () {
      final script = File('scripts/prepare_node_runtime.sh').readAsStringSync();
      final manifest =
          jsonDecode(
                File('tools/node_runtime/manifest.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final platforms = (manifest['platforms'] as Map<String, dynamic>);

      expect(script, contains("['nodeVersion']"));
      expect(script, contains("['source']"));
      expect(script, contains('.part'));
      expect(script, contains('sha256sum'));
      expect(script, contains('shasum -a 256'));
      expect(script, contains('tools/node_runtime/bundled'));
      expect(script, isNot(contains('command -v node')));
      expect(
        platforms.keys,
        containsAll([
          'macos-arm64',
          'macos-x64',
          'linux-arm64',
          'linux-x64',
          'windows-arm64',
          'windows-x64',
        ]),
      );
      for (final value in platforms.values) {
        expect((value as Map<String, dynamic>)['sha256'], hasLength(64));
      }
    },
  );

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

    final bundled = servers.singleWhere(
      (server) => server['id'] == 'simichat-node-bundled',
    );
    expect(bundled['runtime'], 'node-bundled');
    expect(bundled['mobileReady'], isTrue);
    expect(bundled['desktopReady'], isTrue);
    expect(bundled['iosReady'], isFalse);
    expect(bundled['requiresHostNode'], isFalse);
    expect(bundled['requiresHostNpx'], isFalse);
    expect(bundled['requiresDocker'], isFalse);
    final bundle = bundled['bundle'] as Map<String, dynamic>;
    expect(bundle['desktopPrepareScript'], 'scripts/prepare_node_runtime.sh');
    expect(bundle['desktopManifest'], 'tools/node_runtime/manifest.json');
    expect(bundle['androidAbi'], 'arm64-v8a');
    expect(bundle['androidAbis'], ['arm64-v8a']);
    final pageSize = bundle['androidPageSize'] as Map<String, dynamic>;
    expect(pageSize['requiredBytes'], 16384);
    expect(pageSize['elfLoadAlignment'], 'verified');
    expect(
      bundle['androidLibrary'],
      'android/app/src/main/jniLibs/arm64-v8a/libnode.so',
    );
    final verification = bundled['verification'] as Map<String, dynamic>;
    expect(verification['androidPixel8'], 'runtime_verified');
    expect(verification['desktopBundledProcessSmoke'], 'runtime_verified');
    expect(verification['desktopFlutterApp'], contains('runtime_verified'));
  });
}
