import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';

void main() {
  final fakeTool = McpToolWithServer(
    serverId: 'server-1',
    serverName: 'weather',
    tool: const McpTool(
      name: 'web_fetch',
      description: 'Fetch a URL',
      inputSchema: {
        'type': 'object',
        'properties': {'url': {'type': 'string'}},
      },
    ),
  );

  test('parses fenced JSON tool_call blocks', () {
    final calls = parseToolCallsForTesting(
      '''
```tool_call
{"tool":"weather/web_fetch","arguments":{"url":"https://wttr.in/Beijing?lang=zh"}}
```
''',
      [fakeTool],
    );

    expect(calls.length, 1);
    expect(calls.single.serverId, 'server-1');
    expect(calls.single.toolName, 'web_fetch');
    expect(
      calls.single.arguments,
      {'url': 'https://wttr.in/Beijing?lang=zh'},
    );
  });

  test('parses xml-style tool_call blocks with bare function name', () {
    final calls = parseToolCallsForTesting(
      '''
<tool_call>
  <function=web_fetch>
    <parameter=url>https://wttr.in/Beijing?lang=zh</parameter>
  </function>
</tool_call>
''',
      [fakeTool],
    );

    expect(calls.length, 1);
    expect(calls.single.serverId, 'server-1');
    expect(calls.single.toolName, 'web_fetch');
    expect(
      calls.single.arguments,
      {'url': 'https://wttr.in/Beijing?lang=zh'},
    );
  });

  test('strips xml-style tool_call markup from user-visible content', () {
    final stripped = stripToolCallMarkupForTesting(
      '''
先查一下天气。
<tool_call>
  <function=web_fetch>
    <parameter=url>https://wttr.in/Beijing?format=j1</parameter>
  </function>
</tool_call>
''',
    );

    expect(stripped, '先查一下天气。');
  });
}
