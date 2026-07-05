# SimiAIChat — 项目总纲与智能体工作账本

> **定位**：人工智能聊天工具，最终形态 = 好友陪伴（虚拟朋友 / 智能助理）+ 数字孪生（镜像数字人，基于长期对话录入与资料蒸馏生成）。
>
> **技术栈**：Flutter，移动端优先；移动端核心功能稳定后再扩展桌面 / 电脑端。
>
> **主事实来源**：本文件记录项目目标、阶段进度、待办、已完成事项、重要决策与执行约束。`CLAUDE.md` 的项目进度、路线图、已知问题和重要安排已迁移到本文件；后续维护以 `AGENTS.md` 为准。
>
> **最后更新**：2026-07-06。

---

## 0. 文档与协作规则

### 0.1 最新需求确认（2026-06-27）

用户已再次确认本项目完整需求，后续产品和技术推进以本文件梳理后的版本为准：

- 项目不是单纯桌面聊天壳，而是 **移动端优先** 的 Flutter 人工智能聊天工具。
- 最终形态是 **好友陪伴（虚拟朋友 / 智能助理）+ 数字孪生（镜像数字人）**。
- 核心主线必须同时覆盖：多模型接入、智能体编排、定时任务、社交平台接入、个人接口中转、长期记忆、Dreaming 夜间整理、技能市场、数据导出同步、语音图片多模态、无限上下文、用户画像和镜像数字人。
- DeepChat 与 Cherry Studio 作为聊天体验、多模型、频道、个人中转等方向的重点参考；OpenClaw / 龙虾作为社交通道与技能生态重点参考。
- `AGENTS.md` 只维护目标、进度、待办、已完成事项和重要安排；所有具体实现方案继续沉淀到 `docs/`；完整产品需求同步维护在 `docs/requirements.md`。
- `CLAUDE.md` 不再维护项目进度，避免双源冲突。
- 用户原始约定中提到的 `docs/conversations/` 作为仓库侧“对话 Markdown 原始档案”说明 / 脱敏示例目录；真实运行时用户对话 Markdown 必须写入应用私有数据目录并被 Git 忽略，禁止把真实聊天记录提交进仓库。

1. **目标与进度**：`AGENTS.md` 维护项目目标、阶段规划、当前进度、待办、已完成事项、重要决策、验证记录和风险清单。
2. **实现文档**：所有具体功能方案、架构设计、接口设计、数据结构、测试方案、安全方案、迁移方案都放在 `docs/`。
3. **记录语言**：除项目名、文件名、命令、代码标识、协议缩写、外部产品名等必要原文外，记录性文字一律使用中文。
4. **移动端优先**：所有核心体验先以移动端可用、稳定、可测为准，再考虑桌面端增强。
5. **本地优先**：聊天数据、记忆、语音、图片、用户画像默认本地保存；云同步和外部写入必须可选、可关闭、可解释。
6. **验证优先**：生产功能完成前必须跑功能测试、性能验证、安全验证；不能只凭“看起来能用”标记完成。
7. **代码生成规则**：Drift / 本地化生成文件通过命令生成，不手改 `.g.dart` 或本地化生成文件。
8. **敏感数据规则**：不提交接口密钥、本地数据库、用户聊天记录、用户语音、用户图片、Markdown 原始对话档案。
9. **账本维护规则**：新需求先登记到“当前待办”或阶段规划；完成后同步更新“已完成能力”“进度记录”和对应 `docs/` 实现文档，并写清验证结果。

### 0.2 当前进度总览（2026-07-06）

| 方向 | 当前状态 | 下一步重点 |
| --- | --- | --- |
| 移动端 MVP | 基础聊天、会话列表、模型切换、本地 SQLite、Markdown 原始档案、移动端应用名 `SimiAIChat`、包名 `top.simitalk.aichat`、主题与 90%–120% 全局字体、移动端自动化 smoke 已落地，Pixel 8 真实发送 / 重试 / 停止 / 历史搜索 / 模型切换已补证，真机集成发送、设置页、复杂 Markdown 滚动、base64 语音发送、OpenAI 兼容 STT 网络、真实录音按钮、OpenAI 兼容 TTS 网络、原生音频播放通道、长音频播放完成和播放替换 / 中断 smoke 入口已新增并在 Pixel 8 通过 | 真机主链路：iOS 发送链路、长会话、原生播放中断、网络切换、后台恢复 |
| 多模型接入 | 已支持 OpenAI Chat / OpenAI Responses / Claude / Gemini / Ollama 协议适配；模型厂商预设、批量 JSON 导入、连通性测试、测试历史、失败重试、一键测试并剔除不可用模型、渠道 / 模型删除引用清理已落地 | 继续扩展国产 / 免费模型来源引导和更完整的协议兼容性测试 |
| 个人 OpenAI Relay | 已支持 Bearer 鉴权、`/health`、`/v1/health`、`/v1/models`、非流式 / 流式 `/v1/chat/completions`、非流式 buffered `/v1/responses`、CORS 预检、审计、用量统计、并发保护、局域网二次确认、路由策略、多模态安全降级、图片 data URL / 远端图片安全透传、Vision 路由 | 真机长时间运行、更多外部客户端兼容性、后台网络变化恢复 |
| 记忆与 Dreaming / 上下文 | Key Points、本地语义召回、消息语义索引、本地语义搜索开关、Dreaming 前台到期整理 / 通知、用户画像管理 / 历史 / 待确认变更、本地反思机制 v1、反思短期提示注入 v1、反思历史 v1、模型窗口预算裁剪、动态压缩阈值、上下文超限一次严格裁剪重试已落地 | 模型 embedding / ANN、真正后台调度、模型驱动反思、真机长会话基线 |
| 语音 / 图片 / 多模态 | 语音录音、私有归档、OpenAI 兼容 STT / TTS、音频附件发送前 STT 音频接口转写、base64 语音文本粘贴转写、iOS 系统 Speech 原生识别兜底、语音厂商预设、播放停止 / 完成事件、图片 / 文件附件、图片缩略图已落地；Pixel 8 已补 base64 语音粘贴 → audio 附件 → STT sidecar → 模型请求真机 smoke、OpenAI 兼容 STT multipart 网络 fallback smoke、真实录音按钮 → 原生 `.m4a` → STT → 聊天回复 smoke，以及 assistant 播报按钮 → OpenAI 兼容 `/v1/audio/speech` → 临时音频 → 停止播报 smoke，以及应用私有目录 WAV → Android `MediaPlayer` → stopped / completed 事件回传 smoke，以及播放中启动第二段音频时第一段 stopped、第二段 completed 的替换 smoke | 更多 STT / TTS 厂商、真实云端 STT / TTS 长音频、来电 / 音频焦点中断、声音 / 图像 / 表情画像 |
| 数据管理与同步 | `.tar.gz` 导出、系统分享、安全导入、结构化备份 / 恢复、电脑端本地传输、Obsidian Vault 导出、Obsidian 增量同步 / 附件 / 冲突 / stale 清理已落地 | Notion / 语雀 / 思源同步、云备份、Obsidian 双向同步 |
| 数字孪生 | 本地用户画像 v1 已落地，可查看、编辑、删除、恢复历史、逐项采纳 / 拒绝 Dreaming 画像变更 | 声音 / 图像 / 表情处理、镜像数字人生成、代理行为授权与审计 |
| 对话页 Markdown / 字体 | 扩展 Markdown 渲染 v2 已落地：用户输入和 AI 输出统一 Markdown 渲染；行内 code 不再误渲染为代码块；支持 GitHub Web 扩展、旧式 / Obsidian / HTML 图片、行内 / 块级公式、HTML audio/video 安全卡片、HTML details、旧式 details、多种 Mermaid 与 Draw.io / mxGraph 新老格式；移动端正文默认 15sp，缩放范围 90%–120% | 复杂 Markdown 真机滚动已补 Pixel 8 smoke；复杂表格 / 长代码 / 离线 Mermaid 视觉体验继续优化 |
| 最新验证 | 2026-07-06 本轮继续补 Pixel 8 真机主链路：通过本机 OpenAI 兼容 mock 服务 + `adb reverse` + debug 私有 DB seed，验证默认模型展示、真实发送、SSE 回复落库 / UI 展示、Reflection 短期提示进入 system prompt、assistant 重试、慢流停止断开上游并保留部分回复、历史搜索按 `smoke` 过滤；同日继续验证顶部模型菜单 `simichat-mock-a → simichat-mock-b` 切换、`model_switch` 时间线落库、切换后真实发送使用 B 模型；新增 `integration_test/mobile_real_send_smoke_test.dart`，Pixel 8 真机通过设备内本地 OpenAI mock 验证 UI 输入 → SSE → assistant 落库 → UI 展示闭环，并新增 `scripts/smoke_device_integration_send.sh` 封装临时 sqlite3 hook / 恢复 / 真机测试；`flutter --no-version-check analyze` 通过，命令内临时 `sqlite3.source=system` 后全量 `flutter --no-version-check test --no-pub --no-test-assets` 330 个测试通过；Pixel 8 Dreaming/Reflection 72 条长会话基线已完成，iPhone13 release 覆盖安装成功且进程可见；本轮进一步确认 iPhone13 集成发送和普通 `flutter run --debug` 都卡在 Xcode debug session `CONFIGURATION_BUILD_DIR` 超时，问题不在 integration_test 测试体；随后直接 `xcodebuild` Debug 构建可正常产出 `CONFIGURATION_BUILD_DIR` 并构建成功，同一 Debug 产物通过 `devicectl install app` 覆盖安装到 `top.simitalk.aichat`，但 `devicectl process launch` 被设备当前 Locked 状态拒绝，因此 iOS 发送链路下一步必须在物理解锁后复跑；同日新增 `integration_test/mobile_settings_smoke_test.dart` 与 `scripts/smoke_device_integration_settings.sh`，Pixel 8 真机通过设置页入口、主题切换、字体缩放 120% 持久化和返回首页闭环；新增 `integration_test/mobile_markdown_scroll_smoke_test.dart` 与 `scripts/smoke_device_integration_markdown_scroll.sh`，Pixel 8 真机通过复杂 Markdown 长消息、Mermaid / Draw.io 组件实例化和滚动到底部哨兵；新增 `integration_test/mobile_base64_audio_smoke_test.dart` 与 `scripts/smoke_device_integration_base64_audio.sh`，Pixel 8 真机通过 base64 语音粘贴解析、audio 附件归档、fake STT ready sidecar、净化后模型请求和 SSE 回复闭环；新增 `integration_test/mobile_stt_network_smoke_test.dart` 与 `scripts/smoke_device_integration_stt_network.sh`，Pixel 8 真机通过复用当前 OpenAI 兼容聊天渠道调用 multipart `/v1/audio/transcriptions`、ready sidecar、净化后聊天请求和 SSE 回复闭环；新增 `integration_test/mobile_voice_recording_smoke_test.dart` 与 `scripts/smoke_device_integration_voice_recording.sh`，Pixel 8 真机通过聊天页麦克风按钮、Android 原生录音 `.m4a`、audio 附件归档、STT fallback、ready sidecar、净化后聊天请求和 SSE 回复闭环；新增 `integration_test/mobile_tts_network_smoke_test.dart` 与 `scripts/smoke_device_integration_tts_network.sh`，Pixel 8 真机通过 assistant 播报按钮、OpenAI 兼容 `/v1/audio/speech` JSON 请求、临时音频写入、播放接口调用、停止播报和 UI 状态回退闭环；新增 `integration_test/mobile_native_audio_player_smoke_test.dart` 与 `scripts/smoke_device_integration_native_audio_player.sh`，Pixel 8 真机通过应用私有目录 WAV、Android `MediaPlayer` 播放、stop 调用、stopped 事件回传和无错误事件闭环；新增 `integration_test/mobile_long_audio_playback_smoke_test.dart` 与 `scripts/smoke_device_integration_long_audio_playback.sh`，Pixel 8 真机通过 6.5 秒应用私有目录 WAV、Android `MediaPlayer` 自然播放完成、completed 事件回传和无错误事件闭环；随后统一加固 9 个真机 smoke 脚本的 `mktemp` 模板，避免中断后 `/tmp` 字面量文件碰撞导致临时 sqlite hook 残留，并用 Pixel 8 原生音频 smoke 复验脚本恢复；新增 `integration_test/mobile_audio_playback_replace_smoke_test.dart` 与 `scripts/smoke_device_integration_audio_playback_replace.sh`，Pixel 8 真机通过播放中启动第二段 WAV 时第一段 stopped、第二段 completed 且无 error 的替换 / 中断闭环。 | iPhone 真机发送链路、真实云端 STT / TTS、复杂 Markdown 视觉审查等交互仍待补 |


---

## 一、项目目标（Vision）

打造一款以移动端为核心的人工智能聊天工具，核心价值：

1. **无限接入**：支持市面所有人工智能模型厂商，仅需输入接口密钥即可使用；支持批量免费模型引导接入（白嫖模式）；单对话内支持随时切换模型。
2. **智能陪伴**：虚拟好友 / 智能助理，结合记忆系统，做到“了解你”的人工智能伴侣。
3. **数字孪生**：通过长期对话分析用户画像（作息 / 风格 / 思维），生成可代理用户思维的镜像数字人；支持声音、图像、表情等多模态信息，未来可扩展到直播。
4. **本地优先**：聊天记录本地存储，隐私安全，支持导出 / 同步到主流笔记工具。
5. **生态打通**：接入主流社交平台、技能市场、个人接口中转服务。

