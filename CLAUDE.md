# AI Chat App

Flutter 全平台 AI 对话应用，桥接多种 AI 模型协议，支持无限上下文对话。

## 目标

- 全平台：Android / iOS / macOS / Windows / Linux
- 多协议：OpenAI / Claude / Gemini / Ollama，可自定义渠道
- 无限上下文：滚动压缩窗口，单会话无限对话
- 本地优先：SQLite 存储，数据不上云

## 技术栈

Flutter + Riverpod + drift(SQLite) + dio(SSE) + flutter_markdown + flutter_secure_storage + flutter_math_fork + webview_flutter

## 架构

```
lib/
├── core/
│   ├── database/        # drift + SQLite (9 张表 + 8 个 DAO)
│   ├── ai/              # 多协议适配层（5 种协议 + SSE 流式）
│   ├── mcp/             # MCP 客户端（stdio/SSE 传输）
│   ├── context/         # 无限上下文引擎
│   ├── crypto/          # API Key 加密
│   └── skills/          # Skills 系统（SkillHub.cn 市场接入）
├── features/
│   ├── chat/            # 对话主页
│   ├── settings/        # 渠道/模型/MCP/Prompt 配置
│   ├── skills/          # Skills 市场 UI
│   ├── search/          # 全局搜索
│   └── marketplace/     # MCP 市场
├── shared/
│   ├── providers/       # Riverpod 状态管理
│   └── widgets/         # 公共组件
├── l10n/                # 国际化（中/英 ARB）
└── main.dart
```

## 设计文档

| 文档 | 内容 |
|------|------|
| [需求规格](docs/requirements.md) | 功能需求、页面规格、响应式布局 |
| [数据库设计](docs/database.md) | 9 张表结构、DAO 职责划分 |
| [AI 协议适配](docs/ai-protocols.md) | 5 种协议接口、SSE 解析、错误处理 |
| [无限上下文设计](docs/infinite-context.md) | 滚动压缩、summary 生成、token 估算 |
| [UI 设计](docs/ui.md) | 页面布局、消息气泡、主题、桌面侧边栏 |

## 进度

### 已完成

- [x] 项目脚手架 + pubspec 依赖
- [x] 数据库层（9 张表 + 8 个 DAO：sessions/messages/channels/models/folders/attachments/prompts/mcp_servers/skills）
- [x] AI 协议适配层（5 种协议：OpenAI Chat/Response、Claude、Gemini、Ollama）
- [x] 无限上下文引擎（token 估算 + 上下文构建 + 滚动压缩）
- [x] 状态管理层（Riverpod：database/session/channel/folder/chat/prompt/mcp provider）
- [x] UI：对话主页（消息气泡、Markdown 渲染、流式输出、输入区）
- [x] UI：侧边栏（模型选择器跨渠道穷举 + 历史会话列表 + 文件夹分组）
- [x] UI：设置页（渠道管理、模型增删、主题、压缩阈值、Prompt 库、MCP 服务器）
- [x] 多平台适配（桌面侧边栏 280px + 移动端 Drawer，>720px 断点）
- [x] 中断流式输出
- [x] 主题切换持久化
- [x] 压缩阈值滑块交互
- [x] Thinking/推理内容展示（Claude thinking_delta + OpenAI reasoning + Gemini thought + DeepSeek R1）
- [x] LaTeX 数学公式渲染（`flutter_math_fork`，支持 $$...$$ 块级公式）
- [x] Token 实时计数（输入框底部实时估算 + 已完成消息元数据）
- [x] 系统提示词 UI（模型选择器旁 tune 图标，按会话编辑/清除 + 提示词库选择）
- [x] SSE 解析提取（`sse_helper.dart` 共享 `parseSseStream` + `openSseStream`）
- [x] 网络状态提示（`connectivity_provider` + 离线提示条）
- [x] 附件管线接通（`ChatInputBar` → `sendMessage` → `AttachmentDao` → AI 协议多模态）
- [x] Ollama 协议适配（`/api/chat` NDJSON + `/api/tags` 模型列表）
- [x] 键盘快捷键（`Ctrl+N` 新建、`Ctrl+Shift+K` 搜索、`Escape` 取消流式）
- [x] Prompt 库 / 助手模板（`prompts` 表 + 设置页管理 + 对话页选择器）
- [x] 对话 Fork（复制 Session + Messages 到新会话，从指定消息分叉）
- [x] Mermaid 图表渲染（WebView 渲染 `mermaid` 代码块，全屏查看）
- [x] 多语言 i18n（ARB 文件 + `flutter_localizations`，中英双语框架）
- [x] MCP 协议客户端（stdio/SSE 传输，Tool/Resource/Prompt 三大能力，设置页配置）
- [x] Skills 市场接入（SkillHub.cn API 搜索/导入/SHA-256 校验，system prompt 注入）
- [x] Markdown 图片查看（点击放大 + photo_view 缩放 + gal 保存本地）
- [x] 全局搜索（Ctrl+Shift+K，搜索会话标题 + 消息内容）
- [x] 紧凑模型选择器（CompactModelSelector，渠道分组 + 会话级切换）
- [x] MCP 工具调用循环（AI → tool_call 解析 → 执行 → 结果回传 → AI 最终回复，最多 3 轮）

