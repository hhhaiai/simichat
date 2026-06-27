# SimiChat 产品需求总纲

> **定位**：人工智能聊天工具，最终形态 = 好友陪伴（虚拟朋友 / 智能助理）+ 数字孪生（镜像数字人，基于对话录入、长期记忆与用户资料蒸馏生成）。
>
> **技术栈**：Flutter，移动端优先；核心能力在移动端稳定后，再扩展桌面 / 电脑端。
>
> **权威来源**：项目目标、进度、待办、已完成事项和重要安排以根目录 `AGENTS.md` 为准；本文档沉淀产品需求与功能边界。
>
> **最后更新**：2026-06-27。

参考项目：

- [DeepChat](https://github.com/ThinkInAIXYZ/deepchat)：单独聊天、多模型、MCP、技能、远程控制等体验参考。
- [Cherry Studio](https://github.com/CherryHQ/cherry-studio)：模型渠道、模型中转、MCP、助手市场、备份同步、频道化连接器等能力参考。
- OpenClaw / 龙虾：社交平台接入、外部聊天通道、技能生态参考。
- ChatGPT Memory / Dreaming：长期记忆、画像归纳、夜间整理和智能陪伴体验参考。

---

## 一、项目目标（Vision）

打造一款以移动端为核心的人工智能聊天工具，核心价值：

1. **无限接入**：支持市面所有人工智能模型厂商，仅需输入接口密钥即可使用；支持批量免费模型引导接入（日常“白嫖”模式）；单对话内支持随时切换模型。
2. **智能陪伴**：虚拟好友 / 智能助理，结合长期记忆系统，做到“了解你”的人工智能伴侣。
3. **数字孪生**：通过长期对话分析用户画像（作息 / 风格 / 思维），生成可代理用户思维的镜像数字人；支持声音、图像、表情等多模态信息，未来可扩展到直播。
4. **本地优先**：聊天记录本地存储，隐私安全，支持导出 / 同步到主流笔记工具。
5. **生态打通**：接入主流社交平台、技能市场、个人接口中转服务。

---

## 二、核心功能模块

### M1 — 多模型接入

- 支持所有主流人工智能厂商：OpenAI / Claude / Gemini / DeepSeek / 讯飞 / 通义 / 百度等，输入接口密钥即用。
- 支持同时接入 N 个模型 / 厂商 / 渠道。
- 支持批量免费模型引导接入，参考 GitHub 免费大模型列表生态。
- 单个对话内支持随时切换模型。
- 支持将多个模型聚合成个人接口中转服务器，参考 Cherry Studio，对外暴露统一接口转发。

### M2 — 记忆与上下文系统

- 聊天记录全部本地存储，默认不上云。
- 每个对话对应 1 个 Markdown 原始文件。
- 核心记忆点提取后常驻本地索引 / 内存（Key Points），每次对话带入检索结果。
- 跨对话内容支持快速检索，形成“本地聊天 ≈ 本地知识库”的体验。
- 无限上下文设计：超过模型令牌限制时自动提取重要内容并压缩。
- 支持人工智能反思机制（Reflection），用于回答质量、长期偏好、用户画像和任务计划改进。

### M3 — Dreaming（夜间整理）

- 每晚定时对当天聊天内容进行整理总结；默认晚上运行，时间可配置。
- 对用户进行多轮画像分析，参考 ChatGPT 记忆 / Dreaming 机制。
- 提取用户任务画像、行为模式、思维风格、偏好和长期目标。
- 整理结果默认保存在本地，用户可查看、审阅、删除。

### M4 — 定时任务

- 移动端定时任务支持触发系统日历 / 闹钟 / 通知。
- 支持人工智能驱动的提醒与任务调度。
- 后台调度必须遵守 iOS / Android 系统限制，必要时通过通知引导用户打开应用完成整理或确认。

### M5 — 社交平台接入

- 支持接入主流聊天软件：飞书 / Telegram / WhatsApp / QQ / 微信 / Discord / Slack。
- 参考 OpenClaw（龙虾）的社交平台接入方案。
- 参考 Cherry Studio 的“频道”设计，把外部聊天平台视为外部消息通道。
- 社交通道必须有清晰授权、消息边界、身份标识和风控策略。

### M6 — 智能体与编排

- 支持智能体定义与任务编排。
- 支持后续逐步梳理智能体类型、权限边界、工具调用、任务计划、执行审计和人工确认策略。
- 高风险操作必须二次确认，不能默认自动代表用户对外执行。

### M7 — 技能市场

- 支持从技能市场搜索、下载、安装技能。
- 打通 OpenClaw 技能市场。
- 支持腾讯等第三方技能市场。
- 技能安装、更新和执行必须具备权限说明、来源校验、可禁用和可删除能力。

### M8 — 语音与图片

- 支持语音对话：语音文件附件、移动端录音输入、OpenAI 兼容 STT 自动转写配置入口、OpenAI 兼容 TTS 语音播报和 Android / iOS 原生播放通道已落地。
- 后台自动保存语音转文字稿件。
- 语音原始文件本地存储。
- 支持图片输入和多模态模型调用。
- 语音、图片、附件默认不上传；只有用户明确调用模型、启用 STT / TTS 或同步能力时才可外发。

### M9 — 数据管理与同步

- 本地存储为主，支持数据压缩打包 + 系统分享导出；当前已完成本地 `.tar.gz` 压缩包、Android / iOS 系统分享 v1、文件级安全导入 / 恢复 v1、结构化本地数据备份 / 恢复 v1 和电脑端本地传输 v1。
- 支持同步到电脑端，优先本地传输。
- 支持云存储，但必须是可选项。
- 支持同步到笔记工具：Notion / 语雀 / Obsidian / 思源笔记。
- 同步前必须明确范围、目标、加密策略和失败恢复方式。

### M10 — 数字孪生 / 镜像数字人

- 基于用户作息、聊天风格、思维方式进行长期多轮分析。
- 提取用户画像：任务维度 + 个性维度。
- 支持声音 / 图像 / 表情分析与生成。
- 生成可代理用户思维的镜像数字人，支持用户提供信息直接蒸馏。
- 未来支持数字人直播。
- 任何“代理用户”的能力必须明确标注、授权、可审计、可撤销。

### M11 — 界面与个性化

- 全局字体大小调节，布局必须自适应并保持可读性，不能变成一个屏幕只显示一两个字。
- 支持主题换色。
- 移动端优先的界面设计，先确保小屏主链路稳定，再扩展桌面布局。

---

## 三、开发阶段规划

### Phase 1 — 核心聊天功能（移动端 MVP）

目标：跑通单聊 + 多模型切换 + 本地存储。

- [x] 项目初始化：Flutter 工程结构搭建。
- [x] 多模型接入框架：统一人工智能协议抽象层。
- [x] 基础聊天界面：对话主页、消息气泡、Markdown、流式输出、输入区。
- [x] 本地聊天记录存储：SQLite / drift 数据库。
- [x] 单对话内模型切换。
- [x] 基础主题与字体调节。
- [x] 每个对话 1 个 Markdown 原始文件基础能力。
- [ ] 移动端真机主链路冒烟。

### Phase 2 — 记忆与智能化

目标：人工智能能“认识”用户，跨对话有记忆。

- [x] 核心 Key Points 提取与注入 v1。
- [x] Key Points 本地语义向量召回 v1：基于本地语义别名、中文 n-gram 和 cosine similarity 提升长期记忆召回，不外发数据。
- [x] 本地全文检索 v1。
- [x] 历史消息本地语义检索 v1：全局搜索扫描最近 500 条原始消息，用本地语义向量和 cosine similarity 支持“手机端 / 移动端”等近义检索，不外发数据、不持久化 embedding。
- [x] 本地消息语义索引 v1：`message_semantic_index` 本地持久化全部原始消息的轻量语义向量 JSON 和内容哈希，设置页可检查 / 预热 / 修复，语义搜索不再局限最近 500 条。
- [x] 本地语义搜索用户开关 v1：设置页可关闭 / 开启本地语义搜索，关闭后仅使用标题、FTS / LIKE 和 Key Points 字面检索。
- [x] SQLite FTS 搜索索引 v1。
- [x] Dreaming 本地整理 v1。
- [x] Dreaming 前台到期调度 v1。
- [x] Dreaming 前台到期系统通知 v1：前台自动整理产生内容后推送本地完成通知，通知展示整理消息数、记忆候选数和待确认画像变更数；真正系统后台调度仍待实现。
- [ ] 本地向量检索增强：Key Points 本地语义向量召回、本地消息语义索引、用户可控开关已完成；模型 embedding、真正向量数据库 / ANN、增量维护优化和真机长会话基线仍待实现。
- [ ] Dreaming 系统后台调度。
- [ ] 无限上下文长期压缩策略增强。
- [ ] 人工智能反思机制。
- [x] 本地用户画像 v1：从 Key Points 与最近 Dreaming 报告生成可解释画像。
- [x] 用户画像可控管理 v1：用户可在设置页编辑 / 删除画像信号，控制记录本地保存。
- [x] 用户画像版本历史与冲突检测 v1：本地保留最近画像快照，展示偏好冲突提示。
- [x] 用户画像历史差异对比与恢复 v1：展示历史版本相对当前画像的新增 / 移除摘要，并可恢复历史快照。
- [x] Dreaming 待确认画像变更 v1：Dreaming 后生成本地待确认画像变更，用户采纳后才写入正式画像。
- [x] 待确认画像变更逐项采纳 / 拒绝 v1：用户可对单条画像新增 / 移除信号单独采纳或忽略。
- [x] 待确认画像变更详情审阅 v1：用户可查看全部待确认画像差异，并处理卡片未展示的后续单项。
- [ ] 模型驱动画像增量分析。

### Phase 3 — 生态扩展

目标：平台打通，技能扩展。

- [ ] 社交平台接入：飞书 / Telegram / Discord 优先。
- [x] 技能市场基础集成。
- [ ] 多源技能市场集成：OpenClaw、腾讯等。
- [ ] 个人接口中转服务：本地 OpenAI 兼容中转核心服务 v1 已完成（模型列表、非流式 / 流式聊天补全、渠道模型桥接、Bearer 鉴权）；设置页启动 / 停止入口、令牌生成与加密持久化、端口展示、Base URL / curl 示例复制、访问审计、并发保护、局域网开放二次确认、高级路由策略、可配置并发上限、本地脱敏用量统计、持久化脱敏审计明细、JSON 导出、OpenAI 多模态内容安全兼容降级、图片 data URL 端到端透传、模型视觉能力路由、模型能力可见性与设置页 Vision 标注、远端图片 URL 安全下载透传 v1 已完成；真机长时间运行仍待做。
- [x] 定时任务与系统通知联动 v1：Dreaming 前台到期整理完成后推送本地通知，通知失败不阻断整理或聊天主链路。
- [ ] 定时任务与系统日历 / 闹钟联动。
- [ ] MCP 运行时 / 旁车管理。

### Phase 4 — 数据与同步

- [x] 本地数据导出压缩包 v1：设置页可生成 `.tar.gz`，包含 `manifest.json`、`conversations/`、`audio_transcripts/`、默认 `audio_files/`，不包含 API Key 或本机绝对路径。
- [x] 移动端系统分享导出 v1：导出前展示范围确认和原始语音文件开关，Android / iOS 通过原生系统分享面板分享导出包，不新增 Flutter 依赖。
- [x] 安全导入 / 恢复 v1：设置页可选择 SimiChat 导出包并预览，导入前校验 manifest、SHA-256 和路径安全，默认跳过已有文件避免覆盖。
- [x] 结构化本地数据备份 / 恢复 v1：导出 `structured_data/shared_preferences.json`，恢复 Key Points、Dreaming、用户画像、主题 / 字体 / 上下文阈值 / 本地语义搜索开关、系统提示词等白名单本地偏好；默认不覆盖已有偏好，不导出模型 API Key / 渠道密钥。
- [x] 电脑端本地传输 v1：导出后启动临时本地 HTTP 下载服务，使用一次性令牌、过期时间、单次下载限制和安全响应头，支持电脑浏览器下载导出包。
- [ ] Notion / Obsidian / 语雀 / 思源笔记同步。
- [ ] 可选云备份：WebDAV / S3 / 云盘，需端到端加密与明确授权。

### Phase 5 — 数字孪生

- [x] 用户画像分析系统 v1：本地画像结构、构建器、持久化、设置页查看 / 重建 / 编辑 / 删除、冲突提示、版本历史、差异对比、历史恢复、待确认变更、逐项采纳 / 拒绝和全部变更详情审阅。
- [ ] 声音 / 图像 / 表情处理。
- [ ] 镜像数字人生成。
- [ ] 数字人直播能力（长期）。

---

## 四、关键页面需求

### 4.1 对话主页

- 顶部居中：会话议题，可由人工智能自动抽取，首条回复后异步生成，可手动修改。
- 顶部左侧：历史会话入口。
- 顶部右侧：新建会话按钮。
- 消息流：用户消息右对齐，人工智能回复左对齐。
- 人工智能回复支持 Markdown、代码块、图片、LaTeX、思考过程。
- 每条人工智能回复底部操作：复制、重试。
- 流式输出支持中断。
- 底部输入区：多行文本框，发送按钮，附件入口，后续扩展语音录制按钮。

### 4.2 模型选择器

- 位置：移动端优先保证聊天主路径可快速切换；桌面端可放在侧边栏顶部。
- 展示：当前选中模型的名称 + 渠道名。
- 列表内容：所有渠道下的全部模型，不去重穷举。
- 每项显示：`渠道名 / 模型名`，同名模型在不同渠道下各自独立显示。
- 切换后立即生效，更新当前会话默认模型。
- 新建会话时自动选中上次使用的模型。

### 4.3 历史会话页

- 按最近消息时间倒序展示。
- 支持标题 + 内容全文搜索。
- 支持文件夹分组、展开 / 折叠。
- 每条会话支持重命名、移入文件夹、删除。
- 支持新建文件夹。

### 4.4 设置页

- 入口：移动端需清晰可达，可通过头像、设置按钮或抽屉入口进入。
- 模型渠道管理：新增 / 编辑 / 删除渠道；字段包括渠道名、Base URL、接口密钥、协议类型。
- 模型管理：每渠道可配置多个模型，设置默认模型，测试连通性，查看最近测试结果。
- 数据与档案：Markdown 档案、全文索引、Dreaming、导出同步。
- 记忆与画像：Key Points、用户画像、数字孪生基础。
- 语音与多模态：语音权限、STT 状态、图片 / 文件策略。
- 外观：主题、全局字体大小、颜色风格。

### 4.5 响应式布局

| 平台 | 布局 |
| --- | --- |
| 移动端 | 单栏，历史 / 设置 / 搜索可作为独立页面或抽屉入口 |
| 桌面端（宽 > 720px） | 左侧边栏 + 右侧对话区 |

---

## 五、隐私、安全与数据原则

1. 聊天、记忆、语音、图片、画像默认本地保存。
2. 云同步、笔记同步、社交通道转发、模型调用均必须有明确用户动作或配置。
3. 不保存明文接口密钥；不在日志、测试记录、Markdown 档案中暴露密钥。
4. 每个对话 1 个 Markdown 原始文件，但真实用户对话档案必须被 Git 忽略。
5. 用户可查看、编辑、删除记忆和画像。
6. 高风险代理行为必须二次确认。
7. 数字孪生不能默认冒充用户对外发送内容。
8. 每个功能进入 Done 前必须完成：功能测试、性能影响评估、安全影响评估、文档同步。

---

## 六、文档与记录约定

- `AGENTS.md`：中文权威账本，维护目标、进度、TODO、DONE、重要决策。
- `docs/`：所有具体实现文档、架构方案、数据结构、接口设计、测试方案、安全方案。
- `CLAUDE.md`：只保留迁移声明，不再维护项目进度。
- `docs/conversations/`：仅放示例或说明；真实用户对话 Markdown 不得提交。


## 43. 2026-06-27 OpenAI 兼容本地中转访问审计与并发保护 v1 复验

本次继续硬化“个人接口中转服务”：服务层新增脱敏 `OpenAiRelayAuditEvent`，每次请求只记录方法、路径、HTTP 状态码、错误码、模型 id、是否流式、耗时和当前并发数，不记录 prompt、消息内容、Bearer 令牌、API Key、上游 Base URL 或本机路径；聊天补全默认最多 4 个并发请求，超限返回 OpenAI 兼容 `429` / `rate_limit_error` / `concurrency_limit`，并设置 `Retry-After: 1`。`OpenAiRelayController` 聚合本轮运行期间的请求总数、授权请求、拒绝请求、未授权请求、并发拒绝和最近状态，设置页展示“并发保护 / 访问审计”摘要。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay / Provider / 设置页局部测试 | 通过 | `flutter test test/core/openai_compatible_relay_server_test.dart test/shared/openai_relay_provider_test.dart test/shared/settings_page_openai_relay_test.dart` 输出 `00:01 +10: All tests passed!`，覆盖脱敏审计不包含 prompt / token、未授权 / 授权 / chat 请求审计、并发上限 1 时第二个聊天请求返回 429 `concurrency_limit` 与 `Retry-After: 1`、Provider 审计汇总、设置页展示并发保护和暂无请求摘要 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.5s)`；移动端 smoke 链路内再次输出 `No issues found! (ran in 2.3s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:15 +194: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `./scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `./scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=221 avg_ms=2.21`，覆盖 100 次本地 buffered 请求；新增内存计数和脱敏审计对本地请求开销仍处于毫秒级 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过，有既有测试假阳性 | 敏感 `debugPrint` / `print` 扫描无命中；真实密钥字面量扫描仅命中 `test/core/key_encryptor_test.dart` 的测试假 key `sk-test-key-12345`；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；审计事件和设置页摘要不包含 prompt、Bearer token、API Key、上游 Base URL 或本机路径 |
| 代码索引刷新 | 通过 | `index_repository(repo_path="/Users/sanbo/code/simichat", mode="full", persistence=true)` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2167，边 5199 |

结论：SimiChat 本地 OpenAI 兼容中转已具备基础可运维性和抗滥用保护，能在不泄露敏感内容的前提下向用户展示访问摘要，并对过高并发返回标准 429。局域网开放二次确认在下一节继续收口；仍待高级路由策略、可配置并发上限、持久化审计、用量统计和真机长时间运行验证。

## 44. 2026-06-27 OpenAI 兼容本地中转局域网开放二次确认 v1 复验

本次继续硬化“个人接口中转服务”的网络暴露边界：默认仍只绑定 `127.0.0.1`；只有用户在设置页打开“允许局域网设备访问”并二次确认风险后，才会把 relay 绑定到 `0.0.0.0`。取消确认不会改变访问范围。设置页展示局域网候选 IPv4 地址，服务启动后展示局域网 Base URL；界面明确提示只在可信网络中使用，不在公共 Wi-Fi 开启，不把 Bearer 令牌发给他人。局域网绑定偏好不进入结构化备份白名单，避免恢复包意外开启暴露面。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay / Provider / 设置页局部测试 | 通过 | `flutter test test/shared/openai_relay_provider_test.dart test/shared/settings_page_openai_relay_test.dart test/core/openai_compatible_relay_server_test.dart` 输出 `00:01 +12: All tests passed!`，覆盖默认 loopback、选择局域网模式后绑定 `0.0.0.0`、局域网绑定仍需 Bearer 令牌、绑定模式持久化、设置页取消确认不改变状态、确认后展示局域网候选地址 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.5s)`；移动端 smoke 链路内再次输出 `No issues found! (ran in 2.4s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:18 +196: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `./scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `./scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=189 avg_ms=1.89`，局域网地址刷新异步化后不阻塞默认启动路径 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过，有既有测试假阳性 | 敏感 `debugPrint` / `print` 扫描无命中；真实密钥字面量扫描仅命中 `test/core/key_encryptor_test.dart` 的测试假 key `sk-test-key-12345`；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；局域网开放提示、确认和绑定模式不记录 prompt、Bearer token、API Key、上游 Base URL 或本机路径 |
| 代码索引刷新 | 通过 | `index_repository(repo_path="/Users/sanbo/code/simichat", mode="full", persistence=true)` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2178，边 5227 |

结论：本地 OpenAI 兼容中转的默认暴露面仍是仅本机；局域网开放已经具备“显式开关 + 二次确认 + 风险提示 + 候选地址展示 + 可关闭恢复”的基础安全闭环。高级路由策略在下一节继续收口；仍待可配置并发上限、持久化审计、用量统计和真机长时间运行验证。

## 45. 2026-06-27 OpenAI 兼容本地中转高级路由策略 v1 复验

本次继续推进“个人接口中转服务”的 Cherry Studio 式聚合能力：在本地 OpenAI Relay 中新增高级路由策略和路由别名。`/v1/models` 在存在真实模型时展示 `simichat:default`、`simichat:free`、`simichat:fast`；请求缺省 `model` 或使用 `simichat:auto` 时按设置页策略路由；真实模型 id 仍保持直连。路由策略包括指定模型、默认模型、免费优先、本地 / 快速优先。非流式请求在候选模型失败时尝试后续候选，成功响应写入实际命中的模型 id；所有候选失败时返回安全的 `502 upstream_error`，不暴露上游错误详情、API Key、prompt 或本机路径。流式请求不做中途回退，避免 SSE 已输出后切换模型造成协议混乱。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay / Bridge / Provider / 设置页局部测试 | 通过 | `flutter test test/core/openai_compatible_relay_server_test.dart test/core/channel_model_relay_bridge_test.dart test/shared/openai_relay_provider_test.dart test/shared/settings_page_openai_relay_test.dart` 输出 `00:02 +17: All tests passed!`，覆盖路由别名暴露、默认 / 免费 / 本地快速排序、真实模型 id 直连、缺省 model 选路、非流式失败回退、路由策略持久化且不进入结构化备份、设置页策略选择 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.0s)`；补充静默日志调整后再次输出 `No issues found! (ran in 3.2s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:23 +199: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `./scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `./scripts/benchmark_openai_relay.sh` 最终输出 `openai_relay_benchmark requests=100 total_ms=225 avg_ms=2.25`，路由别名与策略判断后 100 次本地 buffered 请求仍处于毫秒级 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过，有既有测试假阳性 | 敏感 `debugPrint` / `print` 扫描无命中；真实密钥字面量扫描仅命中 `test/core/key_encryptor_test.dart` 的测试假 key `sk-test-key-12345`；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；路由策略、别名、回退错误和审计摘要不记录 prompt、Bearer token、API Key、上游 Base URL 或本机路径 |
| 代码索引刷新 | 通过 | `index_repository(repo_path="/Users/sanbo/code/simichat", mode="full", persistence=true)` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2197，边 5307 |

结论：本地 OpenAI 兼容中转已从“指定模型直连”推进到“可配置路由聚合”：用户可通过路由别名和设置页策略把多个模型当作一个本地中转池使用，并在非流式场景获得基础失败回退。仍待可配置并发上限、持久化审计、用量统计、多模态 OpenAI 兼容透传和真机长时间运行验证。


## 46. 2026-06-27 OpenAI 兼容本地中转可配置并发上限 + 本地脱敏用量统计 v1 复验

本次继续推进“个人接口中转服务”的可运维能力：`OpenAiRelayController` 新增 1–32 可配置并发上限，设置页提供“并发上限”下拉，运行中修改会重启本地 relay 并把新上限传入 `OpenAiCompatibleRelayServer`；新增 `OpenAiRelayUsageStats` 本地脱敏累计统计，只记录请求次数、聊天请求、流式请求、成功 / 拒绝 / 未授权 / 限流 / 路由 / 上游错误、耗时和最近状态，不记录 prompt、消息正文、Bearer 令牌、API Key、上游 Base URL、本机路径或用户原始内容。统计写入采用串行队列，避免短时间多请求异步落盘乱序；用户可在设置页一键清空统计。并发配置键与用量统计键均不进入结构化备份白名单。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay / Provider / 设置页局部测试 | 通过 | `flutter test test/shared/openai_relay_provider_test.dart test/shared/settings_page_openai_relay_test.dart test/core/openai_compatible_relay_server_test.dart` 输出 `00:02 +16: All tests passed!`，覆盖并发上限持久化、1–32 越界抛错、启动时保留用户配置、用量统计累计与持久化、清空统计、备份白名单排除、设置页切换 8 并发、展示与清空累计用量 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.7s)`；移动端 smoke 链路内再次输出 `No issues found! (ran in 3.0s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:23 +201: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `./scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `./scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=231 avg_ms=2.31`，串行统计落盘队列不影响本地 buffered 请求毫秒级基线 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过，有既有测试假阳性 | 敏感 `debugPrint` / `print` 扫描无命中；真实密钥字面量扫描仅命中 `test/core/key_encryptor_test.dart` 的测试假 key `sk-test-key-12345`；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；并发配置和用量统计不记录 prompt、Bearer token、API Key、上游 Base URL、本机路径或用户原始内容 |
| 代码索引刷新 | 通过 | `index_repository(repo_path="/Users/sanbo/code/simichat", mode="full", persistence=true)` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2211，边 5362 |

结论：本地 OpenAI 兼容中转已具备用户可调并发保护和本地脱敏用量可见性，能在不纳入备份、不泄露敏感内容的前提下帮助用户控制本机负载与查看累计调用概况。仍待持久化访问日志脱敏明细 / 审计导出、多模态 OpenAI 兼容透传和真机长时间运行验证。


## 47. 2026-06-27 OpenAI 兼容本地中转持久化脱敏审计明细 / 用量导出 v1 复验

本次继续补齐“个人接口中转服务”的本地排障与审计能力：`OpenAiRelayAuditLogEntry` 只保留最近 100 条脱敏审计事件，字段限定为方法、路径、HTTP 状态码、错误码、授权状态、完成时间、模型 id、是否流式、耗时和当前并发；不保存 prompt、messages、Bearer 令牌、API Key、上游 Base URL、本机路径或用户原始内容。设置页展示最近审计摘要，提供“复制审计 JSON”和“清空审计”；导出的 JSON 包含 schema、生成时间、隐私说明、累计用量和审计明细，仅复制到剪贴板，不自动上传、不进入结构化备份。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay / Provider / 设置页局部测试 | 通过 | `flutter test test/shared/openai_relay_provider_test.dart test/shared/settings_page_openai_relay_test.dart test/core/openai_compatible_relay_server_test.dart` 输出 `00:05 +16: All tests passed!`，覆盖审计明细持久化、导出 JSON schema、导出不包含 token / 测试 API Key / 上游 Base URL、结构化备份白名单排除、设置页展示最近审计、复制审计 JSON 入口和清空审计 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.6s)`；移动端 smoke 链路内再次输出 `No issues found! (ran in 4.1s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:24 +201: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `./scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `./scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=266 avg_ms=2.66`，新增最近 100 条脱敏审计明细和 JSON 导出能力后，本地 buffered 请求仍保持毫秒级 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过，有既有测试假阳性 | 敏感 `debugPrint` / `print` 扫描无命中；真实密钥字面量扫描仅命中 `test/core/key_encryptor_test.dart` 的测试假 key `sk-test-key-12345`；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；持久化审计明细与导出 JSON 不包含 prompt、Bearer token、API Key、上游 Base URL、本机路径或用户原始内容 |
| 代码索引刷新 | 通过 | MCP 通道短暂断开后改用本地 CLI：`codebase-memory-mcp cli index_repository '{"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}'` 完成；`codebase-memory-mcp cli index_status '{"project":"Users-sanbo-code-simichat"}'` 返回状态 `ready`，节点 2226，边 5472 |

结论：本地 OpenAI 兼容中转已经具备“脱敏累计统计 + 最近审计明细 + 本地 JSON 导出 + 一键清空”的基础可排障闭环，且审计数据不会进入结构化备份或自动上传。仍待多模态 OpenAI 兼容透传和真机长时间运行验证。


## 48. 2026-06-27 OpenAI 兼容本地中转多模态安全兼容降级 v1 复验

本次补齐“个人接口中转服务”的 OpenAI 多模态 content part 兼容边界：Relay 现在可以接收 `text` / `input_text` / `output_text` 文本片段，以及 `image_url` / `input_image` / `input_audio` / `file` / `input_file` / `video` 等非文本片段。当前策略是“兼容接收 + 安全降级”：文本进入 `AiMessage.content`，非文本片段只生成安全占位与本地类型计数，不下载 URL、不读取 file URL、不解码 data URL、不把远端 URL / base64 / 本机路径 / 文件 id 作为附件传给下游协议。审计事件写入前还会限制 `modelId` 为安全标识形态，避免异常请求把路径或 URL 写入审计明细。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay 局部测试 | 通过 | `flutter test test/core/openai_compatible_relay_server_test.dart` 输出 `00:00 +11: All tests passed!`，覆盖 `text` / `input_text` / `image_url` / `input_image` / `input_audio` / `file` 解析、安全占位、非文本类型计数、响应不泄露 URL / data URL / 文件 id / 本机路径，以及异常 `model` 路径不进入审计 modelId |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.1s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:28 +204: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `./scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!`；脚本内分析再次输出 `No issues found! (ran in 4.2s)` |
| OpenAI relay 性能基线脚本 | 通过 | `./scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=252 avg_ms=2.52`；多模态安全降级解析后，本地 buffered 请求仍保持毫秒级 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过，有既有测试假阳性 | 敏感密钥字面量扫描无真实命中（已忽略既有测试假 key `sk-test-key-12345`）；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；Relay 测试 payload marker 未进入生产代码 / docs；多模态 content part、响应、审计和导出边界不保存 prompt、Bearer token、API Key、上游 Base URL、本机路径、远端图片 URL、data URL、base64 或文件 id |
| 代码索引刷新 | 通过 | MCP 通道短暂断开后继续使用本地 CLI：`codebase-memory-mcp cli index_repository '{"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}'` 返回增量无变化；`codebase-memory-mcp cli index_status '{"project":"Users-sanbo-code-simichat"}'` 返回状态 `ready`，节点 2234，边 5455 |

结论：本地 OpenAI 兼容中转已能安全接收主流 OpenAI 多模态请求格式，保持文本上下文并对非文本内容做脱敏占位，不会因为外部客户端传入图片 URL、data URL、音频数据或文件 id 而泄露到 prompt、响应、审计或导出 JSON。真正图片字节端到端透传仍需单独设计模型视觉能力标注、用户授权、大小限制、下载禁止策略和协议分流。


## 49. 2026-06-27 OpenAI 兼容本地中转图片 data URL 透传 v1 复验

本次在上一轮“多模态安全兼容降级”之上补齐受控图片字节透传闭环：外部 OpenAI 兼容客户端传入 `image_url` / `input_image` 且内容为合法 `data:image/...;base64,...` 时，Relay 会把该片段转成内存态 `AiMessage.attachments` 图片附件，复用现有 OpenAI Chat / OpenAI Responses / Claude / Gemini / Ollama 多模态协议发送给用户选择的上游模型。远端 HTTP(S) 图片 URL、`file://` 本机路径、音频、文件和视频仍然只生成安全占位，不下载、不读取、不落库。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| 附件 / Relay 局部测试 | 通过 | `flutter test test/core/attachment_helper_test.dart test/core/openai_compatible_relay_server_test.dart` 输出 `00:00 +13: All tests passed!`，覆盖图片 data URL 规范化 / 加载、Relay 把 `input_image` data URL 转为 `AiMessage.attachments`、远端 URL 仍安全占位、响应和审计不回显 data URL / base64 / 远端 URL / file URL / 文件 id |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.4s)`；移动端 smoke 链路内再次输出 `No issues found! (ran in 3.9s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:20 +205: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `./scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `./scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=246 avg_ms=2.46`，图片 data URL 解析能力不影响本地文本 buffered 基线 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过，有既有测试假阳性 | 敏感密钥字面量扫描无真实命中（已忽略既有测试假 key `sk-test-key-12345`）；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；Relay inline image 测试 marker 未进入生产代码 / docs；图片 data URL 不写入 SQLite、Markdown、审计、导出或日志 |
| 代码索引刷新 | 通过 | MCP 通道短暂断开后继续使用本地 CLI：`codebase-memory-mcp cli index_repository '{"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}'` 返回增量无变化；`codebase-memory-mcp cli index_status '{"project":"Users-sanbo-code-simichat"}'` 返回状态 `ready`，节点 2242，边 5487 |

结论：本地 OpenAI 兼容中转现在具备受控图片 data URL 端到端透传能力，同时维持远端 URL / file URL 不下载不读取的安全边界。本节结束时模型视觉能力路由仍待补齐，已在第 50 节继续收口；远端图片 URL 如需支持，必须先完成 SSRF 防护、MIME / 大小检测、超时和缓存清理设计。


## 50. 2026-06-27 OpenAI 兼容本地中转模型视觉能力路由 v1 复验

本次在图片 data URL 透传基础上补齐视觉能力路由：`ModelCapability` 新增 `vision`，模型发现会根据显式 metadata 与常见视觉模型名推断能力；`ChannelDao.getChatModels()` 与 `ChannelModelRelayBridge` 允许 `chat` / `vision` 进入聊天模型列表，但继续排除 `embedding`；`OpenAiCompatibleRelayModel` 新增 `supportsVision`，Relay 在解析到图片附件后会把候选路由过滤为视觉模型。直连纯文本模型的图片请求返回 OpenAI 兼容 `400 vision_model_required`，且不会调用上游；别名 / 策略路由会跳过纯文本候选，只转发给支持视觉的模型。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay / Bridge / 模型能力局部测试 | 通过 | `flutter test test/core/openai_compatible_test.dart test/core/channel_model_relay_bridge_test.dart test/core/attachment_helper_test.dart test/core/openai_compatible_relay_server_test.dart` 输出 `00:01 +23: All tests passed!`，覆盖 vision 能力推断、`gemini-embedding` 不误判、Bridge 列出 / 解析视觉模型且标记 `supportsVision`、图片请求指定纯文本模型返回 `vision_model_required` 且不 forward、路由候选过滤到视觉模型 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.1s)`；移动端 smoke 链路内再次输出 `No issues found! (ran in 3.3s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:23 +207: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=272 avg_ms=2.72`，图片请求视觉路由判断不影响本地文本 buffered 毫秒级基线 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无真实命中；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；Relay inline image 测试 marker 未进入生产代码 / docs；视觉路由错误响应与审计不保存 prompt、Bearer token、API Key、上游 Base URL、本机路径、远端图片 URL、data URL、base64 或文件 id |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`codebase-memory-mcp cli index_status {"project":"Users-sanbo-code-simichat"}` 返回状态 `ready`，节点 2245，边 5466 |

结论：本地 OpenAI 兼容中转的图片输入现在不会落到纯文本模型；用户直连纯文本模型时能得到明确的 `vision_model_required` 错误，使用路由别名 / 策略时会自动筛选支持视觉的候选模型。本节结束时仍待远端图片 URL 下载透传策略和真机长时间运行验证；远端图片 URL 安全下载透传已在第 52 节收口。


## 51. 2026-06-27 OpenAI 兼容本地中转模型能力可见性 v1 复验

本次在视觉能力路由之后补齐用户与外部客户端可见性：设置页手动添加模型新增 `Vision 视觉` 选项，并用中文能力标签展示 Chat / Vision / Embedding；批量渠道导入支持 `capability: "vision"`；Relay 的 `GET /v1/models` 在标准 OpenAI 兼容字段外追加脱敏 `capabilities` 与 `supports_vision`，真实模型和 `simichat:*` 路由别名都能表达是否具备视觉候选，不包含 API Key、上游 Base URL、本机路径或令牌。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| 模型能力 / Bridge / Relay / 设置页局部测试 | 通过 | `flutter test test/core/openai_compatible_test.dart test/core/channel_model_relay_bridge_test.dart test/core/openai_compatible_relay_server_test.dart test/shared/settings_page_channel_import_test.dart test/shared/settings_page_model_test_history_test.dart` 输出 `00:03 +24: All tests passed!`，覆盖中文能力标签、vision 导入、路由别名 `supportsVision`、`/v1/models` 的 `capabilities` / `supports_vision` 脱敏元数据 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.3s)`；移动端 smoke 链路内再次输出 `No issues found! (ran in 2.9s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:18 +208: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=276 avg_ms=2.76`，模型能力元数据不影响本地文本 buffered 毫秒级基线 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无真实命中；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；Relay inline image 测试 marker 未进入生产代码 / docs；`capabilities` / `supports_vision` 只暴露能力布尔与枚举，不包含 prompt、Bearer token、API Key、上游 Base URL、本机路径、远端图片 URL、data URL、base64 或文件 id |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`codebase-memory-mcp cli index_status {"project":"Users-sanbo-code-simichat"}` 返回状态 `ready`，节点 2246，边 5476 |

结论：用户现在能在设置页明确标记视觉模型，批量导入也能保留 vision 能力；外部 OpenAI 兼容客户端可以通过 `/v1/models` 的脱敏能力元数据判断真实模型或 `simichat:*` 路由别名是否适合图片请求。本节结束时仍待远端图片 URL 下载透传策略和真机长时间运行验证；远端图片 URL 安全下载透传已在第 52 节收口。

## 52. 2026-06-27 OpenAI 兼容本地中转远端图片 URL 安全下载透传 v1 复验

本次在图片 data URL 透传、视觉模型路由和模型能力可见性之后，补齐受控远端图片 URL 下载透传：设置页新增“允许下载远端图片 URL”开关，默认关闭；开启必须二次确认。Relay 仅在开关开启时处理 OpenAI `image_url` / `input_image` 中的公网 HTTP(S) 图片 URL，下载成功后转为本次请求内存态 data URL 图片附件，并继续走既有 `supportsVision` 视觉路由。默认关闭时继续安全降级为占位文本，不触发 fetcher。

安全边界：同步 URL 检查拒绝非 HTTP(S)、空 host、userInfo、本机 / 内网 / link-local / multicast / unique-local IP、`localhost` / `*.localhost`；默认 fetcher 会先解析 DNS 并拒绝任意不安全解析地址；请求限制 `image/jpeg` / `image/png` / `image/gif` / `image/webp` / `image/bmp`，最大 `1 MB`，默认 `3 秒`超时，不跟随重定向。远端 URL、图片 bytes 和 base64 不写入 SQLite、Markdown、审计明细、用量导出、结构化备份或日志，也不在 OpenAI 响应中回显。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay / Provider / 设置页局部测试 | 通过 | `flutter test test/core/openai_compatible_relay_server_test.dart test/shared/openai_relay_provider_test.dart test/shared/settings_page_openai_relay_test.dart` 输出 `00:04 +25: All tests passed!`，覆盖远端图片安全策略、默认关闭不 fetch、开启后注入 fetcher 转内存附件、开关持久化、不进入结构化备份白名单、设置页二次确认 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.4s)`；移动端 smoke 链路内再次输出 `No issues found! (ran in 2.7s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:16 +211: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=193 avg_ms=1.93`；远端图片策略不影响本地文本 buffered 毫秒级基线 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无真实命中；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；Relay inline image / remote image 测试 marker 未进入生产代码 / docs；远端图片 URL、data URL、base64、图片 bytes、prompt、Bearer token、API Key、上游 Base URL、本机路径不进入响应、审计、导出、日志或结构化备份 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2260，边 5500 |

结论：本地 OpenAI 兼容中转已支持显式授权后的远端图片 URL 安全下载透传，同时保持默认关闭、二次确认、公网地址限制、MIME / 大小 / 超时限制、不重定向和不落盘边界。后续仍待真机长时间运行、弱网场景、DNS 变化场景和连接级 SSRF 防护增强评估。

## 53. 2026-06-27 移动端语音录音输入 v1 复验

本次补齐移动端核心聊天体验中的语音录音入口：`ChatInputBar` 在移动端展示语音按钮，点击后通过 `VoiceRecorderPlatform` 调用 `simichat/voice_recorder` 原生 MethodChannel；Android 使用 `MediaRecorder` 运行时申请 `RECORD_AUDIO` 并录制 `.m4a` 到应用 cache，iOS 使用 `AVAudioRecorder` 请求麦克风权限并录制 `.m4a` 到应用 cache。再次点击停止录音后，Dart 层把录音结果转成 `PendingAttachment(type: audio)`，复用既有发送前校验、应用私有目录归档、SQLite 附件元数据、Markdown 附件名记录和 STT 转写稿件草稿链路。

安全与隐私边界：录音文件只写入应用 cache / 应用文档目录，不写入日志；异常提示不包含完整本机路径；音频附件进入模型请求时仍遵守“非图片附件不读取 / 不 base64 编码原始文件”的既有边界；真实 STT 厂商未配置时不会自动外发音频。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| 语音输入 / 音频归档局部测试 | 通过 | `flutter test test/shared/chat_input_bar_voice_test.dart test/core/audio_file_archive_test.dart test/core/audio_transcript_archive_test.dart test/core/audio_transcription_service_test.dart test/shared/settings_page_voice_input_test.dart` 输出 `00:02 +11: All tests passed!`，覆盖录音按钮开始 / 停止、停止后添加 audio 附件、录音中禁用发送、音频私有归档、转写稿件草稿和设置页 STT 状态 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.0s)`；移动端 smoke 链路内再次输出 `No issues found! (ran in 3.2s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:24 +213: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| OpenAI relay 性能基线脚本 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=262 avg_ms=2.62`；语音输入 UI / 原生通道不影响本地 relay 文本请求基线 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk`，证明 Kotlin `MediaRecorder` / runtime permission 通道可编译 |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app`，证明 Swift `AVAudioRecorder` 通道可编译 |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无真实命中；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；录音代码未新增日志输出，本地录音路径只在应用内部通道与附件管线中流转 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2303，边 5678 |

结论：移动端现在具备真实录音入口和原生运行时权限申请，录音结果可以作为音频附件进入现有本地归档 / STT 草稿链路。后续仍待真实 STT 厂商接入、录音真机长时间 / 中断场景复验和语音播报。



## 54. 2026-06-27 非语音附件原文件导出 / 导入 v1 复验

本次补齐本地数据导出包对图片 / PDF / 文档等非语音附件原文件的覆盖：`DataExportService` 可从 SQLite 附件表加载附件元数据，跳过 `audio`、缺失文件、非普通文件、符号链接和 `exports/` 下文件，把可读取的非语音附件复制到压缩包 `attachments/<message-id>/<attachment-id>-<safe-file-name>`。归档路径会净化 message id、attachment id 和文件名，不写本机绝对路径。`DataImportService` 的导入白名单新增 `attachments/`，可把附件原文件恢复到目标应用目录；当前 v1 只恢复文件，不自动重建 SQLite `attachments` 记录。

安全与隐私边界：导出 manifest 只保存包内相对路径、大小和 SHA-256；不保存源文件绝对路径、缺失文件路径、API Key、Bearer token、模型密钥、prompt 或消息正文。导出失败的单个附件不会阻断整包导出；导入仍保持 manifest 校验、SHA-256 校验、绝对路径 / 反斜杠 / `..` 路径穿越拦截和默认不覆盖已有文件策略。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| 导出 / 导入局部测试 | 通过 | `flutter test test/core/data_export_service_test.dart test/core/data_import_service_test.dart` 输出 `00:00 +11: All tests passed!`，覆盖非语音附件复制到 `attachments/`、路径净化、不泄露源目录、跳过 audio / 缺失附件、导入 `attachments/` 文件恢复 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 5.1s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 3.2s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:25 +215: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| 导出性能基线脚本 | 通过 | `scripts/benchmark_data_export.sh` 输出 `data_export_benchmark files=200 export_ms=101 manifest_files=200 uncompressed_bytes=341504 compressed_bytes=14562` |
| 导入性能基线脚本 | 通过 | `scripts/benchmark_data_import.sh` 输出 `data_import_benchmark files=200 preview_ms=27 import_ms=78 preview_files=200 imported_files=200 imported_bytes=147920` |
| OpenAI relay 性能基线脚本 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=264 avg_ms=2.64`；附件导出能力不影响本地 relay 文本请求基线 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无真实命中；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；附件源路径、缺失路径和原始文件名中的不安全片段不进入 manifest |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2312，边 5709 |

结论：本地导出包现在覆盖会话 Markdown、语音转写稿、可选原始语音文件、非语音附件原文件和白名单结构化偏好，导入侧可安全恢复 `attachments/` 文件。后续仍需设计 SQLite 完整结构化恢复，把恢复后的附件文件重新关联到 sessions / messages / attachments 表。


## 55. 2026-06-27 本地聊天核心数据库备份 / 恢复 v1 复验

本次在文件级导出 / 导入和非语音附件原文件恢复基础上，补齐聊天核心数据库结构化快照：导出包新增 `structured_data/local_database.json`，记录 sessions / messages / attachments 三张核心聊天表；导入时先通过 manifest 与 SHA-256 校验，再恢复会话、消息和附件元数据。附件 `localPath` 不复用源设备绝对路径，而是根据导入目标目录重定向到 `attachments/` 或 `audio_files/` 下的恢复文件。

安全与一致性边界：快照不包含模型 API Key、渠道密钥、上游 Base URL、本机绝对路径或安全存储内容；默认不覆盖已有记录。显式覆盖时使用 upsert 更新，避免 SQLite `REPLACE` 触发外键级联误删。为避免缺失外部依赖导致恢复失败，`folderId`、`defaultChannelModelId`、`channelModelId` 导入时置空；模型渠道、文件夹、提示词、MCP、Skills、搜索索引缓存等非聊天核心表仍待后续单独设计。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| 导出 / 导入局部测试 | 通过 | `flutter test test/core/data_export_service_test.dart test/core/data_import_service_test.dart` 输出 `00:00 +13: All tests passed!`，覆盖 `structured_data/local_database.json` 导出、不泄露附件源绝对路径、导入恢复 sessions / messages / attachments、附件 localPath 重定向、二次导入默认跳过已有记录 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.7s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 6.0s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:24 +217: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `00:03 +4: All tests passed!` |
| 导出性能基线脚本 | 通过 | `scripts/benchmark_data_export.sh` 输出 `data_export_benchmark files=200 export_ms=465 manifest_files=200 uncompressed_bytes=341504 compressed_bytes=14563` |
| 导入性能基线脚本 | 通过 | `scripts/benchmark_data_import.sh` 输出 `data_import_benchmark files=200 preview_ms=84 import_ms=350 preview_files=200 imported_files=200 imported_bytes=147920` |
| OpenAI relay 性能基线脚本 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=1145 avg_ms=11.45`；数据备份恢复代码不在 relay 请求路径上 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无真实命中；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；快照只记录聊天核心表和附件相对归档路径，不记录源设备绝对路径或模型密钥 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2340，边 5795 |

结论：导出 / 导入现在具备从文件恢复升级到“文件 + 白名单偏好 + 聊天核心数据库”的生产闭环。用户迁移导出包后，可恢复会话列表、消息内容和附件元数据；后续仍需继续补齐非聊天核心结构化数据，例如模型渠道配置（不含密钥或需单独安全迁移）、文件夹、提示词、MCP、Skills 与加密备份。


## 56. 2026-06-27 非密钥配置表备份 / 恢复 v1 复验

本次在本地聊天核心数据库快照基础上，继续把可迁移的非密钥配置纳入 `structured_data/local_database.json`：folders / prompts / skills / mcp_servers / model_channels / channel_models。导出包仍不是原始 SQLite 文件，而是受控 JSON 快照；导入时先通过 manifest 与 SHA-256 校验，再按表恢复并默认跳过已有记录。

安全与一致性边界：模型渠道 `apiKeyEncrypted` 绝不导出，MCP `headers` 绝不导出；疑似含 token 的 MCP `args` / `url` 与渠道 `base_url` 会置空。恢复后的模型渠道与 MCP 服务默认禁用，需要用户重新填写密钥 / headers 后手动启用，避免导入包直接触发外部调用。会话 `folderId` 仅在目标库中存在对应文件夹时恢复；`defaultChannelModelId` 与消息 `channelModelId` 仍置空，避免自动绑定缺少密钥的模型渠道。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| 导出 / 导入局部测试 | 通过 | `flutter test test/core/data_export_service_test.dart test/core/data_import_service_test.dart` 输出 `00:02 +15: All tests passed!`，覆盖非密钥配置表入包、`apiKeyEncrypted` / MCP headers / token 参数不入包、导入恢复 folders / prompts / skills / mcp_servers / model_channels / channel_models、模型渠道和 MCP 默认禁用、二次导入默认跳过已有记录 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.2s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 2.9s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:20 +219: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `00:02 +4: All tests passed!` |
| 导出性能基线脚本 | 通过 | `scripts/benchmark_data_export.sh` 输出 `data_export_benchmark files=200 export_ms=95 manifest_files=200 uncompressed_bytes=341504 compressed_bytes=14563` |
| 导入性能基线脚本 | 通过 | `scripts/benchmark_data_import.sh` 输出 `data_import_benchmark files=200 preview_ms=26 import_ms=72 preview_files=200 imported_files=200 imported_bytes=147920` |
| OpenAI relay 性能基线脚本 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=204 avg_ms=2.04`；配置表备份恢复不在 relay 请求路径上 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无真实命中；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；新增快照测试证明模型密钥、MCP headers、疑似 token 参数和本机绝对路径不会进入导出包 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2351，边 5835 |

结论：本地导出 / 导入现在从“文件 + 白名单偏好 + 聊天核心数据库”升级为“文件 + 白名单偏好 + 聊天核心数据库 + 非密钥配置表”。用户迁移导出包后，可恢复文件夹、提示词、Skills、MCP 和模型渠道 / 模型列表的非密钥元数据；真正外部连接仍需用户在目标设备重新填写密钥 / headers 并手动启用。


## 57. 2026-06-27 Obsidian Markdown Vault 导出 v1 复验

本次在本地导出 / 导入闭环基础上，补齐笔记工具方向的第一个可用落点：Obsidian Markdown Vault 本地导出。设置页「导出本地数据」弹窗新增「Obsidian Vault」入口；`ObsidianVaultExportService` 会在应用文档目录 `exports/obsidian-vault-YYYYMMDD-HHMMSS/` 下生成 Obsidian 可直接打开的目录结构，复制会话 Markdown 到 `Conversations/`，复制语音转写 Markdown 到 `Audio Transcripts/`，并生成 `README.md`、`SimiChat-Index.md` 和 `SimiChat-Manifest.md`。

安全与一致性边界：Obsidian Vault v1 只复制 Markdown 文件，不复制 SQLite 数据库、模型 API Key、渠道密钥、MCP headers、结构化配置或本机绝对路径。Manifest 只记录 vault 内相对路径、类型、大小和 SHA-256。Vault 内会包含用户主动导出的聊天正文 / 转写正文，因此仍需要用户在外发前自行确认内容是否适合分享。当前 v1 不自动写入用户已有 Obsidian vault，不做双向同步，不重写附件链接。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Obsidian 导出 / 设置页入口局部测试 | 通过 | `flutter test test/core/obsidian_vault_export_service_test.dart test/shared/settings_page_font_scale_test.dart test/benchmark/obsidian_vault_export_benchmark.dart` 输出 `00:06 +7: All tests passed!`，覆盖会话 / 语音转写 Markdown 复制、README / Index / Manifest 生成、空 vault、忽略非 Markdown 与旧 exports、Manifest 不泄露本机绝对路径、设置页导出弹窗展示「Obsidian Vault」入口 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.9s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 4.0s)` |
| 全量测试 | 通过 | 首次全量测试因语音状态文案测试仍断言旧文案失败，已同步修复测试；复跑 `flutter test` 输出 `00:19 +221: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `00:03 +4: All tests passed!` |
| Obsidian Vault 性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_export.sh` 输出 `obsidian_vault_export_benchmark files=200 export_ms=141 vault_files=203 conversations=200 audio_transcripts=0 bytes=187705` |
| 标准导出性能基线脚本 | 通过 | `scripts/benchmark_data_export.sh` 输出 `data_export_benchmark files=200 export_ms=104 manifest_files=200 uncompressed_bytes=341504 compressed_bytes=14564` |
| 导入性能基线脚本 | 通过 | `scripts/benchmark_data_import.sh` 输出 `data_import_benchmark files=200 preview_ms=19 import_ms=64 preview_files=200 imported_files=200 imported_bytes=147920` |
| OpenAI relay 性能基线脚本 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_benchmark requests=100 total_ms=220 avg_ms=2.20`；Obsidian 导出不在 relay 请求路径上 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无真实命中；敏感 `debugPrint` / `print` 扫描无命中；Android `FileProvider` 路径配置无 `<root-path>`；`docs/conversations/example.md` 仍被 `.gitignore` 忽略；Obsidian Vault Manifest 不记录源设备绝对路径，服务不读取安全存储 / 数据库密钥 / MCP headers |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2381，边 5906 |

结论：SimiChat 现在具备第一个笔记工具落地能力：用户可在本地生成 Obsidian 兼容 Markdown Vault，并通过索引文件快速浏览会话和语音转写。后续仍需继续做 Obsidian 写入已有 vault、增量同步、冲突检测、附件链接重写，以及 Notion、语雀、思源笔记同步；其中写入已有 vault、增量同步和基础冲突检测已在第 58 节推进到 v1。


## 58. 2026-06-27 Obsidian 现有 Vault 增量同步 v1 复验

本次在 Obsidian Markdown Vault 本地导出基础上，补齐“写入用户已有 Obsidian Vault”的生产切片。设置页「导出本地数据」弹窗新增「同步到 Obsidian」入口，用户选择已有 Vault 文件夹后，SimiChat 只写入该 Vault 下的 `SimiChat/` 子目录，避免污染用户原有笔记结构。同步会复制会话 Markdown 到 `SimiChat/Conversations/`，复制语音转写 Markdown 到 `SimiChat/Audio Transcripts/`，并生成 `README.md`、`SimiChat-Index.md`、`SimiChat-Manifest.md` 和 `SimiChat-Sync-State.json`。

安全与一致性边界：同步状态文件只记录相对路径、类型、大小和 SHA-256，不记录本机绝对路径、模型 API Key、渠道密钥、MCP headers 或数据库内容。二次同步时，若目标文件仍等于上次同步版本，会安全更新；若用户在 Obsidian 中手动改过同名 Markdown，默认记录 `target_modified` 冲突并跳过；若目标路径是符号链接、目录等非普通文件，记录 `unsafe_existing_entity` 冲突并跳过，避免写穿链接。同步目标不能位于 `conversations/` 或 `audio_transcripts/` 源档案目录内。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Obsidian 增量同步 / 设置页入口局部测试 | 通过 | `flutter test test/core/obsidian_vault_export_service_test.dart test/shared/settings_page_font_scale_test.dart` 输出 `00:02 +10: All tests passed!`，覆盖首次写入、二次未变跳过、源文件变更安全更新、目标手动修改冲突跳过、符号链接目标不写穿、源档案目录内目标拒绝、设置页展示「同步到 Obsidian」入口 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.0s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 2.8s)` |
| 全量测试 | 通过 | `flutter test` 输出 `00:20 +225: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `00:03 +4: All tests passed!` |
| Obsidian 增量同步性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_sync.sh` 输出 `obsidian_vault_sync_benchmark files=200 first_sync_ms=174 second_sync_ms=224 created=200 unchanged=200 conflicts=0 vault_files=204 bytes=226328` |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；敏感 `debugPrint` / `print` 扫描无命中；同步状态与 Manifest 明确 `contains_absolute_paths: false`；新增测试证明用户修改内容不会被默认覆盖、符号链接目标不会被写穿、同步目标不能位于源档案目录内 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2408，边 5975 |

结论：SimiChat 的 Obsidian 集成已从“生成一个可打开的新 Vault”推进到“安全写入用户已有 Vault 的单向增量同步”。后续仍需继续做附件链接重写、冲突详情界面、可选覆盖策略、双向同步，以及 Notion、语雀、思源笔记同步。

## 59. 2026-06-27 Obsidian 附件链接重写 v1 复验

本次在 Obsidian 现有 Vault 增量同步基础上，补齐附件可用性：`ObsidianVaultExportService` 会从 SQLite 附件表加载可安全读取的非语音附件，复制到 Obsidian Vault 内的 `Attachments/<message-id>/<attachment-id>-<safe-file-name>`，并在会话 Markdown 中把 `attachments` 列表按 `messageId + fileName` 重写为 Obsidian wiki 链接。原始 audio 附件仍不进入 `Attachments/`，继续由 `Audio Transcripts/` 暴露语音转写稿。

安全与一致性边界：附件复制不跟随符号链接，不复制旧 `exports/` 目录，不记录本机绝对路径，不读取安全存储、模型 API Key、渠道密钥或 MCP headers；同步仍只写入用户所选 Vault 下的 `SimiChat/` 子目录，并沿用 `target_modified` 与 `unsafe_existing_entity` 冲突跳过策略。当前同一消息同名附件按第一条建立链接，后续可继续做去重展示和冲突详情界面。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Obsidian 附件链接局部测试 | 通过 | `flutter test test/core/obsidian_vault_export_service_test.dart test/shared/settings_page_font_scale_test.dart` 输出 `+11: All tests passed!`，覆盖非语音附件复制到 `Attachments/`、会话 Markdown 附件项重写为 wiki 链接、audio 附件跳过、设置页同步入口和字体设置回归 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found!`；移动端 smoke 脚本内再次通过静态分析 |
| 全量测试 | 通过 | `flutter test` 输出 `+226: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| Obsidian 增量同步性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_sync.sh` 输出 `obsidian_vault_sync_benchmark files=200 attachments=200 first_sync_ms=349 second_sync_ms=258 created=400 unchanged=400 conflicts=0 vault_files=404 bytes=388724` |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；`debugPrint` / `print` 扫描无命中；附件路径只写入 Vault 相对路径，Manifest / Sync State 不包含本机绝对路径 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 返回增量无变化；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2418，边 6010 |

结论：SimiChat 的 Obsidian 单向同步已具备“会话 Markdown + 语音转写 Markdown + 非语音附件 + 可点击 wiki 链接”的基础闭环。后续仍需继续做冲突详情界面、可选覆盖策略、双向同步、同名附件更精细去重、audio 原文件可选同步，以及 Notion、语雀、思源笔记同步。

## 60. 2026-06-27 Obsidian 同步冲突详情界面 v1 复验

本次在 Obsidian 增量同步和附件链接重写基础上，补齐冲突可解释性。设置页执行「同步到 Obsidian」后，如果同步结果包含 `target_modified` 或 `unsafe_existing_entity` 等冲突，会在保持默认不覆盖策略的前提下弹出「Obsidian 同步冲突详情」：展示 Vault 内相对路径、中文原因说明、新版本 / 现有版本短 SHA，并明确本次没有覆盖用户在 Obsidian 中的文件。

安全与一致性边界：界面只展示 Vault 相对路径和截断后的 SHA-256，不展示本机绝对路径、原始聊天内容、模型 API Key、渠道密钥或 MCP headers；冲突处理仍沿用已有安全策略，`target_modified` 默认跳过，目录 / 符号链接等非普通文件以 `unsafe_existing_entity` 跳过，避免写穿或覆盖非预期文件。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Obsidian 冲突详情局部测试 | 通过 | `flutter test test/core/obsidian_vault_export_service_test.dart test/shared/settings_page_font_scale_test.dart` 输出 `+12: All tests passed!`，覆盖同步冲突检测、附件链接重写和冲突详情组件展示冲突数量、相对路径、中文原因与短 SHA |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.9s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 2.9s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+227: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| Obsidian 增量同步性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_sync.sh` 输出 `obsidian_vault_sync_benchmark files=200 attachments=200 first_sync_ms=392 second_sync_ms=267 created=400 unchanged=400 conflicts=0 vault_files=404 bytes=388724`；冲突详情界面不在无冲突同步热路径上 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；`debugPrint` / `print` 扫描无命中；实现文件、当前需求 / 数据同步文档和 `AGENTS.md` 绝对路径扫描无命中；本验证基线仅保留历史 codebase-memory 命令中的仓库路径记录；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2426，边 6048 |

结论：Obsidian 单向同步现在不仅能安全跳过冲突，也能把冲突原因解释给用户，便于后续手动处理或升级到可选覆盖 / 双向同步。长期剩余项仍包括 Obsidian 可选覆盖策略、双向同步、更完整冲突处理流程、同名附件去重、audio 原文件可选同步，以及 Notion、语雀、思源笔记同步。

## 61. 2026-06-27 Obsidian 可选覆盖冲突策略 v1 复验

本次在冲突详情界面基础上，补齐用户可控的覆盖策略。设置页点击「同步到 Obsidian」后，不再直接进入文件夹选择，而是先弹出「Obsidian 同步策略」：默认「安全同步」会继续跳过用户在 Obsidian 中手动修改过的文件；只有用户明确选择「覆盖冲突」时，才把 SimiChat 当前档案写回普通文件冲突。目录、符号链接等非普通目标仍按 `unsafe_existing_entity` 冲突跳过，避免写穿或覆盖非预期文件。

安全与一致性边界：覆盖策略不改变默认行为，默认仍保护 Obsidian 侧用户改动；覆盖模式只通过用户显式按钮触发，只覆盖普通文件差异，不覆盖目录 / 符号链接，不暴露本机绝对路径、原始聊天内容、模型 API Key、渠道密钥或 MCP headers。同步状态和 Manifest 仍只记录 Vault 相对路径、类型、大小和 SHA-256。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Obsidian 覆盖策略局部测试 | 通过 | `flutter test test/core/obsidian_vault_export_service_test.dart test/shared/settings_page_font_scale_test.dart` 输出 `+14: All tests passed!`，覆盖服务层 `overwriteConflicts: true` 只在显式请求时覆盖普通文件目标、默认冲突仍跳过、符号链接仍不写穿、设置页展示「安全同步 / 覆盖冲突」策略选择 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.4s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 2.9s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+229: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| Obsidian 增量同步性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_sync.sh` 输出 `obsidian_vault_sync_benchmark files=200 attachments=200 first_sync_ms=348 second_sync_ms=244 created=400 unchanged=400 conflicts=0 vault_files=404 bytes=388724`；策略弹窗不在无冲突同步服务热路径上 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；`debugPrint` / `print` 扫描无命中；目标文件绝对路径扫描无命中；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository {"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2428，边 6052 |

结论：Obsidian 单向同步现在具备三层冲突安全能力：默认安全跳过、冲突详情解释、用户显式选择后覆盖普通文件冲突。长期剩余项仍包括 Obsidian 双向同步、更完整冲突处理流程、同名附件去重、audio 原文件可选同步，以及 Notion、语雀、思源笔记同步。

## 62. 2026-06-27 Obsidian 原始音频附件可选同步 v1 复验

本次在 Obsidian 附件链接重写与可选覆盖策略基础上，补齐原始 audio 文件的显式同步能力。`ObsidianVaultExportService.exportVault` 与 `syncToExistingVault` 新增 `includeAudioAttachments` 开关；设置页复用「导出本地数据」弹窗里的「包含原始语音文件」开关：关闭时 Obsidian 只保留 `Audio Transcripts/` 语音转写稿，开启时将 audio 原文件复制到 `Attachments/<message-id>/<attachment-id>-<safe-file-name>`，并把会话 Markdown 中对应附件项重写成 Obsidian wiki 链接。

安全与一致性边界：默认仍不复制原始音频到 Obsidian 附件目录，避免无感扩大导出范围；只有用户在导出弹窗显式开启「包含原始语音文件」时才复制 audio 原文件。附件复制继续拒绝非普通文件、跳过 exports 目录内文件，Manifest / 同步状态只记录 Vault 相对路径、大小和 SHA-256，不记录本机绝对路径、模型 API Key、渠道密钥或 MCP headers。同步冲突策略不变：默认安全跳过用户修改，覆盖冲突仍只对普通文件差异生效，目录 / 符号链接不写穿。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Obsidian 原始音频附件局部测试 | 通过 | `flutter test test/core/obsidian_vault_export_service_test.dart test/shared/settings_page_font_scale_test.dart` 已在本轮实现后通过；新增用例覆盖 `includeAudioAttachments: true` 后 audio 原文件进入 `Attachments/m1/audio_1-voice.m4a`、会话 Markdown 重写为 `[[Attachments/m1/audio_1-voice.m4a|voice.m4a]]`，Manifest 不泄露源设备绝对路径 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.3s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 2.8s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+230: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| Obsidian 增量同步性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_sync.sh` 输出 `obsidian_vault_sync_benchmark files=200 attachments=200 first_sync_ms=404 second_sync_ms=258 created=400 unchanged=400 conflicts=0 vault_files=404 bytes=388724`；默认无冲突同步热路径保持在 200 Markdown + 200 附件量级，audio 显式开启后复用同一附件复制与 wiki 链接重写路径 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；`debugPrint` / `print` 扫描无命中；目标文件绝对路径扫描无命中；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository ...` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2429，边 6050 |

结论：SimiChat 的 Obsidian 单向同步现在具备“会话 Markdown + 语音转写 Markdown + 非语音附件 + 用户显式开启的原始音频附件 + wiki 链接重写 + 冲突安全策略”的基础闭环。长期剩余项仍包括 Obsidian 双向同步、更完整冲突处理流程、同名附件更精细去重，以及 Notion、语雀、思源笔记同步。

## 63. 2026-06-27 Obsidian 同名附件链接精确去重 v1 复验

本次补齐 Obsidian 附件链接重写中的同名附件边界：同一消息内如果存在多个相同 `fileName` 的附件，`ObsidianVaultExportService` 不再把所有 Markdown 附件项都指向第一条附件，而是按会话 Markdown `attachments` 列表出现顺序逐条消耗对应的 `Attachments/<message-id>/<attachment-id>-<safe-file-name>` 路径。例如两个 `duplicate.png` 会分别链接到 `Attachments/m1/att_1-duplicate.png` 和 `Attachments/m1/att_2-duplicate.png`。

安全与一致性边界：本次只改变链接选择逻辑，不扩大附件读取范围；附件复制仍只处理可安全读取的普通文件，继续跳过符号链接、缺失文件和旧 `exports/` 目录。若 Markdown 中同名附件项数量超过实际可复制附件数量，额外项保持原文，不伪造链接。Manifest / 同步状态仍只记录 Vault 相对路径、大小和 SHA-256，不记录本机绝对路径、模型 API Key、渠道密钥或 MCP headers。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Obsidian 同名附件局部测试 | 通过 | `flutter test test/core/obsidian_vault_export_service_test.dart test/shared/settings_page_font_scale_test.dart` 输出 `+16: All tests passed!`，新增覆盖同一消息两个 `duplicate.png` 分别复制到 `att_1-duplicate.png` / `att_2-duplicate.png`，会话 Markdown 按出现顺序生成两个不同 wiki 链接，且不泄露本机绝对路径 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.7s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 2.8s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+231: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| Obsidian 增量同步性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_sync.sh` 输出 `obsidian_vault_sync_benchmark files=200 attachments=200 first_sync_ms=341 second_sync_ms=222 created=400 unchanged=400 conflicts=0 vault_files=404 bytes=388724`；同名附件链接选择是线性计数，不改变同步文件数量级 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；`debugPrint` / `print` 扫描无命中；实现文件、当前需求 / 数据同步文档和 `AGENTS.md` 绝对路径扫描无命中；本验证基线仅保留历史 codebase-memory 命令中的仓库路径记录；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository ...` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2430，边 6040 |

结论：Obsidian 单向同步的附件链路现在覆盖普通附件、可选原始音频、冲突安全策略和同名附件精确链接。长期剩余项收敛到 Obsidian 双向同步、更完整冲突处理流程、同名附件在 Obsidian 侧更清晰的展示命名，以及 Notion、语雀、思源笔记同步。

## 64. 2026-06-27 Obsidian stale 文件安全清理 v1 复验

本次补齐 Obsidian 单向同步的源端删除收敛能力。`syncToExistingVault` 会读取 `SimiChat-Sync-State.json` 中上次成功同步的会话 / 语音转写 / 附件路径，并与本次源端待同步列表比较：如果某个旧路径不再出现在当前源数据中，且目标文件内容仍等于上次同步 SHA，则自动删除该目标文件并计入 `deletedCount` / `sync_deleted`；如果目标文件已被用户在 Obsidian 中修改，则记录 `source_removed_target_modified` 冲突并保留文件。

安全与一致性边界：清理只作用于此前由 SimiChat 写入并记录在同步状态里的相对路径，不扫描或删除用户 Vault 其他文件。删除前会确认目标仍是普通文件并且 SHA-256 等于上次同步值；目录、符号链接等非普通实体以 `stale_unsafe_existing_entity` 冲突跳过；目标被用户改动时保留并提示冲突，避免误删用户在 Obsidian 侧想保留的内容。同步状态和 Manifest 仍不记录本机绝对路径、模型 API Key、渠道密钥或 MCP headers。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Obsidian stale 清理局部测试 | 通过 | `flutter test test/core/obsidian_vault_export_service_test.dart test/shared/settings_page_font_scale_test.dart` 输出 `+18: All tests passed!`，覆盖源文件删除后清理未修改旧目标文件、`sync_deleted: 1` / `deleted_count` 写入索引和状态、目标已被用户修改时记录 `source_removed_target_modified` 并保留 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.4s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 3.8s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+233: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| Obsidian 增量同步性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_sync.sh` 输出 `obsidian_vault_sync_benchmark files=200 attachments=200 first_sync_ms=374 second_sync_ms=231 created=400 unchanged=400 conflicts=0 vault_files=404 bytes=388786`；stale 清理只遍历同步状态差集，不改变无删除场景文件数量级 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；`debugPrint` / `print` 扫描无命中；实现文件、设置页、当前需求 / 数据同步文档和 `AGENTS.md` 绝对路径扫描无命中；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository ...` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2432，边 6046 |

结论：Obsidian 单向同步现在可以处理新增、更新、未变、冲突、用户显式覆盖、同名附件精确链接、原始音频可选同步，以及源端删除后的安全清理。长期剩余项继续聚焦 Obsidian 双向同步、跨设备冲突合并流程、Notion / 语雀 / 思源笔记同步和真机长会话验证。

## 65. 2026-06-27 Obsidian stale 冲突详情解释 v1 复验

本次补齐上一轮 stale 文件安全清理产生的新冲突原因在设置页中的可解释性。`ObsidianSyncConflictDetails` 顶部说明从“没有覆盖 Obsidian 中的文件”调整为“没有覆盖或删除 Obsidian 中的文件”；`describeObsidianSyncConflictReason` 新增 `source_removed_target_modified` 与 `stale_unsafe_existing_entity` 中文说明，分别解释“源文件已删除但 Obsidian 侧目标被用户修改，因此保留”和“源文件已删除但目标不是普通文件，因此跳过清理”。

安全与一致性边界：本次只修改用户可见说明，不改变同步 / 删除策略；冲突详情仍只展示 Vault 相对路径、原因代码和短 SHA，不展示本机绝对路径、原始聊天内容、模型 API Key、渠道密钥或 MCP headers。新增说明确保用户知道 SimiChat 在冲突场景没有覆盖或删除 Obsidian 中的文件。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Obsidian stale 冲突详情局部测试 | 通过 | `flutter test test/shared/settings_page_font_scale_test.dart test/core/obsidian_vault_export_service_test.dart` 输出 `+18: All tests passed!`，覆盖 `target_modified`、`unsafe_existing_entity`、`source_removed_target_modified`、`stale_unsafe_existing_entity` 四类原因中文解释、原因代码和短 SHA 展示 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.6s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 3.3s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+233: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| Obsidian 增量同步性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_sync.sh` 输出 `obsidian_vault_sync_benchmark files=200 attachments=200 first_sync_ms=370 second_sync_ms=220 created=400 unchanged=400 conflicts=0 vault_files=404 bytes=388786`；冲突说明不在无冲突同步热路径上 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；`debugPrint` / `print` 扫描无命中；实现文件、当前需求 / 数据同步文档和 `AGENTS.md` 绝对路径扫描无命中；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository ...` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2433，边 6059 |

结论：Obsidian 单向同步的冲突反馈现在覆盖正常目标修改、非普通目标、源端删除后目标已修改、源端删除后目标非普通实体四类原因，避免用户只看到内部 reason。长期剩余项继续聚焦 Obsidian 双向同步、跨设备冲突合并流程、Notion / 语雀 / 思源笔记同步和真机长会话验证。

## 66. 2026-06-27 语音转写状态 / 失败脱敏导出 v1 复验

本次补齐语音转写 Markdown sidecar 的生产化状态表达与失败脱敏。`AudioTranscriptArchive` 新增 `pending` / `ready` / `empty` / `failed` 四类状态：未配置或尚未执行 STT 时为 `pending`，有转写正文时为 `ready`，STT 完成但未识别到文字时为 `empty`，STT 异常时为 `failed`。`AudioTranscriptionService` 在 STT 失败后会更新同一个 `audio_transcripts/<message-id>/<attachment-id>.md`，并把异常文本脱敏后写入稿件；未知异常对外仍返回统一「语音转文字失败」。

安全与一致性边界：语音转写稿件只记录 message id、attachment id、文件名、大小、状态、转写正文或脱敏错误说明，不记录完整本机音频路径。失败脱敏覆盖本机绝对路径、Windows 路径、`sk-...` 形态密钥、Bearer token、常见 `api_key` / `token` / `secret` / `authorization` 参数，以及带查询串的 URL。标准 `.tar.gz` 导出和 Obsidian Vault 导出 / 同步均直接复制 `audio_transcripts/` 中的 Markdown，因此会继承明确状态与脱敏结果。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| 语音转写 / 导出局部测试 | 通过 | `flutter test test/core/audio_transcript_archive_test.dart test/core/audio_transcription_service_test.dart test/core/data_export_service_test.dart test/core/obsidian_vault_export_service_test.dart` 输出 `+28: All tests passed!`；覆盖 `pending`、`ready`、`empty`、`failed`，失败稿件脱敏，以及 `.tar.gz` / Obsidian 导出中不泄露本机路径、密钥、令牌或 URL |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.8s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 3.1s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+238: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| 数据导出性能基线脚本 | 通过 | `scripts/benchmark_data_export.sh` 输出 `data_export_benchmark files=200 export_ms=115 manifest_files=200 uncompressed_bytes=341504 compressed_bytes=14564`；语音转写状态只是 Markdown 内容生成，不改变导出文件数量级 |
| Obsidian 增量同步性能基线脚本 | 通过 | `scripts/benchmark_obsidian_vault_sync.sh` 输出 `obsidian_vault_sync_benchmark files=200 attachments=200 first_sync_ms=400 second_sync_ms=263 created=400 unchanged=400 conflicts=0 vault_files=404 bytes=388786`；同步继续按既有 Markdown / 附件复制路径工作 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；新增生产代码 `debugPrint` / `print` 扫描无命中；生产代码和文档绝对路径扫描无命中；测试中的 `/Users/sanbo`、`/tmp`、`sk-secret-token`、`token=raw` 均为脱敏断言夹具；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository ...` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2443，边 6076 |

结论：语音转写 sidecar 现在不再只有“等待 / 有正文”两种模糊状态，导出到压缩包或 Obsidian 时可明确区分未转写、成功、空结果和失败；失败场景也不会把本机音频路径、密钥、令牌或 URL 带入用户可分享的 Markdown。长期剩余项仍包括真实 STT 厂商接入、语音播报、录音真机长时间 / 中断场景复验，以及更完整的多模态画像提取。


## 67. 2026-06-27 聊天音频卡片转写状态展示 v1 复验

本次在“语音转写状态 / 失败脱敏导出 v1”基础上，补齐聊天消息内 audio 附件卡片的本地转写状态可见性。`ChatPage` 会为 audio 附件读取 `audio_transcripts/<message-id>/<attachment-id>.md` sidecar 状态，并把状态传入 `MessageBubble`；卡片展示“等待转写 / 转写完成 / 未识别到文字 / 转写失败”。`ChatProvider` 在写入转写草稿、STT 完成或 STT 失败后失效对应状态缓存，确保用户在聊天列表中直接看到最新结果。

安全与隐私边界：消息卡片只展示状态标签，不展示本机音频绝对路径、sidecar 路径、转写失败原始异常、API Key、Bearer token、URL 查询串或用户可分享的本地文件地址。`failed` 状态只使用已脱敏的 sidecar 语义；UI 语义标签同样只包含附件名、大小和状态，不包含完整本机路径。生产目标文件已去除调试输出，避免把转写错误或路径写入日志。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| 聊天音频卡片状态局部测试 | 通过 | `flutter test test/core/audio_transcript_archive_test.dart test/shared/message_bubble_attachment_test.dart test/benchmark/audio_transcript_status_benchmark.dart` 输出 `+10: All tests passed!`；覆盖 sidecar 状态读取、消息气泡状态文案、失败态样式与语义标签不展示完整本机路径 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found!` |
| 全量测试 | 通过 | `flutter test` 输出 `+240: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!`，脚本内静态分析同样通过 |
| 状态读取性能基线 | 通过 | `scripts/benchmark_audio_transcript_status.sh` 输出 `audio_transcript_status_benchmark files=500 read_ms=117 ready=250 empty=250`；500 个 sidecar 状态读取保持在轻量本地文件扫描范围内 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；生产目标 `debugPrint` / `print` 扫描无命中；目标生产代码与当前功能文档（不含历史验证基线命令记录）绝对路径和本地文件 URL 形态扫描无命中；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2453，边 6120；完整索引刷新已执行 |

结论：聊天音频附件现在不需要进入导出包或 Obsidian 才能知道转写状态，移动端对话列表内即可直观看到等待、成功、空结果或失败。长期剩余项仍包括真实 STT 厂商接入与配置入口、转写稿详情查看 / 复制、语音播报、真机长时间录音 / 中断场景复验，以及声音 / 图像 / 表情多模态画像提取。


## 68. 2026-06-27 OpenAI 兼容 STT 引擎与配置入口 v1 复验

本次在语音附件、录音、转写 sidecar 与聊天音频卡片状态展示基础上，补齐真实 STT 自动转写的最小生产闭环。新增 `OpenAiCompatibleSpeechToTextEngine`：对本地归档音频执行 OpenAI 兼容 `/v1/audio/transcriptions` multipart 请求，提交模型与文件字段，解析 `text` / `transcript` / `output_text` 响应，并继续复用 `AudioTranscriptionService` 把结果写回 `audio_transcripts/<message-id>/<attachment-id>.md`。设置页“语音输入”弹窗可启用 / 关闭 STT，配置 Base URL、模型与 API Key；Provider 会在配置完整且密钥可解密时生成默认 `SpeechToTextEngine`，发送或录制 audio 后自动转写。

安全与隐私边界：STT 默认关闭；只有用户在设置页显式启用并填写 API Key 后，音频才会外发到配置的 HTTP(S) STT 服务。API Key 使用现有 `KeyEncryptor` 加密写入本机 SharedPreferences，不进入结构化备份、数据导出包、聊天 Markdown、转写 sidecar、UI 文案或日志；配置弹窗不回显明文密钥，留空保存会保留已有密钥。STT Base URL 仅允许 HTTP(S)，`file://` 等本地文件 URL 会被拒绝。厂商失败响应不会原样展示或写入 sidecar，只转换为安全错误，避免泄露本机音频路径、密钥或原始厂商错误正文。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| STT 引擎 / Provider / 设置页局部测试 | 通过 | `flutter test test/core/openai_speech_to_text_engine_test.dart test/shared/audio_transcription_provider_test.dart test/shared/settings_page_voice_input_test.dart` 输出 `+8: All tests passed!`；覆盖 multipart 请求、响应解析、HTTP(S) Base URL 校验、失败脱敏、API Key 加密持久化、结构化备份排除 STT 配置、设置页已配置 / 未配置状态和密钥不回显 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 4.0s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 2.9s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+246: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| STT 配置性能基线 | 通过 | `scripts/benchmark_stt_config.sh` 输出 `stt_config_benchmark iterations=100 load_ms=3314 engines=100`；配置加载、密钥解密与引擎创建属于设置 / 启动级轻量操作，不在每帧 UI 热路径 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；生产目标 `debugPrint` / `print` 扫描无命中；目标生产代码、当前功能文档和 `AGENTS.md` 绝对路径 / 本地文件 URL 扫描无命中；测试中的 `file:///tmp/stt` 仅用于验证非 HTTP(S) Base URL 被拒绝；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2479，边 6210 |

结论：SimiChat 语音链路现在从“本地录音 + 转写草稿 + 状态展示”推进到“用户可配置真实 OpenAI 兼容 STT 自动转写”。长期剩余项包括更多 STT 厂商预设、转写稿详情查看 / 复制、语音播报、真机长时间录音 / 网络中断场景复验，以及声音 / 图像 / 表情多模态画像提取。


## 69. 2026-06-27 音频转写稿详情查看 / 复制 v1 复验

本次在聊天音频卡片转写状态展示与 OpenAI 兼容 STT 自动转写基础上，补齐用户查看和复制本地转写稿的移动端闭环。`AudioTranscriptArchive.readDetails` 会从 `audio_transcripts/<message-id>/<attachment-id>.md` 中读取状态、正文和转写状态说明；只有 `ready` 且存在正文时才暴露可复制文本。`MessageBubble` 的 audio 附件卡片增加“查看 / 复制转写稿”动作；`ChatPage` 点击后读取本地 sidecar，弹出“语音转写详情”对话框，展示文件名、状态和脱敏正文 / 状态说明，并在可复制时提供“复制正文”。

安全与隐私边界：详情弹窗不展示 sidecar 本机绝对路径，也不展示音频 localPath；失败状态只显示已经由 `AudioTranscriptArchive` 脱敏的错误说明，避免泄露本机路径、API Key、Bearer token、URL 查询串或厂商原始错误正文。`empty` / `failed` / `pending` 均不提供复制正文，防止复制占位文案。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| 音频转写详情局部测试 | 通过 | `flutter test test/core/audio_transcript_archive_test.dart test/shared/message_bubble_attachment_test.dart` 输出 `+12: All tests passed!`；覆盖 `readDetails` 读取 ready 正文、failed 状态不暴露可复制正文、脱敏路径，以及音频卡片“查看 / 复制转写稿”动作 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 3.9s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 2.8s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+249: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| 音频转写详情读取性能基线 | 通过 | `flutter test test/benchmark/audio_transcript_details_benchmark.dart` 输出 `audio_transcript_details_benchmark files=300 read_ms=98 copyable=300`；详情读取是用户点击后的按需本地 sidecar 解析，不在消息列表每帧热路径上 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；生产目标 `debugPrint` / `print` 扫描无命中；目标生产代码、当前功能文档和 `AGENTS.md` 绝对路径 / 本地文件 URL 扫描无命中；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2490，边 6242 |

结论：语音链路现在支持从录音 / 语音附件进入本地转写、状态展示、详情查看和正文复制；用户无需导出文件即可在聊天内使用转写结果。长期剩余项包括更多 STT 厂商预设、语音播报、真机长时间录音 / 网络中断场景复验，以及声音 / 图像 / 表情多模态画像提取。


## 70. 2026-06-27 语音播报 TTS v1 复验

本次在移动端录音、语音转写 sidecar、OpenAI 兼容 STT 和转写详情查看 / 复制基础上，补齐 assistant 回复的语音播报闭环。新增 `OpenAiCompatibleTextToSpeechEngine`，对 OpenAI 兼容 `/v1/audio/speech` 发起 JSON 请求并接收 mp3 bytes；新增 `TextToSpeechService`，对待播报文本做空白归一、4000 字截断和音色格式校验，把生成音频写入应用临时目录 `tts_audio/`；新增 `text_to_speech_provider.dart`，在设置页保存启用状态、Base URL、模型、音色和加密 API Key；消息气泡只在 assistant 非空文本下展示“语音播报”按钮，点击后调用 TTS 服务并通过 `simichat/audio_player` MethodChannel 播放。

安全与隐私边界：TTS 默认关闭；只有用户在设置页显式启用并填写 API Key 后，assistant 文本才会外发到配置的 HTTP(S) TTS 服务。TTS API Key 使用 `KeyEncryptor` 加密保存在本机 SharedPreferences，不进入结构化备份、数据导出包、聊天 Markdown、日志或 UI 明文；配置弹窗不回显明文密钥。TTS Base URL 仅允许 HTTP(S)，`file://` 等本地 URL 会被拒绝。Android `MediaPlayer` 与 iOS `AVAudioPlayer` 原生通道会校验播放文件存在且位于应用私有目录内，避免任意路径播放；厂商失败响应不会原样展示，避免泄露密钥、本机路径或原始响应正文。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| TTS 局部测试 | 通过 | `flutter test test/core/openai_text_to_speech_engine_test.dart test/core/text_to_speech_service_test.dart test/shared/text_to_speech_provider_test.dart test/shared/message_bubble_tts_test.dart test/shared/settings_page_voice_input_test.dart test/core/microphone_permission_manifest_test.dart` 输出 `All tests passed!`；覆盖 `/v1/audio/speech` 请求、bytes 响应、HTTP(S) Base URL 校验、失败脱敏、文本截断、音色校验、临时 mp3 写入、播放器调用、API Key 加密持久化、结构化备份排除 TTS 配置、设置页已配置 / 未配置状态、assistant 播报按钮展示规则和原生通道字符串 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found! (ran in 5.2s)`；移动端 smoke 脚本内再次输出 `No issues found! (ran in 3.3s)` |
| 全量测试 | 通过 | `flutter test` 输出 `+266: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 `+4: All tests passed!` |
| TTS 配置性能基线 | 通过 | `scripts/benchmark_tts_config.sh` 输出 `tts_config_benchmark iterations=100 load_ms=4660 engines=100 services=100`；配置加载、密钥解密、引擎和服务创建属于设置 / 启动级操作，不在每帧 UI 热路径 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 敏感密钥字面量扫描无命中；TTS 生产目标 `debugPrint` / `print` 扫描无命中；生产代码、当前功能文档和 `AGENTS.md` 绝对路径 / `file://` 扫描无命中；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2561，边 6486 |

结论：SimiChat 语音链路现在覆盖语音录入、STT 自动转写、转写状态展示、详情查看 / 复制和 assistant 文本 TTS 播报。长期剩余项包括更多 STT / TTS 厂商预设、真机长时间录音 / 播放、网络中断 / 来电打断场景复验，以及声音 / 图像 / 表情多模态画像提取。


## 71. 2026-06-27 TTS 播放停止控制 v1 复验

本次在 OpenAI 兼容 TTS 语音播报 v1 基础上，补齐用户可中断的播放控制。`TextToSpeechService.stop()` 统一委托 `AudioPlayerPlatform.stop()`；`ChatPage` 记录当前播报消息和生成中状态，播报前先停止上一段原生播放，生成中在消息操作区显示禁用的“正在生成语音”，播放开始后当前 assistant 回复切换为“停止播报”，用户点击后调用 `audioPlayerProvider.stop()` 并清理当前播报状态。`MessageBubble` 新增 `isSpeaking` / `isPreparingSpeech` / `onStopSpeaking`，确保用户消息和非当前消息不展示停止按钮。

安全与隐私边界：本次不扩大任何外发范围，不新增密钥存储。停止操作只调用既有原生 `simichat/audio_player` 的 `stop` 方法，不接收文件路径、不读取本地文件、不写日志、不触碰导出包或 Markdown。生成中状态不展示待播报文本、TTS API Key、临时 mp3 路径或厂商错误详情；失败仍走既有安全错误文案。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| TTS 停止控制局部测试 | 通过 | `flutter test test/core/text_to_speech_service_test.dart test/shared/message_bubble_tts_test.dart test/benchmark/tts_playback_control_benchmark.dart` 输出 `+11: All tests passed!`；覆盖 `TextToSpeechService.stop()` 委托播放器、assistant 播放中展示停止按钮、生成中展示禁用状态、用户 / 空消息不展示播报按钮，以及 1000 次停止控制 benchmark |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found!`；`scripts/smoke_mobile_main_flow.sh` 内置 analyze 复跑同样无问题 |
| 全量测试 | 通过 | `flutter test` 输出 `+269: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 4 个 smoke 全部通过，并复跑 analyze 无问题 |
| TTS 播放控制性能基线 | 通过 | `test/benchmark/tts_playback_control_benchmark.dart` 输出 `tts_playback_control_benchmark iterations=1000 stop_ms=6 stops=1000`；`scripts/benchmark_tts_playback_control.sh` 复跑输出 `iterations=1000 stop_ms=5 stops=1000`；停止控制是轻量本地状态与播放器委托，不在网络或文件写入热路径 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 全仓高置信密钥字面量扫描无命中；TTS 本切片生产目标 `debugPrint` / `print`、本机绝对路径和 `file://` 扫描无命中；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository '{"repo_path":"/Users/sanbo/code/simichat","mode":"full","persistence":true}'` 输出项目 `Users-sanbo-code-simichat` 已 indexed，节点 2574，边 6503；`index_status` 输出 `status: ready` |

结论：TTS 播报从“能生成并播放”补齐为“用户可看到生成 / 播放状态并主动停止”，更接近可长期使用的移动端语音体验。长期剩余项仍包括更多 STT / TTS 厂商预设、真机长时间播放、网络中断 / 来电打断场景复验，以及声音 / 图像 / 表情多模态画像提取。

## 72. 2026-06-27 TTS 播放完成事件回传 v1 复验

本次在 TTS 播放停止控制基础上，补齐自然播放结束后的状态闭环。`AudioPlayerPlatform` 新增 `events` 流和 `AudioPlaybackEvent`，统一解析原生 `playbackCompleted` / `playbackStopped` / `playbackError` 回调；`MethodChannelAudioPlayer` 在监听事件时注册 MethodChannel 回调。Android `MainActivity` 在 `MediaPlayer` 完成、停止、错误时回传当前播放路径；iOS `AppDelegate` 实现 `AVAudioPlayerDelegate`，在播放完成或解码错误时回传同类事件。`ChatPage` 订阅 `audioPlayerProvider.events`，只在事件路径匹配当前 TTS 临时音频时清理 `_speakingMessageId` / `_speakingAudioPath` / `_isPreparingSpeech`，避免旧播放或新播放切换时误清理。

安全与隐私边界：本次不新增外部网络调用、不新增密钥存储、不扩大导出范围。原生事件只在应用内部 MethodChannel 传递应用私有目录下的当前播放路径，不展示到 UI、不写日志、不进入 Markdown / 导出包 / 结构化备份；ChatPage 仅用路径做当前播报匹配，匹配后立即清理状态。原生路径校验仍沿用既有播放入口：Android / iOS 只接受应用私有目录内普通文件。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| TTS 播放事件局部测试 | 通过 | `flutter test test/core/text_to_speech_service_test.dart test/shared/chat_page_tts_playback_event_test.dart test/shared/message_bubble_tts_test.dart test/benchmark/tts_playback_control_benchmark.dart test/benchmark/tts_playback_event_benchmark.dart` 输出 `+15: All tests passed!`；覆盖服务层事件暴露、原生 MethodCall 事件解析、聊天页收到完成事件后自动恢复播报按钮、消息气泡 TTS 状态和停止控制 benchmark |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found!`；`scripts/smoke_mobile_main_flow.sh` 内置 analyze 复跑同样无问题 |
| 全量测试 | 通过 | `flutter test` 输出 `+272: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 4 个 smoke 全部通过，并复跑 analyze 无问题 |
| TTS 播放事件性能基线 | 通过 | `scripts/benchmark_tts_playback_event.sh` 输出 `tts_playback_event_benchmark iterations=10000 parse_ms=12 parsed=10000`；原生事件解析是轻量本地 Map 解析，不在网络或文件写入热路径 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 全仓高置信密钥字面量扫描无命中；TTS 播放事件生产目标日志输出、本机绝对路径和 `file://` 扫描无命中；`git diff --check` 无输出 |

结论：TTS 播放状态现在覆盖“生成中、播放中、用户停止、自然完成、原生错误”五类状态闭环，避免自然播放结束后聊天气泡仍显示“停止播报”。长期剩余项继续聚焦更多 STT / TTS 厂商预设、真机长时间播放、来电 / 音频焦点中断场景复验，以及声音 / 图像 / 表情多模态画像提取。

## 73. 2026-06-27 STT/TTS 厂商预设 v1 复验

本次在 OpenAI 兼容 STT / TTS 配置入口基础上，补齐语音厂商预设第一版，降低“只输入 Key 即可接入”的配置成本。新增 `SpeechProviderPreset` 与 `speech_provider_preset.dart`，集中维护 OpenAI 官方、Groq STT、自定义 OpenAI 兼容三类预设；设置页“语音输入”和“语音播报”弹窗新增“厂商预设”下拉，选择后自动填充 Base URL、STT 模型、TTS 模型和音色。已有配置推断会归一 `/v1` 后缀，避免用户填入 OpenAI 兼容完整路径时无法识别预设。TTS 请求字段同步修正为 OpenAI 兼容的 `response_format: mp3`。

安全与隐私边界：预设只保存公开厂商名称、公开 Base URL、模型名、音色名和文档链接，不包含 API Key、Bearer token、用户文本、音频内容或本机路径。选择预设不会自动启用外发；只有用户显式启用 STT / TTS 并填写 API Key 后，语音或 assistant 文本才会发送到对应服务。API Key 仍沿用本机加密保存策略，不进入结构化备份、导出包、聊天 Markdown、日志或 UI 明文。设置页示例文案不再使用本机绝对路径样例，避免安全扫描和用户误解。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| STT/TTS 预设局部测试 | 通过 | `flutter test test/core/speech_provider_preset_test.dart test/shared/audio_transcription_provider_test.dart test/shared/text_to_speech_provider_test.dart test/shared/settings_page_voice_input_test.dart test/core/openai_text_to_speech_engine_test.dart test/benchmark/speech_provider_preset_benchmark.dart` 输出 `+20: All tests passed!`；文档同步和示例文案调整后复跑 `flutter test test/core/speech_provider_preset_test.dart test/shared/settings_page_voice_input_test.dart test/core/openai_text_to_speech_engine_test.dart` 输出 `+12: All tests passed!`；覆盖 OpenAI / Groq / 自定义预设、`/v1` 后缀归一、Provider 保存、设置页预设展示、选择 Groq STT 自动填充和 TTS `response_format` 字段 |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found!`；移动端 smoke 脚本内置 analyze 复跑同样无问题 |
| 全量测试 | 通过 | `flutter test` 输出 `+277: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 4 个 smoke 全部通过，并复跑 analyze 无问题 |
| STT/TTS 预设性能基线 | 通过 | `test/benchmark/speech_provider_preset_benchmark.dart` 输出 `speech_provider_preset_benchmark iterations=10000 infer_ms=25 matches=20000`；`scripts/benchmark_speech_provider_preset.sh` 复跑输出 `infer_ms=24 matches=20000`；预设推断是轻量字符串归一和列表匹配，不在网络或文件写入热路径 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 全仓高置信密钥字面量扫描无命中；本切片生产目标 `debugPrint` / `print` 扫描无命中；本切片生产代码、当前功能文档的本机绝对路径 / `file://` 扫描无命中；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2626，边 6663 |

结论：语音链路从“可手动配置 OpenAI 兼容 STT / TTS”推进到“常用语音服务可通过预设快速填充”，更贴近用户只输入 Key 即用的目标。长期剩余项继续聚焦更多非 OpenAI 兼容语音厂商、真实移动端长音频 / 长时间播报、网络中断 / 来电 / 音频焦点打断场景，以及声音 / 图像 / 表情多模态画像提取。

## 74. 2026-06-27 OpenAI Relay 健康检查端点 v1 复验

本次在个人接口中转能力基础上，补齐外部客户端 / 用户排障所需的轻量健康检查端点。`OpenAiCompatibleRelaySession` 新增 `GET /health` 与 `GET /v1/health`，继续沿用本地 Bearer 令牌鉴权；鉴权通过后只返回 `object: simichat.relay.health`、`status: ok`、当前聊天并发数、并发上限和远端图片下载开关。健康检查不调用模型列表、不触发上游模型、不返回 Base URL、令牌、API Key、模型 id、prompt、消息内容或本机路径。设置页 Relay 摘要同步展示 `/health`，方便用户知道本地中转服务支持健康检查、模型列表和聊天补全三类路径。

安全与隐私边界：未授权访问 `/health` 与 `/v1/health` 仍返回 OpenAI 兼容鉴权错误，不暴露并发配置或运行状态；授权响应仅包含本地运行状态和布尔 / 数值配置，不包含任何用户内容、上游信息或密钥。健康检查请求会进入既有脱敏审计与用量统计，只记录方法、路径、状态码、错误码、授权状态、耗时和当前并发，不记录 token 或请求内容。文档中出现的 `file://` 仅用于描述被阻断的输入类型，不是可执行配置或泄露的本机路径。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay 健康检查局部测试 | 通过 | `flutter test test/core/openai_compatible_relay_server_test.dart test/benchmark/openai_relay_benchmark.dart` 输出 `+19: All tests passed!`；覆盖 `/health` 未授权不泄露状态、授权返回安全 JSON、`/v1/health` 兼容路径、健康检查不触发模型列表、审计路径记录和 100 次健康检查 benchmark |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found!`；移动端 smoke 脚本内置 analyze 复跑同样无问题 |
| 全量测试 | 通过 | `flutter test` 输出 `+278: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 4 个 smoke 全部通过，并复跑 analyze 无问题 |
| OpenAI Relay 性能基线 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_health_benchmark requests=100 total_ms=188 avg_ms=1.88`，同时 `openai_relay_benchmark requests=100 total_ms=220 avg_ms=2.20`；健康检查只读本地状态，不触发模型列表或上游网络 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 全仓高置信密钥字面量扫描无命中；本切片生产目标 `debugPrint` / `print` 扫描无命中；生产目标无本机绝对路径或 `file://`；当前文档无本机绝对路径，`docs/model-integration.md` 中的 `file://` 是安全边界说明；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2629，边 6679 |

结论：个人 OpenAI 兼容中转现在具备安全的本地健康检查能力，外部客户端和用户排障时可以先验证 Relay 是否可用，而无需调用模型列表或聊天补全。长期剩余项继续聚焦真机长时间运行验证、后台网络变化恢复、更多客户端兼容性测试，以及社交通道 / 外部平台接入。

## 75. 2026-06-27 OpenAI Relay CORS / 浏览器客户端兼容 v1 复验

本次在本地 OpenAI Relay 健康检查、模型列表和聊天补全基础上，补齐浏览器客户端常见的 CORS 预检兼容。Relay 所有响应继续带 `Cache-Control: no-store` 和 `X-Content-Type-Options: nosniff`，并新增 `Access-Control-Allow-Origin: *` 与必要的 `Vary` 头；`OPTIONS` 预检无需 Bearer 令牌，但只对 `/health`、`/v1/health`、`/v1/models`、`/v1/chat/completions` 返回 204，允许方法限定为 `GET / POST / OPTIONS`，允许请求头限定为 `authorization, content-type`。真实 `GET` / `POST` 请求没有放宽，仍必须携带正确 Bearer 令牌。

安全与隐私边界：CORS 预检不返回健康状态、模型列表、聊天内容、令牌、API Key、上游 Base URL 或本机路径；未知路径预检返回安全 `not_found`。浏览器页面即使能探测到预检成功，也无法在不知道 Bearer 令牌时调用真实接口。审计记录只保存方法、路径、状态码、错误码、授权状态、耗时和当前并发，不记录 Origin、token、prompt 或用户内容。

| 验证项 | 结果 | 关键输出 / 结论 |
| --- | --- | --- |
| Relay CORS 局部测试 | 通过 | `flutter test test/core/openai_compatible_relay_server_test.dart test/benchmark/openai_relay_benchmark.dart` 输出 `+20: All tests passed!`；覆盖无令牌 CORS 预检 204、安全 CORS 头、未知路径预检 `not_found`、真实响应 CORS 头、审计 code/path，以及 CORS benchmark |
| 全量静态分析 | 通过 | `flutter analyze` 输出 `No issues found!`；移动端 smoke 脚本内置 analyze 复跑同样无问题 |
| 全量测试 | 通过 | `flutter test` 输出 `+279: All tests passed!` |
| 移动端 smoke 脚本 | 通过 | `scripts/smoke_mobile_main_flow.sh` 输出 4 个 smoke 全部通过，并复跑 analyze 无问题 |
| OpenAI Relay 性能基线 | 通过 | `scripts/benchmark_openai_relay.sh` 输出 `openai_relay_health_benchmark requests=100 total_ms=177 avg_ms=1.77`、`openai_relay_cors_preflight_benchmark requests=100 total_ms=118 avg_ms=1.18`、`openai_relay_benchmark requests=100 total_ms=149 avg_ms=1.49`；CORS 预检只写本地响应头，不触发模型列表或上游网络 |
| Android 构建验证 | 通过 | `flutter build apk --debug` 输出 `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| iOS 构建验证 | 通过 | `flutter build ios --simulator --no-codesign` 输出 `✓ Built build/ios/iphonesimulator/Runner.app` |
| 安全扫描 | 通过 | 全仓高置信密钥字面量扫描无命中；本切片生产目标 `debugPrint` / `print` 扫描无命中；生产目标无本机绝对路径或 `file://`；当前新增验证记录无本机绝对路径；`git diff --check` 无输出 |
| 代码索引刷新 | 通过 | `codebase-memory-mcp cli index_repository` 完成；`index_status` 返回 `Users-sanbo-code-simichat` 状态 `ready`，节点 2635，边 6697 |

结论：个人 OpenAI 兼容中转现在可以被浏览器侧 OpenAI 兼容客户端安全预检和调用，更接近 Cherry Studio / DeepChat 类工具可直接接入的本地中转体验。长期剩余项继续聚焦真机长时间运行验证、更多客户端兼容性测试、局域网运行稳定性和社交通道接入。
