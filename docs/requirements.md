# SimiAIChat 产品需求总纲

> **定位**：人工智能聊天工具，最终形态 = 好友陪伴（虚拟朋友 / 智能助理）+ 数字孪生（镜像数字人，基于对话录入、长期记忆与用户资料蒸馏生成）。
>
> **技术栈**：Flutter，移动端优先；核心能力在移动端稳定后，再扩展桌面 / 电脑端。
>
> **权威来源**：项目目标、进度、待办、已完成事项和重要安排以根目录 `AGENTS.md` 为准；本文档沉淀产品需求与功能边界。
>
> **最后更新**：2026-08-19。
>
> **阅读边界**：本文记录产品目标和需求，不作为当前运行时验收结果。当前代码、验证命令和未补证项以 `current-status.md`、`verification-baseline-2026-08-08.md` 和根目录 `AGENTS.md` 为准；文中带日期的历史质量记录保留当时环境，不覆盖当前结论。

参考项目：

- [DeepChat](https://github.com/ThinkInAIXYZ/deepchat)：单独聊天、多模型、MCP、技能、远程控制等体验参考。
- [Cherry Studio](https://github.com/CherryHQ/cherry-studio)：模型渠道、模型中转、MCP、助手市场、备份同步、频道化连接器等能力参考。
- OpenClaw / 龙虾：社交平台接入、外部聊天通道、技能生态参考。
- ChatGPT Memory / Dreaming：长期记忆、画像归纳、夜间整理和智能陪伴体验参考。

---

## 一、项目目标（Vision）

打造一款以移动端为核心、移动端应用展示名为 **SimiAIChat** 的人工智能聊天工具，核心价值：

1. **无限接入**：支持市面所有人工智能模型厂商，仅需输入接口密钥即可使用；支持批量免费模型引导接入（日常“白嫖”模式）；单对话内支持随时切换模型。
2. **智能陪伴**：虚拟好友 / 智能助理，结合长期记忆系统，做到“了解你”的人工智能伴侣。
3. **数字孪生**：通过长期对话分析用户画像（作息 / 风格 / 思维），生成可代理用户思维的镜像数字人；支持声音、图像、表情等多模态信息，未来可扩展到直播。
4. **本地优先**：聊天记录本地存储，隐私安全，支持导出 / 同步到主流笔记工具。
5. **生态打通**：接入主流社交平台、技能市场、个人接口中转服务。

---

## 二、核心功能模块

### M1 — 多模型接入

- 支持所有主流人工智能厂商：OpenAI / Claude / Gemini / DeepSeek / 讯飞 / 通义 / 百度等，输入接口密钥即用；当前模型渠道预设已覆盖百度千帆 v2、讯飞星火 HTTP、Kimi / Moonshot AI、SiliconFlow、火山方舟、腾讯混元、Groq、Mistral AI、Together AI、Fireworks AI、xAI / Grok、Perplexity 与 DeepInfra OpenAI 兼容入口，并在设置页提示 / 一键复制建议模型名与厂商文档链接，保存渠道后也可在添加模型弹窗中一键填入推荐模型名，降低用户手动添加第一个模型的门槛。
- 支持同时接入 N 个模型 / 厂商 / 渠道。
- 支持批量免费模型引导接入，参考 GitHub 免费大模型列表生态。
- 单个对话内支持随时切换模型。
- 支持将多个模型聚合成个人接口中转服务器，参考 Cherry Studio，对外暴露统一接口转发；当前本地 OpenAI Relay 已支持健康检查、模型列表、聊天补全、Responses API 非流式 / 流式生命周期事件兼容和浏览器 CORS 预检。

### M2 — 记忆与上下文系统

- 聊天记录全部本地存储，默认不上云。
- 每个对话对应 1 个 Markdown 原始文件。
- 核心记忆点提取后常驻本地索引 / 内存（Key Points），每次对话带入检索结果。
- 跨对话内容支持快速检索，形成“本地聊天 ≈ 本地知识库”的体验。
- 无限上下文设计：本地永久保留完整原始对话；超过模型令牌预算时，把既有长期摘要与较旧轮次层级合并成一个有界滚动摘要，同时保留最新 10 条原文。聊天发送前按模型上下文窗口预算裁剪 system / 记忆 / Skills / MCP 工具说明和历史消息，固定为滚动摘要保留小预算并优先保留最新用户问题；接口返回超限时自动严格裁剪重试一次。该能力提供“本地长期会话”，不宣称上游模型单次请求拥有无限 token。
- 支持人工智能反思机制（Reflection），用于回答质量、长期偏好、用户画像和任务计划改进；当前已落地本地启发式反思 v1、未回复会话 / 会话追问压力 / 最后一问未答提醒、敏感标题降级与最后用户问题安全片段、最近 20 次反思历史、反思历史展开审阅 / 精确单条删除 / 清空入口，并可把少量高优先级行动项作为下一轮本机短期提示。可选模型增强反思 v1 默认关闭，用户显式开启后只把长度受限且经过敏感信息处理的摘要发送给默认已启用聊天模型，严格解析 JSON 并与本地安全结论合并；模型失败自动回退本地报告且不残留 pending。一个仓库外配置驱动的远程 OpenAI-compatible 模型已在三个 dayKey 的 72 条长会话上 3 / 3 通过；更多远程模型族和真实多日用户会话仍待质量评估。历史本地模型结果只保留为旧证据，按当前约束禁止再次启动或探测本地模型。

### M3 — Dreaming（夜间整理）

- 每晚定时对当天聊天内容进行整理总结；默认晚上运行，时间可配置。
- 对用户进行多轮画像分析，参考 ChatGPT 记忆 / Dreaming 机制。
- 提取用户任务画像、行为模式、思维风格、偏好和长期目标。
- 整理结果默认保存在本地，用户可查看、审阅、删除；当前已保留最近一次报告和最近 20 次有内容报告历史，并可在设置页查看历史日期、消息覆盖、展开审阅报告预览、删除单条报告和清空报告；整理失败会在本地 failed job 中可见，可重试，也可清除 / 忽略。

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

- 支持语音对话：语音文件附件、移动端录音输入、OpenAI 兼容 STT 自动转写配置入口、OpenAI 兼容 TTS 语音播报、STT/TTS 厂商预设 v1、播放停止控制、播放完成事件回传和 Android / iOS 原生播放通道已落地。
- 支持 ChatGPT 风格实时语音面板：可配置 OpenAI / xAI / 自定义 `wss://` Realtime 服务商、模型、音色、Bearer / ephemeral 凭据和 protocol prefix；支持 WebSocket 文本 fallback、输入转写、助手文本 / 转写、输出音频帧统计、停止回答、断开和加密配置持久化。Android 已接入 16 kHz mono PCM16 `AudioRecord` 采集、24 kHz mono PCM16 `AudioTrack` 播放和原生通道生命周期；iOS 原生 PCM 仍待接入。未连接或不支持平台时必须明确提示，普通麦克风继续使用“录音文件 → STT → 聊天”链路。
- 对话 Composer 采用 ChatGPT 风格单一输入区：支持一次选择多个图片、视频、音频、PDF 和普通文件；支持参考图生图、图片编辑、通用视频生成、声音合成、声音克隆、声音设计、语音识别成文字和已有音乐生成功能。视频 / 音乐 endpoint 与模型可按当前聊天渠道配置，不绑定单一厂商。2026-08-19 确认的本轮改造要求六类工具从 `+` 独立进入本次任务面板、以三态模型能力 / 独立 Options / provider-specific adapter 驱动，并新增“超长粘贴 → 应用私有文本附件 → 文件传输或文本 / 分批降级”和 Artifact MVP；目前大粘贴阈值 / 私有 UTF-8 附件 / 保真元数据与分块器基础已落地。会话草稿恢复 v1 已改为应用私有持久化索引：按会话保存短文本、附件恢复元数据与深度思考开关，快速输入写入按序收敛，冷启动 / 页面重建后仅恢复当前会话；大粘贴正文继续只保留在私有 `composer_drafts` 文件中，不写入偏好存储。文本附件走网络层降级时，单次内容只可使用模型输入预算的一半；其余预算保留给系统提示、历史与序列化误差，超过该安全值必须拒绝本次发送并保留草稿，不能静默截断文件。纯 `document` 文本附件超过单次安全预算时，当前实现会自动创建持久化 `ChunkedContentTask`：分析/总结/问答走 `mapReduce`，翻译/改写/润色/格式转换走严格顺序的 `orderedTransform`；中间结果只写任务表，最终只交付一条 assistant 消息。任务支持每段瞬态重试、停止、进程中断后保留中间结果并由用户“继续 / 从头重试”；混合了图片、音频或其它非文本附件的超预算输入继续明确拒绝，避免只处理其中的文本而遗漏素材。路径 A 已落地一项可验证的真实协议子集：已验证的 OpenAI Responses 模型发送普通 `document` 时使用 `input_file.file_data` 与安全 `filename`，并禁止同一正文重复进入 `input_text`；其它厂商 File API、服务端附件拒绝后的一次性降级和 Artifact 仍属后续阶段。完整阶段、字段、数据结构、测试与验收以 `docs/android-multimodal-long-content-artifact-prd.md` 和 `docs/android-multimodal-long-content-artifact-requirements-refinement.md` 为准。本轮不以新增音乐功能为验收项。
- 图片参数必须把四个维度独立建模：`quality` 是质量，`aspect_ratio` 是宽高比，`resolution` 是 `1K / 2K / 4K` 清晰度档位，`size` 是 `1024x1024 / 1536x1024 / 1024x1536` 等像素分辨率。UI、能力列表、请求序列化、失败重试和冷启动快照均不得把 `2K` 与 `1536x1024` 存入同一个字段。
- 生成结果必须回到同一条消息时间线：图片显示缩略图，视频支持本地播放与进度控制，音频 / 音乐显示播放卡片和文件信息，PDF / 普通文件显示安全文件卡片；生成失败不得写入半条消息。
- 视频 / 音乐等长任务必须持久化 provider job ID、轮询地址、deadline、提交时渠道模型和本地交付 ID；应用首帧后可按 lease 恢复 pending / running 任务。只有媒体文件、用户 / assistant 消息和附件事务全部提交后，任务才进入 `completed`；重复恢复不得创建第二套消息或附件。当前 schema 14、本地恢复和快照测试已通过，但 fake adapter / 内存 SQLite 不替代真实厂商异步协议、真机冷启动和媒体质量验证。
- 后台自动保存语音转文字稿件；设置页启用 OpenAI 兼容 STT 后可自动调用 `/v1/audio/transcriptions` 更新稿件；稿件明确标记 `pending` / `ready` / `empty` / `failed`，失败说明必须脱敏。
- 语音原始文件本地存储。
- 聊天音频卡片应直接展示本地转写状态，方便用户知道语音是否等待转写、已完成、空结果或失败；用户应能从音频卡片查看转写详情，并在转写完成时复制正文。
- 支持图片输入和多模态模型调用。
- 语音、图片、附件默认不上传；只有用户明确调用模型、启用 STT / TTS 或同步能力时才可外发；STT / TTS API Key 不进入结构化备份、导出包、日志或聊天 Markdown。

### M9 — 数据管理与同步

- 本地存储为主，支持数据压缩打包 + 系统分享导出；当前已完成本地 `.tar.gz` 压缩包、语音转写状态 / 失败脱敏导出、非语音附件原文件导出 / 导入 v1、本地聊天核心数据库备份 / 恢复 v1、Android / iOS 系统分享 v1、文件级安全导入 / 恢复 v1、结构化本地数据备份 / 恢复 v1、电脑端本地传输 v1、Obsidian Markdown Vault 导出 v1、Obsidian 现有 Vault 增量同步 v1、Obsidian 附件链接重写 v1、Obsidian 同步冲突详情界面 v1、Obsidian 可选覆盖冲突策略 v1、Obsidian 原始音频附件可选同步 v1、Obsidian 同名附件链接精确去重 v1、Obsidian stale 文件安全清理 v1 和 Obsidian stale 冲突详情解释 v1。
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

- 移动端应用展示名为 `SimiAIChat`；Android `applicationId` 与 iOS Bundle ID 使用 `top.simitalk.aichat`。
- 全局字体大小调节，布局必须自适应并保持可读性，不能变成一个屏幕只显示一两个字；当前量化范围为 90%–120%，5% 步进，默认 100%。
- 移动端聊天正文 / Markdown 正文默认 15sp、最大 18sp；Markdown H1/H2/H3 默认 22/20/18sp；代码默认 13sp；空状态品牌标题默认 26sp，禁止恢复到 40sp+ 的超大标题。
- 对话页 Markdown 渲染应兼容常见新旧格式：标准 Markdown、GitHub 风格扩展、表格、任务列表、脚注、删除线、`$...$` 行内公式、`$$...$$` 块级公式、旧式 `[[img:URL]]` 图片、Mermaid、Draw.io / mxGraph、HTML `<details>` 和旧式折叠块。
- HTML 音频 / 视频、Draw.io XML 等富内容默认走安全展示或源码预览，不执行内嵌 JavaScript。
- 支持主题换色。
- 支持 `ai-chat://` 深度链接 v1：可打开首页、新建会话、设置页、市场页或指定本地会话；非法 scheme / 非法会话 ID 不触发跳转。
- 移动端优先的界面设计，先确保小屏主链路稳定，再扩展桌面布局。
- 移动端聊天交互以用户确认的 ChatGPT 式信息架构和状态切换为基准：左侧会话抽屉（一级导航、置顶、最近、设置和新建聊天）、顶部“聊天 / 工作”分段切换、内容优先的空白消息区，以及固定在键盘安全区上方的单一 Composer。参考只限交互层级与行为，不复制 ChatGPT 品牌、图标、文案、会话数据或视觉资源；交互基准见 `docs/chatgpt-interaction-reference.md`，六项工具、超长内容与 Artifact 的完整实施边界见 `docs/android-multimodal-long-content-artifact-prd.md`。

---

## 三、开发阶段规划

### Phase 1 — 核心聊天功能（移动端 MVP）

目标：跑通单聊 + 多模型切换 + 本地存储。

- [x] 项目初始化：Flutter 工程结构搭建。
- [x] 多模型接入框架：统一人工智能协议抽象层。
- [x] 基础聊天界面：对话主页、消息气泡、Markdown、流式输出、输入区。
- [x] 本地聊天记录存储：SQLite / drift 数据库。
- [x] 单对话内模型切换。
- [x] 基础主题与字体调节：全局字体缩放已收敛为 90%–120%，5% 步进。
- [x] 每个对话 1 个 Markdown 原始文件基础能力。
- [x] 移动端语音录音输入与播报 v1：输入栏语音按钮、Android / iOS 原生运行时权限与 `.m4a` 录音附件已接入；OpenAI 兼容 STT 自动转写、OpenAI 兼容 TTS 语音播报、STT/TTS 厂商预设 v1、停止播报控制和播放完成事件回传已接入；更多非 OpenAI 兼容语音厂商和真机长时间场景仍待实现。
- [x] ChatGPT 风格多模态 Composer v1：多文件输入、视频附件、参考图 / 图片编辑、图片 / 视频 / 音频 / 音乐生成工具和统一本地媒体消息展示已接入；异步媒体任务 schema 11、进程内启动恢复、固定渠道模型和本地幂等交付已接入；通用媒体实现与边界见 `docs/chat-composer-multimodal.md`，真实厂商异步任务与质量仍待验证。
- [x] 会话草稿持久化恢复 v1：会话文本、附件恢复元数据和深度思考开关写入应用私有 `SharedPreferences` 索引；连续保存串行化、最多保留 50 个会话、损坏数据安全忽略，应用重启或聊天页重建后按当前会话恢复。大粘贴正文与附件 bytes / Base64 不进入该索引。
- [x] 实时语音配置与文本 fallback v1：`RealtimeVoiceSession`、provider、Composer 入口和真机面板已接入；Android 原生 PCM 采集 / 播放 v1 和 Pixel 8 smoke 已通过；iOS 原生 PCM、真实 WebSocket + 云端回答仍待补证，不以文件录音伪装实时流。
- [x] 移动端应用身份 v1：Android / iOS 展示名改为 `SimiAIChat`，包名 / Bundle ID 改为 `top.simitalk.aichat`。
- [x] 对话页扩展 Markdown 渲染 v1：兼容参考样例中的新旧 Markdown、数学公式、媒体、Mermaid、Draw.io 和折叠块，具体见 `docs/markdown-rendering.md`。
- [ ] 移动端真机主链路冒烟：Android 多条真机 smoke 与 iOS release 发送 / 后台 / deep link 已补；iOS release 网络恢复 fake connectivity 入口已补，真实 iOS 物理网络切换、手工 UI 停止 / 重试 / 模型切换和长会话仍待补。

### Phase 2 — 记忆与智能化

目标：人工智能能“认识”用户，跨对话有记忆。

- [x] 核心 Key Points 提取与注入 v1：明示偏好 / 画像 / 目标 / 任务可本地提取；Dreaming 中“继续推进 / 请继续 / 请帮 / 帮我 / 现在帮我 / 修复 / 验证 / 复跑 / 补 / 实现 / 看下 / 检查”等明确任务语气会进入 `task` 记忆候选。
- [x] Key Points 本地语义向量召回 v1：基于本地语义别名、中文 n-gram 和 cosine similarity 提升长期记忆召回，不外发数据。
- [x] 本地全文检索 v1。
- [x] 历史消息本地语义检索 v1：全局搜索扫描最近 500 条原始消息，用本地语义向量和 cosine similarity 支持“手机端 / 移动端”等近义检索，不外发数据、不持久化 embedding。
- [x] 本地消息语义索引 v1：`message_semantic_index` 本地持久化全部原始消息的轻量语义向量 JSON 和内容哈希，设置页可检查 / 预热 / 修复，语义搜索不再局限最近 500 条。
- [x] 本地语义搜索用户开关 v1：设置页可关闭 / 开启本地语义搜索，关闭后仅使用标题、FTS / LIKE 和 Key Points 字面检索。
- [x] SQLite FTS 搜索索引 v1。
- [x] Dreaming 本地整理 v1。
- [x] Dreaming 前台到期调度 v1。
- [x] Dreaming 移动端系统后台代码基线 v1：Android WorkManager 一次性唯一任务已在 Pixel 8 真机通过；iOS 使用一次性 `BGProcessingTask`，已完成启动前原生注册、Info.plist、成功后次日重排、失败 15 分钟重试、`ios_background` trigger、后台 App 刷新状态诊断和隔离 release smoke。iOS 设置页在后台 App 刷新关闭 / 受限时提供“打开系统设置”和“重新检查”，smoke READY JSON 直接记录 `backgroundRefreshStatus`，避免只根据 pending task 缺失推断原因。后台 isolate 复用正式 Dreaming / 待确认画像变更 / Reflection / 通知编排，前台到期继续兜底。
- [x] Dreaming 报告历史 v1：`dreaming_digest_history_v1` 保留最近 20 次有内容报告，按 `dayKey` 去重，设置页可查看历史保留次数、日期和消息覆盖，可展开审阅历史报告 Markdown 预览，可删除单条报告，删除当前报告后自动回退到下一条历史，并可清空最近报告与历史报告。
- [x] DreamingJob / DreamingReport SQLite 表与自动 claim v1：本地 `dreaming_jobs` / `dreaming_reports` 与 `DreamingDao` 已落地，支持 job lifecycle、同日报告 upsert、最近报告读取，并随本地数据库快照导出 / 恢复；手动 / 前台到期 / Android WorkManager 运行实际写入 SQLite job/report，并在失败时记录 failed job、阻止半成功报告发布到 SharedPreferences；自动路径使用固定 `dreaming-auto-YYYY-MM-DD` 主键原子 claim，防止前台与后台 isolate 重复运行，failed / 超时 pending / running 可重领，completed / dismissed 不重复；其余 report 回灌、删除、failed job 可见 / 重试 / 清除、错误脱敏和启动提示能力均已落地。
- [ ] 本地向量检索增强：Key Points 本地语义向量召回、本地消息语义索引、用户可控开关已完成；模型 embedding、真正向量数据库 / ANN、增量维护优化和真机长会话基线仍待实现。
- [x] Dreaming Android WorkManager 系统后台调度 v1，并已在 Pixel 8 Home 后分别通过 JobScheduler 强制执行和不调用强制命令的自然调度；自然模式 30 秒 initialDelay、36 秒完成 Dreaming / Reflection，pending 已清除。
- [x] Dreaming Android 强制 deep idle 短时 smoke：Pixel 8 隔离包在调度与结果时均保持 `deep=IDLE`，无永久 idle whitelist，37 秒完成 Dreaming / Reflection；cleanup 自动 `deviceidle unforce`、恢复正式包并清理隔离包 / sqlite hook。force smoke 的 Job ID 只从精确包名 `dumpsys jobscheduler` 读取，不再误用全局 logcat 中其他 App 的 WorkManager Job ID。
- [x] Dreaming Android UI 进程被回收后的 headless 冷启动 smoke：Pixel 8 隔离 App 调度完成并回到 Home 后，以 `am kill` 回收 UI pid，确认 package 未 force-stop；forced 分支等待 WorkSpec 到期后可冷启动不同的新 pid，natural 分支完全不调用 `cmd jobscheduler run`，系统在 249 秒后通过 `SystemJobService` 自然冷启动不同的新 pid，后台 Flutter isolate 完成 Dreaming / Reflection 并清除 pending。自然进程死亡 smoke 默认观察 900 秒，避免用 240 秒过紧窗口误判系统批处理失败；该证据仍不等同于跨小时、跨日或 OEM 长时存活证明。
- [x] Dreaming Android UI 进程死亡后的跨小时自然调度：Pixel 8 使用同一隔离 smoke，设置 3600 秒 initialDelay、7200 秒观察上限，旧 pid `6444` 消失后 job 持久存在，standby bucket 从 `ACTIVE` 自然降到 `RARE`；任务到期后继续由系统批处理，最终在 4360 秒时通过 `SystemJobService` 冷启动新 pid `24325`，完成 Dreaming / Reflection 并清除 pending。该结果证明跨小时存活与自然冷启动，不替代跨日、长时间 Doze 或 OEM 杀后台验证。
- [ ] Dreaming Android 跨日自然调度：已新增可分离 `schedule / status / verify / cleanup` 的安全 smoke；schedule 完成后会恢复正式包和仓库 sqlite 配置，只保留隔离包、JobScheduler job 和 0600 状态文件。harness 会把 seed 消息时间写到预定执行日，避免次日执行时因消息仍属于前一天而误报 `notDue`。Pixel 8 已调度 86400 秒任务，旧 pid `28141` 已消失，目标 dayKey `2026-07-15`，当前 job id `0` 为 waiting；待次日通过独立 verify 检查 Dreaming / Reflection / history / pending、正式包 identity 并清理隔离包。
- [x] Dreaming 后台附加条件代码 / UI / 持久化 v1：设置页可选择“仅充电时执行”和“仅非计费网络执行”，配置随 `dreaming_schedule_v1` 保存、结构化备份与恢复，并在设置变化后重排系统任务。Android 映射为 WorkManager `requiresCharging` / `NetworkType.unmetered`；iOS 映射充电条件，但 `workmanager 0.8.0` 的 Apple 侧只能表达“要求联网”，无法保证 Wi-Fi，设置页已明确提示该平台边界。旧配置默认两项关闭，保持原行为。Pixel 8 真机已证明：无 Wi-Fi 时非计费网络任务被 `jobscheduler run -s` 拒绝，恢复 `WIFI + NOT_METERED + VALIDATED` 后严格放行并完成 Dreaming / Reflection；充电任务在未充电时被严格拒绝，系统 charging 后不使用 `-f`、等待 initialDelay 自然完成 Dreaming / Reflection。
- [ ] Dreaming iOS BGTaskScheduler 真机系统执行和 Android 跨日 Doze / OEM 长期可靠性。2026-07-14 15:19 iPhone13 隔离 release smoke 通过解锁预检、27.5MB release 构建、安装、启动和 READY 文件，但设备原生通道直接返回 `backgroundRefreshStatus=denied`，`scheduledTasks=[BGTaskScheduler] There are no scheduled tasks`；隔离 bundle 已清理、正式包重新运行。用户可从 Dreaming 设置页点“打开系统设置”，开启后点“重新检查”，再继续 pending task / LLDB 严格触发 / Dreaming 与 Reflection 结果持久化验证。Android 已完成短时强制 deep idle、UI 进程回收后的自然冷启动、跨小时自然调度、非计费网络和充电条件阻塞 / 满足后放行真机闭环，但不替代跨日、长时间 Doze 或 OEM 杀后台观察。
- [x] 无限上下文预算控制 v1：根据 `protocol + modelName` 推断模型窗口，动态提高压缩阈值，预算模式不再固定最近 20 条，可在输入预算内尽量保留更多历史；超限错误会给出可操作提示。
- [x] 无限上下文滚动压缩 v2：默认 `gpt-5.3-codex-spark` 使用显式保守 128K 客户端预算；旧 summary 与较旧 original 会原子合并成单一有界滚动摘要，原始消息只标记不删除；同会话请求前 / 回答后压缩 single-flight，预算裁剪固定保留滚动摘要与最新问题。
- [ ] 无限上下文长期质量门禁：仍需在 Pixel 8 使用真实 `gpt-5.3-codex-spark` 做跨越一次以上压缩周期的多轮事实召回、摘要冲突与超限重试质量验收；代码 / mock 回归不能替代该真实模型质量证据。
- [x] Reflection 反思机制 v1：Dreaming 后始终基于本地日报、用户画像和待确认画像变更生成回应质量、未回复会话、会话追问压力、最后一问未答、敏感标题降级和最后用户问题安全片段、上下文、长期记忆、用户画像、任务推进和来源新鲜度的可解释安全基线；来源过期时设置页入口会直接提示先运行今日 Dreaming；支持保存最近 20 次反思历史，可展开审阅历史反思、按 `dayKey + sourceDigestDayKey` 精确删除单条反思、删除反馈显示来源、删除当前最近反思后自动回退并可清空最近反思报告与历史，并把少量高优先级结论 / 行动项作为下一轮本机短期提示，用户可关闭。可选模型增强默认关闭，显式开启后使用默认聊天模型、严格 JSON、输入输出限长与脱敏，并在失败时回退本地报告、清除 pending；一个仓库外配置驱动的远程模型三日长会话门禁已 3 / 3 通过，更多模型族仍待验证。
- [x] 本地用户画像 v1：从 Key Points 与最近 Dreaming 报告生成可解释画像。
- [x] 用户画像可控管理 v1：用户可在设置页编辑 / 删除画像信号，控制记录本地保存。
- [x] 用户画像版本历史与冲突检测 v1：本地保留最近画像快照，展示偏好冲突提示。
- [x] 用户画像历史差异对比与恢复 v1：展示历史版本相对当前画像的新增 / 移除摘要，并可恢复历史快照。
- [x] Dreaming 待确认画像变更 v1：Dreaming 后生成本地待确认画像变更，用户采纳后才写入正式画像。
- [x] 待确认画像变更逐项采纳 / 拒绝 v1：用户可对单条画像新增 / 移除信号单独采纳或忽略。
- [x] 待确认画像变更详情审阅 v1：用户可查看全部待确认画像差异，并处理卡片未展示的后续单项。
- [x] 模型驱动画像增量分析 v1：独立开关默认关闭；只发送限长、脱敏的 Dreaming / 本地候选摘要；模型新增必须带逐字证据，只能追加少量待确认候选，不能删除、覆盖、生成基础身份事实或直接修改正式画像；失败回退本地候选。真实远程质量门禁 3 / 3 和 Pixel 8 系统后台自然冷启动已通过。

### Phase 3 — 生态扩展

目标：平台打通，技能扩展。

- [ ] 社交平台接入：飞书 / Telegram / Discord 优先。
- [x] 技能市场基础集成。
- [ ] 多源技能市场集成：OpenClaw、腾讯等。
- [ ] 个人接口中转服务：本地 OpenAI 兼容中转核心服务 v1 已完成（模型列表、非流式 / 流式聊天补全、Responses API 非流式 / 流式生命周期事件兼容、渠道模型桥接、Bearer 鉴权）；设置页启动 / 停止入口、令牌生成与加密持久化、端口展示、Base URL / curl 示例复制、访问审计、并发保护、局域网开放二次确认、高级路由策略、可配置并发上限、本地脱敏用量统计、持久化脱敏审计明细、JSON 导出、OpenAI 多模态内容安全兼容降级 v1、图片 data URL 端到端透传 v1、模型视觉能力路由 v1、模型能力可见性与设置页 Vision 标注 v1、远端图片 URL 安全下载透传 v1、Bearer 鉴权健康检查端点 v1、CORS / 浏览器客户端兼容 v1 已完成；真机长时间运行仍待做。
- [x] 定时任务与系统通知联动 v1：Dreaming 前台到期整理完成后推送本地通知，通知失败不阻断整理或聊天主链路。
- [ ] 定时任务与系统日历 / 闹钟联动。
- [ ] MCP 运行时 / 旁车管理。
- [x] 深度链接 `ai-chat://` v1：Android / iOS 自定义 URL scheme + Flutter 路由处理已完成；Android Pixel 8 外部 URL 打开 smoke 已补，iPhone13 iOS release URL 打开 smoke 已补。

### Phase 4 — 数据与同步

- [x] 本地数据导出压缩包 v1：设置页可生成 `.tar.gz`，包含 `manifest.json`、`conversations/`、`audio_transcripts/`、默认 `audio_files/`，不包含 API Key 或本机绝对路径；语音转写稿包含明确状态和脱敏失败说明。
- [x] 非语音附件原文件导出 / 导入 v1：导出包新增 `attachments/`，从 SQLite 附件表复制仍可读取的图片 / PDF / 文档等非语音附件原文件，净化归档路径。
- [x] 本地聊天核心数据库备份 / 恢复 v1：导出包新增 `structured_data/local_database.json`，可恢复 sessions / messages / attachments / folders / prompts / skills / mcp_servers / model_channels / channel_models / dreaming_jobs / dreaming_reports，并把附件路径重定向到导入目录；默认不覆盖已有记录，不包含模型 API Key / 渠道密钥 / MCP headers / 本机绝对路径；Dreaming failed job 错误导出 / 恢复时会隐藏 Bearer、sk、token 参数、HTTP(S) URL 和本机路径。
- [x] 移动端系统分享导出 v1：导出前展示范围确认和原始语音文件开关，Android / iOS 通过原生系统分享面板分享导出包，不新增 Flutter 依赖。
- [x] 安全导入 / 恢复 v1：设置页可选择 SimiChat 导出包并预览，导入前校验 manifest、SHA-256 和路径安全，默认跳过已有文件避免覆盖。
- [x] 结构化本地数据备份 / 恢复 v1：导出 `structured_data/shared_preferences.json`，恢复 Key Points、Dreaming 最近报告与报告历史、用户画像、主题 / 字体 / 上下文阈值 / 本地语义搜索开关、系统提示词等白名单本地偏好；默认不覆盖已有偏好，不导出模型 API Key / 渠道密钥。
- [x] 电脑端本地传输 v1：导出后启动临时本地 HTTP 下载服务，使用一次性令牌、过期时间、单次下载限制和安全响应头，支持电脑浏览器下载导出包。
- [x] Obsidian Markdown Vault 导出 v1：生成本地 vault 目录，复制会话 Markdown / 语音转写 Markdown，并生成 README、索引和 Manifest。
- [x] Obsidian 现有 Vault 增量同步 v1：用户可选择已有 Obsidian Vault，同步到 `SimiChat/` 子目录；通过同步状态文件做安全增量更新，目标手动修改或符号链接目标默认冲突跳过。
- [x] Obsidian 附件链接重写 v1：复制可安全读取的附件到 `Attachments/`，并把会话 Markdown 附件列表改写为 Obsidian wiki 链接；audio 原文件是否复制由原始语音开关控制。
- [x] Obsidian 同步冲突详情界面 v1：同步冲突不覆盖，设置页弹窗解释冲突路径、原因和短 SHA，方便用户后续手动处理。
- [x] Obsidian 可选覆盖冲突策略 v1：同步前让用户选择安全同步或覆盖冲突；默认安全跳过，覆盖仅对普通文件差异生效，目录 / 符号链接仍跳过。
- [x] Obsidian 原始音频附件可选同步 v1：由“包含原始语音文件”开关控制 audio 原文件是否复制到 `Attachments/`，开启后音频附件也会重写为 Obsidian wiki 链接。
- [x] Obsidian 同名附件链接精确去重 v1：同一消息内多个同名附件按 Markdown 附件项出现顺序分别链接到不同 `Attachments/` 目标，避免全部指向第一条。
- [x] Obsidian stale 文件安全清理 v1：同步状态中存在但当前源数据已删除的旧文件，若目标仍等于上次同步版本则自动清理；若目标已被用户修改则记录冲突并保留。
- [x] Obsidian stale 冲突详情解释 v1：设置页冲突弹窗解释源端删除但目标已修改 / 目标非普通实体两类 stale 冲突，并明确不会覆盖或删除用户文件。
- [ ] Notion / 语雀 / 思源笔记同步：Obsidian 双向同步、更完整冲突处理和 Notion / 语雀 / 思源笔记仍待实现。
- [ ] 可选云备份：WebDAV / S3 / 云盘，需端到端加密与明确授权。

### Phase 5 — 数字孪生

- [x] 用户画像分析系统 v1：本地画像结构、构建器、持久化、设置页查看 / 重建 / 编辑 / 删除、冲突提示、版本历史、差异对比、历史恢复、待确认变更、逐项采纳 / 拒绝、全部变更详情审阅和默认关闭的模型驱动增量候选。
- [ ] 声音 / 图像 / 表情处理。
- [ ] 镜像数字人生成。
- [ ] 数字人直播能力（长期）。

---

## 四、关键页面需求

### 4.1 对话主页

- 顶部左侧：历史会话抽屉入口。
- 顶部居中：`聊天 / 工作`分段控件；聊天模式下可在次级位置显示会话议题和模型，工作模式下显示当前任务标题与状态。
- 顶部右侧：按当前模式提供新建 / 编辑和更多操作；禁止把新建、重试、设置等全部常驻堆叠。
- 消息流：用户消息右对齐，人工智能回复左对齐。
- 人工智能回复支持扩展 Markdown、代码块、图片、行内 / 块级 LaTeX、Mermaid、Draw.io / mxGraph、折叠块、HTML 音视频安全卡片和思考过程；具体实现见 `docs/markdown-rendering.md`。
- 每条人工智能回复底部操作：复制、重试、语音播报；播报中应可停止，播放自然结束、停止或原生错误后应自动恢复为可再次播报状态。
- 流式输出支持中断。
- 底部输入区：ChatGPT 风格多行单一 Composer，固定在键盘安全区上方；静止状态展示 `+`、文本输入、录音麦克风和实时语音，输入后切换为发送，流式 / 任务执行中切换为停止。`+` 工具菜单提供图片、视频、声音、语音识别和音乐动作，动作结果直接回到当前消息流。
- 草稿边界：草稿严格按会话隔离；进入会话时先恢复本进程草稿，冷启动 cache miss 才读取私有索引。异步恢复不得覆盖用户已开始的编辑；发送成功只清空已消费的文本 / 附件并保留当前深度思考开关。
- 实时语音从 `+` 菜单进入独立的 ChatGPT 风格面板，展示连接状态、用户 / 助手转写、配置摘要、文本 fallback 和停止回答；未接入原生 PCM 时必须明确提示边界，不能将文件录音伪装为实时输入。

### 4.2 模型选择器

- 位置：移动端优先保证聊天主路径可快速切换；桌面端可放在侧边栏顶部。
- 顶部展示：只显示当前选中模型的模型名，末尾固定显示向下箭头；长渠道名不得挤占移动端顶部宽度、导致模型名不可见。
- 渠道名展示：仅在下拉菜单的分组标题、消息元数据和模型详情中显示为 `渠道名 / 模型名`。
- 列表内容：所有渠道下的全部模型，不去重穷举。
- 每项显示：`渠道名 / 模型名`，同名模型在不同渠道下各自独立显示。
- 切换后立即生效，更新当前会话默认模型。
- 新建会话时自动选中上次使用的模型。

### 4.3 历史会话页

- 移动端优先通过左侧抽屉呈现；抽屉顶部提供搜索，按“一级导航 / 已置顶 / 最近”分组，底部固定设置和“新建聊天”主按钮。
- 按最近消息时间倒序展示。
- 支持标题 + 内容全文搜索。
- 支持文件夹分组、展开 / 折叠。
- 每条会话支持重命名、移入文件夹、删除。
- 支持新建文件夹。

### 4.4 设置页

- 入口：移动端需清晰可达，可通过头像、设置按钮或抽屉入口进入。
- 模型渠道管理：新增 / 编辑 / 删除渠道；字段包括渠道名、Base URL、接口密钥、协议类型；选择厂商预设时展示并可复制建议模型名、Base URL 和厂商文档链接；批量 JSON 导入弹窗默认展示 `presetId` 预设示例，并可从剪贴板粘贴 JSON，也可一键复制或恢复固定安全示例 JSON，不复制 / 不恢复用户编辑区里的真实 API Key；导入 JSON 根结构支持单个渠道对象、渠道数组或 `channels` 数组包裹对象，单模型可用 `model` / `modelName` / `defaultModel` 或 `models` 字符串 / 对象简写，并可通过 `presetId` / `providerPresetId` / `provider` / `preset` 引用内置预设 ID、完整显示名称或 `/` 分隔显示名称短别名自动补渠道名、Base URL 和协议，且预设匹配忽略大小写、首尾空格和斜杠两侧空格差异；导入错误提示会脱敏疑似密钥 / token；已保存渠道手动添加模型时可从匹配预设的推荐模型名快速填入，帮助用户在模型列表不可用或权限受限时手动添加模型。
- 模型管理：每渠道可配置多个模型，设置默认模型，测试连通性，查看最近测试结果。
- 数据与档案：Markdown 档案、全文索引、Dreaming、导出同步。
- 记忆与画像：Key Points、用户画像、数字孪生基础。
- 语音与多模态：语音权限、STT 状态、TTS 播报配置、图片 / 文件策略。
- 外观：主题、全局字体大小、颜色风格；移动端字体量化指标为默认 15sp 正文、90%–120% 全局缩放。

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
8. 每个功能进入完成状态前必须完成：功能测试、性能影响评估、安全影响评估、文档同步。

---

## 六、文档与记录约定

- `AGENTS.md`：中文权威账本，维护目标、进度、待办、已完成事项、重要决策。
- `docs/`：所有具体实现文档、架构方案、数据结构、接口设计、测试方案、安全方案。
- `docs/markdown-rendering.md`：对话页 Markdown 渲染能力、移动端字号指标和安全边界。
- `CLAUDE.md`：只保留迁移声明，不再维护项目进度。
- `docs/conversations/`：仅放示例或说明；真实用户对话 Markdown 不得提交。
