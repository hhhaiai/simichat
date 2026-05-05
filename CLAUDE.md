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
│   ├── database/        # drift + SQLite (7 张表 + 6 个 DAO)
│   ├── ai/              # 多协议适配层（5 种协议 + SSE 流式）
│   ├── mcp/             # MCP 客户端（stdio/SSE 传输）
│   ├── context/         # 无限上下文引擎
│   └── crypto/          # API Key 加密
├── features/
│   ├── chat/            # 对话主页
│   ├── history/         # 历史会话 + 文件夹
│   └── settings/        # 渠道/模型/MCP/Prompt 配置
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
| [数据库设计](docs/database.md) | 7 张表结构、DAO 职责划分 |
| [AI 协议适配](docs/ai-protocols.md) | 5 种协议接口、SSE 解析、错误处理 |
| [无限上下文设计](docs/infinite-context.md) | 滚动压缩、summary 生成、token 估算 |
| [UI 设计](docs/ui.md) | 页面布局、消息气泡、主题、桌面侧边栏 |

## 进度

### 已完成

- [x] 项目脚手架 + pubspec 依赖
- [x] 数据库层（7 张表 + 6 个 DAO：sessions/messages/channels/models/folders/attachments/prompts）
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

- [ ] **Web 搜索 / RAG**：接 SearXNG 或搜索 API，工具调用模式让模型决定搜索时机
- [ ] **图片生成**：DALL-E 或 Stable Diffusion API，新消息类型 `image`
- [ ] **DeepLink**：注册 `ai-chat://` scheme，`onGenerateRoute` 解析跳转

### P3：大型特性

- [ ] **数据同步/备份**：WebDAV/S3 + E2E 加密，增量同步，冲突解决
- [ ] **多标签/多窗口**：会话级窗口管理，架构调整
- [ ] **远程控制**：Telegram/Discord Bot 集成，独立 gateway 服务
