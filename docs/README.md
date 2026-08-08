# SimiChat 文档中心

本目录按“当前入口 → 产品与架构 → 功能专题 → 验证记录 → 历史归档”的顺序组织。文档中的命令、路径、协议字段和模型名称必须与当前代码保持一致；历史验证记录保留当时的环境和结论，不自动代表当前状态。

## 0. 权威关系与阅读顺序

### 权威关系

| 内容 | 唯一入口 | 责任 |
| --- | --- | --- |
| 安装、运行、本地模型快速开始 | 根目录 `README.md` | 面向使用者的最短路径 |
| 目标、阶段、待办、已完成事项、重要决策 | 根目录 `AGENTS.md` | 项目总纲和当前账本 |
| 当前状态快速摘要 | `docs/current-status.md` | 当前代码、验证、缺口和下一步 |
| 当前命令与验证结果 | `docs/verification-baseline-2026-08-08.md` | 本轮可复现证据 |
| 产品需求 | `docs/requirements.md` | 产品边界和路线，不替代运行时验收 |
| 具体实现方案 | 本目录对应专题文档 | 架构、接口、数据、测试和安全细节 |
| 历史真机 / smoke 证据 | 带日期的 `docs/*smoke*.md` 等 | 只说明对应日期和环境的结果 |
| Flutter 测试目录约定 | `../test/README.md` | `test/` 扁平目录、命名规则、运行命令和 integration_test 边界 |

### 推荐阅读顺序

1. `README.md`：安装、运行和本地 Ollama 最短路径。
2. `current-status.md`：当前已修复内容、验证门禁和未补证边界。
3. `local-model.md`：Ollama 配置、`gemma4` 默认勾选、网络地址和故障排查。
4. `architecture.md`、`ai-protocols.md`、`database.md`：理解代码边界。
5. 对应功能专题：记忆、Dreaming、同步、社交、MCP、数字孪生等。
6. 验证记录：确认某项功能是在什么日期、什么设备、什么配置下被验证。

## 一、当前入口与状态

| 文档 | 用途 |
| --- | --- |
| [当前项目状态](current-status.md) | 当前代码修复、gemma4 默认选择、验证门禁、未完成 runtime 证据 |
| [本地 Ollama 接入与稳定性](local-model.md) | Ollama 安装、Base URL、模型列表、协议稳定性、故障排查 |
| [当前验证基线（2026-08-08）](verification-baseline-2026-08-08.md) | 当前静态分析、全量测试、构建、mock smoke 和真实 runtime 边界 |
| [移动端 MCP / Skills / 记忆质量门禁（2026-08-08）](mobile-mcp-skills-memory-quality-2026-08-08.md) | Pixel 8 / iPhone13 的 MCP、Skills、Key Point、FTS、semantic、Dreaming / Reflection 逻辑与 UI 证据 |
| [功能实现差距分析（2026-08-07）](implementation-gap-analysis-2026-08-07.md) | 功能项逐项标注已实现、需真机补证或需外部资源 |
| [产品需求总纲](requirements.md) | 产品目标、模块、页面、隐私和路线需求 |

## 二、产品与架构设计

| 文档 | 主题 |
| --- | --- |
| [整体架构](architecture.md) | Flutter 分层、Provider、数据库、协议和生产化门禁 |
| [AI 协议适配层](ai-protocols.md) | OpenAI Chat、Responses、Claude、Gemini、Ollama 和统一流式处理 |
| [多模型接入与个人接口中转](model-integration.md) | 渠道、模型能力、模型切换、Relay 和路由策略 |
| [数据库设计](database.md) | Drift 表、迁移、DAO 和本地持久化边界 |
| [无限上下文](infinite-context.md) | 上下文预算、滚动压缩、摘要和令牌估算 |
| [记忆系统](memory-system.md) | Key Points、Markdown 原始档案、本地搜索和召回 |
| [Dreaming](dreaming.md) | 夜间整理、任务调度、报告、画像和后台边界 |
| [Reflection](reflection.md) | 本地反思、可选模型增强、失败回退和短期提示 |
| [移动端优先 UI 设计系统](ui-design.md) | 主题、字体、移动端布局和可访问性 |
| [历史 UI 设计说明](ui.md) | UI 早期设计与实现参考 |
| [对话页 Markdown 渲染](markdown-rendering.md) | Markdown、公式、Mermaid、Draw.io、媒体卡片和安全边界 |
| [语音、图片与附件](media-attachments.md) | 录音、STT、TTS、图片、文件、归档和多模态输入 |
| [数据同步、导出与笔记工具](data-sync.md) | 导出、导入、Obsidian、Notion、语雀、思源、云备份 |
| [深度链接](deep-linking.md) | `ai-chat://` 外部唤起协议 |
| [技能市场](skills-market.md) | SkillHub、通用 HTTP 技能源、安装和 SHA-256 校验 |
| [社交平台接入](social-channels.md) | Telegram、Discord、飞书、Webhook 平台和 AI 网关 |
| [数字孪生 / 镜像数字人](digital-twin.md) | 画像、媒体信号、替身授权、审计和直播脚本 |
| [MCP Runtime 容器化](MCP_RUNTIME_CONTAINERIZATION.md) | PC Node、容器、SSE、内建工具和权限边界 |

## 三、当前专题补充

| 文档 | 主题 |
| --- | --- |
| [DW Chainless 中转站集成（2026-08-07）](dwchainless-relay-integration-2026-08-07.md) | 中转站预设、注册引导、一键接入和关于页鸣谢 |
| [运行时配置示例](runtime-manifest.example.json) | 仅作格式示例，不放真实地址、密钥或设备路径 |

