import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled runtime controller has no host Node fallback', () {
    final source = File(
      'lib/core/mcp/bundled_node_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('Process.start('));
    expect(source, contains('SIMICHAT_BUNDLED_NODE_PATH'));
    expect(source, contains('找不到随应用分发的 Node runtime'));
    expect(source, isNot(contains('command -v node')));
    expect(source, isNot(contains("Process.start('node'")));
    expect(source, isNot(contains("Process.start('npx'")));
    expect(source, isNot(contains('docker run')));
    expect(source, contains("'requiresHostNode': false"));
    expect(source, contains("'requiresHostNpx': false"));
    expect(source, contains("'requiresDocker': false"));
  });

  test('desktop smoke separates server and SSE evidence', () {
    final source = File(
      'scripts/smoke_bundled_node_runtime.sh',
    ).readAsStringSync();

    expect(source, contains('SERVER_LOG='));
    expect(source, contains('SSE_LOG='));
    expect(source, contains('SIMICHAT_DESKTOP_BUNDLED_NODE_PROCESS_READY'));
    expect(source, contains('requiresHostNode'));
    expect(source, contains('requiresHostNpx'));
    expect(source, contains('requiresDocker'));
    expect(source, contains(r'wait "$SERVER_PID"'));
    expect(source, contains(r'wait "$SSE_PID"'));
    expect(
      Process.runSync('bash', [
        '-n',
        'scripts/smoke_bundled_node_runtime.sh',
      ]).exitCode,
      0,
    );
  });

  test('desktop bundle verifier uses the package binary explicitly', () {
    final source = File('scripts/verify_desktop_bundle.sh').readAsStringSync();
    expect(source, contains('SIMICHAT_BUNDLED_NODE_PATH'));
    expect(source, contains('SIMICHAT_DESKTOP_BUNDLE_BINARY_READY'));
    expect(source, contains('SIMICHAT_DESKTOP_BUNDLE_RUNTIME_READY'));
    expect(source, contains('macos-arm64/node'));
    expect(source, contains('linux-x64/node'));
    expect(source, contains('windows-x64/node.exe'));
    expect(
      Process.runSync('bash', [
        '-n',
        'scripts/verify_desktop_bundle.sh',
      ]).exitCode,
      0,
    );
  });

  test('manifest separates Android embedded and desktop bundled metadata', () {
    final manifest =
        jsonDecode(File('tools/node_runtime/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final android = manifest['android'] as Map<String, dynamic>;
    final platforms = manifest['platforms'] as Map<String, dynamic>;

    expect(manifest['nodeVersion'], '24.11.1');
    expect(manifest['source'], 'https://nodejs.org/dist/v24.11.1/');
    expect(android['runtime'], 'nodejs-mobile');
    expect(android['version'], '18.20.4');
    expect(android['arm64Library'], contains('libnode.so'));
    expect(android['arm64Sha256'], hasLength(64));
    final bundled = manifest['bundled'] as Map<String, dynamic>;
    final macosArm64 = bundled['macos-arm64'] as Map<String, dynamic>;
    expect(macosArm64['path'], 'tools/node_runtime/bundled/macos-arm64/node');
    expect(macosArm64['nodeVersion'], '24.11.1');
    expect(macosArm64['sha256'], hasLength(64));
    expect(
      platforms.keys,
      containsAll(<String>[
        'macos-arm64',
        'macos-x64',
        'linux-arm64',
        'linux-x64',
        'windows-arm64',
        'windows-x64',
      ]),
    );
  });

  test('runtime documentation records verification boundaries', () {
    final doc = File('docs/MCP_BUNDLED_NODE_RUNTIME.md').readAsStringSync();
    expect(doc, contains('Pixel 8 真机'));
    expect(doc, contains('PC Flutter App integration'));
    expect(doc, contains('16 KB page size'));
    expect(doc, contains('不会静默回退宿主机 `node`'));
  });

  test('desktop binary is installed by native bundles, not Flutter assets', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final macosProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final linuxCmake = File('linux/CMakeLists.txt').readAsStringSync();
    final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();

    expect(pubspec, contains('tools/node_runtime/manifest.json'));
    expect(pubspec, isNot(contains('tools/node_runtime/bundled/')));
    expect(macosProject, contains('Bundle Node Runtime'));
    expect(macosProject, contains('UNLOCALIZED_RESOURCES_FOLDER_PATH'));
    expect(macosProject, contains('codesign --force --sign'));
    expect(linuxCmake, contains('install(PROGRAMS'));
    expect(
      linuxCmake,
      contains(r'node_runtime/${SIMICHAT_NODE_RUNTIME_PLATFORM}'),
    );
    expect(windowsCmake, contains('install(PROGRAMS'));
    expect(
      windowsCmake,
      contains(r'node_runtime/${SIMICHAT_NODE_RUNTIME_PLATFORM}'),
    );
  });
}
