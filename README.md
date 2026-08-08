# SimiChat

SimiChat 是一个 Flutter 全平台 AI 对话应用：会话、模型渠道、消息、附件、记忆、Dreaming / Reflection、MCP、语音和数据导出均以本地数据为中心。模型协议通过统一适配层接入，支持远程渠道，也支持 **Ollama 本地模型**。

## 当前定位

- **本地优先**：聊天、上下文压缩、会话标题、Dreaming / Reflection 等功能复用当前会话选中的模型；选中 Ollama 渠道后请求直接发往配置的本地 Ollama 地址。
- **数据本地保存**：SQLite、会话 Markdown、附件、模型渠道和设置都保存在应用本地；API Key 使用本地加密存储。
- **可回退但不静默切云端**：本地 Ollama 不可用时会显示连接错误，不会自动把本地请求改发到远程厂商。
- **跨平台**：Flutter 项目包含 Android、iOS、macOS、Linux 和 Windows 工程；真机 smoke 与静态测试分开记录。
- **MCP 自带运行时**：Android APK 内置 arm64 Node.js Runtime；PC 构建前准备与目标平台匹配的官方 Node binary，App 运行 MCP 时不依赖宿主机 `node` / `npx` / Docker / Podman。
- **移动端扩展安装**：Android / iOS 共用 manifest、SHA-256、权限 allowlist、原子安装、registry 和 quarantine；Skills、声明式 Agents、App Native MCP 可直接安装，Node MCP 按平台 runtime 矩阵运行。

## 快速开始

~~~bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
~~~

运行应用：

~~~bash
flutter run
~~~

## 使用本地 Ollama 模型

1. 安装并启动 Ollama，在本机准备一个模型：

   ~~~bash
   ollama pull gemma4
   ollama serve
   ~~~

2. 打开 SimiChat 的 **设置 → 模型渠道 → 添加渠道**，在“厂商预设”中选择 **Ollama 本地模型**。
3. Base URL 按运行位置填写：
   - macOS / Linux / Windows 桌面端、iOS Simulator：http://127.0.0.1:11434
   - Android Emulator：http://10.0.2.2:11434
   - Android / iOS 真机：填写运行 Ollama 电脑在同一局域网内的 IP，例如 http://192.168.x.x:11434
4. Ollama 通常不需要 API Key，直接留空；如果前面配置了需要 Bearer 鉴权的反向代理，再填写代理密钥。
5. 点击自动获取模型，或在会话顶部选择模型后发送消息。

验证已经运行的本地服务：

~~~bash
OLLAMA_MODEL=gemma4 scripts/smoke_local_ollama.sh
~~~

脚本只检查 /api/tags 和流式 /api/chat，不会启动、停止或修改 Ollama。Android 真机使用局域网地址时，需要让 Ollama 监听局域网地址，并确保防火墙允许端口访问。

## 模型调用链

~~~text
SettingsPage
  -> ModelProviderPreset / ChannelDao
  -> ChatPage / chat_provider.dart
  -> AiService
  -> OllamaProtocol (/api/chat, NDJSON)
  -> 本地 Ollama
~~~

Ollama 适配层同时处理：

- 流式 NDJSON；
- message.content 与 message.thinking；
- 可选 Bearer 鉴权；
- 连接超时、流式空闲超时和响应取消；
- 本地模型列表 /api/tags；
- 图片附件转换为 Ollama images 字段。

## 使用 App 内置 Node MCP

市场中的 **SimiChat 内置 Node Runtime** 适用于需要 Node MCP 工具、但不希望
配置宿主机 Node 环境的场景：

- Android：`arm64-v8a` Node runtime 已随 APK 内置；
- PC：发布构建前运行 `scripts/prepare_node_runtime.sh`，把 manifest 固定的
  官方 Node binary 放入目标 App 自己的 Resources / 安装目录；桌面 binary
  不进入 Flutter assets，也不会被打进 Android APK；
- 运行时由 App 管理本地 SSE，不调用宿主机 `node` / `npm` / `npx`，也不自动
  启动 Docker / Podman；
- PC 容器 Runtime 仍是可选隔离路径，不是 bundled Node 的前置依赖。

具体目录、生命周期、构建命令和证据边界见
[Android / PC 内置 Node Runtime](docs/MCP_BUNDLED_NODE_RUNTIME.md)。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| lib/core/ai/ | 协议适配、模型预设、模型列表和连接测试 |
| lib/shared/providers/ | Riverpod 状态、聊天发送、会话与设置 |
| lib/features/chat/ | 聊天页面与消息交互 |
| lib/features/settings/ | 模型渠道、模型测试、数据和功能设置 |
| lib/core/database/ | Drift 表、迁移和 DAO |
| lib/core/extensions/ | 移动端 MCP / Skill / Agent 包协议、校验、安装、registry 和运行计划 |
| test/ | 全部 Flutter 单元 / Widget / manifest / smoke / benchmark 测试，统一放在一个目录并按文件名区分类型 |
| test/README.md | 测试目录约定、测试类型、运行命令和与 integration_test 的边界 |
| integration_test/ | 移动端集成入口 |
| scripts/ | 稳定性、设备 smoke、基准和本地模型验证脚本 |
| docs/ | 架构、功能设计、验证记录和当前项目状态 |

## 文档入口

- [文档目录](docs/README.md)
- [当前项目状态](docs/current-status.md)
- [本地 Ollama 接入与稳定性说明](docs/local-model.md)
- [当前验证基线](docs/verification-baseline-2026-08-08.md)
- [Android / PC 内置 Node Runtime](docs/MCP_BUNDLED_NODE_RUNTIME.md)
- [Android / iOS 移动端 MCP、Skills、Agent 安装协议](docs/MOBILE_EXTENSIONS.md)
- [MCP Runtime 容器化设计](docs/MCP_RUNTIME_CONTAINERIZATION.md)
- [AI 协议适配层](docs/ai-protocols.md)
- [整体架构](docs/architecture.md)
- [模型接入方案](docs/model-integration.md)
- [产品需求与路线账本](docs/requirements.md)

项目进度、历史验证和协作规则仍集中维护在根目录 AGENTS.md；具体方案和验证证据放在 docs/，避免把实现细节继续堆进项目总纲。

## 验证边界

仓库测试可以证明协议组装、NDJSON/SSE 解析、取消、错误处理、设置页和数据库边界；它们不能替代真实 Ollama 进程、具体模型权重、移动端网络和真机后台验证。真实本地模型验证必须运行 scripts/smoke_local_ollama.sh 并记录模型名、Base URL 类型和结果。

不要把 API Key、Bearer Token、Cookie、真实设备路径或含密钥的配置提交到仓库。