## 四、验证记录与历史归档

### 4.1 当前验证

- [当前验证基线（2026-08-08）](verification-baseline-2026-08-08.md)
- [移动端 MCP / Skills / 记忆质量门禁（2026-08-08）](mobile-mcp-skills-memory-quality-2026-08-08.md)
- [当前项目状态](current-status.md)

### 4.2 移动端主链路和设备验证

以下文档全部是带日期的历史证据，必须结合文档中的设备、构建类型、包名、cleanup 结果和“待补证”说明阅读：

- [移动端主链路](mobile-main-flow-smoke-2026-06-27.md)
- [移动端设备集成发送](mobile-device-integration-send-smoke-2026-07-06.md)
- [移动端真机安装与启动](mobile-device-install-smoke-2026-07-06.md)
- [移动端真实发送 / 重试 / 停止 / 历史搜索](mobile-real-send-smoke-2026-07-06.md)
- [移动端模型切换](mobile-model-switch-smoke-2026-07-06.md)
- [移动端设置页](mobile-settings-smoke-2026-07-06.md)
- [复杂 Markdown 滚动](mobile-markdown-scroll-smoke-2026-07-06.md)
- [Android 后台恢复](mobile-background-restore-smoke-2026-07-07.md)
- [Android 后台流式取消](mobile-background-stream-cancel-smoke-2026-07-07.md)
- [移动端后台流式取消代码边界](mobile-background-stream-cancel-2026-07-07.md)
- [Android 物理断网流式取消](mobile-network-stream-cancel-smoke-2026-07-07.md)
- [移动端网络稳定性](mobile-network-stability-2026-07-06.md)
- [iOS 后台恢复](mobile-ios-background-restore-smoke-2026-07-07.md)
- [iOS release 发送](mobile-ios-release-send-smoke-2026-07-06.md)
- [base64 语音发送](mobile-base64-audio-smoke-2026-07-06.md)
- [STT 网络链路](mobile-stt-network-smoke-2026-07-06.md)
- [TTS 网络链路](mobile-tts-network-smoke-2026-07-06.md)
- [真实录音按钮](mobile-voice-recording-smoke-2026-07-06.md)
- [原生音频播放](mobile-native-audio-player-smoke-2026-07-06.md)
- [长音频播放](mobile-long-audio-playback-smoke-2026-07-06.md)
- [音频播放替换 / 中断](mobile-audio-playback-replace-smoke-2026-07-06.md)
- [音频焦点加固](mobile-audio-focus-hardening-2026-07-06.md)
- [后台脚本加固](mobile-smoke-script-hardening-2026-07-06.md)
- [Pixel 8 长会话 Dreaming / Reflection](mobile-long-conversation-reflection-smoke-2026-07-06.md)
- [Dreaming / Reflection 失败恢复](mobile-dreaming-reflection-recovery-smoke-2026-07-14.md)
- [Android 后台 Dreaming / Reflection](mobile-android-background-dreaming-smoke-2026-07-14.md)
- [iOS 后台 Dreaming / Reflection](mobile-ios-background-dreaming-smoke-2026-07-14.md)
- [移动端远程模型 Reflection 质量](mobile-remote-model-reflection-quality-2026-07-14.md)
- [移动端模型驱动画像质量](mobile-model-user-profile-quality-2026-07-14.md)

### 4.3 Relay / 协议专项验证

- [OpenAI Relay Responses 流式兼容](openai-relay-responses-stream-2026-07-07.md)
- [OpenAI Relay 流式错误收口](openai-relay-stream-error-2026-07-07.md)
- [测试稳定性收口](test-stability-2026-07-06.md)

### 4.4 历史基线

- [历史验证基线（2026-06-27）](verification-baseline-2026-06-27.md)：保留当时的需求、测试、构建和设备证据，不覆盖当前基线。

## 五、状态标签解释

文档中使用以下状态，不允许互相替代：

| 标签 | 含义 |
| --- | --- |
| `implemented` | 代码已经存在，通常还有测试或静态证据 |
| `tested` | 指定测试命令通过，不代表真实设备或外部服务通过 |
| `runtime_verified` | 在真实进程、服务、设备或网络中获得证据 |
| `ui_verified` | 在真实 UI / 设备交互中获得证据 |
| `blocked_with_evidence` | 有明确 blocker、命令或现场证据，不能继续伪造完成 |
| `historical` | 仅适用于文档记录日期当时的状态 |

特别是：`flutter test`、`flutter build`、HTTP mock、静态 manifest 和 source inspection 不能单独升级为 `runtime_verified` 或 `ui_verified`。

## 六、文档维护规则

1. 新功能或修复先更新对应专题文档，再更新 `current-status.md` 和当前验证记录。
2. 每条修复记录至少包含：问题、修改路径、行为变化、测试路径、未覆盖边界。
3. 当前状态只写当前可复现证据；历史结果新增带日期文档，不覆盖旧记录。
4. 文档中的 Base URL、模型名、协议字段、命令和代码路径必须与当前实现一致。
5. 真实服务、真机、长会话和外部账号验证必须单独记录运行环境和 cleanup 结果。
6. 任何 API Key、Bearer Token、Cookie、真实设备私有路径、真实聊天内容都不得进入文档。
7. 变更后运行 Markdown 相对链接检查、`git diff --check`、Dart 分析和相关测试。
