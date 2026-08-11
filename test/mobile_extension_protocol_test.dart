import 'package:ai_chat_app/core/extensions/mobile_extension_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('node-mobile MCP defaults to mobile-mcp-v1', () {
    final manifest = MobileExtensionManifest.fromJson(_json());
    expect(manifest.protocol, 'mobile-mcp-v1');
  });

  test('stdio-compat-v1 is accepted as an in-process protocol', () {
    final manifest = MobileExtensionManifest.fromJson(
      _json(protocol: 'stdio-compat-v1'),
    );
    expect(manifest.protocol, 'stdio-compat-v1');
  });

  test('stdio-v1 is accepted as the JSON-Lines stdio protocol', () {
    final manifest = MobileExtensionManifest.fromJson(
      _json(protocol: 'stdio-v1'),
    );
    expect(manifest.protocol, 'stdio-v1');
  });

  test('unknown node-mobile MCP protocol is rejected', () {
    expect(
      () => MobileExtensionManifest.fromJson(_json(protocol: 'unknown-v9')),
      throwsA(isA<MobileExtensionManifestException>()),
    );
  });

  test('app-native MCP cannot select an arbitrary compiled handler', () {
    expect(
      () => MobileExtensionManifest.fromJson({
        ..._json(),
        'runtime': 'dart',
        'mcpTransport': 'app_native',
        'mcpServerId': 'untrusted-handler',
      }),
      throwsA(isA<MobileExtensionManifestException>()),
    );
  });

  test('node-mobile MCP cannot masquerade as app-native', () {
    expect(
      () => MobileExtensionManifest.fromJson({
        ..._json(),
        'mcpTransport': 'app_native',
        'mcpServerId': 'simichat-local',
      }),
      throwsA(isA<MobileExtensionManifestException>()),
    );
  });

  test('dart MCP must bind to the compiled app-native handler', () {
    expect(
      () => MobileExtensionManifest.fromJson({
        ..._json(),
        'runtime': 'dart',
        'entry': 'server.json',
      }),
      throwsA(isA<MobileExtensionManifestException>()),
    );
  });
}

Map<String, dynamic> _json({String? protocol}) => <String, dynamic>{
  'id': 'protocol-test',
  'version': '1.0.0',
  'type': 'mcp',
  'entry': 'index.mjs',
  'sha256': 'a' * 64,
  'sizeBytes': 1,
  'runtime': 'node-mobile',
  ...?protocol == null ? null : <String, dynamic>{'protocol': protocol},
  'permissions': <String>[],
};