## 参考项目

对标以下三个开源 AI 客户端：

| | [Chatbox](https://github.com/chatboxai/chatbox) | [Cherry Studio](https://github.com/CherryHQ/cherry-studio) | [DeepChat](https://github.com/ThinkInAIXYZ/deepchat) |
|---|---|---|---|
| 技术栈 | Electron + React | Electron + React | Electron + React |
| 平台 | Win/Mac/Linux + Web + iOS/Android | Win/Mac/Linux | Win/Mac/Linux |
| 协议 | OpenAI, Azure, Claude, Gemini, Ollama, ChatGLM | 多云端 + Ollama, LM Studio | 20+ 厂商 + Ollama, LM Studio |
| 特色 | E2E 数据同步, Prompt 库, 团队协作 | 300+ 预置助手, MCP, WebDAV, Mermaid | MCP, Skills, ACP, 远程控制, 多标签, DeepLink |
| 许可 | GPLv3 | AGPLv3 | Apache 2.0 |

## 路线图

### P2：待实现

- [ ] **MCP Runtime 容器层**：把 MCP 从 UI 直接拉起外部进程，升级为独立 Runtime/Sidecar 层（安装、启动、权限、日志、状态统一管理），详见 `docs/MCP_RUNTIME_CONTAINERIZATION.md`
- [ ] **Web 搜索 / RAG**：接 SearXNG 或搜索 API，工具调用模式让模型决定搜索时机
- [ ] **图片生成**：DALL-E 或 Stable Diffusion API，新消息类型 `image`
- [ ] **DeepLink**：注册 `ai-chat://` scheme，`onGenerateRoute` 解析跳转

### P3：大型特性

- [ ] **数据同步/备份**：WebDAV/S3 + E2E 加密，增量同步，冲突解决
- [ ] **多标签/多窗口**：会话级窗口管理，架构调整
- [ ] **远程控制**：Telegram/Discord Bot 集成，独立 gateway 服务

---

## 已知问题清单（2026-05-05 审计）

### 严重 Bug（功能完全失效）

| # | 问题 | 文件 |
|---|------|------|
| BUG-1 | ContextCompressor 写入 `AiChunk.toString()`（即 "Instance of 'AiChunk'"）而非实际内容，上下文压缩功能完全失效 | `context_compressor.dart:79` |
| BUG-2 | SseTransport.connect() 用 `await for` 阻塞等待 SSE 流结束，导致 MCP 初始化永远卡住，SSE 类型 MCP 服务器全部不可用 | `mcp_client.dart:201-235` |
| BUG-3 | getMessagesPaginated 的 limit/offset 参数从未使用，每次返回全部消息 | `message_dao.dart:19-28` |

### 高危问题

| # | 问题 | 文件 |
|---|------|------|
| HI-1 | KeyEncryptor 只是 base64 编码，不是真正加密，数据库可逆 | `key_encryptor.dart` |
| HI-2 | Gemini API Key 暴露在 URL query 参数中，应用 header 方式 | `gemini_protocol.dart:17` |
| HI-3 | MCP SSE 发送 POST 无错误处理（fire-and-forget） | `mcp_client.dart:244-251` |
| HI-4 | MCP 请求无超时机制，服务器无响应会永久挂起 | `mcp_client.dart:97-115` |
| HI-5 | StdioTransport 忽略 stderr，MCP 服务器错误信息丢失 | `mcp_client.dart:163-177` |
| HI-6 | SSE utf8.decode 直接处理原始字节，多字节字符（如中文）跨块切分时会抛异常导致流中断 | `sse_helper.dart` |
| HI-7 | KeyEncryptor.decrypt 未 try-catch，异常导致流状态卡死在 isStreaming: true | `chat_provider.dart:142` |
| HI-8 | MCP tools 基础设施完整但从未注入对话上下文，工具调用形同虚设 | `mcp_provider.dart` + `chat_provider.dart` |

### 中等问题

| # | 问题 | 文件 |
|---|------|------|
| MED-1 | `DropdownButtonFormField` 用了 `initialValue` 而非 `value`，设置页下拉选择后 UI 不更新 | `settings_page.dart:402,510,1138` |
| MED-2 | `flutter_secure_storage` 声明了但从未使用 | `pubspec.yaml:28` |
| MED-3 | `builtInSkills` 定义了但从未插入数据库 | `skill.dart:78-147` |
| MED-4 | 12+ DAO 方法从未调用（死代码） | 各 DAO 文件 |
| MED-5 | i18n 框架已配置但零字符串本地化，全部硬编码中文 | 全部 UI 文件 |
| MED-6 | 通知 ID 硬编码为 0，并发通知互相覆盖 | `notification_service.dart:59` |
| MED-7 | 全局 Dio 缓存 `_dioCache` 永远不清理 | `http_helper.dart:4` |
| MED-8 | 全局 `_streamSubscriptions` 可能泄漏 | `chat_provider.dart:23` |
| MED-9 | 多处 TextEditingController 未 dispose | `sidebar.dart`, `chat_page.dart` |
| MED-10 | Mermaid 依赖硬编码 CDN，离线不可用 | `mermaid_widget.dart` |
| MED-11 | 删除渠道时 Sessions 外键无级联删除 | `tables.dart` |
| MED-12 | SSE openSseStream 无显式取消机制，用户停止生成后网络连接可能未回收 | `sse_helper.dart` |

### 低级问题

| # | 问题 | 文件 |
|---|------|------|
| LOW-1 | 4 个 SSE 协议实现有空的 `finally {}` 块 | 各 protocol 文件 |
| LOW-2 | Claude 模型列表硬编码不会更新 | `claude_protocol.dart` |
| LOW-3 | `userId` 列从未使用 | `tables.dart` |
| LOW-4 | Skill ID 用 name 做主键，有碰撞风险 | `skill.dart` |
| LOW-5 | `intl` 版本钉死无 `^` | `pubspec.yaml` |
| LOW-6 | 30+ 处硬编码 `Colors.grey/green` 未用主题色 | 各 widget |
| LOW-7 | `firstWhere` + 空 catch 吞掉所有异常 | 多处 |
| LOW-8 | `_draftCache` 静态 Map 无限增长不 GC | `chat_page.dart:33` |
| LOW-9 | Dio 错误封装丢失 Status Code 信息（401/429 等） | `sse_helper.dart` |
| LOW-10 | 模型菜单构建逻辑重复（chat_page + model_selector） | 两处 |

---

## 已知问题清单（2026-05-05 审计）

### 严重 Bug（功能完全失效）

| # | 问题 | 文件 | 状态 |
|---|------|------|------|
| BUG-1 | ContextCompressor 写入 `AiChunk.toString()` 而非实际内容，上下文压缩功能完全失效 | `context_compressor.dart:79` | ✅ 已修复 |
| BUG-2 | SseTransport.connect() 用 `await for` 阻塞，MCP 初始化永远卡住 | `mcp_client.dart:201-235` | ✅ 已修复 |
| BUG-3 | getMessagesPaginated 的 limit/offset 参数从未使用 | `message_dao.dart:19-28` | ✅ 已修复 |

### 高危问题

| # | 问题 | 文件 | 状态 |
|---|------|------|------|
| HI-1 | KeyEncryptor 只是 base64 编码，不是真正加密 | `key_encryptor.dart` | ✅ 已修复（AES-256-CBC） |
| HI-2 | Gemini API Key 暴露在 URL query 参数中 | `gemini_protocol.dart:17` | ✅ 已修复（改用 x-goog-api-key header） |
| HI-3 | MCP SSE POST 无错误处理 | `mcp_client.dart:244-251` | ✅ 已修复 |
| HI-4 | MCP 请求无超时机制 | `mcp_client.dart:97-115` | ✅ 已修复（30s 超时） |
| HI-5 | StdioTransport 忽略 stderr | `mcp_client.dart:163-177` | ✅ 已修复 |
| HI-6 | SSE utf8.decode 多字节字符跨块切分异常 | `sse_helper.dart` | ✅ 已修复（_trimIncompleteUtf8） |
| HI-7 | KeyEncryptor.decrypt 未 try-catch，流状态卡死 | `chat_provider.dart:142` | ✅ 已修复（try-catch 包裹） |
| HI-8 | MCP tools 从未注入对话上下文，工具调用形同虚设 | `mcp_provider.dart` + `chat_provider.dart` | ✅ 已修复（工具调用循环 + 解析执行） |

### 中等问题

| # | 问题 | 文件 |
|---|------|------|
| MED-1 | `DropdownButtonFormField` 用了 `initialValue` 而非 `value`，设置页下拉选择后 UI 不更新 | `settings_page.dart:402,510,1138` |
| MED-2 | `flutter_secure_storage` 声明了但从未使用 | `pubspec.yaml:28` |
| MED-3 | `builtInSkills` 定义了但从未插入数据库 | `skill.dart:78-147` |
| MED-4 | 12+ DAO 方法从未调用（死代码） | 各 DAO 文件 |
| MED-5 | i18n 框架已配置但零字符串本地化，全部硬编码中文 | 全部 UI 文件 |
| MED-6 | 通知 ID 硬编码为 0，并发通知互相覆盖 | `notification_service.dart:59` |
| MED-7 | 全局 Dio 缓存 `_dioCache` 永远不清理 | `http_helper.dart:4` |
| MED-8 | 全局 `_streamSubscriptions` 可能泄漏 | `chat_provider.dart:23` |
| MED-9 | 多处 TextEditingController 未 dispose | `sidebar.dart`, `chat_page.dart` |
| MED-10 | Mermaid 依赖硬编码 CDN，离线不可用 | `mermaid_widget.dart` |
| MED-11 | 删除渠道时 Sessions 外键无级联删除 | `tables.dart` |
| MED-12 | SSE openSseStream 无显式取消机制，用户停止生成后网络连接可能未回收 | `sse_helper.dart` |

### 低级问题

| # | 问题 | 文件 |
|---|------|------|
| LOW-1 | 4 个 SSE 协议实现有空的 `finally {}` 块 | 各 protocol 文件 |
| LOW-2 | Claude 模型列表硬编码不会更新 | `claude_protocol.dart` |
| LOW-3 | `userId` 列从未使用 | `tables.dart` |
| LOW-4 | Skill ID 用 name 做主键，有碰撞风险 | `skill.dart` |
| LOW-5 | `intl` 版本钉死无 `^` | `pubspec.yaml` |
| LOW-6 | 30+ 处硬编码 `Colors.grey/green` 未用主题色 | 各 widget |
| LOW-7 | `firstWhere` + 空 catch 吞掉所有异常 | 多处 |
| LOW-8 | `_draftCache` 静态 Map 无限增长不 GC | `chat_page.dart:33` |
| LOW-9 | Dio 错误封装丢失 Status Code 信息（401/429 等） | `sse_helper.dart` |
| LOW-10 | 模型菜单构建逻辑重复（chat_page + model_selector） | 两处 |
