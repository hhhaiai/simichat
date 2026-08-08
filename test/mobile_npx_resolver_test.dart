import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/core/mcp/mobile_npx_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('known npx MCP packages resolve to an in-process profile', () {
    final resolution = MobileNpxResolver.resolve(
      command: 'npx',
      args: const ['-y', '@modelcontextprotocol/server-time'],
    );
    expect(resolution?.packageName, '@modelcontextprotocol/server-time');
    expect(resolution?.profile, 'time');
  });

  test('npx package versions are normalized before the allowlist lookup', () {
    final resolution = MobileNpxResolver.resolve(
      command: 'NPX',
      args: const ['--yes', '@modelcontextprotocol/server-memory@1.0.2'],
    );
    expect(resolution?.packageName, '@modelcontextprotocol/server-memory');
    expect(resolution?.profile, 'memory');
  });

  test(
    'unknown npx package remains rejected instead of starting a process',
    () {
      expect(
        MobileNpxResolver.resolve(
          command: 'npx',
          args: const ['-y', '@example/unknown-mcp'],
        ),
        isNull,
      );
      expect(
        MobileNpxResolver.resolve(command: 'node', args: const ['server.mjs']),
        isNull,
      );
    },
  );

  test(
    'time compatibility profile completes MCP handshake without stdio',
    () async {
      final client = McpClient(
        name: 'mobile-time',
        transport: AppNativeMcpTransport(
          serverId: 'mobile-npx:@modelcontextprotocol/server-time',
          profile: 'time',
        ),
      );
      addTearDown(client.dispose);
      await client.initialize();
      expect(client.tools.map((tool) => tool.name), contains('simichat.now'));
      final result = await client.callTool('simichat.now', const {});
      expect(result.isError, isFalse);
      final hidden = await client.callTool('simichat.fetch', const {});
      expect(hidden.isError, isTrue);
    },
  );
}
