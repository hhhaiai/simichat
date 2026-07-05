import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/widgets/drawio_widget.dart';
import 'package:ai_chat_app/shared/widgets/latex_markdown_widget.dart';
import 'package:ai_chat_app/shared/widgets/mermaid_widget.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile device scrolls complex markdown conversation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await db.channelDao.createChannel(
      id: 'markdown-channel',
      name: 'Markdown Mock',
      baseUrl: 'https://example.invalid',
      apiKeyEncrypted: 'not-used',
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'markdown-model',
      channelId: 'markdown-channel',
      modelName: 'markdown-scroll-model',
    );
    await db.sessionDao.createSession(
      id: 'markdown-session',
      defaultChannelModelId: 'markdown-model',
    );
    await db.sessionDao.updateTitle(
      'markdown-session',
      '复杂 Markdown 真机滚动 smoke',
    );
    await db.messageDao.insertMessage(
      id: 'markdown-user',
      sessionId: 'markdown-session',
      role: 'user',
      content:
          '用户侧 Markdown `requestId` 与列表：\n\n'
          '- 移动端优先\n'
          '- 本地隐私优先',
      channelModelId: 'markdown-model',
    );
    await db.messageDao.insertMessage(
      id: 'markdown-assistant',
      sessionId: 'markdown-session',
      role: 'assistant',
      content: _complexMarkdown,
      channelModelId: 'markdown-model',
      tokens: 2048,
      responseMs: 321,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('复杂 Markdown 真机滚动 smoke'), findsWidgets);
    expect(find.byType(LatexMarkdownWidget), findsWidgets);
    expect(find.byType(MermaidWidget), findsOneWidget);
    expect(find.byType(DrawioWidget), findsOneWidget);
    expect(find.text('Mermaid 图表'), findsOneWidget);

    final tailFinder = find.textContaining(
      'TAIL_SENTINEL_20260706',
      findRichText: true,
    );
    await _scrollUntilVisible(tester, tailFinder);
    expect(tailFinder, findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
  fail('Timed out waiting for $finder');
}

const _complexMarkdown = r'''
# 复杂 Markdown 真机样例

这段内容用于验证移动端长文档滚动、富文本、公式、代码块和图表卡片不会阻塞对话页。

## 表格

| 模块 | 状态 | 备注 |
| --- | --- | --- |
| 对话 | 已验证 | 真机滚动 |
| Markdown | 已验证 | 扩展语法 |

## 数学公式

行内公式：$E = mc^2$。

$$
F = ma
$$

## Mermaid 图

```mermaid
graph TD;
  A[开始] --> B{移动端滚动};
  B -->|通过| C[记录证据];
```

## Draw.io 图

```drawio
<mxGraphModel>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
  </root>
</mxGraphModel>
```

## 长列表

1. 第 1 段：移动端对话智能助理需要稳定长文档阅读体验。
2. 第 2 段：复杂 Markdown 不应阻断滚动。
3. 第 3 段：图表卡片和代码块需要跟随消息列表布局。
4. 第 4 段：用户和助手消息都统一 Markdown 渲染。
5. 第 5 段：底部哨兵用于证明滚动到底部。
6. 第 6 段：继续增加高度，覆盖真机懒加载与滚动边界。
7. 第 7 段：继续增加高度，覆盖真机懒加载与滚动边界。
8. 第 8 段：继续增加高度，覆盖真机懒加载与滚动边界。
9. 第 9 段：继续增加高度，覆盖真机懒加载与滚动边界。
10. 第 10 段：继续增加高度，覆盖真机懒加载与滚动边界。
11. 第 11 段：继续增加高度，覆盖真机懒加载与滚动边界。
12. 第 12 段：继续增加高度，覆盖真机懒加载与滚动边界。
13. 第 13 段：继续增加高度，覆盖真机懒加载与滚动边界。
14. 第 14 段：继续增加高度，覆盖真机懒加载与滚动边界。
15. 第 15 段：继续增加高度，覆盖真机懒加载与滚动边界。
16. 第 16 段：继续增加高度，覆盖真机懒加载与滚动边界。
17. 第 17 段：继续增加高度，覆盖真机懒加载与滚动边界。
18. 第 18 段：继续增加高度，覆盖真机懒加载与滚动边界。
19. 第 19 段：继续增加高度，覆盖真机懒加载与滚动边界。
20. 第 20 段：继续增加高度，覆盖真机懒加载与滚动边界。

## 结尾

TAIL_SENTINEL_20260706
''';
