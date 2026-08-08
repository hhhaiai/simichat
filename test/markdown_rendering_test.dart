import 'package:ai_chat_app/shared/widgets/code_block_widget.dart';
import 'package:ai_chat_app/shared/widgets/drawio_widget.dart';
import 'package:ai_chat_app/shared/widgets/latex_markdown_widget.dart';
import 'package:ai_chat_app/shared/widgets/message_bubble.dart';
import 'package:ai_chat_app/shared/widgets/mermaid_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders extended markdown formats on a mobile viewport', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LatexMarkdownWidget(data: _extendedMarkdown),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Markdown 示例（扩展版本）'), findsOneWidget);
      expect(find.text('视频附件'), findsOneWidget);
      expect(find.text('音频附件'), findsOneWidget);
      expect(find.text('点击展开/折叠'), findsOneWidget);
      expect(find.byType(MermaidWidget), findsOneWidget);
      expect(find.byType(DrawioWidget), findsOneWidget);
      expect(find.text('Draw.io 图'), findsWidgets);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('keeps inline code inline and fenced code as code block', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LatexMarkdownWidget(
            data: '日志字段：`requestId`、`apiHost`、`offline=true/false`。',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('requestId', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('apiHost', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('offline=true/false', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(CodeBlockWidget), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LatexMarkdownWidget(data: '```text\nrequestId\n```'),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CodeBlockWidget), findsOneWidget);
  });

  testWidgets('renders legacy image and diagram syntaxes', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LatexMarkdownWidget(data: _legacyMarkdown),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNWidgets(3));
      expect(find.byType(MermaidWidget), findsNWidgets(3));
      expect(find.byType(DrawioWidget), findsNWidgets(3));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('renders markdown for both user input and assistant output', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  MessageBubble(
                    role: 'user',
                    content:
                        '用户输入 `requestId`\n\n'
                        '```mermaid\n'
                        'graph TD; A-->B;\n'
                        '```',
                    isUser: true,
                  ),
                  MessageBubble(
                    role: 'assistant',
                    content:
                        'AI 输出 `apiHost`\n\n'
                        '```drawio\n'
                        '<mxGraphModel></mxGraphModel>\n'
                        '```',
                    isUser: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(LatexMarkdownWidget), findsNWidgets(2));
      expect(find.byType(MermaidWidget), findsOneWidget);
      expect(find.byType(DrawioWidget), findsOneWidget);
      expect(
        find.textContaining('requestId', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('apiHost', findRichText: true),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

const _extendedMarkdown = r'''
# Markdown 示例（扩展版本）

## 强调和列表

***加粗斜体***

- 项目 1
  - 子项 1

## 图片

[[img:data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=]]

## 数学公式

这是一个行内公式：$E = mc^2$。

$$
F = ma
$$

## 脚注和删除线

这是一个注脚[^1]示例。

[^1]: 这是注脚内容。

~~这是删除线文本。~~

## HTML 媒体

<video width="320" height="240" controls>
  <source src="movie.mp4" type="video/mp4">
</video>

<audio controls>
  <source src="audio.mp3" type="audio/mpeg">
</audio>

## Mermaid 图

```mermaid id="m60lys"
graph TD;
    A[开始] --> B{条件};
    B -->|是| C[过程 1];
```

## Draw.io 图

```drawio id="uizfzg"
<mxGraphModel>
  <root>
    <mxCell id="0"/>
  </root>
</mxGraphModel>
```

## details

<details>
  <summary>点击展开/折叠</summary>

### 示例标题

这是折叠内容。

</details>
''';

const _onePixelPng =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

const _legacyMarkdown =
    '''
[[img:$_onePixelPng]]

[image:$_onePixelPng]

<img src="$_onePixelPng" alt="inline html image">

:::mermaid
graph TD;
    A --> B;
:::

[mermaid]
sequenceDiagram
    Alice->>Bob: Hi
[/mermaid]

<div class="mermaid">
flowchart LR
  A --> B
</div>

:::draw.io
<mxGraphModel>
  <root><mxCell id="0"/></root>
</mxGraphModel>
:::

[mxgraph]
<mxGraphModel>
  <root><mxCell id="1"/></root>
</mxGraphModel>
[/mxgraph]

<mxGraphModel>
  <root><mxCell id="2"/></root>
</mxGraphModel>
''';
