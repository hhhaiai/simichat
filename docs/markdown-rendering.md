# 对话页 Markdown 渲染与移动端字号方案

> 对应模块：M11。状态：移动端扩展 Markdown 渲染 v1 已落地。最后更新：2026-07-02。

## 1. 目标

- 对话页优先支持移动端阅读体验。
- 兼容常见新旧 Markdown 写法，参考样例：`/Users/sanbo/Desktop/PersonalAIBrain/test/markdown.md`。
- 标准 Markdown、GitHub 风格 Markdown、数学公式、图表、折叠块和旧式图片语法应尽量在聊天气泡内直接识别。
- 字体不能过大，必须给出可量化基准，便于后续微调。

## 2. 当前实现

入口仍为 `LatexMarkdownWidget`，由 assistant 消息和流式消息复用：

- `MessageBubble`：assistant 正文渲染。
- `StreamingBubble`：流式输出渲染。

渲染能力：

1. 标准 Markdown：标题、强调、列表、链接、引用、代码块、水平线、表格。
2. GitHub Web 扩展：`markdown` 包使用 `md.ExtensionSet.gitHubWeb`，覆盖表格、删除线、任务列表、脚注、自动链接、emoji、header id、alert block 等扩展基础。
3. 旧式图片：预处理 `[[img:URL]]` 为标准 `![image](URL)`。
4. 图片：支持网络图片、`data:` 图片、本地 `file:` 或相对路径图片；图片可点开查看。
5. 数学公式：
   - 块级 `$$ ... $$` 使用 `flutter_math_fork` 渲染。
   - 行内 `$...$` 使用自定义 inline syntax 渲染，不再降级为 inline code。
6. 代码块：
   - 普通代码块走带语言标题、行号和复制按钮的 `CodeBlockWidget`。
   - `mermaid` 代码块走既有 `MermaidWidget`。
   - `drawio` / `mxgraph` 代码块走 `DrawioWidget`，移动端先提供安全源码预览、复制和全屏查看。
7. 折叠块：
   - 兼容旧式 `:::details` / `:::collapse`。
   - 兼容 HTML `<details><summary>...</summary>...</details>`，转换为 Flutter `ExpansionTile`。
8. HTML 媒体：
   - `<audio>` / `<video>` 会识别 `<source src="...">` 或标签 `src`。
   - 移动端 v1 先渲染为安全媒体卡片，展示类型和地址，不执行内嵌 HTML / JavaScript。

## 3. 安全边界

- 不执行 Markdown 内嵌 JavaScript。
- 不执行 Draw.io XML 内的任意 HTML / JavaScript。
- HTML `<audio>` / `<video>` 先做安全识别和展示，不自动联网播放。
- Markdown 图片仍按现有图片加载策略处理；远端图片加载由用户内容触发。
- 应用改名不修改 `simichat.*` 数据格式标识、MethodChannel 名称、导出包前缀或 API Key 兼容加密 salt，避免破坏历史数据。

## 4. 移动端字号量化指标

默认 `fontScale = 100%`，全局可调范围收敛为 `90%–120%`，步进 `5%`。

| 场景 | 默认字号 | 120% 后 | 说明 |
| --- | ---: | ---: | --- |
| 聊天正文 / Markdown `p` / 输入框 | 15sp | 18sp | 主阅读基准 |
| Markdown 正文行高 | 1.60 | - | 比原 1.80 更紧凑 |
| H1 | 22sp | 26.4sp | 避免移动端标题过大 |
| H2 | 20sp | 24sp |  |
| H3 | 18sp | 21.6sp |  |
| H4 | 16sp | 19.2sp |  |
| H5 | 15sp | 18sp |  |
| H6 | 14sp | 16.8sp |  |
| 引用 / 表格 | 14sp | 16.8sp | 辅助阅读 |
| inline code / code block | 13sp | 15.6sp | 保持代码密度 |
| 元信息 / token / 模型名 | 11–12sp | 13.2–14.4sp | 不抢正文层级 |
| 空状态品牌标题 | 26sp | 31.2sp | 替代原 42sp，避免“超级大” |

## 5. 验证

已完成验证：

- `test/shared/markdown_rendering_test.dart`：390×844 移动视口渲染扩展 Markdown，覆盖旧式图片、行内公式、块级公式、HTML audio/video、HTML details、Mermaid 和 Draw.io。
- `test/shared/settings_provider_test.dart`：覆盖字体缩放范围收敛为 90%–120%。
- `test/core/app_identity_test.dart`：覆盖移动端展示名和 Android / iOS 包名。
- `flutter analyze`：通过。
- `flutter test`：289 个测试通过。
- `scripts/smoke_mobile_main_flow.sh`：4 个移动端 smoke 通过，脚本内置 `flutter analyze` 通过。
- `flutter build apk --debug`：通过，生成 `build/app/outputs/flutter-apk/app-debug.apk`。
- `flutter build ios --simulator --no-codesign`：通过，生成 `build/ios/iphonesimulator/Runner.app`。
- `git diff --check`：无输出。



## Markdown 渲染 v2 补充（2026-07-03）

- 用户输入消息和 AI 输出消息统一使用 `LatexMarkdownWidget` 渲染，保证输入 / 输出两侧能力一致。
- 修复行内代码（如 `requestId` / `apiHost` / `offline=true/false`）被误渲染成大代码块的问题；只有 fenced / 多行代码继续使用 `CodeBlockWidget`。
- 图片兼容补充：标准 Markdown 图片、旧式 `[[img:...]]` / `[[image:...]]`、Obsidian `![[...]]`、简写 `[img:...]` / `[image:...]`、HTML `<img src="...">`。
- Mermaid 兼容补充：```mermaid fenced code、无语言但源码可识别的 Mermaid 代码块、`:::mermaid`、`[mermaid]...[/mermaid]`、HTML `<div class="mermaid">...`。
- Draw.io / mxGraph 兼容补充：```drawio / ```draw.io / ```mxgraph / ```diagrams.net fenced code、XML 代码块自动识别、`:::draw.io`、`[mxgraph]...[/mxgraph]`、原始 `<mxGraphModel>...</mxGraphModel>` 块。
- 回归测试：`test/shared/markdown_rendering_test.dart` 覆盖行内 code、fenced code、图片新老格式、Mermaid / Draw.io 新老格式、用户输入和 AI 输出统一渲染。