---

## 二、核心功能模块

### M1 — 多模型接入

- 支持所有主流人工智能厂商：OpenAI / Claude / Gemini / DeepSeek / 讯飞 / 通义 / 百度等，输入接口密钥即用。
- 支持批量免费模型引导接入，参考 GitHub 免费大模型列表生态。
- 支持单对话内随时切换模型。
- 支持同时接入 N 个模型 / 厂商 / 渠道。
- 支持将多个模型聚合成个人接口中转服务器，参考 Cherry Studio，对外暴露统一接口转发。当前本地 OpenAI Relay 已支持健康检查、模型列表、聊天补全、Responses API 非流式兼容端点、CORS 预检、路由策略、审计统计和多模态安全边界。

### M2 — 记忆与上下文系统

- 聊天记录全部本地存储，默认不上云。
- 每个对话对应 1 个 Markdown 原始文件。
- 核心记忆点提取后常驻本地索引 / 内存（Key Points），每次对话带入检索结果。
- 跨对话内容支持快速检索，形成本地知识库和本地检索增强生成能力。
- 无限上下文设计：超过模型令牌限制时自动提取重要内容并压缩；发送前按模型窗口预算裁剪上下文，优先保留最新用户问题，真实接口返回超限时自动严格裁剪重试一次。
- 支持人工智能反思机制（Reflection），用于回答质量、长期偏好、用户画像和任务计划改进。

### M3 — Dreaming（夜间整理）

- 每晚定时对当天聊天内容进行整理总结；默认晚上运行，时间可配置。
- 对用户进行多轮画像分析，参考 ChatGPT 记忆 / Dreaming 机制。
- 提取用户任务画像、行为模式、思维风格、偏好和长期目标。

### M4 — 定时任务

- 移动端定时任务支持触发系统日历 / 闹钟 / 通知。
- 支持人工智能驱动的提醒与任务调度。

### M5 — 社交平台接入

- 支持接入主流聊天软件：飞书 / Telegram / WhatsApp / QQ / 微信 / Discord / Slack。
- 参考 OpenClaw（龙虾）的社交平台接入方案。
- 参考 Cherry Studio 的“频道”设计，把外部聊天平台视为外部消息通道。

### M6 — 智能体与编排

- 支持智能体定义与任务编排。
- 具体智能体类型、权限边界、编排方式和界面形态后续逐步梳理明确。

### M7 — 技能市场

- 支持从技能市场搜索、下载、安装技能。
- 打通 OpenClaw 技能市场。
- 支持腾讯等第三方技能市场。

### M8 — 语音与图片

- 支持语音对话：语音输入 / 播报。
- 后台自动保存语音转文字稿件。
- 语音原始文件本地存储。
- 支持图片输入和多模态模型调用。

### M9 — 数据管理与同步

- 本地存储为主，支持数据压缩打包 + 系统分享导出。
- 支持同步到电脑端，优先本地传输。
- 支持云存储，但必须是可选项。
- 支持同步到笔记工具：Notion / 语雀 / Obsidian / 思源笔记。

### M10 — 数字孪生 / 镜像数字人

- 基于用户作息、聊天风格、思维方式进行长期多轮分析。
- 提取用户画像：任务维度 + 个性维度。
- 支持声音 / 图像 / 表情分析与生成。
- 生成可代理用户思维的镜像数字人，支持用户提供信息直接蒸馏。
- 未来支持数字人直播。

### M11 — 界面与个性化

- 全局字体大小调节，布局自适应，保证可读性；移动端默认正文 15sp，全局缩放 90%–120%。
- 主题换色支持。
- 移动端优先的界面设计。

---

## 三、参考项目

