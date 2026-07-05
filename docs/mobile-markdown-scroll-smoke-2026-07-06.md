# 复杂 Markdown 真机滚动 smoke 验证记录（2026-07-06）

## 目标

补齐 P0 真机主链路中的复杂 Markdown 长文档滚动证据：在真实移动设备上验证对话页可以加载包含表格、公式、Mermaid、Draw.io / mxGraph、长列表和底部哨兵的长 assistant 消息，并能滚动到底部且不抛 Flutter 异常。

该验证不依赖外部 API Key，不访问真实模型，不读取或清理用户真实数据。

## 新增验证入口

新增文件：`integration_test/mobile_markdown_scroll_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_markdown_scroll.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，结束后恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

## 测试设计

测试使用真机 `integration_test` 跑完整对话页渲染与滚动：

1. 使用内存 SQLite 和 mock SharedPreferences，避免读写真机用户数据。
2. 将视口固定为 390×844，覆盖移动端布局。
3. 种入 `Markdown Mock / markdown-scroll-model` 渠道 / 模型和会话 `复杂 Markdown 真机滚动 smoke`。
4. 种入一条用户 Markdown 消息和一条长 assistant Markdown 消息。
5. assistant 消息覆盖：表格、行内 / 块级公式、Mermaid fenced code、Draw.io / mxGraph fenced code、20 项长列表和 `TAIL_SENTINEL_20260706` 底部哨兵。
6. 启动完整 `AiChatApp` 后验证：`LatexMarkdownWidget`、`MermaidWidget`、`DrawioWidget` 都进入 Widget 树，Mermaid 标题可见。
7. 滚动到 `TAIL_SENTINEL_20260706` 并验证尾部可达。
8. 确认 `tester.takeException()` 为空。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_markdown_scroll.sh 37101FDJH0077P
```

脚本内部执行：

```bash
flutter --no-version-check test integration_test/mobile_markdown_scroll_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.7s
00:00 +0: mobile device scrolls complex markdown conversation
00:06 +1: (tearDownAll)
00:07 +1: All tests passed!
```

结论：Pixel 8 真机上，复杂 Markdown 长 assistant 消息可进入对话页，Mermaid / Draw.io 组件可实例化，消息列表可滚动到底部哨兵，未出现 Flutter 测试框架捕获的异常。

## 调试记录

首次运行暴露两个测试断言问题，均未改业务代码：

- 测试预期 `Draw.io / mxGraph 图表`，实际 `DrawioWidget` 标题为 `Draw.io 图`；已改为以 `DrawioWidget` 类型断言为准，避免测试绑定错误文案。
- 滚到底部后顶部用户消息会被 `ListView` 回收，不能再断言顶部 `requestId` 仍在 Widget 树；已移除该不适合滚动到底场景的断言。

## 验证与边界

本轮已验证：

- 新增复杂 Markdown 真机 integration smoke。
- 新增可重复执行脚本并自动恢复临时 sqlite3 hook。
- Pixel 8 真机通过复杂 Markdown 渲染组件实例化和长消息滚动到底闭环。
- 正式 `pubspec.yaml` 不保留临时 `hooks:`。

本轮未覆盖：

- iPhone13 复杂 Markdown smoke；当前设备仍因 Locked 状态拒绝 launch，需要物理解锁后复跑。
- Mermaid WebView 的远端 CDN 成功加载与图形视觉正确性；本轮只证明组件实例化、对话页滚动和 Flutter 异常边界。
- 手工视觉审查；后续仍应补充截图 / 视觉检查以确认长表格、长代码和离线 Mermaid 的阅读体验。