- [DeepChat](https://github.com/ThinkInAIXYZ/deepchat)：单独聊天功能、多模型、多标签、MCP、技能、远程控制等能力参考。
- [Cherry Studio](https://github.com/CherryHQ/cherry-studio)：模型渠道、人工智能中转、MCP、助手市场、备份同步、频道化连接器等能力参考。
- [Chatbox](https://github.com/chatboxai/chatbox)：端到端数据同步、提示词库、团队协作、移动端覆盖等能力参考。
- OpenClaw / 龙虾：社交软件接入、外部聊天通道、技能生态参考。
- ChatGPT 记忆 / Dreaming：长期记忆、用户画像、夜间整理和智能体验参考。

---

## 四、当前架构快照

- 应用定位：Flutter 全平台人工智能对话应用，移动端优先。
- 技术栈：Flutter + Riverpod + drift(SQLite) + dio(SSE) + flutter_markdown + flutter_secure_storage + flutter_math_fork + webview_flutter。
- 当前代码目录：
  - `lib/core/database/`：drift + SQLite，表与 DAO。
  - `lib/core/ai/`：多协议适配层、模型能力、模型测试、SSE 流式输出。
  - `lib/core/context/`：无限上下文、摘要压缩、令牌估算。
  - `lib/core/crypto/`：接口密钥加密。
  - `lib/core/mcp/`：MCP 客户端，stdio/SSE 传输。
  - `lib/core/notification/`：本地通知服务。
  - `lib/core/skills/`：技能系统与市场接入。
  - `lib/features/chat/`：对话主页。
  - `lib/features/settings/`：渠道、模型、MCP、提示词、主题等配置。
  - `lib/features/search/`：全局搜索。
  - `lib/features/skills/`：技能市场界面。
  - `lib/features/marketplace/`：MCP 市场界面。
  - `lib/shared/providers/`：Riverpod 状态管理。
  - `lib/shared/widgets/`：公共组件。
  - `lib/l10n/`：中英文 ARB 国际化。

---

## 五、开发阶段规划与当前状态

### Phase 1 — 核心聊天功能（移动端 MVP）

> 目标：跑通单聊 + 多模型切换 + 本地存储。

- [x] 项目初始化：Flutter 工程结构搭建。
- [x] 多模型接入框架：统一人工智能协议抽象层。
- [x] 基础聊天界面：对话主页、消息气泡、Markdown、流式输出、输入区。
- [x] 本地聊天记录存储：SQLite / drift 数据库。
- [x] 单对话内模型切换：紧凑模型选择器、会话级模型切换。
- [x] 基础主题切换与持久化。
- [x] 每个对话 1 个 Markdown 原始文件：基础追加服务已接入聊天主路径。
- [x] 全局字体调节：90%–120% 全局缩放，5% 步进，应用级 `TextScaler` 生效，设置页可调且持久化；Markdown 正文默认 15sp，H1/H2/H3 为 22/20/18sp。
- [x] 移动端自动化主链路冒烟：390×844 移动视口，启动、自动会话、新建会话、设置页、无模型发送保护、抽屉历史搜索。
- [x] 移动端应用身份：Android / iOS 展示名改为 `SimiAIChat`，Android `applicationId` 与 iOS Bundle ID 改为 `top.simitalk.aichat`。
- [x] 对话页扩展 Markdown 渲染：兼容参考样例中的标准 / GitHub / 旧式 Markdown、数学公式、HTML 媒体、折叠块、Mermaid、Draw.io / mxGraph。
- [ ] 移动端真机主链路冒烟：新建会话、发送、停止、重试、模型切换、历史搜索、设置。

### Phase 2 — 记忆与智能化

> 目标：人工智能能“认识”用户，跨对话有记忆。

- [ ] 本地检索增强知识库：本地全文检索 v1、SQLite FTS 搜索索引、Key Points 本地语义向量召回 v1、历史消息本地语义检索 v1、本地消息语义索引 v1、本地语义搜索用户开关 v1 已落地；模型 embedding 和真正向量数据库仍待实现。
- [x] 核心 Key Points 提取与注入 v1：明示记忆点本地提取、持久化、关键词 + 本地语义向量召回并注入系统提示词。
- [x] Dreaming 前台到期整理与系统通知 v1：前台到期自动整理、待确认画像提案和完成通知已落地；真正系统后台调度仍待实现。
- [x] 无限上下文压缩基础策略：滚动压缩、摘要生成、令牌估算、模型窗口预算、请求前裁剪、动态压缩阈值和超限错误兜底。
- [x] 本地反思机制 v1：Dreaming 后基于本地日报、用户画像和待确认画像变更生成回应质量、上下文、长期记忆、用户画像和任务推进的可解释反思报告；设置页可查看 / 手动运行，保存最近 20 次反思历史，并可控制是否把少量高优先级结论 / 行动项作为下一轮本机短期提示；模型驱动反思仍待实现。

### Phase 3 — 生态扩展

> 目标：平台打通，技能扩展。

- [ ] 社交平台接入：飞书 / Telegram / Discord 优先。
- [x] 技能市场基础集成：SkillHub.cn 搜索 / 导入 / SHA-256 校验 / 系统提示词注入。
- [ ] 多源技能市场集成：OpenClaw、腾讯等。
- [ ] 个人接口中转服务：本地 OpenAI 兼容中转核心服务已完成（`/health`、`/v1/health`、`/v1/models`、非流式 / 流式 `/v1/chat/completions`、非流式 buffered `/v1/responses`、渠道模型桥接）；设置页启动 / 停止入口、令牌生成与加密持久化、端口展示、Base URL / curl 示例复制、访问审计、并发保护、局域网开放二次确认、高级路由策略、可配置并发上限、本地脱敏用量统计、持久化脱敏审计明细、JSON 导出、CORS 预检、OpenAI 多模态内容安全兼容降级、图片 data URL 端到端透传、模型视觉能力路由、模型能力可见性与设置页 Vision 标注、远端图片 URL 安全下载透传已完成；真机长时间运行和更多客户端兼容性仍待做。
- [ ] 定时任务 → 系统日历 / 闹钟联动；Dreaming 前台到期系统通知 v1 已完成。
- [x] MCP 协议客户端基础能力：stdio/SSE、Tool / Resource / Prompt。
- [x] MCP 工具调用循环：人工智能 → 工具调用 → 工具结果 → 人工智能最终回复。
- [ ] MCP 运行时 / 旁车：安装、启动、权限、日志、状态统一管理。

### Phase 4 — 数据与同步

- [x] 本地数据导出压缩包 v1：设置页可生成 `.tar.gz`，包含 `manifest.json`、`conversations/`、`audio_transcripts/`、默认 `audio_files/`，不包含 API Key 或本机绝对路径。
- [x] 语音转写状态 / 失败脱敏导出 v1：`audio_transcripts/*.md` 明确包含 `pending` / `ready` / `empty` / `failed` 状态；STT 失败会更新 sidecar 且不泄露本机路径、密钥、令牌或 URL，导出包与 Obsidian 同步直接继承该安全稿件。
- [x] 非语音附件原文件导出 / 导入 v1：导出包新增 `attachments/`，从 SQLite 附件表复制仍可读取的图片 / PDF / 文档等非语音附件原文件，净化归档路径。
- [x] 本地聊天核心数据库备份 / 恢复 v1：导出 `structured_data/local_database.json`，恢复 sessions / messages / attachments 三张核心聊天表，并把附件 localPath 重定向到导入后的 `attachments/` / `audio_files/` 文件；默认不覆盖已有记录，不导出模型 API Key / 渠道密钥 / 本机绝对路径。
- [x] 非密钥配置表备份 / 恢复 v1：同一 `structured_data/local_database.json` 继续覆盖 folders / prompts / skills / mcp_servers / model_channels / channel_models；不导出 `apiKeyEncrypted` 或 MCP headers，疑似含 token 的 MCP args / url 与渠道 baseUrl 会置空，恢复后的模型渠道和 MCP 默认禁用。
- [x] 移动端系统分享导出 v1：导出前展示范围确认和原始语音文件开关，Android / iOS 通过原生系统分享面板分享导出包，不新增 Flutter 依赖。
- [x] 安全导入 / 恢复 v1：可预览 SimiChat `.tar.gz` 导出包，校验 manifest / SHA-256 / 路径安全，默认不覆盖已有文件，设置页提供导入入口。
- [x] 结构化本地数据备份 / 恢复 v1：导出并恢复 `structured_data/shared_preferences.json` 白名单偏好，覆盖 Key Points、Dreaming、用户画像、主题 / 字体 / 上下文阈值 / 本地语义搜索开关、系统提示词；默认不覆盖已有偏好，不包含模型 API Key / 渠道密钥。
- [x] 电脑端本地传输 v1：设置页导出后可启动临时 HTTP 下载服务，提供一次性令牌链接、过期时间、单次下载限制和安全响应头，电脑浏览器可下载导出包。
- [x] Obsidian Markdown Vault 导出 v1：设置页可生成 `exports/obsidian-vault-YYYYMMDD-HHMMSS/`，复制会话 Markdown / 语音转写 Markdown 并生成 README、索引和 Manifest。
- [x] Obsidian 现有 Vault 增量同步 v1：设置页可选择已有 Obsidian Vault，并写入 `SimiChat/` 子目录；通过同步状态文件安全更新未被用户改动的文件，目标手动修改或符号链接目标默认冲突跳过。
- [x] Obsidian 附件链接重写 v1：同步 / 导出时复制可安全读取的附件到 `Attachments/`，并把会话 Markdown 附件列表重写成 Obsidian wiki 链接；audio 原文件是否复制由原始语音开关控制。
- [x] Obsidian 同步冲突详情界面 v1：同步发现冲突时展示相对路径、原因说明和短 SHA，默认仍不覆盖用户在 Obsidian 中的改动。
- [x] Obsidian 可选覆盖冲突策略 v1：同步前展示安全同步 / 覆盖冲突选择；默认安全跳过，用户显式选择后才覆盖普通文件冲突，目录 / 符号链接仍跳过。
- [x] Obsidian 原始音频附件可选同步 v1：复用导出弹窗“包含原始语音文件”开关，开启时把 audio 原文件复制到 `Attachments/` 并重写附件链接，关闭时只保留语音转写稿。
- [x] Obsidian 同名附件链接精确去重 v1：同一消息内同名附件按 Markdown 附件项出现顺序逐条绑定不同 `Attachments/` 路径，避免全部指向第一条。
- [x] Obsidian stale 文件安全清理 v1：源会话 / 转写 / 附件删除后，同步会清理仍等于上次同步版本的旧目标文件；若 Obsidian 侧已修改则记录冲突并保留。
- [x] Obsidian stale 冲突详情解释 v1：设置页冲突弹窗可解释源端已删除但目标已修改 / 目标非普通实体两类 stale 冲突，明确不会覆盖或删除用户文件。
- [ ] Notion / 语雀 / 思源笔记同步；Obsidian 双向同步和更完整冲突处理仍待实现。
- [ ] 云备份：WebDAV / S3 / 云盘，可选开启，端到端加密。

### Phase 5 — 数字孪生

- [x] 用户画像分析系统 v1：从本地 Key Points 与最近 Dreaming 报告生成可解释画像，设置页可查看 / 重建 / 编辑 / 删除画像信号，并支持冲突提示、版本历史、差异对比、恢复历史版本、待确认画像变更、逐项采纳 / 拒绝和全部变更详情审阅。
- [ ] 声音 / 图像 / 表情处理。
- [ ] 镜像数字人生成。
- [ ] 数字人直播能力（长期）。

---

## 六、已完成能力（从 `CLAUDE.md` 迁移并按当前代码整理）

- [x] 项目脚手架与 `pubspec` 依赖。
- [x] 数据库层：9 张表 + 8 个 DAO，覆盖 sessions / messages / channels / models / folders / attachments / prompts / mcp_servers / skills。
- [x] 人工智能协议适配层：OpenAI Chat / OpenAI Responses / Claude / Gemini / Ollama。
- [x] SSE 流式输出与共享 SSE 辅助工具。
- [x] 无限上下文引擎：令牌估算、上下文构建、滚动压缩、模型窗口预算裁剪、上下文超限错误识别与一次严格裁剪重试。
- [x] Riverpod 状态管理：database / session / channel / folder / chat / prompt / mcp 等状态提供器。
- [x] 对话主页：消息气泡、Markdown 渲染、流式输出、输入区。
- [x] 侧边栏：模型选择器、历史会话列表、文件夹分组。
- [x] 设置页：渠道管理、模型增删、主题、压缩阈值、提示词库、MCP 服务器。
- [x] 渠道 / 模型删除引用清理：删除渠道或模型前先清空会话默认模型和消息模型引用，避免已有会话 / 消息导致删除失败或残留。
- [x] 多平台响应式：桌面侧边栏 280px + 移动端抽屉导航，`720px` 断点。
- [x] 中断流式输出。
- [x] 主题切换持久化。
- [x] 压缩阈值滑块交互。
- [x] 思考过程 / 推理内容展示：Claude thinking_delta、OpenAI reasoning、Gemini thought、DeepSeek R1。
- [x] LaTeX 数学公式渲染。
- [x] 令牌实时计数。
- [x] 会话级系统提示词界面与提示词库选择。
- [x] 网络状态提示。
- [x] 附件管线：输入区 → 发送 → 附件 DAO → 人工智能协议多模态；已补附件数量 / 大小 / 类型校验和发送前存在性校验。
- [x] 消息气泡附件展示：发送后的图片 / PDF / 文档以文件卡片展示名称、类型图标和大小。
- [x] Ollama `/api/chat` NDJSON 与 `/api/tags` 模型列表。
- [x] 键盘快捷键：`Ctrl+N` 新建、`Ctrl+Shift+K` 搜索、`Escape` 取消流式。
- [x] 提示词库 / 助手模板。
- [x] 对话分叉。
- [x] Mermaid 图表渲染。
- [x] 中英 i18n 框架。
- [x] MCP 协议客户端：stdio/SSE、Tool / Resource / Prompt。
- [x] 技能市场接入：SkillHub.cn 接口搜索 / 导入 / SHA-256 校验，系统提示词注入。
- [x] Markdown 图片查看与保存。
- [x] 对话页扩展 Markdown 渲染 v1：`LatexMarkdownWidget` 使用 GitHub Web 扩展集并补充旧式图片、行内公式、HTML audio/video 安全卡片、HTML details、旧式 details、Mermaid、Draw.io / mxGraph。
- [x] 移动端应用身份 v1：应用展示名 `SimiAIChat`，Android / iOS 包名 `top.simitalk.aichat`；保留 `simichat.*` 数据格式和 `ai_chat_app` Dart 包名以避免破坏历史数据与 import。
- [x] 全局搜索。
- [x] 紧凑模型选择器。
- [x] 模型连通性测试历史记录：SharedPreferences 本地保存最近结果，设置页模型行展示最近测试状态和时间。
- [x] 一键测试并剔除不可用模型：设置页渠道下可批量测试当前模型；成功模型保留，失败模型自动删除并清理对应测试历史。
- [x] MCP 工具调用循环，最多 3 轮。
- [x] 严重 / 高危历史审计问题已修复：上下文压缩内容错误、MCP SSE 初始化卡住、分页失效、接口密钥弱加密、Gemini 密钥 URL 暴露、MCP 超时与错误处理、SSE 中文跨块解码、工具调用未接入等。

---

## 七、当前待办（按生产化优先级）

### P0 — 基线稳定与生产化门禁

- [x] 生成 Drift 与本地化代码后，`flutter analyze` 通过。
- [x] `flutter test` 全量通过（2026-07-02 复验：289 个测试通过；2026-06-27 旧基线为 286 个）。
- [x] 建立移动端主链路冒烟脚本 / 记录：`scripts/smoke_mobile_main_flow.sh` + `docs/mobile-main-flow-smoke-2026-06-27.md`；2026-07-02 复验 4 个 smoke 测试通过。
- [x] 建立轻量性能基线：分析、测试、代码生成、搜索索引、Dreaming、Dreaming 通知调度、用户画像、本地数据导出、安全导入、结构化备份 / 恢复、电脑端本地传输、Obsidian Vault 导出、Obsidian 增量同步、Obsidian 附件同步 / 链接重写、冲突详情界面、可选覆盖冲突策略、原始音频附件可选同步、同名附件链接精确去重、stale 文件安全清理、stale 冲突详情解释、语音转写状态 / 失败脱敏导出、聊天音频卡片转写状态读取、STT 配置加载 / 引擎创建、音频转写详情读取、TTS 配置加载 / 引擎 / 服务创建、TTS 播放停止控制、TTS 原生播放事件解析、STT/TTS 厂商预设推断、OpenAI Relay 健康检查端点、CORS 预检和 Responses API 非流式端点耗时已记录；真机和长会话基线仍待补。
- [x] 建立轻量安全基线：密钥字面量、日志输出、对话档案提交风险已扫描；本地数据导出压缩包、移动端系统分享、安全导入、结构化备份 / 恢复、电脑端本地传输、Obsidian Vault 导出 / 增量同步 / 附件链接重写 / 冲突详情界面 / 可选覆盖冲突策略 / 原始音频附件可选同步 / 同名附件链接精确去重 / stale 文件安全清理 / stale 冲突详情解释 / 语音转写失败脱敏 / 聊天音频卡片转写状态展示 / OpenAI 兼容 STT 配置密钥 / 音频转写详情查看复制 / OpenAI 兼容 TTS 配置密钥 / 原生播放边界 / 停止播报控制 / 播放完成事件回传、STT/TTS 厂商预设、OpenAI Relay 健康检查端点、CORS 预检、Responses API 非流式端点和本地通知 ID 专项已补，桌面分享 / 云同步 / 社交通道专项仍待补。

### P1 — 移动端核心聊天体验

- [x] 每个对话 1 个 Markdown 原始文件基础追加：新聊天主路径会写入会话 Markdown。
- [x] SQLite 与 Markdown 一致性校验、历史重建服务、标题同步基础能力。
- [x] 暴露手动修复入口、异常修复队列和一键重试修复。
- [x] 全局字体大小调节：90%–120%，5% 步进，持久化保存，应用级 TextScaler 生效，设置页可调；移动端正文默认 15sp、最大 18sp，空状态品牌标题 26sp。
- [x] 移动端语音录音输入与播报链路 v1：录音按钮、原生录音、停止后作为 audio 附件进入本地归档 / STT 草稿链路；OpenAI 兼容 STT 引擎与配置入口已落地；OpenAI 兼容 TTS 语音播报 v1 已落地；STT/TTS 厂商预设 v1 已落地。
  - [x] 基础能力：语音文件附件识别、原始语音文件复制到应用私有目录、消息气泡音频卡片、转写稿件 Markdown 草稿归档。
  - [x] STT 可注入抽象、转写完成后自动更新 `audio_transcripts/*.md` 的服务管线。
  - [x] 语音转写稿件状态与错误脱敏：未转写为 `pending`，有正文为 `ready`，空结果为 `empty`，失败为 `failed`，失败说明不暴露本机路径、密钥、令牌或 URL。
  - [x] 聊天音频卡片转写状态展示 v1：消息气泡中的 audio 附件会读取本地转写 sidecar，并显示“等待转写 / 转写完成 / 未识别到文字 / 转写失败”，STT 更新后自动刷新，不展示本机路径。
  - [x] 移动端麦克风权限声明：iOS `NSMicrophoneUsageDescription`、Android `RECORD_AUDIO` 已写入平台配置。
  - [x] 设置页“语音与多模态 / 语音输入”状态入口：展示权限声明、STT 引擎是否配置，并提示当前可先通过附件发送语音文件。
  - [x] 移动端录音按钮 + 原生运行时权限申请 + 本地录音附件 v1：Android `MediaRecorder` / iOS `AVAudioRecorder` 通过 `simichat/voice_recorder` MethodChannel 录制 `.m4a`，停止后作为 `audio` 附件进入现有归档与 STT 草稿管线。
  - [x] OpenAI 兼容 STT 引擎与配置入口 v1：设置页可配置启用状态、Base URL、模型和 API Key；发送 / 录制语音后自动调用 `/v1/audio/transcriptions`，API Key 加密本地保存且不进入结构化备份、导出包、日志或聊天 Markdown。
  - [x] iOS 系统 Speech 原生识别兜底 v1：当显式 STT / 当前 OpenAI 兼容聊天渠道音频接口失败或不可用时，iOS 通过 `simichat/native_speech_to_text` 调用 `SFSpeechURLRecognitionRequest` 识别应用私有目录内 `.m4a` 录音，并把识别文本写入 sidecar 后作为普通聊天内容发送。
  - [x] base64 语音文本输入 v1：聊天输入支持 `data:audio/...;base64,...` 或“base64 的语音字符：...”粘贴；发送前先解码为临时 `audio` 附件并复用现有 STT 级联，原始 base64 不写入聊天上下文 / Markdown，非法、超大或格式不明的 payload 会在本地拦截。
  - [x] 音频转写稿详情查看 / 复制 v1：音频卡片可打开转写详情弹窗，展示状态和脱敏正文 / 状态说明；`ready` 转写支持一键复制正文，不展示本机 sidecar 路径。
  - [x] OpenAI 兼容 TTS 语音播报 v1：设置页可启用 TTS、配置 Base URL / 模型 / 音色 / 加密 API Key；AI 回复卡片提供播报按钮，生成临时 mp3 后通过 `simichat/audio_player` 调用 Android `MediaPlayer` / iOS `AVAudioPlayer`，原生侧限制只能播放应用私有目录内文件。
  - [x] TTS 播放停止控制 v1：播报生成中显示禁用的“正在生成语音”状态；开始播放后当前 assistant 回复显示“停止播报”，用户可主动停止原生播放并清除当前播报状态。
  - [x] TTS 播放完成事件回传 v1：Android / iOS 原生播放器在完成、停止、错误时回传终止事件，聊天页按当前音频路径自动清理“停止播报”状态，避免播放结束后 UI 仍显示播报中。
  - [x] STT/TTS 厂商预设 v1：设置页语音输入 / 语音播报弹窗提供厂商预设下拉，支持 OpenAI、Groq STT 与自定义 OpenAI 兼容配置，一键填充 Base URL、模型和音色；预设推断兼容 `/v1` 后缀。
  - [ ] 继续补更多非 OpenAI 兼容语音厂商，并完成真机长时间语音播报和来电 / 音频焦点中断场景复验。
- [x] 图片 / 文件附件输入基础稳定化：类型识别、8 个附件数量限制、25 MB 单文件上限、发送前存在性校验、数据库与 Markdown 归档路径保护。
- [x] 消息内本地图片缩略图预览：发送后图片附件展示缩略图、文件名、大小，完整本地路径不进入界面文本。
- [x] 对话级模型切换体验完善：切换记录写入当前会话时间线，切换失败回滚选择，`model_switch` 记录不进入 AI 请求上下文。

### P1 — 模型接入与个人中转

- [x] 扩展主流厂商预设清单第一版：OpenAI、Claude、Gemini、DeepSeek、通义千问 / 阿里云百炼、OpenRouter、Ollama，可在设置页快速填充渠道。
- [x] 设计并落地批量免费模型引导接入流程：设置页支持粘贴 JSON 批量导入渠道 / 模型，API Key 加密落库，Ollama 可空 Key。
- [x] 一键测试并剔除不可用模型：设置页渠道下的批量测试入口已改为“测试并剔除”，逐个测试模型后保留成功模型，失败模型自动从本地渠道模型列表删除，并清理对应测试历史。
- [x] 渠道 / 模型删除引用清理：删除渠道或单个模型前先清空 `sessions.defaultChannelModelId` 与 `messages.channelModelId` 引用，再删除模型 / 渠道，避免已有会话或消息导致删除失败。
- [x] OpenAI 兼容接口的本地转发 / 代理最小实现：本地 `OpenAiCompatibleRelayServer` 支持 Bearer 令牌、loopback 默认绑定、请求大小限制、`/v1/models`、非流式 / 流式 `/v1/chat/completions`，并通过 `ChannelModelRelayBridge` 接入已启用聊天模型。
- [x] OpenAI 兼容本地中转设置页启动入口 v1：设置页可生成 / 输入至少 16 位本地令牌、加密持久化令牌、启动 / 停止 loopback relay、展示 Base URL、复制不含真实令牌的 curl 示例，并验证令牌不进入结构化备份。
- [x] OpenAI 兼容本地中转访问审计与并发保护 v1：服务层记录脱敏请求审计事件（方法、路径、状态码、错误码、模型 id、耗时，不记录 prompt / token / API Key），聊天补全默认最多 4 个并发，超限返回 OpenAI 兼容 429 `concurrency_limit`，设置页展示审计摘要。
- [x] OpenAI 兼容本地中转局域网开放二次确认 v1：默认仍仅绑定 `127.0.0.1`；用户在设置页二次确认风险后才允许绑定 `0.0.0.0`，展示局域网候选地址 / Base URL，取消确认不改变访问范围。
- [x] OpenAI 兼容本地中转高级路由策略 v1：新增 `simichat:default` / `simichat:free` / `simichat:fast` / `simichat:auto` 路由别名，设置页可选择指定模型、默认模型、免费优先、本地 / 快速优先；缺省 model 或别名按策略选路，非流式请求支持候选失败后的安全回退。
- [x] OpenAI 兼容本地中转可配置并发上限 + 本地脱敏用量统计 v1：并发上限可在 1–32 间选择并持久化，启动时传给本地 relay；累计用量只记录请求数、聊天请求数、流式数、成功 / 拒绝 / 未授权 / 限流 / 上游错误、平均耗时和最近状态，不记录 prompt、Bearer token、API Key、上游 Base URL 或本机路径；统计可在设置页一键清空，统计键不进入结构化备份。
- [x] OpenAI 兼容本地中转持久化脱敏审计明细 / 用量导出 v1：最近 100 条审计明细本地持久化，只保存方法、路径、状态码、错误码、授权状态、模型 id、是否流式、耗时和当前并发；设置页展示最近审计、支持复制脱敏审计 JSON 和清空审计，审计键不进入结构化备份。
- [x] OpenAI 兼容本地中转多模态安全兼容降级 v1：支持解析 OpenAI `text` / `input_text` / `image_url` / `input_image` / `input_audio` / `file` 等 content part；文本保留，远端 URL / file URL / 音频 / 文件等非文本片段只生成安全占位和类型计数，不读取或转发远端 URL、本机文件路径、base64 或文件 id；审计 model id 仅保留安全标识形态。
- [x] OpenAI 兼容本地中转图片 data URL 透传 v1：支持 `image_url` / `input_image` 中的 `data:image/...;base64,...` 转为临时内存态 `AiMessage.attachments`，沿现有 OpenAI / Claude / Gemini / Ollama 图片协议链路发送；限制图片 MIME 与解码后最大 1 MB，不写入 SQLite、Markdown、审计、导出或日志。
- [x] OpenAI 兼容本地中转模型视觉能力路由 v1：新增 `vision` 能力标注和 `supportsVision` 路由筛选；图片请求指定纯文本模型返回 OpenAI 兼容 `400 vision_model_required` 且不调用上游，路由别名 / 策略只会把图片请求转发给视觉模型。
- [x] OpenAI 兼容本地中转模型能力可见性 v1：设置页手动添加模型支持选择 `Vision 视觉`，导入 JSON 可保存 `vision` 能力，模型列表使用中文能力标签；`GET /v1/models` 脱敏返回 `capabilities` 与 `supports_vision`，路由别名在存在视觉候选时也标记可视觉路由。
- [x] OpenAI 兼容本地中转远端图片 URL 安全下载透传 v1：默认关闭，设置页二次确认开启；仅允许公网 HTTP(S) 图片，阻断本机 / 内网 / link-local / multicast / unique-local / `localhost`，限制 MIME、1 MB、3 秒超时且不跟随重定向；远端 URL 与图片字节不写入 SQLite、Markdown、审计、导出或日志。
- [x] OpenAI Relay 健康检查端点 v1：新增 Bearer 鉴权的 `GET /health` 与 `GET /v1/health`，只返回状态、当前聊天并发、并发上限和远端图片下载开关，不触发模型列表、不暴露令牌、模型、API Key、上游 Base URL 或本机路径；设置页说明同步展示 `/health`。
- [x] OpenAI Relay CORS / 浏览器客户端兼容 v1：所有响应带 `Access-Control-Allow-Origin: *` 与安全缓存头；支持无令牌 `OPTIONS` 预检，仅对 `/health`、`/v1/health`、`/v1/models`、`/v1/chat/completions`、`/v1/responses` 返回 204 和受限方法 / 头清单，实际请求仍必须 Bearer 鉴权。
- [x] 渠道连通性测试结构化结果：认证失败、权限不足、接口 / 模型不存在、限速 / 额度、服务异常、超时、协议不支持等错误解释与建议。
- [x] 模型连通性测试历史记录：单模型 / 批量测试后本地保存每个模型最近一次结果，设置页展示成功 / 失败 / HTTP 状态 / 时间摘要，且不保存 API Key、请求内容或原始错误详情。
- [x] 失败后的自动重试策略：仅对超时、429、5xx、连接异常等瞬时失败自动重试；401 / 403 / 404 / 协议不支持等永久配置错误不重试。

### P1 — 记忆、Markdown 档案与 Dreaming

- [x] 本地 Markdown 原始档案基础存储方案落地。
- [x] Markdown 标题同步、历史消息重建服务、一致性校验基础能力。
- [x] Markdown 手动修复入口、异常修复队列和一键重试修复。
- [x] 核心 Key Points 数据结构与提取流程：本地启发式提取用户明示偏好 / 画像 / 目标 / 任务，SharedPreferences 持久化，关键词相关性 + 本地语义向量召回并注入系统提示词。
- [x] 本地全文检索 v1：全局搜索已支持多关键词分词、消息 / 标题 / Key Points 统一排名、摘要片段和模型切换时间线过滤；本地消息语义索引 v1 会为全部原始消息持久化轻量语义向量，补足“手机端 / 移动端”等近义表达检索；设置页支持关闭 / 开启本地语义搜索。
- [x] SQLite FTS 搜索索引 v1：`messages_fts` 虚拟表、触发器、自动补建 / 重建和 LIKE 安全回退已接入消息搜索。
- [x] SQLite FTS + 本地消息语义索引维护 v1：健康检查、预热 / 修复、设置页“本地搜索索引”入口和 2000 条消息性能基线脚本已落地。
- [x] Dreaming 本地整理 v1：手动运行今日整理，生成本地日报、会话摘要、关键词和记忆候选，并写入本地记忆。
- [x] Dreaming 前台到期调度 v1：默认 22:00、时间可配置、开关可配置；到点后打开应用自动整理当天一次。
- [x] Dreaming 前台到期系统通知 v1：自动整理有内容后推送本地完成通知，展示整理消息数、记忆候选数和待确认画像变更数；通知 ID 使用 FNV 稳定正整数，避免固定 ID 覆盖和 Dart `hashCode` 漂移。
- [ ] Dreaming 系统后台调度：移动端后台限制、通知唤起、仅充电 / Wi-Fi 条件仍待实现；当前 v1 不保证应用关闭后自动运行。
- [ ] 本地向量检索增强：Key Points 本地语义向量召回 v1 已接入聊天上下文，本地消息语义索引 v1 已接入全局搜索，并已提供用户可控开关；模型 embedding、真正向量数据库 / ANN、增量维护优化和真机长会话基线仍待实现。
- [x] 本地用户画像 v1：基于 Key Points 与最近 Dreaming 报告抽取偏好、目标、任务、基础画像、表达风格、作息线索和关键词。
- [x] 用户画像可控管理 v1：支持本地编辑 / 删除画像信号，重建画像时保留用户控制，并过滤敏感内容。
- [x] 用户画像版本历史与冲突检测 v1：本地持久化最近 20 个画像版本，重建 / 编辑 / 删除 / Dreaming 后自动记录历史，偏好冲突提示可在设置页查看。
- [x] 用户画像历史差异对比与恢复 v1：设置页展示历史版本相对当前画像的新增 / 移除摘要，并支持一键恢复历史画像快照。
- [x] Dreaming 待确认画像变更 v1：手动 Dreaming 与前台到期 Dreaming 生成本地待确认画像变更，用户采纳后才写入正式画像。
- [x] 待确认画像变更逐项采纳 / 拒绝 v1：设置页可对单条新增 / 移除画像信号单独采纳或忽略，剩余提案自动收敛，采纳单项写入画像历史。
- [x] 待确认画像变更详情审阅 v1：提案超过 4 条差异时可打开详情弹窗查看全部差异，并对详情中的任意单项采纳 / 忽略。
- [x] 本地反思机制 v1：`ReflectionService` 基于最近 Dreaming、用户画像和待确认画像变更生成可解释结论与行动项，`assistant_reflection_v1` 本地持久化，`assistant_reflection_history_v1` 保留最近 20 次反思，`assistant_reflection_prompt_enabled_v1` 控制是否注入下一轮短期提示，设置页提供“本地反思 / 自我优化”入口。
- [ ] Dreaming 模型驱动画像增量分析工作流。

### P2 — 生态扩展

- [ ] 社交通道抽象与飞书 / Telegram / Discord 优先接入方案。
- [ ] 多源技能市场接入与权限隔离。
- [ ] MCP 运行时 / 旁车容器层。
- [x] 定时任务与系统通知联动 v1：Dreaming 前台到期整理完成后推送本地通知，通知失败不影响主链路。
- [ ] 定时任务与系统日历 / 闹钟联动。
- [ ] 网页搜索 / 检索增强生成。
- [ ] 图片生成。
- [ ] 深度链接 `ai-chat://`。

### P3 — 数据同步与数字孪生

- [x] 本地数据导出压缩包 v1：`DataExportService` 生成 `simichat-export-YYYYMMDD-HHMMSS.tar.gz`，写入 `manifest.json`、会话 Markdown、语音转写稿和可选原始语音文件，设置页已提供本地生成入口。
- [x] 移动端系统分享导出 v1：`DataExportShareService` 限制只分享 `simichat-export-*.tar.gz`，设置页导出前确认范围，Android 使用 `FileProvider + ACTION_SEND`，iOS 使用 `UIActivityViewController`。
- [x] 安全导入 / 恢复 v1：`DataImportService` 支持预览、manifest 格式校验、SHA-256 校验、路径穿越拦截、导入范围白名单和冲突跳过，设置页提供导入文件选择入口。
- [x] 结构化本地数据备份 / 恢复 v1：`StructuredDataBackupService` 只处理 SharedPreferences 白名单键，`DataExportService` 将结构化快照纳入导出包，`DataImportService` 导入时恢复白名单偏好且默认跳过已有键。
- [x] 非密钥配置表备份 / 恢复 v1：`LocalDatabaseSnapshotService` 导出 / 恢复 folders、prompts、skills、mcp_servers、model_channels、channel_models；模型密钥和 MCP headers 永不入包，恢复后需用户重新填密钥 / headers 并手动启用外部连接。
- [x] 电脑端本地传输 v1：`LocalDataTransferServer` 使用临时 `HttpServer` 暴露单个导出包，设置页提供「电脑端传输」入口，错误令牌 / 路径 / 方法不会泄露文件内容或本机路径。
- [x] Obsidian Markdown Vault 导出 v1：`ObsidianVaultExportService` 生成本地 vault 目录，复制会话 / 转写 Markdown，生成 `SimiChat-Index.md` 和 `SimiChat-Manifest.md`，Manifest 不写本机绝对路径。
- [x] Obsidian 现有 Vault 增量同步 v1：`ObsidianVaultExportService.syncToExistingVault` 写入用户选择的现有 vault 下 `SimiChat/` 子目录，维护 `SimiChat-Sync-State.json`，支持新增 / 更新 / 未变统计和冲突跳过。
- [x] Obsidian 附件链接重写 v1：复制附件到 Obsidian `Attachments/`，会话 Markdown 的附件列表改写为 wiki 链接；audio 由原始语音开关控制，同一消息同名附件按 Markdown 附件项出现顺序逐条绑定不同路径。
- [x] Obsidian 同步冲突详情界面 v1：设置页同步后如有 `target_modified` / `unsafe_existing_entity` / `source_removed_target_modified` / `stale_unsafe_existing_entity` 冲突，弹窗展示相对路径、中文原因、短 SHA 和安全跳过说明。
- [x] Obsidian 可选覆盖冲突策略 v1：设置页同步前弹出策略选择，安全同步为默认；覆盖冲突只在用户明确选择后覆盖普通文件差异，非普通文件仍冲突跳过。
- [x] Obsidian 原始音频附件可选同步 v1：导出弹窗原始语音开关控制 Obsidian audio 原文件是否进入 `Attachments/`，并同步重写会话 Markdown 音频附件链接。
- [x] Obsidian stale 文件安全清理 v1：`syncToExistingVault` 会比较 `SimiChat-Sync-State.json` 与当前源列表，自动删除未被用户改动的旧同步文件；已修改目标以 `source_removed_target_modified` 冲突保留。
- [ ] Notion / 语雀 / 思源笔记同步；Obsidian 双向同步和更完整冲突处理仍待实现。
- [x] 用户画像结构定义 v1：`UserProfile` / `UserProfileBuilder` / `user_profile_v1` 本地持久化；`user_profile_controls_v1` 保存用户编辑 / 删除控制；`user_profile_history_v1` 保存最近画像版本；`UserProfile.conflicts` 保存偏好冲突提示；`UserProfileDiff` / `UserProfileChangeItem` 支持差异对比与逐项处理；`UserProfileChangeProposal` / `user_profile_change_proposals_v1` 支持待确认画像变更。
- [ ] 声音 / 图像 / 表情多模态画像提取。
- [ ] 镜像数字人生成与长期演进。

---

## 八、进度记录

> 说明：本节记录“能代表项目阶段推进”的里程碑；更细的测试输出、性能数据和安全扫描明细沉淀到 `docs/verification-baseline-2026-06-27.md`。

### 8.1 总纲与账本

| 日期 | 事项 | 状态 |
| --- | --- | --- |
| 2026-07-02 | 记录 `SimiAIChat` 应用名、`top.simitalk.aichat` 移动端包名、扩展 Markdown 渲染和移动端字号量化指标，并新增 `docs/markdown-rendering.md` | 已完成 |
| 2026-06-27 | 项目目标梳理，`AGENTS.md` 初始化为项目目标、进度、TODO、DONE、重要安排的主账本 | 已完成 |
| 2026-06-27 | `CLAUDE.md` 项目进度、路线图、已知问题迁移到 `AGENTS.md`，后续以 `AGENTS.md` 为准 | 已完成 |
| 2026-06-27 | 根据用户最新完整需求重整项目总纲、核心模块、阶段规划、文档索引和协作规则 | 已完成 |
| 2026-06-27 | 明确 `docs/` 存放所有实现文档；`docs/conversations/` 只允许说明 / 脱敏示例，真实用户对话 Markdown 必须在应用私有目录并被 Git 忽略 | 已完成 |

### 8.2 核心能力里程碑

| 日期 | 模块 | 里程碑 | 状态 |
| --- | --- | --- | --- |
| 2026-06-27 | 移动端 MVP | 基础聊天、Markdown、流式输出、会话列表、设置页、主题、全局字体、模型切换、移动端自动化 smoke | 已完成 |
| 2026-06-27 | Markdown 档案 | 每会话 Markdown 原始档案、标题同步、SQLite 重建、一致性校验、设置页修复入口、修复队列和一键重试 | 已完成 |
| 2026-06-27 | 多模型接入 | 主流厂商预设、批量 JSON 渠道导入、模型连通性结构化结果、测试历史记录、瞬时失败自动重试、一键测试并剔除不可用模型、渠道 / 模型删除引用清理 | 已完成 |
| 2026-06-27 | 语音 / 多模态 | 语音文件附件、私有音频归档、STT 转写 sidecar、转写状态展示、详情查看 / 复制、移动端录音、OpenAI 兼容 STT、OpenAI 兼容 TTS、播放停止、播放完成事件、STT/TTS 厂商预设 | 已完成 |
| 2026-07-05 | 语音 / 多模态 | base64 语音文本粘贴识别：发送前解码为临时音频附件，复用 STT 级联；原始 base64 不进入聊天上下文 / Markdown，非法 / 超大 payload 本地拦截 | 已完成 |
| 2026-07-06 | base64 语音真机 smoke 入口 | 新增 `integration_test/mobile_base64_audio_smoke_test.dart` 和 `scripts/smoke_device_integration_base64_audio.sh`，测试使用真机 `integration_test`、内存 SQLite、设备内 OpenAI 兼容 SSE mock 和 fake STT，验证 UI 粘贴 `data:audio/wav;base64,...` 后原始 base64 不进数据库用户消息或模型请求，audio 附件归档，`audio_transcripts/` sidecar 为 `ready`，模型请求携带转写文本并返回 assistant；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | OpenAI 兼容 STT 网络真机 smoke 入口 | 新增 `integration_test/mobile_stt_network_smoke_test.dart` 和 `scripts/smoke_device_integration_stt_network.sh`，测试使用真机 `integration_test`、内存 SQLite 和设备内 OpenAI 兼容 mock，同时覆盖 `/v1/audio/transcriptions` multipart 和 `/v1/chat/completions` SSE；未配置独立 STT Provider 时复用当前 `openai_chat` 渠道 API Key 和 Base URL 先转写音频，再把转写文本注入聊天请求；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | 真机录音按钮 smoke 入口 | 新增 `integration_test/mobile_voice_recording_smoke_test.dart` 和 `scripts/smoke_device_integration_voice_recording.sh`，测试使用真机 `integration_test`、内存 SQLite、设备内 OpenAI 兼容 mock 和预授予麦克风权限，验证聊天输入栏麦克风按钮触发 Android 原生 `MediaRecorder` 录制 `.m4a`，停止后作为 audio 附件发送，随后走 STT fallback、ready sidecar、净化后聊天请求和 SSE 回复；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | OpenAI 兼容 TTS 网络真机 smoke 入口 | 新增 `integration_test/mobile_tts_network_smoke_test.dart` 和 `scripts/smoke_device_integration_tts_network.sh`，测试使用真机 `integration_test`、内存 SQLite、mock SharedPreferences、本地 TTS mock 和 fake audio player，验证 assistant 消息播报按钮调用 `/v1/audio/speech`，生成临时 `tts_audio/` 文件，进入停止播报状态并可回退；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | 原生音频播放通道真机 smoke 入口 | 新增 `integration_test/mobile_native_audio_player_smoke_test.dart` 和 `scripts/smoke_device_integration_native_audio_player.sh`，测试使用真机 `integration_test` 和正式 `MethodChannelAudioPlayer`，在应用临时目录生成 WAV 文件，验证 Android `MediaPlayer` 可播放应用私有目录音频，`stop()` 后 stopped 事件回传且无 error 事件；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-06-27 | 记忆 / 搜索 | Key Points 本地记忆、本地语义向量召回、历史消息语义检索、本地消息语义索引、本地语义搜索开关、SQLite FTS 搜索索引 | 已完成 |
| 2026-06-27 | Dreaming / 用户画像 | Dreaming 前台到期整理、系统通知、待确认画像变更、本地用户画像、画像编辑 / 删除 / 历史 / 差异 / 恢复、逐项采纳 / 拒绝 | 已完成 |
| 2026-06-27 | 数据导出 / 导入 | 本地 `.tar.gz` 导出、系统分享、安全导入、结构化偏好备份 / 恢复、聊天核心数据库备份 / 恢复、非密钥配置表备份 / 恢复、电脑端本地传输 | 已完成 |
| 2026-06-27 | Obsidian 同步 | Obsidian Vault 导出、现有 Vault 增量同步、附件链接重写、冲突详情、可选覆盖冲突、原始音频可选同步、同名附件精确去重、stale 文件安全清理和解释 | 已完成 |
| 2026-06-27 | OpenAI Relay | 本地 OpenAI 兼容中转核心服务、设置页启动入口、访问审计、并发保护、局域网二次确认、高级路由、可配置并发、脱敏用量统计、审计明细持久化 / 导出 | 已完成 |
| 2026-06-27 | OpenAI Relay 多模态 | 多模态 content part 安全降级、图片 data URL 透传、Vision 能力路由、模型能力可见性、远端图片 URL 安全下载透传 | 已完成 |
| 2026-06-27 | OpenAI Relay 兼容性 | Bearer 鉴权健康检查 `/health` / `/v1/health`、浏览器 CORS 预检、非流式 buffered `/v1/responses` Responses API 兼容端点 | 已完成 |
| 2026-07-02 | 移动端应用身份 | Android / iOS 展示名 `SimiAIChat`，Android `applicationId` 与 iOS Bundle ID `top.simitalk.aichat`；保留历史数据格式标识 | 已完成 |
| 2026-07-02 | 对话页 Markdown / 字体 | GitHub Web 扩展、旧式图片、行内 / 块级公式、HTML audio/video 安全卡片、HTML details、旧式 details、Mermaid、Draw.io / mxGraph；字体范围 90%–120%，正文 15sp | 已完成 |
| 2026-07-03 | Markdown 渲染 v2 | 修复行内 code 被误渲染为大代码块；用户输入与 AI 输出统一使用 Markdown 渲染；补齐旧式 / Obsidian / HTML 图片、`:::mermaid`、`[mermaid]`、HTML Mermaid、`draw.io` / `mxgraph` / 原始 `mxGraphModel` 等新老格式兼容 | 已完成 |
| 2026-07-02 | 双机真机覆盖安装 | Pixel 8 通过 `adb install -r` 覆盖安装并启动；iPhone13 通过 `devicectl` 安装 release `Runner.app` 并启动；未卸载、未清数据，旧包仍保留 | 已完成 |
| 2026-07-03 | 音频附件 STT 音频接口前置转写 | audio 附件发送时先调用 OpenAI 兼容 `/v1/audio/transcriptions`：优先使用设置页 STT 配置，未配置时复用当前 `openai_chat` / `openai_response` 渠道 Base URL 与 API Key；成功后把转写结果作为普通文本发给聊天模型，不再把 audio base64 交给聊天模型 | 已完成 |
| 2026-07-03 | iOS 系统 Speech 原生识别兜底 | 在 STT 引擎链路增加 fallback：显式 STT 配置、当前 OpenAI 兼容聊天渠道音频接口均失败 / 返回空时，iOS 调用 `SFSpeechURLRecognitionRequest` 识别应用私有目录内录音；新增 `NSSpeechRecognitionUsageDescription` 权限说明、Dart MethodChannel 引擎和 fallback 引擎测试 | 已完成 |
| 2026-07-05 | 无限上下文预算控制 | 聊天发送前按 `protocol + modelName` 推断模型窗口，预留输出 token 后按 `maxInputTokens` 裁剪 system / memory / skills / MCP 工具说明和历史消息；预算模式不再固定最近 20 条，可在窗口内尽量保留更多历史，优先保留最新用户问题；上下文超限流式错误会严格裁剪重试一次，失败时保留可操作提示 | 已完成 |
| 2026-07-06 | 本地反思机制 | Dreaming 后基于本地日报、用户画像和待确认画像变更生成回应质量、上下文、长期记忆、用户画像和任务推进的可解释反思报告；设置页可查看 / 手动运行，结构化备份包含 `assistant_reflection_v1`、`assistant_reflection_history_v1` 与 `assistant_reflection_prompt_enabled_v1`；复核时修正弹窗关闭后运行反思使用父级 `WidgetRef`，并新增可关闭的反思短期提示注入、最近 20 次反思历史、长会话质量基线和短期提示预览，短期提示优先保留可直接改善下一轮回复的任务推进项 | 已完成 |
| 2026-07-06 | 当前基线真机覆盖安装 | 提交 `d67a6f4` 已在 Pixel 8 通过 `adb install -r` 覆盖安装并启动，iPhone13 通过 `devicectl` release 覆盖安装成功且 Runner 进程可见；本轮 Dreaming 修复后 debug 包再次在 Pixel 8 `adb install -r` 覆盖安装成功，`firstInstallTime=2026-07-02 23:29:09` 保持不变，`lastUpdateTime=2026-07-06 02:36:21`，`dataDir=/data/user/0/top.simitalk.aichat`，未卸载、未清数据 | 已完成 |
| 2026-07-06 | Pixel 8 长会话 Dreaming / Reflection 真机验证 | 使用 debug `run-as` 安全种入专用 72 条长会话并保留 DB 备份；真机可显示第 69–72 轮；修复弹窗关闭后运行 Dreaming 使用已销毁 `WidgetRef` 的问题并新增延迟 Dreaming widget 回归；修复包覆盖安装后手动 Dreaming 生成 2026-07-06 日报（1 个会话、72 条消息、36/36 用户 / 助手消息、耗时 101 ms），生成待确认画像变更和 Reflection（5 条结论、4 个行动项、历史 1 次），设置页短期提示预览可见 | 已完成 |
| 2026-07-06 | Pixel 8 真实发送 / 重试 / 停止 / 搜索真机验证 | 使用本机 OpenAI 兼容 mock 服务和 `adb reverse`，通过 debug `run-as` 安全种入专用 mock 渠道、模型和会话；真机默认模型可见，真实发送触发 `/v1/chat/completions` SSE 请求并落库 assistant 回复，Reflection 短期提示进入 system prompt；重试后 mock 请求数从 1 增至 2；慢流停止后上游记录 `broken_pipe=true` 且 assistant 只保留前 2 个 chunk；历史搜索 `smoke` 可过滤到专用会话并排除长会话 | 已完成 |
| 2026-07-06 | Pixel 8 模型切换 / 切换后发送真机验证 | 复用本机 OpenAI 兼容 mock 服务和同一 smoke 会话，安全种入 `simichat-mock-a` / `simichat-mock-b` 两个模型；真机顶部菜单可从 A 切换到 B，`sessions.default_channel_model_id` 更新为 B，时间线新增 `model_switch` system 消息；切换后真实发送触发 `/v1/chat/completions` SSE 请求，mock 日志模型为 `simichat-mock-b`，assistant 回复 `MOCK-B reply 20260706` 以 B 模型落库并在 UI 显示 | 已完成 |
| 2026-07-06 | 真机集成发送 smoke 入口 | 新增 `integration_test/mobile_real_send_smoke_test.dart` 和 `scripts/smoke_device_integration_send.sh`，测试在设备内启动本地 OpenAI 兼容 SSE mock，使用内存 SQLite seed 渠道 / 模型 / 会话，并通过真实 Widget 输入与发送验证 UI → `sendMessage` → SSE → assistant 落库 → UI 展示闭环；脚本会自动临时追加并恢复 `sqlite3.source=system` hook；Pixel 8 已通过；iPhone13 Flutter debug session 曾卡 `CONFIGURATION_BUILD_DIR` 超时，直接 `xcodebuild` Debug 构建和 Debug 覆盖安装均成功，但 `devicectl process launch` 被设备 Locked 状态拒绝，iOS 发送链路需设备物理解锁后复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | 设置页真机 smoke 入口 | 新增 `integration_test/mobile_settings_smoke_test.dart` 和 `scripts/smoke_device_integration_settings.sh`，测试使用真机 `integration_test`、内存 SQLite 和 mock SharedPreferences，验证首页进入设置页、`外观` / `主题模式` / `字体大小` / `数据与档案` 可见，选择 `深色模式` 后持久化 `theme_mode=dark`，字体缩放保存为约 120% 后持久化 `font_scale≈1.2`，并通过平台返回回到首页；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | 复杂 Markdown 真机滚动 smoke 入口 | 新增 `integration_test/mobile_markdown_scroll_smoke_test.dart` 和 `scripts/smoke_device_integration_markdown_scroll.sh`，测试使用真机 `integration_test`、内存 SQLite 和 mock SharedPreferences，种入包含表格、公式、Mermaid、Draw.io / mxGraph、长列表与 `TAIL_SENTINEL_20260706` 的长 assistant Markdown 消息，验证 `LatexMarkdownWidget`、`MermaidWidget`、`DrawioWidget` 实例化并滚动到底部哨兵；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | base64 语音真机发送 smoke 入口 | 新增 `integration_test/mobile_base64_audio_smoke_test.dart` 和 `scripts/smoke_device_integration_base64_audio.sh`，测试使用真机 `integration_test`、内存 SQLite、mock SharedPreferences、设备内 OpenAI 兼容 SSE mock 和 fake STT，验证粘贴 base64 音频后本机解析为 audio 附件、数据库和模型请求均不包含原始 base64、转写 sidecar 为 `ready`、聊天请求携带转写文本并完成 SSE 回复；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | OpenAI 兼容 STT 网络真机 smoke 入口 | 新增 `integration_test/mobile_stt_network_smoke_test.dart` 和 `scripts/smoke_device_integration_stt_network.sh`，测试使用真机 `integration_test`、内存 SQLite、mock SharedPreferences 和设备内 OpenAI 兼容 mock，验证未配置独立 STT 时当前 `openai_chat` 渠道会先发 multipart `/v1/audio/transcriptions`（Bearer 渠道 Key、默认 `whisper-1`、音频文件名可见），sidecar 更新为 `ready`，随后 `/v1/chat/completions` 只收到转写文本且不含原始 base64；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | 真机录音按钮 smoke 入口 | 新增 `integration_test/mobile_voice_recording_smoke_test.dart` 和 `scripts/smoke_device_integration_voice_recording.sh`，测试使用真机 `integration_test`、内存 SQLite、mock SharedPreferences、设备内 OpenAI 兼容 mock 和 Android 预授权麦克风权限，验证聊天页麦克风按钮开始 / 停止真实录音，生成 `simichat-recording-*.m4a` audio 附件并归档，随后 multipart STT、ready sidecar、净化后聊天请求和 SSE 回复闭环；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | OpenAI 兼容 TTS 网络真机 smoke 入口 | 新增 `integration_test/mobile_tts_network_smoke_test.dart` 和 `scripts/smoke_device_integration_tts_network.sh`，测试使用真机 `integration_test`、内存 SQLite、mock SharedPreferences、本地 `/v1/audio/speech` mock 和 fake audio player，验证 TTS 配置加载、assistant 播报按钮、Bearer Key、模型 / 音色 / 输入文本 / `response_format=mp3` JSON 请求、临时音频文件写入、停止播报按钮和 UI 回退；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | 原生音频播放通道真机 smoke 入口 | 新增 `integration_test/mobile_native_audio_player_smoke_test.dart` 和 `scripts/smoke_device_integration_native_audio_player.sh`，测试使用真机 `integration_test` 和正式 `MethodChannelAudioPlayer`，验证应用私有目录内测试 WAV 可交给 Android `MediaPlayer` 播放，调用 `stop()` 后可收到 `AudioPlaybackEventType.stopped`，且没有 `error` 事件；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | 长音频原生播放真机 smoke 入口 | 新增 `integration_test/mobile_long_audio_playback_smoke_test.dart` 和 `scripts/smoke_device_integration_long_audio_playback.sh`，测试使用真机 `integration_test` 和正式 `MethodChannelAudioPlayer`，验证应用私有目录内 6.5 秒 PCM WAV 可交给 Android `MediaPlayer` 自然播放完成，收到 `AudioPlaybackEventType.completed`，真实等待时间大于 4 秒且没有 `error` 事件；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |
| 2026-07-06 | 真机 smoke 脚本临时 hook 恢复加固 | 统一修复 9 个 `scripts/smoke_device_integration_*.sh` 的 `mktemp` 模板，去掉 `XXXXXX` 后的 `.yaml` / `.lock` 后缀，避免中断后 `/tmp/simichat-pubspec.XXXXXX.yaml` 字面量文件导致后续脚本启动失败或临时 sqlite hook 残留 | 已完成 |
| 2026-07-06 | 原生音频播放替换 / 中断真机 smoke 入口 | 新增 `integration_test/mobile_audio_playback_replace_smoke_test.dart` 和 `scripts/smoke_device_integration_audio_playback_replace.sh`，测试使用真机 `integration_test` 和正式 `MethodChannelAudioPlayer`，验证第一段 6.5 秒 WAV 播放中启动第二段 0.9 秒 WAV 时，第一段收到 stopped，第二段收到 completed，且没有 error 事件；Pixel 8 已通过，iPhone13 因设备 Locked 暂未复跑 | 已完成 Pixel 8 / iOS 待补 |

### 8.3 最新验证基线

| 日期 | 验证项 | 结果 |
| --- | --- | --- |
| 2026-07-06 | Dreaming/Reflection 真机回归与全量测试：`flutter --no-version-check analyze`、命令内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test --no-pub --no-test-assets`、`flutter --no-version-check test --no-pub --no-test-assets test/shared/settings_page_dreaming_test.dart -r expanded`、`flutter --no-version-check build apk --debug --no-pub`、`adb -s 37101FDJH0077P install -r ...`、Pixel 8 UI dump / screenshot / SharedPreferences / logcat 检查 | 静态检查无问题；局部 Dreaming 设置页 3 个 widget 测试通过，新增延迟 Dreaming 回归可复现并防止弹窗关闭后使用已销毁 `WidgetRef`；全量 330 个测试通过；正式 `pubspec.yaml` 未保留临时 sqlite3 hook；Pixel 8 修复包覆盖安装成功且不清数据，72 条长会话可见，Dreaming 生成 72 条消息日报，Reflection 生成 5 条结论 / 4 个行动项 / 1 次历史，短期提示预览可见；logcat 未再出现 disposed ref 异常 |
| 2026-07-06 | Pixel 8 真实发送 smoke：本机 mock OpenAI 服务、`adb reverse tcp:18080 tcp:18080`、debug `run-as` DB seed、UI 截图、SQLite 消息查询、mock 服务请求日志、历史搜索 UI dump | 真机默认模型 `Pixel8 local Mock OpenAI / simichat-mock` 可见；真实发送后 DB 有 user + assistant，UI 显示 `Pixel8 mock reply 20260706` 和 `147 tokens · 772ms`；mock 服务收到 `/v1/chat/completions`、`stream=true`、模型 `simichat-mock`，且 system prompt 包含本地 Reflection 短期提示；点击重试后 assistant 回复增至 2 条、请求数增至 2；慢流停止后 partial assistant 保持 27 字符，mock 记录 `broken_pipe=true`；历史搜索 `smoke` 命中 smoke 会话并排除长会话 |
| 2026-07-06 | Pixel 8 模型切换 smoke：本机 mock OpenAI 服务、`adb reverse tcp:18080 tcp:18080`、debug `run-as` DB seed、UI 菜单 / 截图、SQLite 会话与消息查询、mock 服务请求日志 | 顶部模型从 `Pixel8 local Mock OpenAI / simichat-mock-a` 切换为 `simichat-mock-b`；菜单列出 `simichat-mock`、`simichat-mock-a`、`simichat-mock-b`；DB 中 `sessions.default_channel_model_id=device-mock-model-b-20260706`，新增 1 条 `message_type='model_switch'` system 记录；切换后发送 `switch test20260706`，mock 收到 `model=simichat-mock-b`、`stream=true`、`system_has_reflection=true`，UI 显示 `MOCK-B reply 20260706` 和 `29 tokens · 461ms`，assistant 以 B 模型落库 |
| 2026-07-06 | 真机集成发送 smoke：`integration_test/mobile_real_send_smoke_test.dart`、设备内 `dart:io` OpenAI SSE mock、内存 SQLite seed、Pixel 8 真机运行、iPhone13 尝试 | `./scripts/smoke_device_integration_send.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_real_send_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证 `Integration Mock OpenAI / integration-mock-model`、用户输入 `device integration send`、mock 收到 `model=integration-mock-model` / `stream=true`、assistant `DEVICE integration reply 20260706` 落库并在 UI 展示；修正测试等待条件为 DB 落库后继续等待 UI 文本出现，脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用；iPhone13 同一测试在终止旧 / 新 Runner 后仍失败，并给出 `Error starting debug session in Xcode: Timed out waiting for CONFIGURATION_BUILD_DIR to update`；普通 `flutter run --debug --no-resident --no-publish-port` 在相同 sqlite hook 条件下也复现同层错误；继续绕过 Flutter CLI 直接 `xcodebuild -showBuildSettings` 可正常得到 `CONFIGURATION_BUILD_DIR=/Users/sanbo/Library/Developer/Xcode/DerivedData/Runner-edfmvbaktobcznbgqfxmjxwlhuce/Build/Products/Debug-iphoneos`，`xcodebuild build` 成功，同一 Debug `Runner.app` 通过 `devicectl install app` 覆盖安装成功，但 `devicectl process launch` JSON 明确返回 `RequestDenied` / `Locked`，因此 iOS 发送仍待设备物理解锁后复跑 |
| 2026-07-06 | 设置页真机 smoke：`integration_test/mobile_settings_smoke_test.dart`、Pixel 8 真机运行、主题 / 字体 SharedPreferences 持久化 | `./scripts/smoke_device_integration_settings.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_settings_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证首页 `未选择模型` 状态、进入设置页、`外观` / `主题模式` / `字体大小` / `数据与档案` 可见，选择 `深色模式` 后 `theme_mode=dark`，字体缩放保存到约 120% 后 `font_scale≈1.2` 且 UI 显示 `当前: 120%`，平台 back route 可返回首页；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 复杂 Markdown 真机滚动 smoke：`integration_test/mobile_markdown_scroll_smoke_test.dart`、Pixel 8 真机运行、Mermaid / Draw.io 组件与底部哨兵 | `./scripts/smoke_device_integration_markdown_scroll.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_markdown_scroll_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证对话页加载会话 `复杂 Markdown 真机滚动 smoke`、`LatexMarkdownWidget` / `MermaidWidget` / `DrawioWidget` 进入 Widget 树、Mermaid 标题可见，并滚动到 `TAIL_SENTINEL_20260706` 底部哨兵；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | base64 语音真机发送 smoke：`integration_test/mobile_base64_audio_smoke_test.dart`、Pixel 8 真机运行、fake STT、audio sidecar 和净化后模型请求 | `./scripts/smoke_device_integration_base64_audio.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_base64_audio_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证 UI 粘贴 `data:audio/wav;base64,...` 后数据库 user message 只保留 `已接收 base64 语音` 占位且不含原始 base64 / `data:audio`，附件表新增 `fileType=audio` 的 `inline-base64-audio.wav`，fake STT 收到归档路径，`audio_transcripts/` sidecar 状态为 `ready` 且正文为 `Pixel8 voice transcript 20260706`，mock `/v1/chat/completions` 请求最后一条 user content 包含转写结果且不含原始 base64，assistant `DEVICE base64 audio reply 20260706` 落库并展示；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | OpenAI 兼容 STT 网络真机 smoke：`integration_test/mobile_stt_network_smoke_test.dart`、Pixel 8 真机运行、multipart STT 和净化后聊天请求 | `./scripts/smoke_device_integration_stt_network.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_stt_network_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证 UI 粘贴 `data:audio/wav;base64,...` 后未配置独立 STT Provider 时会复用当前 `openai_chat` 渠道先请求 `/v1/audio/transcriptions`，STT mock 收到 `Authorization: Bearer network-api-key`、`multipart/form-data`、默认 `whisper-1` 和 `inline-base64-audio.wav` 文件名；sidecar 状态为 `ready` 且正文为 `Pixel8 network STT transcript 20260706`；随后 mock `/v1/chat/completions` 最后一条 user content 包含转写结果且不含原始 base64 / `data:audio`，assistant `DEVICE STT network reply 20260706` 落库并展示；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 真机录音按钮 smoke：`integration_test/mobile_voice_recording_smoke_test.dart`、Pixel 8 真机运行、Android 原生录音和 STT fallback | `./scripts/smoke_device_integration_voice_recording.sh 37101FDJH0077P` 通过，脚本先 debug 覆盖安装并 `pm grant top.simitalk.aichat android.permission.RECORD_AUDIO`，随后临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_voice_recording_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；验证聊天页麦克风按钮进入停止状态，约 1.6 秒后停止并新增 audio 附件，数据库附件为 `simichat-recording-*.m4a` 且文件大小大于 0、归档文件存在；STT mock 收到 `Authorization: Bearer voice-recorder-api-key`、`multipart/form-data`、默认 `whisper-1` 和录音文件名；sidecar 为 `ready` 且正文为 `Pixel8 real recorder transcript 20260706`；聊天请求包含转写文本且不含 `base64` 或本机归档路径，assistant `DEVICE voice recorder reply 20260706` 落库并展示；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | OpenAI 兼容 TTS 网络真机 smoke：`integration_test/mobile_tts_network_smoke_test.dart`、Pixel 8 真机运行、TTS JSON 请求和停止播报 | `./scripts/smoke_device_integration_tts_network.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_tts_network_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；验证 assistant 消息 `DEVICE TTS assistant message 20260706` 的播报按钮触发 `/v1/audio/speech`，mock 收到 `Authorization: Bearer tts-network-key`、`application/json`、`model=tts-network-mock-model`、`voice=alloy`、原始输入文本和 `response_format=mp3`；返回 bytes 被写入 `tts_audio/` 临时文件且大小大于 0，fake audio player 收到播放路径，UI 显示停止播报，点击停止后回到语音播报按钮；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 原生音频播放通道真机 smoke：`integration_test/mobile_native_audio_player_smoke_test.dart`、Pixel 8 真机运行、Android `MediaPlayer` 和 stopped 事件 | `./scripts/smoke_device_integration_native_audio_player.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_native_audio_player_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；测试在应用临时目录生成 1.8 秒 PCM WAV，调用正式 `MethodChannelAudioPlayer.playFile()` 后再 `stop()`，验证收到 `AudioPlaybackEventType.stopped`，文件仍存在且大于 WAV header，并且没有 `AudioPlaybackEventType.error`；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 长音频原生播放真机 smoke：`integration_test/mobile_long_audio_playback_smoke_test.dart`、Pixel 8 真机运行、Android `MediaPlayer` 和 completed 事件 | `./scripts/smoke_device_integration_long_audio_playback.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_long_audio_playback_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；测试在应用临时目录生成 6.5 秒 24 kHz PCM WAV，调用正式 `MethodChannelAudioPlayer.playFile()` 后等待自然完成，7 秒左右收到 `AudioPlaybackEventType.completed`，真实等待时间大于 4 秒，文件仍存在且大于 WAV header，并且没有 `AudioPlaybackEventType.error`；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 真机 smoke 脚本恢复机制加固：9 个 `scripts/smoke_device_integration_*.sh`、Pixel 8 抽样复验 | 修复 `mktemp /tmp/simichat-pubspec.XXXXXX.yaml` / `mktemp /tmp/simichat-pubspec-lock.XXXXXX.lock` 为无后缀模板，避免中断后字面量 `/tmp` 文件碰撞；`./scripts/smoke_device_integration_native_audio_player.sh 37101FDJH0077P` 通过，脚本结束后 `hooks_present=False`，`git diff --check` 无输出；本轮确认未提交后台恢复 smoke 草稿，因为当前 Flutter integration lifecycle 注入会挂起测试泵 |
| 2026-07-06 | 原生音频播放替换 / 中断真机 smoke：`integration_test/mobile_audio_playback_replace_smoke_test.dart`、Pixel 8 真机运行、Android `MediaPlayer` stopped / completed 事件 | `./scripts/smoke_device_integration_audio_playback_replace.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_audio_playback_replace_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；测试在应用临时目录生成 6.5 秒与 0.9 秒两段 PCM WAV，第一段播放约 350 ms 后启动第二段，验证第一段收到 `AudioPlaybackEventType.stopped`、第二段收到 `AudioPlaybackEventType.completed`、第一段无 completed 且全程没有 `AudioPlaybackEventType.error`；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用，`hooks_present=False` |
| 2026-07-05 | 无限上下文预算控制回归：`flutter test test/core/model_context_budget_test.dart test/core/context_builder_test.dart test/shared/chat_provider_context_limit_test.dart test/shared/chat_provider_audio_test.dart`、`flutter analyze`、`flutter test` | 局部 18 个测试通过；覆盖模型预算推断、未知模型 8K 保守回退、旧 OpenAI 小窗口模型保守预算、长上下文模型动态提高压缩阈值、预算模式超过旧 20 条上限、小预算裁剪但保留最新用户问题、上下文超限错误识别 / 用户提示、语音转写链路未回退；静态检查无问题；全量 318 个测试通过 |
| 2026-07-03 | Markdown v2 与 iOS 系统 Speech 兜底回归：`flutter test test/shared/markdown_rendering_test.dart`、`flutter analyze`、`flutter test`、`git diff --check`、`flutter build ios --release` | Markdown 局部 4 个测试通过，全量 305 个测试通过；行内 code 保持行内，fenced code 仍为代码块；用户输入 / AI 输出统一 Markdown 渲染；旧式 / HTML 图片、Mermaid / Draw.io 新老格式均有回归；fallback 引擎可在在线 STT 失败或空结果后继续尝试 iOS 原生 Speech；iOS release 构建成功；people iPhone 当前 `unavailable`，覆盖安装被设备离线状态阻塞 |
| 2026-06-27 | OpenAI Relay Responses API 局部测试与 benchmark：`flutter test test/core/openai_compatible_relay_server_test.dart test/benchmark/openai_relay_benchmark.dart` | 23 个测试通过；覆盖 `/v1/responses` buffered 输出、多模态 input 解析、`stream=true` 安全拒绝、CORS 预检；局部 benchmark 中 `/v1/responses` 100 次平均约 3.14 ms |
| 2026-06-27 | OpenAI Relay benchmark 脚本：`scripts/benchmark_openai_relay.sh` | 通过；`/v1/responses` 100 次平均约 1.59 ms，健康检查约 1.91 ms，CORS 预检约 1.24 ms，聊天补全约 1.41 ms |
| 2026-06-27 | 模型管理局部回归：`flutter test test/core/channel_dao_test.dart test/shared/settings_page_channel_import_test.dart` | 5 个测试全部通过；覆盖渠道 / 模型删除引用清理、一键测试并剔除不可用模型 |
| 2026-06-27 | 静态检查：`flutter analyze` | 无问题 |
| 2026-06-27 | 全量测试：`flutter test` | 286 个测试全部通过 |
| 2026-06-27 | 移动端 smoke：`scripts/smoke_mobile_main_flow.sh` | 4 个 smoke 全部通过，脚本内置 `flutter analyze` 无问题 |
| 2026-06-27 | Android release 真机安装：`flutter build apk --release` + `adb -s 37101FDJH0077P install -r build/app/outputs/flutter-apk/app-release.apk` + `adb shell monkey` | Pixel 8 覆盖安装成功并启动；包名 `com.aichat.ai_chat_app`，版本 `1.0.0` |
| 2026-06-27 | iOS release 真机安装：`flutter run -d 00008110-0016349A3A20A01E --release --no-resident` + `xcrun devicectl device process launch` | iPhone13 release 安装并启动成功；Bundle ID `com.aichat.aiChatApp`；未使用 debug 模式 |
| 2026-06-27 | Android 构建：`flutter build apk --debug` | 通过，生成 debug APK |
| 2026-06-27 | iOS 构建：`flutter build ios --simulator --no-codesign` | 通过，生成 simulator Runner.app |
| 2026-06-27 | 安全 / 格式复核 | `git diff --check` 无输出；生产代码目标无 `print/debugPrint`、无本机绝对路径 / 本机文件 URL；生产与文档高置信密钥字面量扫描未发现真实密钥 |
| 2026-07-02 | 应用身份 / Markdown / 字体局部测试：`flutter test test/core/app_identity_test.dart test/shared/settings_provider_test.dart test/shared/markdown_rendering_test.dart test/core/data_export_share_platform_test.dart test/core/microphone_permission_manifest_test.dart` | 13 个测试全部通过，覆盖 Android / iOS 应用身份、字体范围、扩展 Markdown、平台通道路径 |
| 2026-07-02 | 静态检查：`flutter analyze` | 无问题 |
| 2026-07-02 | 全量测试：`flutter test` | 289 个测试全部通过；同步修复 `test/shared/dreaming_provider_test.dart` 的日期敏感断言，显式固定消息时间为 2026-06-27 |
| 2026-07-02 | 移动端 smoke：`scripts/smoke_mobile_main_flow.sh` | 4 个 smoke 全部通过，脚本内置 `flutter analyze` 无问题 |
| 2026-07-02 | Android 构建：`flutter build apk --debug` | 通过，生成 `build/app/outputs/flutter-apk/app-debug.apk`；源码配置 `namespace` / `applicationId` 为 `top.simitalk.aichat`，应用 label 为 `SimiAIChat` |
| 2026-07-02 | iOS 构建：`flutter build ios --simulator --no-codesign` | 通过，生成 `build/ios/iphonesimulator/Runner.app`；构建产物 `Info.plist` 确认为 `CFBundleDisplayName=SimiAIChat`、`CFBundleIdentifier=top.simitalk.aichat`、`CFBundleName=SimiAIChat` |
| 2026-07-02 | Android 真机覆盖安装与启动：`adb -s 37101FDJH0077P install -r build/app/outputs/flutter-apk/app-debug.apk` + `adb shell monkey` | Pixel 8 成功安装并启动；`package=top.simitalk.aichat`，`versionName=1.0.0`，`firstInstallTime=2026-07-02 23:29:09`，`lastUpdateTime=2026-07-02 23:38:17`，`dataDir=/data/user/0/top.simitalk.aichat`，启动后 pid `6420`；未执行卸载或清数据，旧包 `com.aichat.ai_chat_app` 仍存在 |
| 2026-07-02 | iOS release 真机覆盖安装与启动：`xcrun devicectl device install app --device 00008110-0016349A3A20A01E build/ios/Release-iphoneos/Runner.app` + `xcrun devicectl device process launch` | iPhone13 成功安装并启动；`Name=SimiAIChat`，`Bundle Identifier=top.simitalk.aichat`，`Version=1.0.0`，启动后进程 pid `77277`；未执行卸载或清数据，旧 Bundle `com.aichat.aiChatApp` 仍存在；iOS debug 启动限制已通过 release 安装规避 |
| 2026-07-02 | iOS 双机真机覆盖安装与启动：`xcrun devicectl device install app` + `xcrun devicectl device process launch` | `people`（iPhone 14 Pro Max）与 `biao的iPhone`（iPhone16,2）均已安装并启动 `SimiAIChat`；Bundle ID `top.simitalk.aichat`，版本 `1.0.0`；`people` 进程 pid `53843` / `54736`，`biao的iPhone` 进程 pid `1152`；`biao的iPhone` 先通过 `xcrun devicectl manage pair` 配对；未执行卸载或清数据 |
| 2026-07-03 | 静态检查：`flutter analyze` | 无问题 |
| 2026-07-02 | 安全 / 格式复核 | `git diff --check` 无输出；移动端源码旧包名 / 旧显示名扫描无命中 |
| 2026-07-05 | codebase-memory | 本轮无限上下文预算控制后已刷新，项目 `Users-sanbo-code-simichat` 节点 2772、边 7067 |

### 8.4 当前明确未完成项

| 优先级 | 待办 | 说明 |
| --- | --- | --- |
| P0 | 移动端真机主链路冒烟 | 已完成 Pixel 8 覆盖安装与启动、专用 72 条长会话显示、手动 Dreaming / Reflection 弹窗和短期提示预览、mock OpenAI 真实发送 / SSE 回复 / 重试 / 停止慢流 / 历史搜索 / 模型切换与切换后发送验证，并新增可重复真机集成发送、设置页、复杂 Markdown 滚动、base64 语音发送、OpenAI 兼容 STT 网络、真实录音按钮、OpenAI 兼容 TTS 网络、原生音频播放通道、长音频播放完成和播放替换 / 中断 smoke 脚本且 Pixel 8 通过；iPhone13 release 覆盖安装与进程可见性已完成；同一集成发送测试和普通 debug 启动曾卡在 Xcode debug session `CONFIGURATION_BUILD_DIR` 超时，直接 `xcodebuild` Debug 构建和覆盖安装已成功，但当前设备 Locked 导致 launch 被拒绝；仍需在物理解锁后补 iOS 发送链路、真实云端 STT / TTS 长音频、来电 / 音频焦点中断、网络切换、后台恢复等交互验证 |
| P1 | Dreaming 系统后台调度 | 当前为前台到期整理 + 通知；需补系统后台限制下的稳定方案 |
| P1 | 无限上下文与反思增强 | 已有模型窗口预算裁剪、动态压缩阈值、基础压缩、本地记忆、本地反思 v1、反思历史 v1、可关闭的反思短期提示注入和 Pixel 8 72 条 seed 长会话 Dreaming/Reflection 基线；仍需真实模型长会话压缩质量评估、模型驱动反思、模型驱动画像增量分析 |
| P1 | OpenAI Relay 真机 / 长时间运行 | 当前本地测试、构建和 benchmark 已过；仍需真实移动端网络、局域网、客户端兼容性验证 |
| P2 | 社交平台接入 | 飞书 / Telegram / Discord 优先；微信 / QQ / WhatsApp / Slack 后续梳理授权边界 |
| P2 | 多源 Skills 市场 | SkillHub 基础已落地；OpenClaw、腾讯等市场仍待接入 |
| P3 | Notion / 语雀 / 思源 / 云备份 | Obsidian 链路较完整；其他笔记工具、云备份和双向同步仍待实现 |
| P3 | 数字孪生 | 用户画像 v1 已完成；声音 / 图像 / 表情处理、镜像数字人生成、直播能力仍是长期方向 |


## 九、重要决策与约定

1. **存储原则**：所有聊天数据本地优先，云同步为可选项，绝不强制上传。
2. **对话原始文件**：每个对话对应一个 `.md` 原始文件；仓库侧约定目录为 `docs/conversations/`，只允许存放说明或脱敏示例；真实运行时用户数据存放在应用私有数据目录，必须被 Git 忽略，不得直接提交到仓库。实现方案见 `docs/memory-system.md`。
3. **实现文档**：所有功能的详细实现文档存放于 `docs/` 文件夹；对话页 Markdown 与字号方案见 `docs/markdown-rendering.md`。
4. **移动端优先**：功能在移动端稳定后再考虑桌面端适配。
5. **智能体记录**：本文件负责维护项目目标、进度、待办、已完成事项及重要安排。
6. **生产化标准**：每个功能进入完成状态前，必须有功能验证、性能影响评估、安全影响评估。
7. **参考项目使用方式**：DeepChat / Cherry Studio 只作为能力和体验参考，不直接复制许可不兼容代码。

---

## 十、文档索引（docs/）

| 文档 | 说明 |
| --- | --- |
| `docs/architecture.md` | 整体架构设计、模块边界、数据流、生产化门禁 |
| `docs/model-integration.md` | 多模型接入、渠道、模型能力、接口中转方案 |
| `docs/memory-system.md` | 记忆、Markdown 原始档案、本地检索增强生成、Key Points |
| `docs/dreaming.md` | Dreaming 夜间整理机制、画像提取、定时调度 |
| `docs/reflection.md` | 本地反思机制、报告结构、触发流程、安全边界和测试记录 |
| `docs/social-channels.md` | 社交平台接入方案、频道抽象、权限边界 |
| `docs/skills-market.md` | 技能市场集成、多源市场、权限、安全、安装更新 |
| `docs/data-sync.md` | 本地数据导出压缩包、附件原文件导出 / 导入、移动端系统分享、云备份、电脑端传输、笔记工具同步 |
| `docs/digital-twin.md` | 数字孪生 / 镜像数字人、画像、蒸馏、多模态输入 |
| `docs/ui-design.md` | 移动端优先界面规范、主题、字体、可访问性 |
| `docs/markdown-rendering.md` | 对话页扩展 Markdown 渲染能力、移动端字号指标和安全边界 |
| `docs/media-attachments.md` | 语音、图片、文件附件、归档和多模态输入策略 |
| `docs/mobile-main-flow-smoke-2026-06-27.md` | 移动端主链路冒烟脚本、自动化结果、真机待测清单 |
| `docs/mobile-device-install-smoke-2026-07-06.md` | 当前提交 Android / iOS 真机覆盖安装、启动 / 进程可见性证据和后续真机长会话待测清单 |
| `docs/mobile-long-conversation-reflection-smoke-2026-07-06.md` | Pixel 8 72 条长会话、Dreaming、Reflection、短期提示预览真机验证和 disposed ref 回归记录 |
| `docs/mobile-real-send-smoke-2026-07-06.md` | Pixel 8 本地 mock OpenAI 真实发送、SSE、重试、停止慢流和历史搜索真机验证记录 |
| `docs/mobile-model-switch-smoke-2026-07-06.md` | Pixel 8 顶部模型菜单切换、`model_switch` 落库和切换后真实发送真机验证记录 |
| `docs/mobile-device-integration-send-smoke-2026-07-06.md` | 真机集成发送 smoke 入口 / 脚本、Pixel 8 通过证据、iPhone13 Xcode debug session 卡点、直接 xcodebuild 成功和设备 Locked launch 边界记录 |
| `docs/mobile-settings-smoke-2026-07-06.md` | 设置页真机 smoke 入口 / 脚本、Pixel 8 主题模式与字体缩放持久化验证记录 |
| `docs/mobile-markdown-scroll-smoke-2026-07-06.md` | 复杂 Markdown 真机滚动 smoke 入口 / 脚本、Pixel 8 Mermaid / Draw.io 组件和底部哨兵滚动验证记录 |
| `docs/mobile-base64-audio-smoke-2026-07-06.md` | base64 语音真机发送 smoke 入口 / 脚本、Pixel 8 fake STT、audio sidecar 和净化后模型请求验证记录 |
| `docs/mobile-stt-network-smoke-2026-07-06.md` | OpenAI 兼容 STT 网络真机 smoke 入口 / 脚本、Pixel 8 multipart STT fallback、audio sidecar 和净化后聊天请求验证记录 |
| `docs/mobile-voice-recording-smoke-2026-07-06.md` | 真机录音按钮 smoke 入口 / 脚本、Pixel 8 Android 原生录音、STT fallback、audio sidecar 和净化后聊天请求验证记录 |
| `docs/mobile-tts-network-smoke-2026-07-06.md` | OpenAI 兼容 TTS 网络真机 smoke 入口 / 脚本、Pixel 8 TTS JSON 请求、临时音频写入和停止播报验证记录 |
| `docs/mobile-native-audio-player-smoke-2026-07-06.md` | 原生音频播放通道真机 smoke 入口 / 脚本、Pixel 8 Android MediaPlayer、应用私有目录音频和 stopped 事件验证记录 |
| `docs/mobile-long-audio-playback-smoke-2026-07-06.md` | 长音频原生播放真机 smoke 入口 / 脚本、Pixel 8 6.5 秒 WAV、Android MediaPlayer 和 completed 事件验证记录 |
| `docs/mobile-smoke-script-hardening-2026-07-06.md` | 真机 smoke 脚本临时 sqlite hook 恢复机制、`mktemp` 模板修复和 Pixel 8 抽样复验记录 |
| `docs/mobile-audio-playback-replace-smoke-2026-07-06.md` | 原生音频播放替换 / 中断真机 smoke 入口 / 脚本、Pixel 8 两段 WAV 替换播放和 stopped / completed 事件验证记录 |
| `docs/requirements.md` | 产品需求总纲、核心模块、阶段规划、页面需求、隐私安全原则 |
| `docs/database.md` | SQLite / drift 表结构、DAO 职责 |
| `docs/ai-protocols.md` | OpenAI / Claude / Gemini / Ollama 等协议适配 |
| `docs/infinite-context.md` | 滚动压缩、摘要生成、令牌估算 |
| `docs/ui.md` | 历史界面设计文档 |
| `docs/MCP_RUNTIME_CONTAINERIZATION.md` | MCP 运行时 / 旁车容器化方案 |
| `docs/verification-baseline-2026-06-27.md` | 当前功能测试、性能验证、安全验证基线 |

---

## 十一、仍需跟踪的历史审计问题

### 中等优先级

| 序号 | 问题 | 位置 |
| --- | --- | --- |
| MED-1 | `DropdownButtonFormField` 使用 `initialValue` 而非 `value`，设置页下拉选择后界面可能不更新 | `settings_page.dart:402,510,1138` |
| MED-2 | `flutter_secure_storage` 已声明但使用情况需复核 | `pubspec.yaml:28` |
| MED-3 | `builtInSkills` 定义了但是否插入数据库需复核 | `skill.dart:78-147` |
| MED-4 | 12+ DAO 方法从未调用，需清理死代码或补测试 | 各 DAO 文件 |
| MED-5 | i18n 框架已配置但界面字符串本地化覆盖不足，仍有大量硬编码中文 | 全部界面文件 |
| MED-7 | 全局 Dio 缓存 `_dioCache` 缺少清理策略 | `http_helper.dart:4` |
| MED-8 | 全局 `_streamSubscriptions` 可能泄漏 | `chat_provider.dart:23` |
| MED-9 | 多处 `TextEditingController` 需要复核释放逻辑 | `sidebar.dart`、`chat_page.dart` |
| MED-10 | Mermaid 依赖硬编码 CDN，离线不可用 | `mermaid_widget.dart` |
| MED-12 | `openSseStream` 无显式取消机制，用户停止生成后网络连接可能未回收 | `sse_helper.dart` |

### 已关闭问题

| 序号 | 结论 | 关闭依据 |
| --- | --- | --- |
| MED-6 | 已修复：通知 ID 不再固定为 0，回复通知和 Dreaming 通知统一使用 `buildStableNotificationId(namespace, key)` 生成跨运行稳定正整数 ID | 2026-06-27 Dreaming 前台到期系统通知调度 v1，`test/core/notification_service_test.dart` 覆盖同输入稳定、不同 namespace / key 不同、ID 范围合法 |
| MED-11 | 已修复：删除渠道 / 模型前会先清空 `sessions.defaultChannelModelId` 与 `messages.channelModelId` 引用，再删除模型和渠道，避免已有会话或消息导致删除失败 | 2026-06-27 渠道 / 模型删除引用清理，`test/core/channel_dao_test.dart` 与 `test/shared/settings_page_channel_import_test.dart` 覆盖 |

### 低优先级

| 序号 | 问题 | 位置 |
| --- | --- | --- |
| LOW-1 | 4 个 SSE 协议实现存在空 `finally {}` 块 | 各协议文件 |
| LOW-2 | Claude 模型列表硬编码，不会自动更新 | `claude_protocol.dart` |
| LOW-3 | `userId` 列从未使用 | `tables.dart` |
| LOW-4 | Skill ID 使用 name 做主键，有碰撞风险 | `skill.dart` |
| LOW-5 | `intl` 版本钉死，无 `^` | `pubspec.yaml` |
| LOW-6 | 30+ 处硬编码 `Colors.grey/green`，未使用主题色 | 各组件文件 |
| LOW-7 | `firstWhere` + 空 catch 吞掉所有异常 | 多处 |
| LOW-8 | `_draftCache` 静态 Map 无限增长，不做回收 | `chat_page.dart:33` |
| LOW-9 | Dio 错误封装丢失状态码信息，例如 401 / 429 | `sse_helper.dart` |
| LOW-10 | 模型菜单构建逻辑重复 | `chat_page.dart` + `model_selector.dart` |

---

## 十二、仓库协作规范

### 项目结构与模块组织

这是一个 Flutter 全平台人工智能聊天应用；移动端展示名为 `SimiAIChat`，Android / iOS 包名为 `top.simitalk.aichat`。Dart 包名暂保留 `ai_chat_app`，主要 Dart 代码位于 `lib/`；测试位于 `test/`；实现文档位于 `docs/`。

### 构建、测试与开发命令

- `flutter pub get`：安装 Flutter / Dart 依赖。
- `dart run build_runner build --delete-conflicting-outputs`：表结构或 DAO 变更后重新生成 Drift 数据库代码。
- `flutter gen-l10n`：`lib/l10n/*.arb` 文案变更后重新生成本地化输出。
- `flutter run -d macos`：在 macOS 设备上本地运行；也可替换为其他设备编号。
- `flutter analyze`：运行 analyzer 和 lint 检查。
- `flutter test`：运行全部单元测试和组件测试。

### 代码风格与命名规范

使用 Dart 默认风格，并遵守 `package:flutter_lints/flutter.yaml`。变更 Dart 文件后使用 `dart format` 格式化。优先使用 2 空格缩进；文件名使用 `lower_snake_case.dart`；类和组件使用 `UpperCamelCase`；方法、字段、状态提供器、变量使用 `lowerCamelCase`。

### 提交与合并请求规范

提交标题应简短、具体、强调意图。合并请求应包含摘要、测试结果、关联问题；界面变更应附截图或录屏。涉及结构定义、本地化、平台配置或依赖变更时必须明确说明。
