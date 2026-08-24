# SimiAIChat — 项目总纲与智能体工作账本

> **定位**：人工智能聊天工具，最终形态 = 好友陪伴（虚拟朋友 / 智能助理）+ 数字孪生（镜像数字人，基于长期对话录入与资料蒸馏生成）。
>
> **技术栈**：Flutter，移动端优先；移动端核心功能稳定后再扩展桌面 / 电脑端。
>
> **主事实来源**：本文件记录项目目标、阶段进度、待办、已完成事项、重要决策与执行约束。`CLAUDE.md` 的项目进度、路线图、已知问题和重要安排已迁移到本文件；后续维护以 `AGENTS.md` 为准。
>
> **最后更新**：2026-08-24。

---

## 0. 文档与协作规则

### 0.0.3 2026-08-24 TTS / 声音设计 / 声音克隆 / STT 真机稳定性复验

- **代码修复**：OpenAI-compatible TTS 生成文件扩展名现在跟随实际 `response_format`，不再把 WAV / AAC / FLAC / Opus 固定保存成 `.mp3`；HTTP 200 但响应为 JSON / HTML / text 错误体时会在落盘前拒绝，避免时间线出现“看似音频、点击却无声”的坏附件。SimiRouter 请求的 `speed` 在 wire 层发送 JSON number，而不是字符串。
- **声音克隆兼容修复**：参考音频 data URI 按真实扩展名映射 MIME。Pixel 8 真实差分确认，同一条 1.968 秒 MP3 在 `audio/mpeg` 下连续超时，而当前 SimiRouter legacy clone 上传会把 subtype 当作临时扩展名；MP3 改用网关兼容的 `audio/mp3` 后，同一参考音频数秒内成功生成并完成 Android 原生播放。WAV、M4A/MP4、OGG/Opus、AAC、FLAC、WebM 继续使用各自明确 MIME，未知格式在请求前拒绝。
- **STT 兼容修复**：`/v1/audio/transcriptions` 先走 multipart；仅在 400 / 415 / 422 协议或内容类型拒绝时回退 JSON data URI。`language=auto` 在 multipart 和 JSON 两条路径均省略，中文 / 英文分别发送 `zh` / `en`。
- **真实 Provider E2E**：`mimo-v2.5-tts` 已分别完成 MP3 与 WAV 合成；WAV 下载结果为 RIFF/PCM 16-bit、mono、24 kHz、2.24 秒，扩展名与容器一致。`mimo-v2.5-tts-voicedesign` 已按“文本 + 风格 + 语速 + MP3”生成 24 kHz / 1.968 秒音频。`mimo-v2.5-tts-voiceclone` 已分别用 WAV 与修复后的 MP3 参考音频生成可播放 MP3。`mimo-v2.5-asr` 已完成 `auto / zh / en` 三种语言路径，回环音频真实返回 `Voice clonistability test.`；独立识别时间线与 audio-only 先识别再交给 Chat 的联合发送路径均已验证。
- **Android 播放与时间线**：上述 MP3、WAV、声音设计和两种克隆结果均写入当前会话的 assistant audio attachment；Android `MediaPlayer` 有 started / stopped 或 completed 事件、24 kHz `AudioTrack` 帧交付和 Audio Focus request / abandon，播放按钮在结束后恢复。失败请求保留输入与参考附件，不写入伪成功音频。
- **Production Release**：Pixel 8 `37101FDJH0077P` 已以 `adb install -r` 覆盖安装当前正式包，未卸载、未清数据；`ANDROID_RELEASE_PARITY status=verified`，构建 APK 与设备 `base.apk` SHA-256 均为 `c9c8eb30d4a6e96d98ed7a8f35228517c9a7f6f543f15b62d2717183b139f60c`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持不变，安装后 PID `29832`。
- **自动门禁**：语音影响面 27 个测试文件 **179 / 179 通过**；最终修复聚焦 `openai_text_to_speech_engine_test.dart`、`openai_speech_to_text_engine_test.dart`、`text_to_speech_provider_test.dart` **39 / 39 通过**；完整 Flutter JSON reporter 复跑 **1235 / 1235 通过**（`done.success=true`、0 error），随后独立 compact 复跑再次 **1235 / 1235 通过**。更早一次 compact 完整运行曾以 `+1234 -1` 结束，但工具输出截断未保留失败用例，未计为通过；后续两次持久化/独立复跑未复现，语音专项也未出现失败。`flutter --no-version-check analyze --no-pub` 为 `No issues found`，`git diff --check` 无输出。
- **剩余边界**：当前证明的是本次短音频、当前 SimiRouter 账号和 Pixel 8 Production Release；长文本 / 长音频、弱网 / 超时恢复、连续批量生成、iOS provider 播放与真实来电 / 闹钟 / 第三方播放器焦点抢占仍需单独压力和真机门禁。

### 0.0.2 2026-08-24 默认对话、客户端长上下文与图片参数真机复验

- 用户未选择模型或会话绑定的旧模型已失效时，客户端从已启用 Chat 模型中精确回退到 `gpt-5.3-codex-spark`；已有有效显式选择不被覆盖。新会话、顶部模型胶囊、发送前门禁和会话 `defaultChannelModelId` 使用同一解析规则，不会凭空创建渠道或凭据。
- `gpt-5.3-codex-spark` 按保守 128K 模型窗口、115200 最大输入和 57600 动态压缩阈值处理。旧 summary 与较旧原始消息合并为单一 1024-token 滚动摘要，最新 10 条原始消息保留，所有原文仍保存在 SQLite / 时间线 / 搜索 / 导出；同会话压缩 single-flight，上游超限后只做一次 65% 严格预算裁剪重试。该能力是客户端长期会话，不代表上游模型拥有无限 token。
- 图片任务面板的“质量 / 宽高比 / 清晰度 / 分辨率”摘要均为可点击 `ActionChip`，移动端分别打开选择抽屉；`1K/2K/4K` 是清晰度档位并保存为 `resolution`，`1024x1024/1536x1024/1024x1536` 是像素分辨率并保存为 `size`。能力声明、typed request、失败重试与冷启动快照都按两个独立维度处理，模型切换会分别清除不支持的旧值。
- 本次拆分后的最终代码门禁：全量 Flutter 测试 **1230 / 1230 通过**，`flutter --no-version-check analyze --no-pub` 为 `No issues found`，`git diff --check` 无输出；图片参数聚焦回归 **96 / 96 通过**，覆盖 Widget、能力校验、wire 序列化、失败重试、任务快照和旧快照兼容。
- Pixel 8 `37101FDJH0077P` 已覆盖安装拆分后的 Production Release，`ANDROID_RELEASE_PARITY status=verified`；构建 APK 与设备 `base.apk` SHA-256 均为 `7130a5042c01b3df99e8655dca86e8b8f47517f82e67baed824be270f544b4e9`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持不变，安装后 PID `20256`。
- 真机默认 Chat E2E：新建对话未打开模型选择器，顶部直接显示 `gpt-5.3-codex-spark`；发送 `Reply only OK` 后真实返回 `OK`，结果卡显示 `SimiRouter AI 中转站 / gpt-5.3-codex-spark`。
- 拆分后的 Production Release 真机 UI 已确认 `gpt-image-2` 同时出现并可点击“清晰度 · 2K”和“分辨率 · 1536x1024”；清晰度抽屉只列 `自动 / 1K / 2K / 4K`，像素分辨率抽屉只列 `自动 / 1024x1024 / 1536x1024 / 1024x1536`，高级设置同步展示两个独立值。
- 真机联合请求以 `resolution=2K`、`size=1536x1024` 提交后从“正在生成图片…”进入“已生成图片”，时间线和图片附件均已交付；下载 PNG 为 **1,447,276 bytes、1387x1134**，SHA-256 为 `110c1dcff303c18e881b44a8b13261f903869abc3e16cfb01706bcb924ec4396`。因此客户端 UI / snapshot / serializer / 交付链路为 `[PARITY VERIFIED]`，但 provider 没有执行请求的 `1536x1024`，上游像素尺寸为 `[PARITY BROKEN]`；本次只完成联合请求，不能扩写为 baseline / resolution only / size only / ratio only 的完整差分。
- 待补：为可用图片渠道确认真实 capability / 参数协议或切换到实际遵守比例、像素尺寸、清晰度和质量的 provider，并按 baseline / resolution only / size only / ratio only / resolution + size 下载核对真实像素；使用真实 `gpt-5.3-codex-spark` 跨越至少一次 57600-token 压缩周期验证早期事实召回、冲突摘要和超限重试质量。

### 0.0.1 2026-08-23 多模态发送路由与 Android Release 验证

- 图片 / 视频 / TTS / 声音设计 / 声音克隆 / STT 均从设置中已配置渠道选择默认模型，媒体路由持久化 `channelModelId`、profile、endpoint 和 task options；模型获取后按能力自动测试，添加确认提示不被测试提示覆盖。
- 已接入用户整理的 OpenAI-compatible、xAI Grok Imagine、SimiRouter TTS / STT、音色查询和账号额度协议；图片模式只展示图片能力模型，顶部胶囊显示完整模型名和向下箭头；输入框点击可弹出 Android 输入法。
- 2026-08-22 补充联合语音发送：底部 Composer 发送 audio + typed text 时先调用绑定的 `mimo-v2.5-asr`（或当前 STT）再交给 Chat 模型，时间线保存合并正文与音频附件，成功后清除语音草稿；图片 / 视频 / 语音工作区统一使用底部输入框。Artifact 卡片编辑入口固定右下角，HTML 可视化编辑支持组件文字 / CSS 颜色修改。
- 2026-08-22 进一步收敛为单一 Composer：移除 AppBar 的一级图片 / 视频 / 语音模式条和聊天区常驻媒体工作区，媒体动作统一从底部 `+` 菜单进入，任务参数继续在发送前 bottom sheet 配置；Artifact 卡片保存回调回写当前时间线卡片草稿，返回后再次打开仍使用修改后的 HTML / Markdown。
- 2026-08-23 修复顶部切换媒体模型后 Composer 仍硬编码调用普通 Chat 的路由缺陷：活动会话与空会话均改为读取 `creationModeProvider` / `voiceCreationToolProvider` 后进入统一创建模式路由；TTS 生成消息的 `channelModelId` 现在优先保存当前 TTS 配置绑定的模型，而不是会话旧的文字 Chat 模型。
- 2026-08-23 补充 SimiRouter TTS 八种预设音色的可读中文显示标签：冰糖/alloy、茉莉/echo、Mia/nova、Chloe/shimmer、苏打/onyx、白桦/fable、Milo/milo、Dean/dean。设置页与聊天页 TTS 任务面板显示可读名称，发送请求仍使用原始 `voice` ID。
- 门禁：analyze 通过，全量 Flutter 测试 1196 项通过，Pixel 8 `37101FDJH0077P` 正式包 `top.simitalk.aichat` 通过 `scripts/smoke_android_release_install_launch.sh` 覆盖安装 parity；`firstInstallTime` 与 `dataDir` 保持不变。


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
10. **测试目录规则**：Flutter 单元、Widget、manifest、smoke 和 benchmark 文件统一放在 `test/` 根目录；按 `_test.dart` / `_benchmark.dart` 命名区分类型，目录约定和命令维护在 `test/README.md`；真实设备集成测试继续放在 `integration_test/`。

### 0.2 当前进度总览（2026-07-14）

| 方向 | 当前状态 | 下一步重点 |
| --- | --- | --- |
| 移动端 MVP | 基础聊天、会话列表、模型切换、本地 SQLite、Markdown 原始档案、移动端应用名 `SimiAIChat`、包名 `top.simitalk.aichat`、主题与 90%–120% 全局字体、移动端自动化 smoke 已落地，Pixel 8 真实发送 / 重试 / 停止 / 历史搜索 / 模型切换已补证，Android 真机集成发送已通过，iPhone13 release 覆盖安装 / 启动 / 进程可见已通过，people iOS release 发送闭环已通过，设置页、复杂 Markdown 滚动、base64 语音发送、OpenAI 兼容 STT 网络、真实录音按钮、OpenAI 兼容 TTS 网络、原生音频播放通道、长音频播放完成和播放替换 / 中断 smoke 入口已新增并在 Pixel 8 通过，Android 音频焦点基础处理与 iOS AVAudioSession 中断基础处理已完成代码级加固，Android Wi-Fi / data 网络恢复、飞行模式恢复和 Home 后台恢复已在 Pixel 8 通过，前台网络断开取消所有已加载 streaming 会话并在联网恢复后提示手动重试的代码级保护已落地，Android Wi-Fi / data 与 airplane mode 物理断网 streaming 取消 smoke 已在 Pixel 8 通过，iOS release 后台恢复已在 iPhone13 通过，people 锁屏阻塞历史已记录，脚本失败清理可恢复普通 release，iOS release send / retry / model-switch / stop harness 复查发现停止慢流红灯并已补取消订阅、SSE CancelToken 传播和脚本失败恢复，修复后全链路已在 iPhone13 复跑通过，后台切出取消所有已加载 streaming 会话、恢复前台提示和冷启动持久化待重试 marker 的代码级保护已落地，marker 指向非当前自动选中会话时会先切回该会话，marker 指向已删除 / 不存在会话时会自动清理，后台待重试 marker 已从旧单值兼容推进到列表恢复，多条恢复会显示数量提示并提供显式“重试全部”用户动作，重复 / 空 marker 在读写两侧都会被清洗去重，用户主动重试不再依赖消息 Provider 预加载，快速切后台 / 前台的 marker 写入 / 清理竞态已补回归，非当前会话后台流取消已补代码级回归，Android 真机慢流取消 smoke 已在 Pixel 8 通过，Android 音频焦点丢失 debug-only 设备 smoke 已从直接 listener 模拟推进到 competing AudioFocus 系统仲裁路径并在 Pixel 8 通过，外部 helper APK 抢占系统音频焦点 smoke 已在 Pixel 8 通过，Android deep link 外部 `ACTION_VIEW` URL 打开 smoke 已在 Pixel 8 通过，iOS release deep link `--payload-url` URL 打开 smoke 已在 iPhone13 通过，iOS release 网络恢复 fake connectivity harness / 脚本入口和门禁已补 | 真机主链路：iOS release 手工 UI 停止 / 重试 / 模型切换、长会话、真实来电 / 闹钟 / 第三方媒体播放器音频焦点抢占、iOS 真机音频中断、iOS 网络切换真机复跑、后台未完成请求恢复 |
| 多模型接入 | 已支持 OpenAI Chat / OpenAI Responses / Claude / Gemini / Ollama 协议适配；模型厂商预设、百度千帆 / 讯飞星火 / Kimi / SiliconFlow / 火山方舟 / 腾讯混元 / Groq / Mistral / Together / Fireworks / xAI / Perplexity / DeepInfra OpenAI 兼容预设、设置页预设建议模型名提示 / 一键复制、Base URL 复制和文档链接复制、添加模型弹窗推荐模型名快速填入、批量 JSON 导入支持单渠道对象 / 数组 / channels 包裹对象、单模型 `model` / `modelName` / `models` 字符串简写，支持 presetId / provider 显示名 / 短别名预设填充且斜杠空格容错、批量导入安全示例 JSON 粘贴 / 复制 / 恢复、连通性测试、测试历史、失败重试、一键测试并剔除不可用模型、渠道 / 模型删除引用清理已落地；OpenAI Chat / Responses / Claude / Gemini 通过统一 SSE helper 传播取消，Ollama 本地 NDJSON 流也已支持 `CancelToken` 停止传播 | 继续扩展国产 / 免费模型来源引导和更完整的协议兼容性测试 |
| 个人 OpenAI Relay | 已支持 Bearer 鉴权、`/health`、`/v1/health`、`/v1/models`、非流式 / 流式 `/v1/chat/completions`、非流式 buffered / 流式 SSE 生命周期事件 `/v1/responses`、CORS 预检、审计、用量统计、并发保护、局域网二次确认、路由策略、多模态安全降级、图片 data URL / 远端图片安全透传、Vision 路由 | 真机长时间运行、更多外部客户端兼容性、后台网络变化恢复 |
| 记忆与 Dreaming / 上下文 | Key Points、本地语义召回、消息语义索引、本地语义搜索开关、Dreaming 前台到期整理 / 通知、Android WorkManager 强制 / 自然 / 短时 deep idle / UI 进程被回收后 forced、自然与跨小时 headless 冷启动真机系统后台、iOS BGTaskScheduler `BGProcessingTask` 代码 / 原生注册 / 调度诊断、设置页移动端系统后台边界与 iOS 后台 App 刷新状态、Dreaming 报告历史 v1 展开审阅 / 单条删除 / 清空入口、Dreaming 明确任务语气 task 记忆候选、DreamingJob / DreamingReport SQLite 表与 DAO、手动 / 前台到期 / 系统后台 Dreaming 编排、跨 isolate SQLite 原子 claim、失败恢复 / 脱敏 / 通知、用户画像管理 / 历史 / 待确认变更、本地反思机制 v1、默认关闭且失败回退本地规则的可选模型增强反思 v1、反思未回复 / 追问压力 / 重复追问 / 最新任务 / 最后一问提醒、来源新鲜度、短期提示注入、反思历史管理、模型窗口预算裁剪、动态压缩阈值和上下文超限重试已落地 | iOS BGTask 真机系统执行（当前后台 App 刷新关闭）、模型 embedding / ANN、Android 跨日 Doze / OEM 长期补证、真实外部模型长会话反思质量门禁、模型驱动画像增量分析 |
| 语音 / 图片 / 多模态 | 语音录音、私有归档、OpenAI 兼容 STT / TTS、音频附件发送前 STT 音频接口转写、base64 语音文本粘贴转写、iOS 系统 Speech 原生识别兜底、语音厂商预设、播放停止 / 完成事件、图片 / 文件附件、图片缩略图已落地；Pixel 8 已补 base64 语音粘贴 → audio 附件 → STT sidecar → 模型请求真机 smoke、OpenAI 兼容 STT multipart 网络 fallback smoke、真实录音按钮 → 原生 `.m4a` → STT → 聊天回复 smoke，以及 assistant 播报按钮 → OpenAI 兼容 `/v1/audio/speech` → 临时音频 → 停止播报 smoke，以及应用私有目录 WAV → Android `MediaPlayer` → stopped / completed 事件回传 smoke，以及播放中启动第二段音频时第一段 stopped、第二段 completed 的替换 smoke；Android 音频焦点基础处理已在原生侧加固，焦点丢失会停止播放、duck 会临时降音量；iOS 已补 `AVAudioSession` interruption began 停止播放和音频会话释放 | 更多 STT / TTS 厂商、真实云端 STT / TTS 长音频、真实来电 / 闹钟 / 其他播放器焦点抢占、iOS 真机音频中断、声音 / 图像 / 表情画像 |
| 数据管理与同步 | `.tar.gz` 导出、系统分享、安全导入、结构化备份 / 恢复、Dreaming SQLite job / report 随本地数据库快照导出恢复、Dreaming failed job 导出 / 恢复错误和 URL 脱敏、电脑端本地传输、Obsidian Vault 导出、Obsidian 增量同步 / 附件 / 冲突 / stale 清理、Notion 同步 v1、WebDAV 云备份 v1 已落地 | 语雀 / 思源同步、S3 / 云盘、Obsidian 双向同步 |
| 数字孪生 | 本地用户画像 v1 已落地，可查看、编辑、删除、恢复历史、逐项采纳 / 拒绝 Dreaming 画像变更 | 声音 / 图像 / 表情处理、镜像数字人生成、代理行为授权与审计 |
| 对话页 Markdown / 字体 | 扩展 Markdown 渲染 v2 已落地：用户输入和 AI 输出统一 Markdown 渲染；行内 code 不再误渲染为代码块；支持 GitHub Web 扩展、旧式 / Obsidian / HTML 图片、行内 / 块级公式、HTML audio/video 安全卡片、HTML details、旧式 details、多种 Mermaid 与 Draw.io / mxGraph 新老格式；移动端正文默认 15sp，缩放范围 90%–120% | 复杂 Markdown 真机滚动已补 Pixel 8 smoke；复杂表格 / 长代码 / 离线 Mermaid 视觉体验继续优化 |
| 最新验证 | 2026-07-14 本轮继续补 Android UI 进程死亡后的跨小时无 force 自然调度：复用 natural process-death 隔离 smoke，设置 3600 秒 initialDelay 和 7200 秒观察窗口；旧 pid `6444` 消失后 JobScheduler job 跨越一小时持续存在，电量 / 存储 / Doze / 后台限制 / quota 约束满足，standby bucket 从 `ACTIVE` 自然降到 `RARE`。一小时到期后 job 进入 ready，系统继续批处理约 12 分钟，最终 elapsed `4360` 秒时为 `SystemJobService` 冷启动新 pid `24325`，后台 Flutter isolate 完成 `status=completed digest=2026-07-14 reflection=2026-07-14`，prefs 含最近报告 / 历史且无 pending；cleanup 后 deep state `ACTIVE`、正式包 pid `24737`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook；最终全量稳定门禁 523 项和 analyze 通过。该结果把 Android 稳定证据推进到跨小时，但仍不替代跨日、长时间 Doze 或 OEM 严格后台限制；2026-07-14 本轮继续补 Android UI 进程被回收后的无 shell force 自然调度：新增独立 natural wrapper，旧 pid `2639` 消失后 JobScheduler job 保持 `ACTIVE` bucket、约束满足并进入 ready；前两次 180 / 240 秒窗口过紧，最终 900 秒观察中系统在 249 秒后为 `SystemJobService` 冷启动新 pid `4668`，后台 Flutter isolate 完成 `status=completed digest=2026-07-14 reflection=2026-07-14`，prefs 含最近报告 / 历史且无 pending，cleanup 后 deep state `ACTIVE`、正式包 pid `4980`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook；目标静态门禁 6 项、最终全量稳定门禁 523 项和 analyze 通过。该结果证明进程死亡后的自然系统调度可恢复，但 initialDelay 不是精确执行时间，仍不替代跨小时 / 跨日 Doze 或 OEM 长期观察；同日 iPhone13 隔离 release BGTask smoke 再次通过解锁预检、构建、安装和 READY，但系统仍返回 `There are no scheduled tasks`，cleanup 后正式包已恢复运行，iOS 系统后台执行继续受后台 App 刷新状态约束；2026-07-14 本轮补 Android UI 进程被系统回收后的 WorkManager headless 冷启动真机 smoke：Pixel 8 隔离包先调度 30 秒 initialDelay 的 job，Home 后以 `am kill` 回收旧 pid `30424`，确认 package 未进入 stopped 状态并等待 35 秒使 WorkSpec 到期，再精确 force job id `0`；`ActivityManager` 随后为 `SystemJobService` 冷启动不同的新 pid `30629`，后台 Flutter isolate 输出 `status=completed digest=2026-07-14 reflection=2026-07-14`，cleanup 后 deep state `ACTIVE`、正式包 pid `30813`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook 残留；目标静态门禁 5 项、最终全量稳定门禁 522 项和 analyze 通过。该证据只证明 WorkSpec 到期后 forced callback 可冷启动 headless 进程，不替代自然时延、数小时 / 跨日 Doze 或 OEM 杀后台观察；2026-07-14 本轮补 Android WorkManager 系统后台 Dreaming / Reflection：一次性唯一任务、后台 ProviderContainer、跨 isolate SQLite 原子 claim、Reflection pending retry 和设置页边界已落地；Pixel 8 独立包 `top.simitalk.aichat.backgroundsmoke` 在 Home 后先尝试 Android 16 namespaced JobScheduler 命令，因最终 `workmanager 0.8.0` 使用 legacy job 自动回退到无 namespace 命令并成功强制运行真实系统 job，输出 `status=completed digest=2026-07-14 reflection=2026-07-14`，隔离 prefs 含 Dreaming / Reflection 最近报告与历史，cleanup 后正式包 identity 不变、pid `12024`、无隔离包 / sqlite hook 残留；最终全量稳定门禁 499 项通过、analyze 无问题，日志无 `WARNING (drift)` / `multiple databases`；同日补 Pixel 8 Dreaming / Reflection 失败恢复独立包真机 smoke：安全路径 build / adb 安装 `top.simitalk.aichat.dreamingsmoke`，真机先输出 pending `dayKey=2026-07-14 attempts=1`，Home / resumed 后输出 recovered `attempts=2 history=1`；cleanup 无隔离包 / sqlite hook 残留，普通 release pid 可见，修正后 smoke 前后正式包 firstInstallTime / dataDir 不变，代码门禁 124 项和 analyze 通过。首次 `flutter test -d` 动态 applicationId 方案错误卸载正式包，Pixel 8 私有数据丢失且 LocalTransport / D2D restore 均 `-1000`，已废弃该路径、补静态门禁并记录事故；2026-07-13 本轮补 Reflection 独立失败恢复 v1：新增 `assistant_reflection_pending_v1`，反思开始前写 pending、最近报告与历史均保存后清除；应用启动 / 恢复前台 / 前台定时检查自动重试，旧来源先从 Dreaming 历史、再从 SQLite report 按 dayKey 恢复；设置页展示来源与尝试次数并允许清除，手动失败有明确反馈，清空 / 删除来源报告同步清理，结构化备份包含 pending。移动端正常路径与失败恢复 smoke、Reflection / Dreaming / 通知 / 设置页 / 上下文注入 / SQLite / 导出导入稳定门禁 120 项通过，`flutter --no-version-check analyze --no-pub` 无问题，1000 条消息 Dreaming 基准 `run_ms=78` / `digest_elapsed_ms=74` / `memory_candidates=40`；2026-07-09 本轮继续补 PC Node MCP 容器 Runtime 可用工具与权限边界：容器 `runtime-server.mjs` 新增 `simichat.fs_list` / `simichat.fs_read_text` / `simichat.fetch_text`，文件工具限制在 `MCP_RUNTIME_WORKSPACE_ROOT` 内并限制文本字节数，fetch 仅允许 HTTP(S) GET，避免继续依赖宿主机 `npx` filesystem/fetch 类 MCP；`scripts/mcp_runtime_container.sh smoke` 扩展验证 fs / fetch 工具，真实容器 smoke 输出 `SMOKE_FS_TOOL_OK` / `SMOKE_FETCH_TOOL_OK`，复查未留下运行容器 / 临时镜像。2026-07-09 本轮继续补 MCP Runtime App 侧管理入口：新增 `lib/shared/providers/mcp_runtime_provider.dart`，用 Riverpod 管理 PC Node 容器 Runtime 状态 / 启动 / 停止 / smoke，自带移动端 unsupported 边界文案；设置页 MCP 区新增“MCP Runtime（内建 / PC 容器）”入口，移动端明确走 App 内建 Runtime，PC 端可触发容器状态刷新 / 启动 / 停止 / 自检；`pubspec.yaml` 将 Runtime 脚本 / Dockerfile / Node server 作为 Flutter assets 打包，桌面安装后可释放到应用支持目录执行，不依赖源码仓库路径；新增 `test/mcp_runtime_provider_test.dart` 与 `test/settings_page_mcp_runtime_test.dart` 覆盖移动端边界、PC 容器生命周期解析、失败诊断和设置页入口。验证：新增测试 4 项通过；MCP 聚焦 14 项通过；Runtime asset manifest 测试 6 项通过；`flutter --no-version-check analyze --no-pub` 无问题；全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 472 项通过；真实容器 smoke 继续通过且未留下运行容器 / 临时镜像；2026-07-08 本轮补 MCP 市场旧 stdio 外部依赖降级：市场安装 `stdio` / `npx` 类旧条目时默认 `isEnabled=false`，不再自动连接也不提供 SnackBar 直接连接动作，提示优先使用 `SimiChat Node 容器 Runtime`；`app_native` 与 SSE 容器项仍可自动连接。2026-07-08 本轮继续加固 PC Node MCP 容器侧车自检：`scripts/mcp_runtime_container.sh` 新增 `smoke` 命令，覆盖启动容器、`/health`、MCP SSE endpoint、`tools/list` 和 `simichat.echo` 工具调用；README / 容器 manifest 测试同步约束该入口。已启动 OrbStack / Docker daemon（`docker info` 返回 29.4.0），默认 `node:22-alpine` 拉取被 Docker Hub `Bad Gateway` 阻塞后，为 Dockerfile / 脚本补 `SIMICHAT_MCP_RUNTIME_BASE_IMAGE` 基镜像覆盖；使用本机预拉取且自带 Node 22 的 `ghcr.io/basketikun/infinite-canvas:latest` 成功跑通真实容器 smoke，输出 `SMOKE_HEALTH_OK` / `SMOKE_TOOL_LIST_OK` / `SMOKE_TOOL_CALL_OK`，复查未留下运行容器并清理临时 `simichat-mcp-runtime:smoke` 镜像；Flutter 聚焦测试通过。2026-07-08 本轮补 MCP SSE 相对 endpoint 回归：新增 `test/mcp_sse_transport_test.dart`，先红灯确认容器 SSE 服务返回 `/mcp/messages/...` 相对地址时 `SseTransport` 会对相对 URI 直接 POST 并超时，修复后通过 `Uri.parse(url).resolve(...)` 按 SSE 源地址解析 message endpoint；验证 MCP 聚焦 9 项通过，`flutter --no-version-check analyze --no-pub` 无问题；同日尝试真实容器 smoke 时宿主 Docker daemon 未启动（`Cannot connect to the Docker daemon at unix:///Users/sanbo/.orbstack/run/docker.sock`），未留下运行容器；2026-07-08 本轮继续补 PC Node MCP 容器侧车 v1：新增 `tools/mcp_runtime/container/Dockerfile` / `runtime-server.mjs` / `package.json`、`scripts/mcp_runtime_container.sh`、`docs/runtime-manifest.example.json` 和市场项 `SimiChat Node 容器 Runtime`，容器内自带 Node 并通过 MCP SSE 暴露 `simichat.node_runtime_info` / `simichat.echo`，脚本不调用宿主机 node/npm/npx；验证 `test/mcp_runtime_container_manifest_test.dart` 4 项通过；2026-07-08 本轮补 MCP App 内建 Runtime 自依赖基线：新增 `app_native` 传输和 `AppNativeMcpTransport`，内建 `simichat.now` / `simichat.runtime_info`，MCP 市场首项 `SimiChat 内建工具` 可安装后自动连接，设置页默认 App 内建，移动端 / PC 端不依赖宿主机 Node / npx / Python；验证 `test/mcp_app_native_transport_test.dart` 4 项通过，`flutter --no-version-check analyze --no-pub` 无问题，全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 461 项通过；外部 Node MCP Runtime/容器侧车仍待下一步补；2026-07-07 本轮补 Dreaming failed job URL 脱敏：新增设置页 / 导出 / 恢复断言，先红灯确认 failed job 错误摘要仍会显示 `https://example.test/...`；修复后设置页 `_sanitizeDreamingFailedJobError()` 和 snapshot `_safeDiagnosticString()` 将 HTTP(S) URL 替换为 `[链接]`，同时保留独立 `token=***` / `api_key=***` 脱敏。验证：聚焦 3 项红灯后转绿；设置页 / 导出 / 导入 / Dreaming / DAO / 结构化备份专项 51 项通过；2026-07-07 本轮补 Dreaming failed job 恢复错误脱敏：新增 `restores dreaming failed job errors as sanitized diagnostics`，先红灯确认旧导出包 / 外部包导入时 `dreaming_jobs.error` 会原样写入 SQLite；修复后 `restoreSnapshot()` 落库前复用 `_safeDiagnosticString()`，避免导入 Bearer、`sk-*`、`token=raw` 和 `/Users/...` 路径。验证：聚焦用例红灯后转绿；导出 / 导入 / Dreaming / DAO / 结构化备份专项 36 项通过；2026-07-07 本轮补 Dreaming failed job 导出 / 恢复错误脱敏：新增 `exports dreaming failed job errors without leaking secrets or paths`，先红灯确认 `structured_data/local_database.json` 的 `dreaming_jobs.error` 会原样泄露 Bearer、`sk-*`、`token=raw` 和 `/Users/...` 路径；修复后 `LocalDatabaseSnapshotService` 导出层使用 `_safeDiagnosticString()` 二次脱敏，保留 failed 状态和可诊断摘要但不带原始密钥 / 本机路径。验证：聚焦用例红灯后转绿；导出 / 导入 / Dreaming / DAO / 结构化备份专项 35 项通过；2026-07-07 本轮补 Dreaming failed job 错误摘要脱敏：新增 `dreaming failed job error summary is sanitized`，先红灯确认设置页 failed job 弹窗会直接显示 Bearer token、`sk-*`、`token=raw` 和 `/Users/...` 本机路径；修复后 `_formatDreamingFailedJob()` 只展示脱敏摘要（`Bearer ***`、`[本机路径]`、`token=***`），避免失败截图 / 屏幕共享泄露密钥或本机路径。验证：聚焦用例通过；设置页 / Dreaming / DAO 专项 28 项通过；完整 Dreaming / 通知稳定门禁 86 项通过，warning 扫描 `WARNING (drift)|multiple databases` 无输出；2026-07-07 本轮补 Dreaming 设置页手动运行失败反馈：新增 `dreaming manual run failure shows retryable feedback`，先红灯确认 `_runDreaming()` 会把 `runDreamingDigest()` 异常抛到 Flutter 测试框架且无用户提示；修复后设置页手动运行失败显示“Dreaming 失败，可到设置页重试”，不崩溃、不写半成功报告，并保留最近未解决 failed job 供设置页查看 / 重试。验证：聚焦用例通过；设置页 / Dreaming / DAO 专项 27 项通过；完整 Dreaming / 通知稳定门禁 85 项通过；2026-07-07 本轮补 Dreaming 前台到期失败本地通知：新增 `buildDreamingDigestFailedNotificationBody()` 和 `NotificationService.showDreamingDigestFailed()`，失败通知标题为“Dreaming 整理失败”，正文为“YYYY-MM-DD 整理失败，可到设置页重试”，不回显底层错误；`_runDueDreamingIfNeeded()` 捕获前台到期整理失败后读取最近未解决 failed job 并通过 `dreamingDigestFailedNotifier` 推送，同一进程同一 dayKey 只通知一次。验证：通知文案和移动端失败通知 smoke 均先红灯，修复后 `flutter --no-version-check test --no-pub --no-test-assets test/notification_service_test.dart -r expanded` 8 项通过，`flutter --no-version-check test --no-pub --no-test-assets test/mobile_main_flow_smoke_test.dart --name dreaming -r expanded` 9 项通过；完整 Dreaming / 通知稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/mobile_main_flow_smoke_test.dart test/notification_service_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 84 项通过；2026-07-07 本轮补 Dreaming failed job 启动 / 恢复前台主动提示：新增移动端 smoke 红灯 `mobile startup prompts for unresolved dreaming failure` 和 `mobile resume prompts for unresolved dreaming failure`，`ResponsiveShell` 启动任务 / `resumed` 生命周期会在 due Dreaming 检查后读取 `latestFailedDreamingJobProvider`，存在未解决 failed job 时弹出“上次 Dreaming 失败，可到设置页重试”，并提供“去设置”动作；同一进程同一 failed job 只提示一次，避免反复打扰。验证：两条用例均先红灯，修复后 `flutter --no-version-check test --no-pub --no-test-assets test/mobile_main_flow_smoke_test.dart --name "dreaming failure" -r expanded` 2 项通过；Dreaming smoke `--name dreaming` 8 项通过；Dreaming / 设置页 / DAO 专项 26 项通过；完整 Dreaming 稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/mobile_main_flow_smoke_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 75 项通过；2026-07-07 本轮补 Dreaming failed job 可见状态与重试入口：新增 `DreamingDao.getLatestUnresolvedFailedJob()`，只返回未被同日后续 completed job 覆盖的最近 failed job；新增 `latestFailedDreamingJobProvider`，`runDreamingDigest()` 成功 / 失败后刷新该状态；设置页 Dreaming tile 会提示“最近失败 YYYY-MM-DD · 可重试”，弹窗展示失败来源 / 错误并提供“重试最近失败”，重试成功后失败提示消失。先红灯于缺少 `getLatestUnresolvedFailedJob()` 和 UI 提示；修复后 `flutter --no-version-check test --no-pub --no-test-assets test/dreaming_dao_test.dart test/dreaming_provider_test.dart test/settings_page_dreaming_test.dart -r expanded` 26 项通过；Dreaming / 数据完整门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 54 项通过；2026-07-07 本轮补 Dreaming job 去重 / 恢复：先用 `runDreamingDigest reuses same-day in-flight job` 红灯确认同日并发手动触发会产生 2 个 completed job，再用 `runDreamingDigest fails stale unfinished jobs before new run` 红灯确认崩溃残留 pending / running 不会被收敛；修复后 `runDreamingDigest()` 按 `dayKey` 复用 in-flight Future，并在新运行前通过 `DreamingDao.failUnfinishedJobsByDay()` 将同日未完成 job 标记 failed，避免重复落库和 stale running 阻塞后续后台调度；专项 `flutter --no-version-check test --no-pub --no-test-assets test/dreaming_dao_test.dart test/dreaming_provider_test.dart -r expanded` 12 项通过；Dreaming / 数据完整门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 52 项通过；`flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出；`pubspec.yaml` / `pubspec.lock` 无临时 sqlite hook 残留；2026-07-07 本轮补 iOS release 网络恢复 smoke 入口：新增 `release_network_smoke_harness.dart` 与 `scripts/smoke_ios_release_network_restore.sh`，通过 `SIMICHAT_RELEASE_NETWORK_SMOKE=true` 注入 fake `ConnectivityMonitor` 模拟 `wifi -> none -> wifi`，写入 `Documents/ai_chat/release_network_smoke/ios-release-network-smoke.json`，脚本具备安装前解锁预检、临时 sqlite system hook、失败 / 成功后普通 release 恢复路径；本轮按用户要求未触碰 people，仅完成代码 / 脚本 / manifest 门禁，`test/release_send_smoke_manifest_test.dart` 14 项通过，`flutter --no-version-check analyze` 无问题；2026-07-07 本轮继续推进 Android 音频焦点丢失 smoke：在 Pixel 8 `37101FDJH0077P` 上将 `mobile_audio_focus_loss_smoke_test.dart` 从直接调用 `simulateAudioFocusLossForTesting` 推进为 debug-only `requestCompetingAudioFocusForTesting` 竞争 `AUDIOFOCUS_GAIN_TRANSIENT`，覆盖 Android `AudioManager` 焦点仲裁路径，`scripts/smoke_device_integration_audio_focus_loss.sh 37101FDJH0077P` 通过，随后继续新增 `integration_test/mobile_external_audio_focus_smoke_test.dart` 与 `scripts/smoke_device_external_audio_focus.sh`，脚本临时生成独立 helper APK `top.simitalk.aichat.audiofocusstealer`，在 SimiChat 播放静音 WAV 并输出 `SIMICHAT_EXTERNAL_AUDIO_FOCUS_READY` 后从另一个包请求 `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE`，Pixel 8 通过并验证 stopped、无 completed、无 error，helper 包已卸载；随后新增 `scripts/smoke_android_audio_focus_suite.sh`，一键串联 debug-only competing focus 与外部 helper APK 抢占焦点两条 smoke 并自动恢复普通 Android release，Pixel 8 通过，最终 release 启动 pid `12728`；iPhone13、people 与 biao 的 iPhone 复跑 iOS release send 均被 launch preflight timeout / CoreDevice 定位失败安全拒绝，未安装 smoke 包；本轮继续复查 iOS release 发送 smoke：在 iPhone13 `00008110-0016349A3A20A01E` / CoreDevice `CAFC7AFA-4565-5C8D-B724-090061D144D0` 上，当前 release send harness 的发送 / 重试 / 模型切换前半段进入真实 release 路径，但 stop 慢流先红灯于 runId `ios-release-send-20260707100852` 与 `ios-release-send-20260707101242`，mock 记录 `lastUser=ios release stop smoke` / `completed=true` / `brokenPipe=false`；随后修复 `cancelStreaming()` 显式取消 active `StreamSubscription`，补 `openSseStream()` 下游取消时传播 `CancelToken.cancel()`，release send harness 内置 SSE mock 关闭 `bufferOutput`，并把 `smoke_ios_release_send.sh` 加固为安装 smoke 包前必须 launch preflight 证明设备已解锁，Locked / timeout / 未证明解锁均 exit 2，安装 smoke 后失败会自动恢复普通 release；本轮已恢复普通 release 覆盖安装到 iPhone13（`databaseSequenceNumber=4376`），但设备随后 Locked / preflight timeout，修复后的 release send 全链路复跑被安全拒绝，待设备解锁后重跑；随后用 Pixel 8 复跑 Android 后台慢流取消真机 smoke，先红灯暴露取消订阅后 `DioException [request cancelled]` 未被吞掉和 teardown 后 lifecycle 读 disposed provider 风险，修复后 `scripts/smoke_android_background_stream_cancel.sh 37101FDJH0077P` 通过，并用 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release（pid `4150`，`lastUpdateTime=2026-07-07 10:41:24`）；同日继续补 Ollama 本地 NDJSON 流式取消传播，先红灯确认 `CancelToken.cancel()` 后旧实现不会结束流（`TimeoutException: cancelDone`），修复后 `test/ollama_protocol_test.dart` 通过，并与 OpenAI Chat / Responses / release manifest / retry 聚焦回归 21 项通过；同日继续补 Android 音频焦点丢失设备 smoke：新增 `integration_test/mobile_audio_focus_loss_smoke_test.dart` 与 `scripts/smoke_device_integration_audio_focus_loss.sh`，先红灯确认缺少 `simulateAudioFocusLossForTesting` 原生入口，随后在 Android `MainActivity` 增加 `ApplicationInfo.FLAG_DEBUGGABLE` 限制的 debug-only 测试方法，触发 `AUDIOFOCUS_LOSS_TRANSIENT` 后复用正式 `stopAudioPlayback()`；Pixel 8 通过该 smoke，验证播放中收到 stopped、无 completed、无 error；同日继续补 Android 后台慢流取消真机 smoke：新增 `integration_test/mobile_background_stream_cancel_smoke_test.dart` 与 `scripts/smoke_android_background_stream_cancel.sh`，先红灯复现真实慢流取消时 `DioException [request cancelled]` 和异步流程触碰已 dispose provider 风险，随后在 `chat_provider` 中记录后台取消错误并让 `_runAssistantResponse()` 保持可重试错误后直接返回；Pixel 8 通过 `scripts/smoke_android_background_stream_cancel.sh 37101FDJH0077P`，验证真实 `/v1/chat/completions` 慢流请求进入等待首 token 后 lifecycle inactive/resumed 会保留 `backgroundStreamingInterruptedMessage`、展示“已停止后台生成，可点重试继续”、消费 marker，且不落库 assistant 半截回复；随后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release 并启动 pid `22529`；同日继续补后台待重试 marker 代码级恢复：新增用例先红灯确认 marker 指向非当前会话时仍停在最新会话，修复后冷启动会切回 marker 会话、恢复错误条并消费 marker；继续补 stale marker 清理和列表 marker 恢复，冷启动可恢复多条仍存在会话的后台中断错误态、跳过缺失会话并清理新旧 marker；随后补用户主动重试 DAO 兜底和快速切后台 / 前台 marker 写入 / 清理竞态，`test/mobile_main_flow_smoke_test.dart` 16 项通过、`test/chat_provider_retry_test.dart` 1 项通过；同日延续移动端真机稳定性补证：Android Wi-Fi / data 断开恢复、Android 飞行模式恢复、Android Home 后台再前台恢复均已在 Pixel 8 通过；新增 iOS release 后台恢复 smoke harness / 脚本；先在 people 上尝试时被 CoreDevice Locked 阻塞且脚本已执行普通 release 恢复，本轮随后在 iPhone13 复跑通过（runId `ios-release-background-20260707100131`，launch pid `80004`，suspend/resume 后 `gapMs=3214` / `status=passed`），脚本最终恢复普通 release 并启动 pid `80007`；2026-07-06 本轮继续补 Pixel 8 真机主链路：通过本机 OpenAI 兼容 mock 服务 + `adb reverse` + debug 私有 DB seed，验证默认模型展示、真实发送、SSE 回复落库 / UI 展示、Reflection 短期提示进入 system prompt、assistant 重试、慢流停止断开上游并保留部分回复、历史搜索按 `smoke` 过滤；同日继续验证顶部模型菜单 `simichat-mock-a → simichat-mock-b` 切换、`model_switch` 时间线落库、切换后真实发送使用 B 模型；新增 `integration_test/mobile_real_send_smoke_test.dart`，Pixel 8 真机通过设备内本地 OpenAI mock 验证 UI 输入 → SSE → assistant 落库 → UI 展示闭环，并新增 `scripts/smoke_device_integration_send.sh` 封装临时 sqlite3 hook / 恢复 / 真机测试；`flutter --no-version-check analyze` 通过，命令内临时 `sqlite3.source=system` 后全量 `flutter --no-version-check test --no-pub --no-test-assets` 330 个测试通过；Pixel 8 Dreaming/Reflection 72 条长会话基线已完成，iPhone13 release 覆盖安装成功且进程可见；本轮进一步确认 iPhone13 集成发送和普通 `flutter run --debug` 都卡在 Xcode debug session `CONFIGURATION_BUILD_DIR` 超时，问题不在 integration_test 测试体；随后直接 `xcodebuild` Debug 构建可正常产出 `CONFIGURATION_BUILD_DIR` 并构建成功，同一 Debug 产物通过 `devicectl install app` 覆盖安装到 `top.simitalk.aichat`，但 `devicectl process launch` 曾被设备 Locked 状态拒绝；本轮进一步按用户要求确认 iOS 必须 release 运行，debug integration 不再作为 iOS 有效证明；新增 `scripts/smoke_ios_release_install_launch.sh` 复跑 iPhone13 release 构建 / 覆盖安装 / 启动通过（Runner.app 33.1MB，安装 `bundleID=top.simitalk.aichat` / `databaseSequenceNumber=4264`，launch pid `79321`）；随后新增 `scripts/smoke_ios_release_send.sh` 和 release-only harness，在 people 设备通过 iOS release 发送闭环（runId `ios-release-send-20260706121606`，mock 收到 `/v1/chat/completions` / `model=ios-release-smoke-model` / `lastUser=ios release send smoke`，assistant 回复 `IOS release smoke reply 20260706`，脚本恢复普通 release 后 launch pid `64165`，补充取证 `SMOKE_ARCHIVE_ABSENT`）；同日新增 `integration_test/mobile_settings_smoke_test.dart` 与 `scripts/smoke_device_integration_settings.sh`，Pixel 8 真机通过设置页入口、主题切换、字体缩放 120% 持久化和返回首页闭环；新增 `integration_test/mobile_markdown_scroll_smoke_test.dart` 与 `scripts/smoke_device_integration_markdown_scroll.sh`，Pixel 8 真机通过复杂 Markdown 长消息、Mermaid / Draw.io 组件实例化和滚动到底部哨兵；新增 `integration_test/mobile_base64_audio_smoke_test.dart` 与 `scripts/smoke_device_integration_base64_audio.sh`，Pixel 8 真机通过 base64 语音粘贴解析、audio 附件归档、fake STT ready sidecar、净化后模型请求和 SSE 回复闭环；新增 `integration_test/mobile_stt_network_smoke_test.dart` 与 `scripts/smoke_device_integration_stt_network.sh`，Pixel 8 真机通过复用当前 OpenAI 兼容聊天渠道调用 multipart `/v1/audio/transcriptions`、ready sidecar、净化后聊天请求和 SSE 回复闭环；新增 `integration_test/mobile_voice_recording_smoke_test.dart` 与 `scripts/smoke_device_integration_voice_recording.sh`，Pixel 8 真机通过聊天页麦克风按钮、Android 原生录音 `.m4a`、audio 附件归档、STT fallback、ready sidecar、净化后聊天请求和 SSE 回复闭环；新增 `integration_test/mobile_tts_network_smoke_test.dart` 与 `scripts/smoke_device_integration_tts_network.sh`，Pixel 8 真机通过 assistant 播报按钮、OpenAI 兼容 `/v1/audio/speech` JSON 请求、临时音频写入、播放接口调用、停止播报和 UI 状态回退闭环；新增 `integration_test/mobile_native_audio_player_smoke_test.dart` 与 `scripts/smoke_device_integration_native_audio_player.sh`，Pixel 8 真机通过应用私有目录 WAV、Android `MediaPlayer` 播放、stop 调用、stopped 事件回传和无错误事件闭环；新增 `integration_test/mobile_long_audio_playback_smoke_test.dart` 与 `scripts/smoke_device_integration_long_audio_playback.sh`，Pixel 8 真机通过 6.5 秒应用私有目录 WAV、Android `MediaPlayer` 自然播放完成、completed 事件回传和无错误事件闭环；随后统一加固 9 个真机 smoke 脚本的 `mktemp` 模板，避免中断后 `/tmp` 字面量文件碰撞导致临时 sqlite hook 残留，并用 Pixel 8 原生音频 smoke 复验脚本恢复；新增 `integration_test/mobile_audio_playback_replace_smoke_test.dart` 与 `scripts/smoke_device_integration_audio_playback_replace.sh`，Pixel 8 真机通过播放中启动第二段 WAV 时第一段 stopped、第二段 completed 且无 error 的替换 / 中断闭环；随后 Android 原生播放补上 `AudioManager` 音频焦点处理，焦点丢失 / 短暂丢失会停止播放，允许 duck 时降音量并在焦点恢复时还原；direct-channel 原生音频 smoke 因 instrumentation 不属于普通前台用户点击流，显式使用 `playFileForTesting(..., skipAudioFocusRequest: true)` 跳过焦点请求并改为真实时间轮询事件；已通过静态回归、全量 335 个测试、`flutter --no-version-check analyze`、临时 sqlite hook 下 Android debug APK 与 iOS Debug 构建和 Pixel 8 静音原生播放 / 长音频 / 替换播放三条 smoke 复验；随后 iOS 原生播放补上 `AVAudioSession.interruptionNotification`，interruption began 会停止播放并回传 stopped，播放完成 / 错误 / 停止 / 启动失败都会释放音频会话。 | iOS release 手工 UI 停止 / 重试 / 模型切换、真实云端 STT / TTS、真实第三方播放器 / 来电 / 闹钟音频焦点抢占、iOS 真机音频中断、iOS 网络切换 / Android 飞行模式细分、复杂 Markdown 视觉审查等交互仍待补 |

#### 0.2.0 2026-08-18 多模态客户端、模型切换与 Android Release 复验

- 当前工作树已经具备 ChatGPT / OpenAI 风格移动聊天页：顶部模型入口、消息展示区、底部多行 Composer、`+` 多模态菜单、图片 / 参考图 / 图片编辑、视频 / 音乐任务、STT / TTS、声音设计 / 克隆配置和 Realtime 语音面板；实现证据与未验证边界分别记录在 `docs/chat-composer-multimodal.md`、`docs/media-attachments.md`、`docs/multimodal-capability-audit-2026-08-18.md`。
- luna_worker 完成模型切换真机 smoke 初始化竞态修复和 cleanup 幂等修复；主线程进一步加固隔离脚本：固定当前工作树 `modelswitch` APK、安装前 `aapt` applicationId 校验、隔离包已存在时拒绝覆盖、正式包完整 `pm path` / `base.apk` hash / `firstInstallTime` / `dataDir` 保护、唯一日志、四个 marker 的唯一性和顺序校验。正式包不执行 `install`、`uninstall`、`pm clear`、`force-stop`、`monkey` 或 `am start`。
- Pixel 8 `37101FDJH0077P` 真机执行 `scripts/smoke_device_integration_model_switch.sh 37101FDJH0077P` 通过：`SIMICHAT_MODEL_SWITCH_BASELINE` → `SIMICHAT_MODEL_SWITCH_UI_ACTION` → `SIMICHAT_MODEL_SWITCH_DB_EVIDENCE` → `SIMICHAT_MODEL_SWITCH_SMOKE_PASS`；会话默认模型、Riverpod 选中模型和 SQLite `model_switch` system message 均从 `model-switch-first` 切换到 `model-switch-second`；`top.simitalk.aichat.modelswitch` 已清理。
- 随后用 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 重新构建并 `adb install -r` 覆盖安装 production Release。`ANDROID_RELEASE_PARITY status=verified`；APK / 设备 `base.apk` SHA-256 为 `4c129d2ac4b9e4fbcf310f8f950081447ff58f2042f7c455f8221b25fcb34247`，证书 SHA-256 为 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 不变，`lastUpdateTime=2026-08-18 10:02:22`，PID `25256`，前台 `top.simitalk.aichat/.MainActivity`。
- 随后由 `luna_worker` 完成 Composer 声音工具增量：`声音合成`、`声音克隆`、`声音设计` 三个独立入口、稳定 key、独立 disabled reason、参考音频附件消费和设置中已归档参考音频复用；`ChatPage` 普通 / 空会话均接入现有 provider-aware TTS 边界。`test/chat_input_bar_voice_tools_test.dart` 4 项通过，声音 / 图片 / 媒体 / ChatPage focused 回归 61 项通过。
- 本轮 Flutter analyzer 无问题；全量 Flutter 测试 **1012 项通过**，`dart format`、`git diff --check` 无输出。上述媒体 / 语音 / Realtime 测试主要是本地 mock、loopback、fake adapter、Widget 或 protocol evidence，不宣称真实厂商云端 E2E；真实 OpenAI / xAI / Gemini / Claude、Ollama inference、Realtime WSS、视频 / 音乐生成、真实 TTS / 声音克隆 / 声音设计与长音频质量仍待外部凭据和服务配置。
- 最新 Production Release 覆盖安装 hash 为 `4c129d2ac4b9e4fbcf310f8f950081447ff58f2042f7c455f8221b25fcb34247`，`lastUpdateTime=2026-08-18 10:02:22`，PID `25256`；UI Automator 已在真机展开并滚动 `+` 菜单，看到 `生成视频`、`声音合成`、`声音克隆`、`声音设计`、`生成音乐` 以及未配置原因。模型切换隔离 smoke 也在同一工作树重新通过，正式包仍保持同一 path / hash / firstInstallTime / dataDir，隔离包已清理。

#### 0.2.1 Android 跨日 Dreaming / Reflection 进行中验证

- 2026-07-14 已补跨日分离式 `schedule / status / verify / cleanup` 基础设施：harness 将 seed 消息时间写入预定执行日；30 秒两阶段自然调度 / 独立 verify 自测和 600 秒未到期主动 cleanup 均已通过；目标静态门禁 7 项、全量稳定门禁 524 项和 `flutter --no-version-check analyze --no-pub` 已通过。
- Pixel 8 `37101FDJH0077P` 已安全调度 86400 秒真实任务，隔离包 `top.simitalk.aichat.backgroundsmoke` 的旧 pid `28141` 已消失，JobScheduler job id `0` 当前为 `waiting`，目标 dayKey 为 `2026-07-15`。原 `/tmp` 状态文件在任务仍等待时提前消失，已补红灯回归并把默认状态路径改为仓库私有 `.omx/state/android-background-dreaming-cross-day.state`（0600）；当前任务状态已从设备 / 账本证据恢复，独立 `status` 再次显示 job `waiting`。调度退出后正式包已恢复，firstInstallTime / dataDir 不变，仓库无临时 sqlite hook。
- 该项仍为进行中：到期后必须执行独立 `verify`，确认 Dreaming / Reflection 最近报告与历史、无 `assistant_reflection_pending_v1`、目标 dayKey 和正式包 identity，再自动清理隔离包；verify 前禁止重新 schedule、卸载隔离包或提前标记跨日验证通过。

#### 0.2.2 Dreaming / Reflection 后台附加条件 v1

- 2026-07-14 已补用户可配置的“仅充电时执行”和“仅非计费网络执行”：`DreamingScheduleConfig` / `dreaming_schedule_v1` 新增默认关闭的 `requiresCharging` / `requiresUnmeteredNetwork`，旧配置兼容，设置变化立即重排系统后台任务，结构化备份 / 恢复保留配置。
- Android WorkManager 映射为 `requiresCharging` 与 `NetworkType.unmetered`；iOS 支持充电条件，但 `workmanager 0.8.0` 的 Apple 侧只能表达“要求联网”，不能严格保证 Wi-Fi，移动端设置页已明确提示该边界。390x844 设置页操作、配置 / 调度 / 平台映射 / 备份聚焦 36 项通过；新增真机约束门禁后全量稳定门禁 530 项通过，`flutter --no-version-check analyze --no-pub` 无问题。
- Pixel 8 独立包真机约束 smoke 已闭环：非计费网络 job 在 Wi-Fi 关闭时被严格 `jobscheduler run -s` 拒绝，恢复 `WIFI + NOT_METERED + VALIDATED` 后放行，66 秒完成 Dreaming / Reflection 且无 pending；充电诊断包注册后的系统 `JobInfo` 明确为 `Requires: charging=true`，未充电时 `Unsatisfied constraints: CHARGING` 且严格运行被拒绝，随后系统切换为 `get-battery-charging=true`、`Satisfied constraints` 包含 `CHARGING`，任务未使用 `-f`，在 300 秒 initialDelay 后由 JobScheduler 自然执行，elapsed `322` 秒完成 `digest=2026-07-14 reflection=2026-07-14`。cleanup 后 battery mock 恢复、正式包 firstInstallTime / dataDir 不变、无约束隔离包 / sqlite hook，原跨日 job id `0` 仍 waiting。
- 同轮模型 Reflection 兼容性继续补强：真实采样确认小模型会返回尾逗号、全角右括号、缺失根闭合、`nextStep` / `nextAction` action object 和 schema 占位内容，解析层只对这些已证实模式做保守修复并继续执行全部安全过滤。更关键的是 `AiProtocol → AiService → ChannelModelRelayBridge` 新增 `jsonResponse` 提示，Reflection 正式路径对 Ollama 使用 `format=json`、`think=false`、`temperature=0`，普通聊天保持原行为。修正 live gate 本地规则已占满 8+8、导致模型永远无空间的错误数据后，本机真实 Ollama `qwen3:4b` 曾在 72 条长会话上连续 5 / 5 通过，单次约 14.7–14.9 秒，本地 5 条结论 / 4 个行动项合并为最终 8 / 8，保留全部本地安全基线且无密钥、URL、本机路径和虚假完成结论。该结果只作为历史证据保留，按当前用户约束禁止再次启动、探测或重跑本地模型；后续模型质量验证只使用仓库外配置驱动的远程接口。最终全量稳定门禁 544 项通过，`flutter --no-version-check analyze --no-pub` 无问题，`git diff --check` 无输出。
- 2026-07-15 02:34 补系统后台通知失败隔离：审计发现完成通知抛异常会把已经持久化成功的 Dreaming / Reflection 继续向外抛成 WorkManager 失败，失败通知抛异常也会掩盖原始 `failed` 结果。新增两条回归均先红灯；修复后通知作为可选副作用有界捕获，只记录异常类型、不记录可能含敏感信息的错误正文。完成通知失败仍返回 `completed` 并保留 completed job、Dreaming / Reflection 当前与历史且无 pending；失败通知失败仍返回 `failed` 并保留 failed job。background runner 单文件 8 项、Dreaming / Reflection / 通知 / 调度聚焦 50 项通过；提交前使用低优先级完整稳定门禁复核 569 项全部通过，`flutter --no-version-check analyze --no-pub` 无问题，`git diff --check` 通过。Android 跨日 job id `0` 仍为 `waiting`，未被扰动。本轮未启动、调用或探测 Ollama / 本地模型。

#### 0.2.3 iOS BGTask 阻塞诊断与系统设置入口

- 2026-07-14 iPhone13 隔离 release smoke 再次通过解锁预检、27.5MB 构建、安装、启动和 READY 文件；增强后的 READY JSON 由原生通道直接输出 `backgroundRefreshStatus=denied`，同时 `scheduledTasks=[BGTaskScheduler] There are no scheduled tasks`，明确证明系统后台任务未进入 pending 的当前原因。
- 设置页 denied / restricted 状态新增“打开系统设置”和“重新检查”：原生通道使用 `UIApplication.openSettingsURLString`，用户返回后可主动刷新状态。TDD 红灯后 iOS 状态 / release manifest / 设置页聚焦 27 项通过；iOS release 真机构建也验证 Swift 通道可编译。新增 1 项测试后全量稳定门禁 531 项通过，`flutter --no-version-check analyze --no-pub` 无问题。
- cleanup 后隔离 bundle 已卸载，正式 `top.simitalk.aichat` 存在并运行 pid `86792`，仓库无 sqlite hook。该结果只让 blocker 可诊断、可操作；BGTask Dreaming / Reflection 真机执行仍必须在用户开启后台 App 刷新后重新验证。
- 2026-07-14 23:50 新增无构建、无安装的只读入口 `scripts/check_ios_background_refresh_status.sh`：只启动已安装正式 App、通过 LLDB 读取 `UIApplication.backgroundRefreshStatus`、detach 后校验正式 App identity，不替换工程、不安装 / 卸载 bundle、不修改 App 数据。LLDB 使用系统 `/usr/bin/true` 作为临时 arm64 target，不依赖 `build/ios` 或本地 Runner 产物。iPhone13 当前实时读取 `raw=1 status=denied`，因此安全跳过必然失败的 release BGTask smoke；状态 / 脚本 / 原生通道聚焦 7 项通过。取证：`/tmp/simichat-ios-background-refresh-status-20260714235035.log`。
- 2026-07-15 01:47 只读状态入口补 LLDB 瞬时中断恢复：真机一次附加成功后，`backgroundRefreshStatus` 表达式被临时 `SIGSTOP` 中断并返回空状态，手工复跑立即成功。脚本现仅在读取失败时重新启动正式 App、获取新 pid 并最多重试 1 次，成功即停止；仍不构建、不安装、不卸载、不改数据，并继续比较正式 App identity。manifest 测试先红后绿，shell 语法和 diff 检查通过；通过 `/tmp` xcrun wrapper 注入首次 LLDB 失败后，第二次真机读取成功输出 `raw=1 status=denied`，取证 `/tmp/simichat-ios-background-refresh-retry-20260715014745.log`。Android 跨日 job id `0` 同时复查仍为 `waiting`，未被扰动；本轮未启动或访问 Ollama / 本地模型。

### 0.2.4 2026-08-07 DW Chainless 中转站集成与图片生成

- **需求**：模型部分预置自有中转站 `https://api.dwchainless.com/`；用户填 Key 即用，无 Key 通过应用内 H5 打开 `https://api.dwchainless.com/sign-up?aff=Bslh` 直接注册；在关于页鸣谢中转站（带图标）。
- **已确认能力**：官网 200；`/v1` 301；`/v1/models` 401（Bearer 鉴权，确认 OpenAI 兼容）。Base URL 取 `https://api.dwchainless.com/v1`。
- **厂商预设**：`ModelProviderPreset` 新增可选 `signUpUrl`；新增 `dwchainless` OpenAI 兼容预设（推荐模型 `gpt-4o-mini` / `deepseek-chat` / `qwen-plus`，docsUrl 官网，signUpUrl 注册页），支持按 id / 显示名 / 别名查找。
- **设置页渠道区**：顶部 SimiRouter 推广卡片保留未接入 / 缺 Key / 已接入三态；添加渠道预设提示改为紧凑品牌卡，只展示接入说明、推荐模型和「获取 Key / 访问官网」两个明确动作。
- **应用内 H5**：新增 `InAppH5Page`，注册页与官网均通过 `webview_flutter` 在应用内打开，隐藏地址栏；当前策略已由 0.2.20 收紧为仅允许初始 host 的 HTTPS，阻止跨域、HTTP 降级以及 `intent:` / `mailto:` / `tel:` 等自定义 scheme；不再依赖 `url_launcher` 或系统浏览器。
- **关于页鸣谢**：新增「鸣谢 · SimiRouter AI 中转站」ListTile，点击进入无地址栏的内置官网 H5 页面。
- **图片生成 v1**：新增 `ImageGenerationService`（OpenAI 兼容 `/v1/images/generations`，优先 `b64_json` 本地保存、失败安全下载远端 URL、单图 10MB 上限）；`chat_provider.generateImage()` 编排（插入用户提示词消息 → 调用当前渠道 + 可配置图片模型 → 保存 `generated_images/` → 插入 assistant 消息 + 图片附件）；聊天输入框「✨」生成按钮（有文本且非流式时可用）；设置页新增「图片生成」区块 +「图片生成配置」弹窗（模型默认 `dall-e-3`，复用当前渠道 Base URL / Key）。生成图片本地保存不进入云端。
- **测试**：新增 `settings_page_dwchainless_test`（5）、`model_provider_preset_test` dwchainless 断言（2）、`image_generation_service_test`（7）、`chat_input_bar_image_generation_test`（2）、`settings_page_image_generation_test`（1）；因推广卡片增加页首高度，`settings_page_font_scale_test` 3 项与 `mobile_main_flow_smoke_test` 1 项改为先滚动到目标 tile。
- **验证**：`flutter --no-version-check analyze --no-pub` 无问题；全量 `flutter --no-version-check test --no-pub -r expanded` 586 项全部通过。
- **差距分析**：所有未完成项已映射到 `docs/implementation-gap-analysis-2026-08-07.md`（标注已实现 / 需真机补证 / 需外部资源及方案依赖）。

### 0.2.4.1 2026-08-09 SimiRouter 注册 / 官网内置 H5 体验

- 注册入口固定为 `https://api.dwchainless.com/sign-up?aff=Bslh`，点击「获取 Key」或预设提示卡中的同名按钮后，使用 `InAppH5Page` 原生页面打开，不跳转系统浏览器、不展示地址栏。
- 「访问官网」和关于页鸣谢使用同一套内置 H5 页面；页面顶部只保留返回、刷新和页面标题，WebView 历史优先于退出页面。
- WebView 当前只允许初始 host 的 HTTPS 主导航，跨域、HTTP 降级、`intent:` / `mailto:` / `tel:` 等自定义 scheme 直接阻止；Android / iPhone / Mac 使用系统 WebView，其他平台显示原生不支持提示，不回退外部浏览器。
- 添加渠道中的 SimiRouter 预设提示从完整 URL + 三个复制按钮收敛为品牌、接入说明、推荐模型和「获取 Key / 访问官网」两个主动作；官网地址不再作为可见文本出现在设置页。
- 验证覆盖 `test/in_app_h5_page_test.dart`、`test/settings_page_dwchainless_test.dart`、`test/model_provider_preset_test.dart` 及设置页预设 / 导入回归；全量 Flutter 测试 696 项通过，Pixel 8 真机 H5 路由 smoke 通过；真实网页内容的网络加载仍需单独联网观察。

### 0.2.5 2026-08-07 社交 / 搜索 / 云备份 / 笔记同步 / 多源技能市场 v1

把此前「需外部资源」的功能按**可配置凭据 + mock 测试**的生产级方式真正落地，均带本地 mock 服务器 / 注入式测试：

- **WebDAV 云备份 v1**：`WebDavBackupService` 用用户口令 E2E 加密导出包（`KeyEncryptor.encryptWithPassword`，口令不落盘）后 PUT 上传；PROPFIND 列出；下载解密后用 `DataImportService` 恢复。设置页「数据与档案 / 云备份 (WebDAV)」。
- **网页搜索 / RAG v1**：`WebSearchService`（DuckDuckGo Instant Answer，免 Key）；注册为 App 内建 MCP 工具 `simichat.web_search`，AI 可在对话中检索增强。
- **Telegram Bot 社交通道 v1**：`ChannelAdapter` 抽象（供飞书 / Discord 复用）+ `TelegramBotAdapter`（getMe / getUpdates 长轮询 offset 去重 / sendMessage）+ `ChannelBotGateway`（AI 应答，每用户有界历史）+ `telegramBotProvider`（Token 加密落盘，定时轮询）。设置页「社交通道 / Telegram Bot」。
- **Notion 同步 v1**：`NotionSyncService`（Integration Token + 父页面下创建子页面 + heading / paragraph 块）+ 设置页批量导出会话。
- **多源技能市场 v1**：`SkillMarketplaceSource` 抽象（统一 search / install + SHA-256 校验）+ `SkillHubMarketplaceSource` 适配器 + `GenericHttpSkillMarketplaceSource`（自定义 HTTP 技能源，OpenClaw 风格 index.json）。
- **依赖**：`xml ^6.6.1`（WebDAV PROPFIND 解析）。
- **测试**：新增 WebDAV 服务 / 设置、网页搜索 / MCP 工具、Telegram 适配器 / 网关、Notion 服务 / 设置、技能市场 5 类测试；`settings_page_dreaming_test` 9 处反思入口因设置页新增区块改为滚动后 `ensureVisible` 再点击。
- **验证**：`flutter --no-version-check analyze --no-pub` 无问题；全量 `flutter --no-version-check test --no-pub -r expanded` **614 项全部通过**；`git diff --check` 干净。

### 0.2.6 2026-08-07 社交 / 云备份 / 笔记同步 / 数字孪生扩展 v1（第二批）

继续把「需外部凭据」的功能按**可配置凭据 + mock / 本地服务器测试**的生产级方式落地：

- **语雀同步 v1**：`YuqueSyncService`（Token 在仓库 namespace 下创建 markdown 文档）+ 设置页批量导出。
- **思源同步 v1**：`SiyuanSyncService`（Token 通过 `/api/filetree/createDocWithMd` 在笔记本下创建文档）+ 设置页批量导出。
- **S3 云备份 v1**：`S3BackupService` 实现 **AWS SigV4 请求签名**（HMAC-SHA256），PUT/GET/ListObjectsV2，导出包口令 E2E 加密；兼容 AWS / MinIO / R2 / COS；设置页「S3 云备份」。
- **Discord Bot v1**：`DiscordBotAdapter`（REST getMe / sendMessage + **Gateway WebSocket** 收 MESSAGE_CREATE）+ AI 应答网关 + 设置页；测试用本地 WebSocket 网关。
- **飞书 Bot v1**：`FeishuBotAdapter`（tenant_access_token + im/v1/messages 发送 + **本地 webhook 收件箱**接收，回调 URL 指向公网隧道）+ AI 应答网关 + 设置页。
- **数字孪生 / 镜像数字人 v1**：`PersonaProfileGenerator` 把画像蒸馏为「人格配置 / 替身 system prompt」+ `MediaPersonaAnalyzer`（emoji / 语音 / 图片媒体信号）；设置页可预览人格配置；替身回复明确标注须用户显式授权且全程审计、当前未启用。
- **验证**：`flutter --no-version-check analyze --no-pub` 无问题；全量 `flutter --no-version-check test --no-pub -r expanded` **633 项全部通过**；`git diff --check` 干净。

### 0.2.7 2026-08-07 社交 / 云盘 / 替身回复扩展 v1（第三批）

继续把剩余「需外部凭据」功能按**可配置凭据 + mock / 本地服务器测试**落地：

- **WhatsApp / Slack / 微信公众号 / QQ 适配器 v1**：新增 `WebhookChannelAdapter` 基类（本机 webhook 收件箱 + poll 排空），四个平台均实现「REST 发送 + webhook 事件解析」；`webhook_bot_provider` 一个设置入口覆盖四平台 + AI 应答网关。测试含 mock REST 与 webhook 回调（`social_webhook_adapters_test`）。
- **OneDrive 云盘备份 v1**：`OneDriveBackupService`（Microsoft Graph 上传 / 列出 / 下载）+ 设置页；导出包口令 E2E 加密，口令不落盘。
- **替身回复授权 v1**：`personaAuthorizationProvider`（显式授权持久化 + 时间戳，异步读取不覆盖用户操作）；`chat_provider.generatePersonaReply`（仅授权后以镜像人格为最近用户消息生成回复）；聊天附件菜单「替身回复」入口；设置页数字孪生对话框含授权开关（二次确认）。
- **验证**：`flutter --no-version-check analyze --no-pub` 无问题；全量 `flutter --no-version-check test --no-pub -r expanded` **645 项全部通过**；`git diff --check` 干净。

### 0.2.8 2026-08-07 替身审计日志落库 + 数字人直播 v1（第四批）

- **替身审计日志落库 v1**：新增 `persona_audit_logs` Drift 表（schema v7 → v8，含迁移）与 `PersonaAuditLogDao`；授权 / 撤销 / 每次替身回复（会话、消息、摘要、时间）自动落库；设置页数字孪生对话框新增「审计日志」历史查看与清空。测试：`persona_audit_log_dao_test`。
- **数字人直播 v1**：`LiveStreamScriptGenerator` 从镜像人格生成直播脚本（开场 / 话题 / 结束）+ RTMP 推流目标配置与校验 + 开播会话记录；设置页「数字人直播」。实际视频推流由用户在 OBS 等工具指向配置的 RTMP 地址。测试：`live_stream_service_test`、`settings_page_live_stream_test`。
- **验证**：`flutter --no-version-check analyze --no-pub` 无问题；全量 `flutter --no-version-check test --no-pub -r expanded` **652 项全部通过**；`git diff --check` 干净。
- **真机**：Pixel 8 release 安装 / 启动、设置页 smoke、真实发送 smoke 通过；iPhone13 release 构建通过，安装待设备 UDID 加入 provisioning profile。

### 0.2.9 2026-08-08 本地模型收口、gemma4 默认选择与文档结构整理

- **Ollama 配置**：设置页通过“添加渠道 → 厂商预设 → Ollama 本地模型”接入本地服务；API Key 可留空，空值读取使用 `KeyEncryptor.decryptOrEmpty()`，云端协议仍使用必填 Key 规则。
- **默认模型**：Ollama 自动获取模型后默认勾选 `gemma4` 及其 `gemma4:*` tag 变体；云端渠道继续默认勾选全部新模型；推荐模型顺序为 `gemma4`、`qwen3:4b`、`llama3.2:3b`。
- **协议稳定性**：Ollama NDJSON 保留 `message.thinking` / `message.content`，增加连接 / 空闲超时、取消 client 回收、有限错误正文和可选 Bearer 鉴权；`/api/tags` 模型列表同样支持可选鉴权。
- **验证**：本地模型专项 39 项通过；全量 Flutter 测试 660 项通过；`flutter --no-version-check analyze --no-pub` 无问题；Android Debug APK 构建通过；`git diff --check` 和 smoke 脚本语法通过；mock Ollama smoke 输出 `LOCAL_OLLAMA_SMOKE_OK`。
- **未完成边界**：本机真实 Ollama 当前不可连接，`gemma4` 权重、移动端网络、长会话和后台运行仍需真实 runtime / 设备补证。
- **文档入口**：当前状态使用 `docs/current-status.md`；专题导航使用 `docs/README.md`；当前验证使用 `docs/verification-baseline-2026-08-08.md`。历史带日期文档不覆盖当前状态。

### 0.2.10 2026-08-08 移动端 MCP / Skills / 记忆稳定性专项

- **MCP**：移动端在管理器层拒绝 `stdio`，不进入 `Process.start()`；旧 enabled `stdio` 配置不会阻塞 provider；App Native、SSE、endpoint 相对路径、timeout、非 2xx、disconnect、pending 清理和重复 dispose 均已收口。
- **Skills**：SkillHub 损坏本地缓存可隔离恢复；线上列表和 Generic HTTP 技能统一 512 KB 上限；JSON / UTF-8 / SHA-256 / 页码 / 搜索竞态 / HTTP client dispose 已收口。
- **记忆**：消息 / session / FTS / semantic 查询统一限制结果上限；全局搜索旧请求不会覆盖新请求；Key Point、索引预热 / 修复、Dreaming / Reflection / background runner / user profile 专项保持本地失败回退。
- **真机证据**：Pixel 8 和 iPhone13 的 MCP / Skills / 记忆逻辑专项各 162 项通过；真实移动 UI smoke 各 1 项通过。iPhone13 首次 UI 复跑发现 MCP 添加弹窗 `DropdownButtonFormField` 窄屏右侧溢出 12 px，加入 `isExpanded: true` 后两台设备均复跑通过。
- **仓库门禁**：全量 Flutter 测试 672 项通过，`flutter --no-version-check analyze --no-pub` 无问题，`git diff --check` 无输出。
- **未完成边界**：真实远程 MCP 长时弱网恢复、iOS 系统 BGTask 实际执行、Android OEM / 跨日长期后台和真实 Ollama `gemma4` runtime 仍按独立文档保留未证明状态。
- **文档入口**：专项详见 `docs/mobile-mcp-skills-memory-quality-2026-08-08.md`；当前状态和验证基线已同步更新。

### 0.2.11 2026-08-08 App Native MCP 真机无外部依赖验证

- **真机闭环**：新增 `integration_test/mobile_mcp_app_native_real_smoke_test.dart`，Pixel 8 和 iPhone13 各通过 1 项真实设备 smoke；通过真实 `McpManager` 完成 `initialize`、`tools/list`、`simichat.runtime_info` 和 `simichat.now` 工具调用。
- **依赖断言**：真机结果确认 `externalProcess=false`、`requiresNode=false`、`requiresNpx=false`、`requiresPython=false`、`mobileReady=true`；没有启动 HTTP mock、远程 SSE、Node、npx、Python、Docker 或 Podman。
- **决策**：当前移动端 App Native 已满足不依赖外部环境的 MCP 基线，不增加 Android Node.js 容器。移动端 `stdio` 继续拒绝；只有未来需要手机运行任意第三方 Node MCP 时，才另行设计 APK 内置 Node runtime，不把 PC Docker / Podman 侧车误称为 Android 容器。
- **证据**：`/tmp/simichat-mcp-app-native-real-pixel8.log`、`/tmp/simichat-mcp-app-native-real-iphone13.log`；详细边界见 `docs/MCP_RUNTIME_CONTAINERIZATION.md` 和 `docs/mobile-mcp-skills-memory-quality-2026-08-08.md`。

### 0.2.12 2026-08-09 Android / iOS 移动端扩展包安装与 Agent 计划

- **统一包协议**：新增 `lib/core/extensions/`，MCP、Skill、Agent 共用 JSON envelope、manifest、entry SHA-256、size、权限 allowlist、相对路径校验、`.part` 下载、原子安装、registry 和 quarantine；不执行 npm、npx、shell、Docker、Podman 或下载二进制。
- **三类接入**：Skill 通过 `SkillDao.upsertSkill` 接入现有 system prompt；Declarative Agent 通过 `MobileAgentRuntime` 生成请求计划，空模型默认 `gemma4`；App Native MCP 通过 shared provider 安装后创建配置并连接现有 `McpManager`。
- **移动端入口**：新增 `/mobile-extensions` 页面，可从 Android / iOS 文件选择器导入扩展包，查看状态、启用和卸载；MCP 市场页面提供入口。
- **验证**：`test/mobile_extension_installer_test.dart` 纳入全量测试；Android Pixel 8 与 iPhone13 真机运行 `scripts/smoke_device_mobile_extensions.sh` 均输出 `SIMICHAT_MOBILE_EXTENSIONS_APP_NATIVE_READY`，覆盖 Skill SHA-256、Agent `gemma4`、App Native MCP `initialize` / `tools/list` / `tools/call` 和 Agent 卸载；全量 Flutter 测试 **686 项通过**，`flutter analyze` 和 `git diff --check` 通过。
- **未完成边界**：iOS `runtime=node-mobile` 的 `NodeMobile.framework` / native bridge 尚未纳入当前发布构建；纯 JS MCP 包可以校验和落盘，但 iOS 纯 JS MCP 真机运行仍需 framework、health、SSE 和工具调用证据。完整矩阵见 `docs/MOBILE_EXTENSIONS.md`。

### 0.2.13 2026-08-09 内置 Node Runtime、纯 JS MCP 移动端运行与跨平台构建门禁

- **内置 Node Runtime**：Android 用 `nodejs-mobile v18.20.4` 的 `arm64-v8a/libnode.so` + JNI bridge 在 App 进程内启动 Node，iOS 用 `NodeMobile.xcframework` + Objective-C++ / Swift bridge，PC 用随 App 分发的 Node binary（App 管理的本地子进程，`externalProcess=true` 只表示非宿主机 PATH）；Docker / Podman 仅保留为可选隔离侧车，不再被内置 Node 路径隐式调用。Android 16k page 支持与 runtime 矩阵可移植性已加固，桌面与 Android 包构建可复现。详见 `docs/MCP_BUNDLED_NODE_RUNTIME.md`。
- **纯 JS MCP 移动端运行**：移动端运行时不调用 `node / npm / npx / shell / Docker / Podman / child_process / Process.start`；纯 JS 扩展通过 App 自有 Node runtime 或 App Native in-process adapter 运行，`runtime-server.mjs` 提供 health、扩展注册与 MCP SSE / message endpoint，注册时校验 manifest、entry SHA-256、路径边界、文件数量 / 大小、禁止能力和 `nativeAddon=false`；`stdio-compat-v1` 与 legacy npx adapter 走同一内置 runtime，MCP 配置可保留 `transport: stdio` 由管理器转接，未知第三方包、native addon、依赖 shell 的 CLI 和未审核 npx 包继续拒绝。iPhone13 真机 marker 已出现并验收通过。详见 `docs/mobile-node-mcp-runtime-2026-08-09.md` 与 `docs/MOBILE_MCP_RUNTIME.md`。
- **CI 跨平台构建门禁**：Flutter 源码在包构建前生成、bundled runtime 矩阵可移植、桌面与 Android 包构建可复现，跨平台 package build 门禁全部收口。
- **纯本地真机验收**：新增 `integration_test/mobile_mcp_skills_memory_local_real_smoke_test.dart` 与统一入口 `scripts/smoke_device_mobile_mcp_skills_memory_local.sh`，在 Pixel 8 与 iPhone13 上验证 App Native MCP `initialize` / `tools/list` / `tools/call`、Skill 本地安装 / SHA-256 / registry 恢复、真实 SQLite 重开后 FTS / semantic / 本地搜索、Key Point 用隔离 key 写入 / 重建 notifier 后召回、移动端页面与全局搜索 UI 可见，以及内置 NodeMobile / 纯 JS MCP / stdio-compat-v1 / legacy npx adapter 继续通过。`KeyPointMemoryNotifier` 新增可选 `storageKey`，生产默认 `key_point_memory_v1` 不变，真机测试用隔离 key 不覆盖用户记忆。详见 `docs/mobile-mcp-skills-memory-local-device-2026-08-09.md`。

### 0.2.14 2026-08-09 SimiRouter AI 中转站品牌升级（dwchainless rebrand）

- **品牌接入**：`dwchainless` 预置渠道显示名改为「SimiRouter AI 中转站」，Base URL / 官网 / 注册地址保持 `api.dwchainless.com` 不变，`id` 保持 `dwchainless` 兼容旧配置与批量导入；新增品牌 logo 资源 `assets/branding/simirouter.png`（预设 `logoAsset` 字段），渠道列表、模型选择器、预设提示卡和关于页鸣谢均显示真实 logo。
- **卡片历史设计**：本轮曾使用品牌头像 + 6 项能力标签 + 三按钮；该长卡方案已由 0.2.20 的紧凑三态卡替代，不再作为当前 UI。
- **验证**：全量 Flutter 测试 694 项通过，`flutter analyze` 与 `git diff --check` 通过；预设锁定一键接入（仅填 Key）与品牌图标回归覆盖在 `settings_page_dwchainless_test.dart`、`model_provider_preset_test.dart`。

### 0.2.15 2026-08-09 移动端 stdio 兼容接入

- **配置语义**：移动端设置页重新提供 `Stdio（移动兼容 / 内置 Runtime）`；已审核的 legacy `npx` 配置继续映射到 App Native adapter，已安装的 `node-mobile` / `stdio-compat-v1` 扩展保留 `transport: stdio`，由 App-owned Node Runtime 私下走 loopback bridge。
- **边界**：移动端不启动宿主机 `node`、`npx`、shell 或任意外部子进程；未知命令不再显示笼统的“移动端不支持 stdio”，而是提示安装移动兼容包或改用 SSE。
- **市场与 UI**：已审核 stdio 条目可在移动端自动启用并连接；未知 stdio 条目保持待启用，设置页按“App 内建适配器 / 内置 Node Runtime / 需要移动兼容 Runtime”显示具体状态。
- **验证**：`flutter --no-version-check analyze --no-pub` 无问题；聚焦 MCP / Runtime / extension 测试 26 项通过；全量 Flutter 测试 698 项通过；Pixel 8 `37101FDJH0077P` 和 iPhone13 `00008110-0016349A3A20A01E` 均通过 `SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY`、`SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY`、`SIMICHAT_STDIO_CONFIG_MCP_DEVICE_READY` 和 `SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY`；Pixel 8 MCP / Skills / memory UI smoke 输出 `SIMICHAT_MCP_SKILLS_MEMORY_UI_READY`；两台设备均已恢复普通 release，Android release pid `19229`、iOS release pid `16318` 可见；`git diff --check` 通过。

### 0.2.16 2026-08-09 移动端标准 stdio JSONL session 修正

- **问题修正**：上一版把移动 `stdio` 配置映射到 `AppNativeMcpTransport` 或 loopback `SseTransport`，只保留了配置语义，没有真实 stdin / stdout 行协议；本轮明确废止这条作为新实现的路径。
- **真实链路**：新增 `MobileStdioTransport`；移动 `McpManager` 将 `command` 与 `args` 送入 `BundledNodeRuntime.startStdioSession()`，Dart 逐行写入 `/runtime/stdio/<session-id>/stdin`，逐行读取 `/runtime/stdio/<session-id>/stdout`，支持 `initialize`、`tools/list`、`tools/call`、通知和 `close`。已审核 `npx` 只作为随包 profile 的命令选择器，未知命令在 start 阶段拒绝，不调用宿主机 `npx` / shell / `Process.start()`。
- **扩展协议**：新增 `stdio-v1` manifest 协议名；`stdio-compat-v1` 仅保留旧安装包兼容，不再作为新 stdio 语义的证明。
- **代码级验证**：`test/mobile_stdio_transport_test.dart` 启动真实 `runtime-server.mjs`，完成 `health -> stdio/start(command,args) -> stdin JSON line -> stdout JSON line -> initialize -> tools/list -> tools/call -> close`；未知 command 也覆盖 start 阶段拒绝。`node --check`、聚焦测试和 `flutter analyze` 通过。
- **真机验证**：Android Pixel 8（`37101FDJH0077P`）与 iPhone13（`00008110-0016349A3A20A01E`）均已通过真实设备 marker `SIMICHAT_MOBILE_STDIO_PROTOCOL_DEVICE_READY`；`stdio-v1 / JSONL mobile stdio` 现标记为 `runtime_verified`。旧 `stdio-compat-v1` marker 仍保留为历史兼容证据，不把旧对象 adapter 误写成新 stdio 实现。

### 0.2.17 2026-08-09 内置 H5 登录态 Cookie 持久化与关闭入口

- **历史方案**：本轮曾新增 `InAppH5CookieStore` 手工读取 / 重建 WebView Cookie；复审确认 Dart `WebViewCookie` 无法保留 Secure / HttpOnly / SameSite / expires 等完整属性，该方案已由 0.2.20 删除，不能作为当前登录态实现。
- **关闭入口**：H5 顶栏新增「关闭」按钮直接退出页面，登录 / 注册完成后无需一步步返回。
- **历史验证**：曾完成“清空引擎后从 App store 恢复”的测试，但该测试会鼓励丢失安全属性的重建路径，不再作为现行门禁；当前门禁见 0.2.20。

### 0.2.18 2026-08-09 SimiRouter mimo TTS 三模式与 ASR 接入

- **TTS 三种模式**（`/v1/audio/speech`）：`mimo-v2.5-tts` 语音合成（8 种预设音色：冰糖-alloy / 茉莉-echo / Mia-nova / Chloe-shimmer / 苏打-onyx / 白桦-fable / Milo-milo / Dean-dean）、`mimo-v2.5-tts-voicedesign` 声音设计（style 文字描述）、`mimo-v2.5-tts-voiceclone` 声音克隆（参考音频 base64 data URI）；统一支持语速 0.25-4 与输出格式 mp3 / wav / opus / aac / flac。引擎按模型名自动切换请求体，非 SimiRouter 模型保持原 4 字段行为。
- **ASR**：`mimo-v2.5-asr` multipart 支持 `language`（auto / zh / en）；`auto` 表示服务端自动检测，因此请求中省略 `language`，只在 zh / en 时发送明确语言代码，避免 OpenAI 兼容服务把字面值 `auto` 当作无效 ISO-639-1 代码；通道 fallback 引擎在模型名含 asr / whisper / transcribe 时透传模型名，避免聊天模型名误传转录接口。
- **配置与 UI**：`TextToSpeechConfig` 新增 speed / responseFormat / style / referenceAudioPath（加密外字段均为普通 SharedPreferences 键），`SpeechToTextConfig` 新增 language；TTS 配置对话框在 SimiRouter 模型下显示三模式模型下拉、8 音色下拉、声音风格输入、参考音频选择（file_picker）、语速滑条与输出格式下拉；STT 对话框在 mimo-v2.5-asr 下显示识别语言下拉。语音预设新增 `dwchainless`（mimo TTS + ASR 一键填充）。
- **2026-08-10 稳定性复核**：声音克隆 wav 选择改用 `FileType.custom`，避免 `allowedExtensions` 与 `FileType.audio` 的真机参数冲突；保存时校验存在、WAV、非空和 10 MB 上限，再以唯一临时目录中的 `.part -> rename` 复制到 `Application Support/tts/reference_audio/`，不再长期依赖文件选择器缓存路径；替换 / 清空配置只删除 App 自己管理的旧副本，不删除用户外部原文件。声音设计在启用配置保存时即校验 style；mimo 响应的 Accept MIME、本地临时文件扩展名与 mp3 / wav / opus / aac / flac 选择保持一致，非 mimo 模型继续固定 mp3；配置摘要按模式显示音色 / 声音设计 / 声音克隆，不再展示不适用字段。
- **验证**：全量 Flutter 测试 **724 项通过**（新增引擎三模式请求体断言、语音设计缺 style / 克隆缺参考音频拒绝、provider 扩展字段持久化与校验、预设 / 音色 / 模式判断、TTS / STT 对话框 UI），`flutter analyze` 无问题，Pixel 8 真机设置页 smoke 通过。真实合成 / 识别需 dwchainless API Key，人工验证。

### 0.2.19 2026-08-09 图片编辑 / 深度思考 / 输入栏整理 / Markdown 样式

- **图片生成 / 编辑事务**：`ImageGenerationService` 新增 `edit()`（`POST /v1/images/edits` multipart：image 文件 + prompt + model + n + size）；生成 / 编辑先做渠道能力预检并调用上游，成功后才以 `.part -> rename` 保存图片，再在单个 SQLite 事务内写入 user、assistant、attachment 和 token。上游失败不写幽灵消息或 token；数据库失败删除未引用图片；事务提交后页面销毁或 Markdown 派生档案失败不会误删已引用图片。编辑弹窗在 320×568、120% 字号下使用有限宽度预览；业务错误只在弹窗内显示一次，保留提示词可重试，回调意外抛错也会恢复按钮，不再永久卡在“编辑中”。入口两处：输入栏加号菜单「编辑图片」和消息图片长按「编辑此图」。
- **识图 / 深度思考能力门禁**：`ModelCapability` 新增 `reasoner` 位、显式元数据和模型名推断；Vision 与 Reasoner 支持使用可重叠判定，不让带 reasoning 后缀的视觉模型因单标签推断而失去识图能力。`o1 / o3 / o4 / r1` 等短代号按分隔符精确匹配，不再把 `foo1 / mirror1 / audio4` 一类普通名称误判为 Reasoner；上下文预算的 o 系列判断同步使用 token 边界，避免普通模型被错误提升到 128K 窗口。显式 `embedding` 能力会否决宽泛名称提示，避免 `gemini-embedding-*` 被误选为 Vision。聊天模型查询已纳入 `reasoner` 并继续排除 `embedding`，只有推理模型的渠道也可直接选择。输入栏新增「深度思考」toggle（`deepThinkNotifier`）。纯文本开启后发送自动查找当前渠道 reasoner 模型；当前渠道无 reasoner 时明确阻止并保留输入。图片附件发送前自动选择当前渠道 Vision 模型；无 Vision 时明确阻止并保留图片 / 输入。Vision / Reasoner 仅通过 `overrideModelId` 路由本次请求，基础模型、会话默认模型和顶部选择器保持用户原选择；流式气泡及最终 assistant 消息记录本次实际模型。图片与深度思考同时启用时 Vision 优先并明确提示本次不切换 reasoner。
- **输入栏整理**：加号菜单重排（拍照 / 相册 / 文件 / 编辑图片 / 替身），常规宽度 Row 按钮顺序为加号、文本框、麦克风、生成图片、深度思考、发送；小于 380px 时把生成图片 / 深度思考收进可滚动的加号菜单，320×568、120% 字号下文本框宽度保持至少 120 logical pixels，避免功能图标把输入区挤成单字竖排。
- **Markdown 样式**：标题 h1-h3 配色映射 primary 系；引用块左侧竖条加粗（primary 6px）；新增自定义表格 builder（表头背景 + 斑马纹 + 圆角边框，替换默认表格样式）。代码块语言标签 / 行号 / 复制 / 折叠为既有能力。
- **验证**：全量 Flutter 基线 **757 项通过**；最后边界修正后的渠道 / H5 / Vision / Reasoner / TTS / STT / 图片聚焦回归 **123 项通过**，上下文预算边界 **5 项通过**，日志扫描无 RenderFlex overflow、Flutter exception、未处理异步异常或点击命中警告。覆盖图片无 Vision / 自动切 Vision、深度无 reasoner / 自动切 reasoner、短模型代号与 embedding 误判保护、reasoner-only 渠道可选择、短 o 系列上下文预算边界、单次模型覆盖不改会话默认值、显式 Reasoner 元数据、Vision + Reasoner 重叠能力、OpenAI Chat `image_url` / Responses `input_image` 的 MIME + 完整 base64、图片上游 / 数据库失败不污染会话、编辑异常可重试、TTS 合成请求串行门禁 / 非 mp3 扩展名 / 声音设计必填 / 声音克隆私有归档、mimo TTS / ASR 精确模型识别与大写历史配置回显、STT auto 省略语言字段，以及 320px / 120% 字号输入区与编辑弹窗。`flutter analyze` 与 `git diff --check HEAD` 无问题；Android Release APK 与 iOS unsigned Release `Runner.app` 已在上述收口后重新构建通过。本轮按要求未做真机和真实云端质量复验。

### 0.2.20 2026-08-09 SimiRouter 紧凑渠道卡、H5 预热与登录态加固

- **紧凑渠道卡**：移除六项常驻营销标签；未接入只显示一句定位和「获取 Key / 一键接入 / 官网」，缺 Key 显示「获取 Key / 补充 Key / 官网」，已接入只显示状态与「管理 / 官网」。已有渠道直接编辑，不重复创建；Base URL 仅在 HTTPS、精确 host `api.dwchainless.com`、443 端口且无 userInfo 时识别。三个动作改为单排等宽布局，320×568、120% 字号下整卡小于 170 logical pixels且每个按钮保持至少 44 logical pixels 点击高度。
- **网页加载体验**：设置页以最多 12 秒的隐藏 WebView 预热官网，同一 App 进程同 origin 成功后只执行一次，完成 / 失败 / 超时后立即释放；官网与注册页复用系统 WebView 磁盘缓存。第三方主 JS / CSS 不复制进 App assets，避免 3MB 级 bundle、部署 hash、CSP / CORS 与登录 origin 漂移；本地只保留品牌 logo 和原生加载壳。
- **账号登录态**：官网、获取 Key、关于页共用系统 WebView 默认持久 profile（Cookie、localStorage、IndexedDB、磁盘缓存）；线上 bundle 会把账号资料写入同 origin `localStorage['user']`。App 不读取、复制或重建认证 Cookie；Android 通过 `CookieManager.flush()`，iOS 使用 `WKWebsiteDataStore.default()` 完成屏障。页面完成、SPA 路由和生命周期触发的 flush 会合并；补齐 drain 循环退出到完成回调之间的尾随请求竞态，确保最后一次 flush 不会悬空。关闭交互最多等待 2 秒，平台通道异常不会卡住退出。
- **安全修正**：删除 0.2.17 的 `InAppH5CookieStore` 手工 fallback，因为 `WebViewCookie` 只能重建 name / value / domain / path，会丢失 Secure / HttpOnly / SameSite / expires 并可能覆盖原始 Cookie。H5 主帧当前只允许初始 host / port 的 HTTPS 且拒绝 userInfo，阻止跨域、相似域名、非 443 端口和 HTTP 降级；非主帧仍允许验证码 / iframe 正常加载，被阻止的主帧跳转提供明确 SnackBar 反馈。
- **验证边界**：H5 / 渠道定向测试覆盖紧凑高度、120% 字号、44px 点击目标、三态动作、编辑原渠道、相似域名 / 自定义端口 / userInfo 拒绝、预热入口、HTTPS / 同 host / 同 port 导航、关闭 / 返回和原生 profile flush 超时；全量 Flutter 基线 **757 项通过**，最后能力聚焦回归 **123 项通过**，上下文预算边界 **5 项通过**，`flutter analyze`、`git diff --check HEAD` 无问题；Android Release APK 与 iOS unsigned Release `Runner.app` 均基于最终代码重新构建并确认包含品牌资源。真机集成门禁仍需验证带期限 Cookie + localStorage 在关闭 / 重开后复用，不主动 `clearCookies()`；按用户当前要求未执行安装或真机验证。真实账号首次登录 → 关闭 → 重开 → App 进程重启仍需使用用户账号做最终 UI 验收。

### 0.2.21 2026-08-17 ChatGPT 风格多模态 Composer 与通用媒体消息

- **输入框**：ChatGPT 风格单一 Composer 保留文本主路径；加号菜单支持多文件选择、相机 / 相册、图片编辑、图片生成、视频生成、声音合成、生成音乐、深度思考和替身回复。小屏幕次要动作进入可滚动菜单，工具成功后清空文本与附件，失败保留草稿。
- **附件**：附件策略新增 `video` 类型和 `mp4 / mov / webm / mkv / 3gp / ogv` 等扩展名；文件选择支持一次多选，未知扩展名仍作为 `document` 保留。现有 8 个附件 / 单文件 25 MB 校验继续生效。
- **媒体服务**：新增 `UniversalMediaService`，支持可配置视频 / 音乐 endpoint 和模型，复用当前聊天渠道 Base URL / API Key；支持二进制、`b64_json` / `base64`、data URI、常见媒体 URL 响应；视频参考图用 multipart。图片生成新增参考图参数，复用 `/v1/images/edits`；既有 TTS 三模式 / STT 管线保留，并新增“声音合成结果写回会话”动作。
- **消息体**：图片继续缩略图 / 放大 / 长按编辑；视频附件使用 `video_player` 预览、播放 / 暂停 / 进度拖动，解码失败回退文件卡片；音频卡片新增播放 / 停止，音乐与声音合成结果使用同一条音频展示链路。
- **本地持久化**：生成视频 / 音乐 / 语音结果使用 `.part -> rename` 后写入 `generated_videos/`、`generated_music/`、`generated_speech/`，SQLite 事务同时写 user 提示、assistant 消息和附件元数据；不把 API Key 或本机路径写入日志 / Markdown。
- **验证**：新增 `docs/chat-composer-multimodal.md`、通用媒体服务测试、视频附件识别 / 展示测试、Composer 工具菜单测试；`flutter analyze --no-pub` 已通过，聚焦多模态测试通过。真实视频编码、异步任务轮询、音乐长音频和外部厂商质量仍需仓库外配置与真机验证，不能由 mock 测试替代。

### 0.2.22 2026-08-18 模型选择器收口、会话草稿隔离回归与 Android 覆盖安装

- **模型选择**：`ChannelDao.getChatModels()` 统一通过 `ModelCapability.isChatSelectableModel()` 过滤启用模型；旧数据中 capability 误标为 `chat` 的 `dall-e-3` 等图片生成模型，以及 embedding / video / audio / music 专用模型不会进入聊天模型选择器；chat / vision / reasoner 仍可选。模型列表刷新不会改写当前 `selectedModelIdProvider`。
- **会话草稿**：新增稳定的 ChatPage 草稿隔离回归，覆盖 A / B 会话切换后文本草稿分别恢复，不依赖易挂起的本地 SSE fixture。
- **验证**：全量 Flutter 测试 **909 项通过**；`flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出。
- **Android 真机**：Pixel 8 `37101FDJH0077P` 使用 `scripts/smoke_android_release_install_launch.sh` 构建并执行 `adb install -r` 覆盖安装成功；安装后 `versionName=1.0.0`、`versionCode=1`、PID `29841` 可见，`firstInstallTime=2026-08-18 02:12:04`、`dataDir=/data/user/0/top.simitalk.aichat` 保持不变，说明未卸载 / 清空原应用数据；最终 APK SHA-256 为 `55b942e430b20912f51bf9f4be23b97af2ce82de309e2bf30f895c1e01433fa0`。
- **未完成边界**：真实视频编码 / 异步任务轮询、音乐长音频、外部厂商质量和多媒体真机闭环仍需配置实际接口后单独验证；本轮不将离线 mock 或安装启动证据描述为真实云端媒体成功。

### 0.2.23 2026-08-18 实时语音面板与最终 Android 覆盖安装

- **实时语音核心**：新增 `RealtimeVoiceSession`、`realtimeVoiceProvider` 和 ChatGPT 风格 `RealtimeVoicePanel`，支持 OpenAI / xAI / 自定义 `wss://` endpoint、Bearer / ephemeral 凭据、模型 / 音色 / protocol prefix 配置、WebSocket 文本 fallback、输入转写、助手文本 / 转写、输出音频帧统计、停止回答、断开与配置持久化。凭据使用 `KeyEncryptor` 加密保存，不进入状态摘要、日志或 UI 文本。
- **Composer 入口**：ChatGPT 风格 `+` 菜单新增「实时语音对话」，保留普通麦克风的“录音文件 → STT → 聊天”路径；面板明确标注当前尚未接入原生 PCM 麦克风采集与实时 PCM 播放队列，不把文件录音冒充实时流。
- **本轮验证**：`flutter --no-version-check analyze --no-pub` 无问题；实时语音 focused 测试 **16 项通过**；全量 Flutter 测试 **912 项通过**；`git diff --check` 无输出。
- **Android 真机**：Pixel 8 `37101FDJH0077P` 执行 `scripts/smoke_android_release_install_launch.sh`，Release APK 构建成功（81.7 MB），`adb install -r` 返回 `Success`，APK SHA-256 为 `cb8861b2cee84a4c4f60f5e4b71b7d8b5afea04b6f97ecf10910dcefde073b40`；安装后 `versionName=1.0.0`、`versionCode=1`、PID `31179` 可见，`firstInstallTime=2026-08-18 02:12:04` 与 `dataDir=/data/user/0/top.simitalk.aichat` 保持不变，确认是覆盖安装且未清空原应用数据。
- **真机 UI 证据**：UI Automator 已确认启动页显示 `SimiAIChat`、`未选择模型`、`添加附件`、`语音输入`；打开 `+` 菜单可见相机、相册、多文件（图片 / 视频 / 音频 / PDF / 普通文件）、`实时语音对话`、`编辑图片`、`生成图片`、`深度思考`；实时面板已在真机打开并显示连接状态、转写区、配置表单和 PCM 边界提示。未配置外部 API Key，因此不把真实 Realtime、视频、音乐或云端 TTS / STT 质量描述为已完成。

### 0.2.24 2026-08-18 声音合成 / 声音克隆 / 声音设计 Composer 入口

- `luna_worker` 在不改协议层、数据库或安装脚本的范围内完善 `ChatInputBar`：`+` 菜单新增独立的 `声音合成`、`声音克隆`、`声音设计` 入口和稳定 key；声音克隆默认要求并消费第一条 `audio` 参考附件，或由上游声明复用设置中已归档参考音频；声音设计只消费文本描述。
- `ChatPage` 普通会话和空会话均接入三个回调，按 `TextToSpeechConfig` 的 provider、模式、API Key、风格描述和参考音频状态生成独立 disabled reason。未满足条件时入口保持可见但不可点击，不把设置项或本地回调描述成云端已可用。
- 新增 `test/chat_input_bar_voice_tools_test.dart`，覆盖三入口回调、文本 / 参考附件消费、缺少参考音频禁用、disabled reason 阻断和已配置参考音频复用；该测试 4 项通过，Composer / ChatPage / TTS 聚焦回归 61 项通过。
- 主线程复查后 `flutter --no-version-check analyze --no-pub` 无问题，完整 `flutter --no-version-check test --no-pub --no-test-assets -r compact` 共 **1012 项通过**，`dart format` 与 `git diff --check` 通过。
- 在 Pixel 8 `37101FDJH0077P` 当前 Production Release 上，UI Automator 展开并滚动 `+` 菜单实机看到 `生成视频`、`声音合成`、`声音克隆`、`声音设计`、`生成音乐` 及未配置原因；该证据证明客户端入口与状态门禁，不替代真实 TTS / 声音克隆 / 声音设计供应商 E2E。

### 0.2.25 2026-08-18 声音克隆临时参考音频优先级与最终 Android 覆盖安装

- `ChatInputBar` 的声音克隆入口现在优先消费当前 Composer 中的第一条 `audio` 附件；只有当前没有参考音频时，才通知 `ChatPage` 回退到设置中已归档的参考音频。声音克隆完成后只移除实际消费的附件；无附件且无归档参考音频时继续保留禁用状态和“附加参考音频”原因。
- `ChatPage` 普通会话与空会话 Composer 在 TTS 已启用、SimiRouter `voiceClone`、Base URL / model / voice / 加密 Key 有效但未归档参考音频时，不再提前关闭入口；用户附加当前音频后允许执行一次性克隆，临时参考音频不会写回持久化 TTS 配置。
- `dart format`、`flutter --no-version-check analyze --no-pub`、`git diff --check` 均通过；声音工具 / ChatPage / 图片 / 草稿 / 消息附件 focused 回归 **42 项通过**，完整 `flutter --no-version-check test --no-pub --no-test-assets -r compact` **1016 项通过**。
- 随后在 Pixel 8 `37101FDJH0077P` 执行 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P`。脚本构建 `app-production-release.apk`（81.9 MB），只执行 `adb install -r` 覆盖安装并返回 `Success`；`ANDROID_RELEASE_PARITY status=verified`，构建 APK 与设备 `base.apk` SHA-256 均为 `f7d43858f7d4292eb538189c99bb631294c92ad21ac36b64907c861fb3cb1556`，证书 SHA-256 为 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 不变，`lastUpdateTime=2026-08-18 11:08:00`，PID `28329`，启动组件为 `top.simitalk.aichat/.MainActivity`。
- 本轮没有对正式包执行卸载、清空数据或 `am force-stop`；隔离包检查为 clean。媒体 / 语音 / Realtime 的本地测试、loopback、fake adapter 和客户端入口证据仍不替代真实 OpenAI / xAI / Gemini / Claude、Ollama inference、视频 / 音乐生成、云端 TTS / STT、声音克隆 / 声音设计和 Realtime WSS E2E。

### 0.2.26 2026-08-18 Rerank 协议落地、会话置顶与新对话入口

- 按用户决策确认多对话 / openai / claude / gemini / grok 与生图 / 视频 / 音乐 / TTS / STT / 向量化均已存在：多对话 = Sessions 表 + 侧边栏历史列表；Grok 维持 xAI 预设走 OpenAI 兼容协议（对话 / 生图 / 视频 / 语音全通），不新增独立协议代码。
- Rerank 完整落地：`ModelCapability` 新增 `rerank` 能力（normalize / 名字推断 hints / 聊天选择器否决 / vision+reasoner 否决 / 标签"Rerank 重排"），推断顺序先于 embedding（`bge-reranker` / `gte-rerank` 同时命中 embedding 前缀）；新建 `lib/core/ai/rerank_client.dart` 走 `/v1/rerank`，单解析器兼容 Jina / Cohere / OpenAI 兼容三种线格式并按分数降序；`ModelTester` 播放按钮接入 rerank 连通性测试（30 秒超时）；添加模型对话框能力下拉加 Rerank 项、模型名自动推断能力默认值；新增 Jina / Cohere 厂商预设（Jina 无 `/v1/models`，预设描述注明用推荐模型手动添加）。
- 会话置顶：schema 13 新增 `sessions.is_pinned`（`ALTER TABLE` 迁移，老库即时无损；快照 export / restore 往返 `is_pinned`，旧快照默认 false）；`SessionDao.setPinned` 与 `getAllSessions` 置顶优先排序；侧边栏新增"已置顶"独立分组置于日期分组之上（文件夹内会话不提供置顶入口，避免重复出现），会话弹出菜单加"置顶 / 取消置顶"。
- ChatGPT 风格对齐：侧边栏图标行下方新增全宽"新建对话"按钮（移动端点击后自动收起抽屉，桌面端为持久侧边栏 no-op）；AppBar 的 "+" 保留（需求 4.1 移动端顶栏入口）。
- 自动标题精修（已有 `_generateTitle`，只改细节）：标题为空串时也触发；模块级 `_titleGenerationInFlight` 防双生成；生成前重读会话标题防覆盖用户手动重命名；改用首条用户消息概括主题（400 字截断）；流加 30 秒总超时（Dio 流式默认 5 分钟）；写入前 30 字符截断；fork 会话标题在建会话时即写入，不会被覆盖。
- 验证：`dart run build_runner build --delete-conflicting-outputs` 重新生成 drift 代码；`flutter --no-version-check analyze --no-pub` 无问题；全量 `flutter test` **1102 项通过**（修复 `media_job_persistence_test` 两处 schema 硬编码：期望版本 11→13；模拟 v8 老库时移除 v8 后新增的 `capabilities` / `is_pinned` 列，避免迁移重复加列）。Rerank 仅覆盖客户端解析与连通性测试入口，未做真实 Jina / Cohere 云端 E2E；置顶 / 新对话按钮为 widget / DAO 回归，未做真机 UI 取证。

### 0.2.27 2026-08-19 顶部模型名称可见性与 Android 覆盖安装

- **顶部模型选择器**：按用户确认，聊天 AppBar 的模型胶囊不再显示可能很长的 `渠道名 / 模型名`；现在只显示当前实际选中的模型名，末尾保持固定的向下箭头。渠道名仍保留在模型下拉菜单分组、消息元数据和模型切换记录中，因而不会影响渠道辨识或历史追溯。
- **回归**：`test/chat_model_selector_ui_test.dart` 新增当前模型名、旧渠道前缀不再出现在胶囊、末尾存在 `keyboard_arrow_down_rounded`、展开菜单后顶部和已选项各显示一次模型名的断言；与 `test/model_switch_smoke_manifest_test.dart`、`test/chat_page_model_label_test.dart` 共 **12 项通过**。`flutter --no-version-check analyze --no-pub` 与 `git diff --check` 均通过。
- **Android 真机**：Pixel 8 `37101FDJH0077P` 使用 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 构建并以 `adb install -r` 覆盖安装 Production Release；未卸载、未清空数据、未执行 `am force-stop`。安装后正式包 `top.simitalk.aichat` 的 `firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持不变，`lastUpdateTime=2026-08-19 17:27:37`，PID `20951`，前台组件为 `top.simitalk.aichat/.MainActivity`。实机截图确认顶栏显示 `gpt-5.3-codex-spark` 和末尾下拉箭头；截图不替代真实云端媒体链路验证。

### 0.2.28 2026-08-19 会话草稿跨进程恢复 v1

- **持久化范围**：新增 `ChatComposerDraftStore`，以应用私有 `SharedPreferences` 索引按会话保存 Composer 的短文本、附件恢复元数据与深度思考开关。保存操作串行化、默认至多保留 50 个会话；损坏 JSON、未知格式和非法附件会安全忽略，不阻塞聊天主链路。
- **隐私与一致性**：大粘贴原文继续只保留在应用私有 `composer_drafts` UTF-8 文件；索引不保存原文、附件 bytes、完整 Base64、渠道凭据或诊断信息。聊天页在生命周期切出与销毁前保存最新快照；发送成功只清空文本和已消费附件，保留深度思考设置。
- **恢复与隔离**：先恢复本进程缓存；仅冷启动 cache miss 读取持久化索引。恢复 generation、用户编辑 generation 和当前会话三重检查阻止异步旧结果覆盖新输入；附件异步恢复后仅重建对应 Composer。`ChatInputBar` 会话同步不再伪造一次用户草稿变更，避免将未加载的持久化草稿写空。
- **验证与部署**：新增 `test/chat_composer_draft_store_test.dart`（保存/重载、PastedText 元数据、会话隔离、串行覆盖、淘汰、删除和损坏数据）与 `test/chat_page_persisted_draft_test.dart`（聊天页冷启动恢复文本/附件/深度思考及 A/B 会话隔离）。草稿/附件专项 **19 项通过**，多模态聚焦 **112 项通过**，`flutter --no-version-check analyze --no-pub` 与 `git diff --check` 均通过。Pixel 8 `37101FDJH0077P` 已使用 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 覆盖安装正式 Production Release：`firstInstallTime=2026-08-18 07:11:12` 和 `dataDir=/data/user/0/top.simitalk.aichat` 保持不变，`lastUpdateTime=2026-08-19 18:39:12`，PID `24303`，前台为 `MainActivity`，无隔离 smoke 包。发布后截图确认正式聊天页可用；手工输入草稿 → 系统回收 → 重启后的真实设备恢复仍待下一轮独立交互 smoke 补证。

### 0.2.29 2026-08-19 超长文本附件单次降级防截断

- **问题与修复**：旧的文本文件降级会先把 UTF-8 正文交给通用上下文裁剪；当附件超过窗口时，裁剪器可能只保留开头，而用户仍以为整个文件已发送。现在通过 `singleTextFallbackTokenBudget()` 只允许文本附件占模型最大输入预算的一半；余量留给 `ContextBuilder` 已受限的系统提示、最新问题、历史、序列化与 token 估算误差。
- **失败语义**：预算不足时，在消息与附件写入本地数据库之前返回明确的预检错误：“文本附件超过当前模型的单次安全输入预算”；用户草稿与原始私有文件保持不变，可缩短内容、切换更大上下文模型，或等待下一阶段的可恢复分批任务。该修复不把任意 400、认证、额度或超时误判为附件降级。
- **验证与部署**：`test/chat_provider_attachment_routing_test.dart` 新增 half-window 预算断言和超长 `.md` 发送未落库 / 可重试回归；与文本抽取、上下文、草稿和大粘贴相关组合共 **34 项通过**，`flutter --no-version-check analyze --no-pub` 与 `git diff --check` 无问题。Pixel 8 `37101FDJH0077P` 已覆盖安装 Production Release：`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持，`lastUpdateTime=2026-08-19 18:50:20`，PID `24898`，`MainActivity` 在前台且无隔离包。真实渠道的原生 File API 与后续分批任务不在本条范围内。

### 0.2.30 2026-08-19 可恢复长内容分批任务 v1

- **路径 C 已实现**：纯 `document` 文本附件无法安全装入单次请求时，`sendMessage()` 先持久化用户消息和私有附件，再创建 `ChunkedContentTask`，而不是截断或只显示“稍后支持”。`mapReduce` 用于总结、问答、分析和提取：每段结果只写入 `chunk_results`，全部完成后才发送一次 reduce；`orderedTransform` 用于翻译、改写、润色和格式转换：零 overlap 严格按 `chunkIndex` 拼接，绝不追加会删段或重排的最终润色请求。两种策略都只向消息时间线和 Markdown 档案交付一条最终 assistant 回复。
- **持久化、恢复与竞态**：schema 升至 **14**，新增 `chunked_content_tasks`，保存无凭据路由快照、附件 ID、范围/哈希、尝试次数、内部结果、进度、lease 和确定性的最终消息 ID。每段请求最多首次 + 2 次瞬态重试；认证、参数和内容拒绝不自动重试。Stop 会取消 `CancelToken`、停止后续段并以 SQLite 状态为最终裁决；最终 reduce 在 Stop 后晚到也不会写入 assistant。冷启动只把 `preparing/running/reducing` 收敛为“应用已中断，可继续未完成部分或从头重试”，不会自动重放可能计费的请求。
- **聊天交互与前置校验**：聊天页新增不泄露 chunk 原文的“长内容”工作卡，显示策略、进度、安全错误和“停止 / 继续 / 从头重试”。重试会先确认原始附件、渠道模型和无凭据请求快照仍可用；模型已删除或附件不可用时保持 failed/cancelled，不会留下没有 worker 的伪进行中卡片。混合图片、音频或其它非文本附件的超预算输入仍拒绝，防止只处理文本而静默丢失其它素材。
- **自动验证与部署**：新增 `test/chunked_content_task_test.dart`，覆盖策略、数据边界、唯一最终回复、瞬态重试、段间停止、reduce 晚到 Stop 竞态、缓存 chunk 续跑和 completed 重放幂等；新增 `test/chat_page_chunked_content_task_test.dart`，覆盖工作卡、Stop、重试动作和缺少模型前置校验；`test/app_bootstrap_test.dart` 覆盖首帧后的长内容恢复钩子，`test/media_job_persistence_test.dart` 覆盖 schema 14 新表与 v8 升级。聚焦组合 **55 项通过**，`flutter --no-version-check analyze --no-pub` 与 `git diff --check` 无问题。随后 Pixel 8 `37101FDJH0077P` 通过 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 构建并 `adb install -r` 覆盖安装正式 Production Release：构建包与设备 `base.apk` SHA-256 均为 `0cb02258c80d2604974d11dd8a542c6a4dac0068b4200661cb55955f633730b2`，`ANDROID_RELEASE_PARITY status=verified`，签名 SHA-256 为 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，`firstInstallTime=2026-08-18 07:11:12` 与 `dataDir=/data/user/0/top.simitalk.aichat` 保持不变，`lastUpdateTime=2026-08-19 20:58:53`，启动 PID `30656`，前台为 `top.simitalk.aichat/.MainActivity`，无隔离 smoke 包。
- **未补证边界**：OpenAI Responses 的普通 `document` 原生 `input_file`（路径 A 子集）已实现；其它 provider 的 File API / `FileTransport`、服务端明确附件拒绝后的一次性 File→文本降级、跨设备备份/导入中间结果、完整聊天/工作分段视图、Artifact MVP，以及已配置真实云端模型的长文 E2E、Pixel 8 手工“超长附件 → 分段 → Stop → 继续”交互 smoke 仍待补证；不得由本地 fake sender、SQLite 或安装启动替代。

### 0.2.32 2026-08-21 图片生成本次任务面板与多图任务快照 v1

- **图片任务面板**：移动端 `+ → 生成图片` 进入独立底部任务面板，支持本次提示词、图片模型（名称 + 下拉箭头）、多参考图、质量、宽高比、`1K / 2K / 4K` 清晰度、`width x height` 像素分辨率和生成数量；没有已配置图片模型时只显示真实空状态并可进入设置，不伪造请求。
- **类型化提交**：新增图片面板回调边界，将全部图片参考附件转换为 `ImageGenerationOptions`，通过 `ImageGenerationRequestAdapter` 和 `MediaRequestProviderProfile` 进入图片请求；服务层支持多图响应、multipart 多参考图和本地私有归档，失败 / 取消仍保留可重试任务。
- **任务快照 / 重试**：`ImageGenerationTask` 保存模型、参考图集合、数量、比例、清晰度、像素分辨率、质量和 route model id；重试不会退回全局设置或静默取第一张参考图；同一 assistant 消息可落库多张图片附件。
- **验证**：图片服务 typed wire、图片任务流、Composer 全部参考图消费回归与图片能力契约聚焦测试通过；`flutter --no-version-check analyze --no-pub` 和 `git diff --check` 通过。当前尚未以真实云端凭据在 Pixel 8 上完成图片模型 / 多图请求 E2E，Production Release 覆盖安装待本轮完成。

### 0.2.33 2026-08-21 语音合成本次任务面板与 typed TTS 参数 v1

- **任务面板**：移动端 `+ → 声音合成` 现在优先打开本次任务底部面板，支持编辑输入内容、选择音色、滑动语速和选择输出格式；面板取消不会改写设置页，提交后才把本次选项传给请求层。旧的直接合成回调继续保留兼容边界。
- **真实请求参数**：`synthesizeSpeechMessage()` 接受本次 `voice / speed / responseFormat / model` 覆盖，并按 provider 构造新的 TTS engine；OpenAI-compatible 与 SimiRouter 请求体都保留实际语速 / 输出格式，xAI 仅使用其标准 TTS 支持的 voice、language、speed 和 codec，不把声音设计 / 克隆字段伪造到 xAI。
- **结果交付**：合成结果仍保存为当前会话 assistant 音频附件，沿用 `generated_speech/` 原子写入、播放 / 下载 / 重试链路；任务失败保留输入草稿，不写入半成品消息。
- **验证**：新增 Composer 面板回调优先级回归和 TTS typed wire 回环断言；`chat_input_bar_voice_tools_test.dart`、`openai_text_to_speech_engine_test.dart` 聚焦通过，`flutter --no-version-check analyze --no-pub` 无问题。全量 `flutter --no-version-check test --no-pub --no-test-assets -r json` **1176 项可见测试通过**（含 201 项隐藏测试）；此前模型选择器旧断言已按移动端“只显示模型名”需求更新。Pixel 8 `37101FDJH0077P` 已执行 `scripts/smoke_android_release_install_launch.sh`：Release APK 82.5 MB，`adb install -r` 返回 `Success`，构建包 / 设备 `base.apk` SHA-256 均为 `de0f5624bd3980e272fa6594baa7d158e3a56cdece5819ed060af9e459718272`，签名 SHA-256 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，`ANDROID_RELEASE_PARITY status=verified`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持，`lastUpdateTime=2026-08-21 13:21:29`，PID `26911`。真机截图确认顶部模型名带向下箭头，`+ → 生成图片` 面板真实显示模型、质量、宽高比、分辨率、生成数量和“开始生成”；截图 `/tmp/simichat-image-panel.png`。设计 / 克隆面板代码在该 APK 之后追加，需重新覆盖安装；尚未用真实 TTS / 图片云端凭据完成生成结果质量 E2E。

### 0.2.34 2026-08-21 声音设计 / 声音克隆本次任务面板 v1

- **声音设计**：`+ → 声音设计` 打开一次性面板，支持朗读文本、自然语言声音风格、温柔 / 活泼 / 成熟 / 磁性 / 沉稳 / 故事感快捷标签、语速和输出格式；快捷标签只追加，不覆盖用户已有描述。
- **声音克隆**：`+ → 声音克隆` 打开一次性面板，展示本次 Composer 已选参考音频（文件名、大小、仅当前任务语义），支持多音频单选、朗读文本、语速和输出格式；无附件但设置中有有效归档参考音频时明确显示使用配置音频，无任何参考音频时拒绝提交。
- **请求与交付**：两个面板都通过 `synthesizeSpeechMessage()` 的 typed 覆盖传递 `style / referenceAudioPath / speed / responseFormat`，仍受 SimiRouter provider 模式门禁；xAI 不接收未声明的声音设计 / 克隆字段。成功结果进入当前会话 `generated_speech/` audio 附件，失败保留草稿与参考附件。
- **验证**：新增 Composer 设计 / 克隆面板回调优先级与参考附件边界测试，`chat_input_bar_voice_tools_test.dart` **8 项通过**；`flutter --no-version-check analyze --no-pub` 和 `git diff --check` 无问题。随后 Pixel 8 `37101FDJH0077P` 已重新覆盖安装包含本条代码的 Production Release：构建包 / 设备 `base.apk` SHA-256 均为 `b200b61ab9adfbc918e6f8dfa9ea3e7eecd7b87ff9c5e37603869ece8a411fb7`，`ANDROID_RELEASE_PARITY status=verified`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持，`lastUpdateTime=2026-08-21 13:35:11`，PID `28225`。真实声音设计 / 克隆 provider E2E 仍需仓库外凭据；当前设备没有可用 TTS 云端配置，因此只验证了真实 App 启动与安装 parity。

### 0.2.35 2026-08-21 独立语音识别任务面板 v1

- **任务面板**：Composer 新增 `识别语音` 工具，要求先附加音频文件；面板支持在多条音频中单选，并选择 `自动 / 中文 / 英文` 识别语言。
- **结果链路**：新增 `recognizeSpeechMessage()`，复用当前已配置 STT engine 和 `AudioTranscriptionService`，识别结果以 assistant 文本消息写回当前会话时间线；语言只通过单次 override 生效，任务结束自动清除，不改设置页默认语言。
- **边界**：无 STT 配置、无音频、文件不存在或 provider 失败时直接返回可操作错误，不写半成品消息；本地 transcript archive 继续复用既有安全路径和脱敏规则。
- **验证**：`chat_input_bar_voice_tools_test.dart` 新增识别任务回调和附件选择回归；`flutter --no-version-check analyze --no-pub` 无问题。真实 STT provider、长音频、视频转写和 Pixel 8 识别结果质量仍待仓库外凭据验证。

### 0.2.36 2026-08-21 视频生成完整任务面板与 typed 多参考链路 v1

- **任务面板**：`+ → 生成视频` 现在使用一次性任务配置，支持多选参考图、独立首帧图、参考音频、时长、宽高比和分辨率；所有附件角色保存在 `VideoGenerationConfig`，旧 `onGenerateVideo` 回调仍保留兼容。
- **请求链路**：新增 `generateVideoWithOptions()`，按 `openai_sora`、`xai_grok_video`、自定义 OpenAI-compatible / configuredAsync profile 映射 `VideoGenerationOptions`。参考图、首帧图和参考音频分别通过 `UniversalMediaService.submitVideoWithOptions()` 进入显式附件字段；JSON 端点使用 data URI，multipart 端点使用重复文件字段，不把本机路径写进普通 JSON，也不静默丢弃多参考图。
- **任务状态与重试**：通用媒体 worker 现在透传 `referenceImagePaths`、`firstFrameImagePath`、`referenceAudioPath`、字段名和 typed `requestFields`；失败重试保存完整视频配置和附件集合，成功后视频结果继续以 assistant `video` 附件写入当前会话时间线。
- **验证**：新增视频任务面板 Widget 回归和 typed 视频实际 wire 回环（多参考图、首帧、参考音频、时长 / 比例 / 分辨率），`test/chat_input_bar_video_tools_test.dart`、`test/universal_media_service_test.dart`、`test/media_request_options_test.dart` 聚焦通过；全量 `flutter --no-version-check test --no-pub --no-test-assets -r json` **1179 项可见测试通过**（含 202 项隐藏测试），`flutter --no-version-check analyze --no-pub` 无问题。
- **验证与部署**：随后 Pixel 8 `37101FDJH0077P` 执行 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P`，Production Release 构建 82.6 MB，`adb install -r` 返回 `Success`，`ANDROID_RELEASE_PARITY status=verified`；构建包 / 设备 `base.apk` SHA-256 均为 `4465ffa1f164e30fe97873c7f193b57fd6dc7023657bbcb04223f4c21a954f1c`，签名 SHA-256 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持，`lastUpdateTime=2026-08-21 14:17:06`，启动 PID `31119`，隔离包检查 clean。当前最新 APK 已覆盖安装并启动。
- **未补证边界**：真实 Sora / xAI / 自定义视频云端账号、长轮询和生成质量仍需仓库外 provider 凭据；协议回环和 Release parity 不替代真实云端视频结果质量 E2E。

### 0.2.37 2026-08-21 移动端一级多模态模式导航 v1

- **统一入口**：新增 `CreationModeSwitcher` 和 `creationModeProvider`，顶部固定提供 `聊天 / 图片 / 视频 / 语音` 四个一级模式；模式状态不依赖模型名称，也不改变当前会话默认聊天模型。
- **工作区**：`ChatPage` 在非聊天模式显示对应的图片、视频、语音轻量工作区，继续调用既有 typed 图片 / 视频 / TTS / STT / 音乐任务链路，任务结果仍进入当前会话时间线；聊天模式保持原消息列表、停止、重试和 Composer。
- **能力边界**：图片、视频、语音入口依据已配置模型能力 / TTS / STT 配置动态显示；没有可用能力时显示真实去设置空状态，未声明的语音子入口隐藏，不伪造生成结果。
- **实现文档与验证**：新增 `docs/multimodal-mode-navigation.md`、`test/creation_mode_switcher_test.dart`；模式切换测试、模型选择器、移动端主流程聚焦回归通过，全量 Flutter 测试 **1180 项可见 / 203 项隐藏** 通过，`flutter --no-version-check analyze --no-pub` 无问题。Pixel 8 `37101FDJH0077P` 已通过 `scripts/smoke_android_release_install_launch.sh` 覆盖安装 Production Release：APK / 设备 `base.apk` SHA-256 均为 `af7c2f6874908f545ea469928417e519fb09cf0096e1b8615c45bde743ec6b2d`，签名 SHA-256 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持，`lastUpdateTime=2026-08-21 15:27:55`，PID `2690`，隔离包检查 clean。真机 UI Automator / 截图已确认四个模式可切换，图片模式显示可编辑提示词、参数摘要和“生成图片”入口。

### 0.2.38 2026-08-21 模型任务联动与 Artifact 工作台 v1

- **模型单一工作区状态**：新增 `activeCreationModelIdProvider` / `voiceCreationToolProvider`；常规移动端顶部模型胶囊打开可搜索底部抽屉，按渠道 / 能力展示模型并提供“管理模型”，窄屏保留 PopupMenu 降级。图片、视频、语音模型选择同步任务类型、工具配置和顶部任务标签，不改写聊天会话默认模型；聊天模型切换使用 `recordInConversation: false`，只显示短时 SnackBar，不写入新的 `model_switch` 时间线消息。
- **能力标签**：`ModelCapability` 增加显式 `tts` / `asr` / `voice_design` / `voice_clone`，页面按能力过滤；旧 `audio` 行保留 TTS 兼容回退，禁止再按模型名称分散判断音频任务。
- **Artifact 工作台**：`HtmlArtifactCard` 改为紧凑文件成果卡片，完整 HTML（含未 fenced 文档）和显式 Markdown fenced 内容进入独立 `ArtifactWorkbenchPage`；HTML 使用隔离 WebView 预览，Markdown 提供阅读视图，源码 / 可视化入口支持全屏草稿编辑、自动换行切换和应用私有目录下载，不在聊天区展开长源码。
- **验证**：模型选择、语音任务标签、Artifact 卡片 / 完整 HTML 抽取聚焦测试通过；`flutter --no-version-check analyze --no-pub` 无问题，`git diff --check` 无输出。最终全量测试与 Android Release parity 需以本轮最后命令输出为准。
- **未补证边界**：Artifact 跨会话 DAO / 版本历史 / AI 结构化 Patch / 多资源 ZIP、真实 HTML 外部资源策略、真实云端 TTS / ASR / 视频质量仍待后续 provider 与真机交互门禁；当前不伪造已完成的版本同步。

### 0.2.39 2026-08-21 模型能力一致性与任务参数动态化补充

- **旧音频模型一致性**：新增 `ModelCapability.voiceCapabilityForModel()` 作为旧 `audio` 元数据的集中兼容解析点；显式 `tts` / `asr` / `voice_design` / `voice_clone` / `music` 优先，旧 `mimo-v2.5-asr` 等模型的默认语音任务不再由顶部、工作区和配置动作分别猜测。模型选择器、语音工作区和 TTS / STT 配置共享同一解析结果；新增 `isVoiceDesign` / `isVoiceClone` 能力谓词，并补显式 `tts` 模型可见性回归。
- **视频参数**：视频面板从 `MediaRequestProviderProfile` 读取当前模型支持的时长、比例、分辨率、首帧图、参考图数量和参考音频能力；未声明字段隐藏，默认值取支持列表，避免向不支持 `6s / 1080p` 的模型发送固定参数。
- **语音参数摘要**：语音工作区按 TTS / ASR / 音乐 / 声音设计 / 声音克隆切换参数摘要，隐藏其它任务字段；详细提交仍复用既有底部任务表单和真实服务链路。
- **验证**：`flutter --no-version-check analyze --no-pub` 无问题；模型能力、模型选择器、模式切换和视频任务聚焦测试通过；串行全量测试 `1185` 项可见 / `204` 项隐藏、`0` errors、`1389` success、`0` fail；`git diff --check` 无输出。Pixel 8 `37101FDJH0077P` Production Release 覆盖安装通过 `ANDROID_RELEASE_PARITY status=verified`，最终 APK / 设备 `base.apk` SHA-256 均为 `14a4a1958cffc2193f91ff1adf1d883034404cf6733d3a6e1e967e0187e52322`，签名 SHA-256 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持，`lastUpdateTime=2026-08-21 17:56:03`，PID `11890`，隔离包 clean。真机 UI Automator 已确认语音模式顶部 `mimo-v2.5-asr + 语音识别`、ASR 参数摘要和模型底部抽屉入口。
- **边界**：Artifact 跨会话 DAO / 版本历史 / AI 结构化 Patch / 多资源 ZIP，以及真实云端 TTS / ASR / 视频质量仍待后续 provider 与真机交互门禁。

### 0.2.40 2026-08-21 CCSwitch / Claude 额度查询

- **实现**：新增 `ChannelQuotaClient` 与 `channelQuotaProvider`。设置页每个非 SimiRouter 渠道展开后提供手动“查询额度 / 刷新”；Claude OAuth 按 CCSwitch 使用的 `GET /api/oauth/usage` 读取 `five_hour` / `seven_day` 等窗口、使用率和重置时间，OpenAI 兼容 / new-api 读取 `/dashboard/billing/usage` 与可选 `/dashboard/billing/subscription`。
- **边界与隐私**：查询不在打开设置时自动遍历渠道，不把额度响应写入 SQLite、备份或聊天记录；鉴权失败、404、限流、超时只显示脱敏中文错误，不回显响应正文或密钥。SimiRouter 原有专属用量行继续保留，避免重复请求。
- **验证与部署**：`test/channel_quota_client_test.dart`、SimiRouter billing、设置页和模型选择聚焦回归通过；`flutter --no-version-check analyze --no-pub`、`git diff --check` 通过。Pixel 8 `37101FDJH0077P` 以 `adb install -r` 覆盖安装当前 Production Release，`ANDROID_RELEASE_PARITY status=verified`，APK / 设备 hash `34ced0dd2a66e275eea3be3bc12bd596df49e7b5ca75c45923455860ee9dac95`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持，安装后 PID `14099`；设置页真实取证确认 SimiRouter 用量行返回“已用 $0.16 · 未设限额”。
- **待补证**：真实 Claude OAuth / CCSwitch token 仍需用户在设置页手动点按“查询额度”完成一次真机账号闭环；不以本地 fake endpoint 测试替代真实账号证据。

### 0.2.41 2026-08-21 媒体模式模型选择器按能力收窄

- **问题**：图片模式的模型底部抽屉和窄屏 PopupMenu 误使用完整模型目录，Chat / TTS / ASR 等不支持生图的模型被置灰展示，造成用户误以为可以用于图片生成。
- **修复**：`ChatModelSelector` 在图片 / 视频 / 语音模式只把当前工作区能力模型传给抽屉和 PopupMenu；聊天模式仍保留完整目录，并允许媒体行作为配置工具的快捷入口。图片模式现在只展示 `ModelCapability.image` 模型。
- **验证与部署**：新增 `image mode picker only exposes image-capable models` 回归；模型选择器聚焦 **8 项通过**，`flutter --no-version-check analyze --no-pub`、`git diff --check` 通过。Pixel 8 真机切换到图片模式后打开模型抽屉，UI Automator 仅看到 `grok-imagine-image-lite`、`grok-imagine-image-quality`、`gpt-image-1.5`、`gpt-image-2` 等 Image 图片生成模型，未出现 `grok-4.x`、`mimo-v2.5-chat` 或 TTS / ASR；Production Release `ANDROID_RELEASE_PARITY status=verified`，APK / 设备 hash `b85a5f06740f0753bb0c914e6d86262f2da0e52141161b6810eeba9db81eb0a6`，正式包 `firstInstallTime` / `dataDir` 保持不变。

### 0.2.31 2026-08-19 OpenAI Responses 原生普通文档传输 v1

- **路径 A 子集已实现**：当渠道协议为 `openai_response` 且模型级文件契约已验证时，`.txt` / `.md` 等普通 `document` 附件不再被文本提取器重复拼入 `input_text`，而是通过 Responses `input_file` 的 `file_data=data:<mime>;base64,...` 和 `filename` 一次发送原始字节。`Ai.Attachment.fileName` 使用用户安全文件名；发送前会去目录、控制字符和 `.` / `..`，不把应用私有归档路径或用户目录带到上游请求。
- **保持的边界**：PDF 沿用已有原生 `input_file` 路线；非 Responses、未声明原生文件能力或未验证的模型仍走受限文本降级 / `ChunkedContentTask`，不会伪造文件字段。当前尚未把“服务端明确拒绝附件”自动改发为文本，也尚未声明其它厂商的真实 File API。
- **验证与部署**：`test/openai_response_protocol_test.dart` 覆盖普通文档 `input_file` 和安全文件名；`test/chat_provider_attachment_routing_test.dart` 使用 Dio 回环 adapter 断言实际 Responses 请求中的 `input_text` 只含用户问题、`input_file` 只含原始 UTF-8 bytes、私有路径与裸文档正文均不泄露，且助手结果会写回会话。两份测试共 **20 项通过**，`flutter --no-version-check analyze --no-pub` 与 `git diff --check` 无问题。随后 Pixel 8 `37101FDJH0077P` 使用正式 Production Release 覆盖安装：构建 APK 与设备 `base.apk` SHA-256 均为 `7b51c6e768f1261d16a2f75a7c9f9bd48d3eb1a47e4d9a322aea816bbf716d28`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持不变，`lastUpdateTime=2026-08-19 21:37:17`，PID `32597`，前台为 `top.simitalk.aichat/.MainActivity`，无隔离 smoke 包。该验证是协议回环与 Release 覆盖安装，不等同已配置真实云端的文档 E2E。

### 0.3 2026-07-14 模型增强 Reflection 验证补充

- 2026-07-14 22:57 将非流式远程 Reflection 修复推进到 Pixel 8 正式后台真机闭环。首次 wrapper 预检收到临时 `401`，在构建前安全退出、设备未变化；为预检新增最多 3 次有界重试，只重试 `401 / 408 / 429 / 5xx / curl 失败 / 200 空内容`，manifest 红灯后转绿。复跑时 attempt 1 为 401、attempt 2 成功，独立 `backgroundmodelsmoke` build / install 后 READY pid `8925` 被回收，JobScheduler 未使用 shell force，在 elapsed `324` 秒时由 `SystemJobService` 冷启动 pid `10117`，完成 `status=completed digest=2026-07-14 reflection=2026-07-14`。prefs 同时含 Dreaming / Reflection 当前与历史，`generationMode=model`，无 pending / `model_fallback`，日志与 prefs 无配置地址 / key。cleanup 后隔离包和 sqlite hook 无残留，正式包 pid `10528`、firstInstallTime `2026-07-14 00:29:02`、dataDir `/data/user/0/top.simitalk.aichat` 不变，跨日 job id `0` 仍 waiting；最终全量稳定门禁 557 项通过。取证：`/tmp/simichat-android-background-dreaming-20260714224926.log`、`/tmp/simichat-android-background-dreaming-prefs-20260714224926.xml`。
- 2026-07-14 22:40 补远程模型三日长会话 Reflection 质量门禁。审计发现旧 live quality 工具仍默认 loopback 本地模型，已改为只读取仓库外 `MODEL_CONFIG_FILE`，要求 600 / 400、只允许远程 `openai_chat` 并拒绝 loopback；代码 / 脚本 / 测试 / 文档不包含真实地址、key 或模型默认值。真实流式采样两组三轮分别出现 1 次和 2 次 HTTP 200 空 content/thinking，因后台结构化 Reflection 不需要逐字展示，正式 `openai_chat` Reflection 改走非流式单次响应，普通聊天 SSE 和其他协议不变。真实非流式响应暴露 `<think>` + 首个 JSON + 重复 fenced JSON，解析器新增字符串 / 转义感知的平衡对象提取，保留全部既有安全过滤。远程 72 条长会话按 2026-07-14 / 15 / 16 三个 dayKey 严格门禁 3 / 3 通过，分别耗时 27.744 / 29.701 / 14.554 秒，attempts `[2,1,1]`，本地 5 / 4 均保留并合并为最终 8 / 8，合成密钥 / URL / 路径和虚假完成描述均未进入结果；第一轮一次临时 401 后重试成功，接口可用性波动如实保留。聚焦 38 项、全量稳定门禁 557 项、analyze、diff、hook / 泄漏扫描通过；跨日 job id `0` 仍 waiting，正式包 pid `5438`，隔离包无残留。详见 `docs/archive/mobile-remote-model-reflection-quality-2026-07-14.md`。
- 2026-07-14 22:06 对 21:56 SQLite-only 新进程恢复补丁完成最终复核：`bash -n` 覆盖恢复与跨日脚本，Dreaming / Reflection manifest、provider、background runner 聚焦 32 项通过；`scripts/smoke_full_stability_gate.sh -r expanded` 全量 550 项通过；`flutter --no-version-check analyze --no-pub` 无问题，`git diff --check`、sqlite hook 残留和外部模型真实地址 / key 仓库扫描均通过。Pixel 8 正式包仍为 pid `5438`、firstInstallTime `2026-07-14 00:29:02`、dataDir `/data/user/0/top.simitalk.aichat`，SQLite-only / 远程模型隔离包均不存在，Android 跨日 job id `0` 继续 `waiting`。本轮没有启动、调用或探测 Ollama / 本地模型；现行模型验证只允许读取仓库外 600 / 400 配置文件调用远程接口。
- 2026-07-14 21:56 Pixel 8 补 SQLite-only Dreaming / Reflection 新进程真机恢复：独立 `top.simitalk.aichat.dreamingsqlitesmoke` 第一次 pid `5157` 只落 completed SQLite report + Reflection pending，不写 Dreaming 当前 / history；`am force-stop` 后第二次新 pid `5263` 经正式 `ResponsiveShell` 启动任务回灌 Dreaming 当前 / history，生成 Reflection 当前 / history 并清 pending，输出 `dreamingHistory=1 reflectionHistory=1`。设备 prefs 确认 `dreaming_digest_v1`、Dreaming history、Reflection 当前 / history 均存在且 pending 不存在；cleanup 后隔离包和 sqlite hook 无残留，正式包 pid `5438`、firstInstallTime `2026-07-14 00:29:02`、dataDir `/data/user/0/top.simitalk.aichat` 未变化，Android 跨日 job id `0` 仍 waiting。取证：`/tmp/simichat-dreaming-reflection-device-20260714215600.log`、`/tmp/simichat-dreaming-reflection-prefs-20260714215600.xml`。
- 2026-07-14 21:38 补 Reflection pending 的 SQLite digest 回灌：旧 `_retryPendingAssistantReflection()` 从 `dreaming_reports` 解码目标 digest 后只用于局部 Reflection 生成，不同步当前 Dreaming / history，后台 runner 可能找不到来源 digest、漏掉完成通知，UI 也可能只见 Reflection 不见来源。既有按 dayKey 恢复测试新增 history 断言先红灯为 `Actual: []`；修复后 SQLite 恢复项总是记录 history，仅当当前 digest 为空或更旧时更新当前值。新增“当前缺失时发布 digest”和“新后台 ProviderContainer 从 SQLite 回灌后完成 Reflection / 通知”两条回归；Reflection provider + runner 18 项、移动端聚焦 20 项和全量稳定门禁 550 项通过，analyze 无问题。Android 跨日 job 仍为 `waiting`，未被扰动。
- 2026-07-14 21:28 补 Dreaming 跨存储完成顺序稳定性：旧 `_runDreamingDigest()` 在 SQLite report upsert 后先标记 job `completed`，再保存 `dreaming_digest_v1` / history，provider 写入失败或后台进程在两层存储之间退出时可能留下不可重试的静默 completed，进而跳过画像提议和 Reflection。新增故障注入回归先红灯为 `Expected failed / Actual completed`；修复后 digest 和 history 均持久化成功后才 `markJobCompleted()`。异常会留下 failed job 和 SQLite report 供重试 / 诊断，进程直接退出则 job 保持未完成并可由 stale claim 恢复。`dreaming_provider_test.dart` 11 项、Dreaming / background runner / DAO / Reflection / 移动端聚焦 22 项和全量稳定门禁 548 项通过，analyze 无问题；Android 跨日 job 仍保持 `waiting`，未受本轮修改影响。
- 2026-07-14 21:21 iPhone13 再次可用后复跑隔离 release BGTask Dreaming / Reflection：解锁预检、27.5MB 签名构建、安装和 READY 均成功，但设备原生 `backgroundRefreshStatus=denied`，`BGTaskScheduler` 返回 `There are no scheduled tasks`，脚本在 LLDB 模拟前安全拒绝，未把前台启动误报为系统后台成功。本轮补正式 App 身份守卫，cleanup 现在必须比较 smoke 前后的名称、bundle、版本和 build 行；manifest 回归先红后绿，真机失败清理复跑未出现身份变化错误，仅正式 `top.simitalk.aichat` 保留，无隔离 bundle / 临时工程替换 / sqlite hook。Android 跨日 job id `0` 仍为 `waiting`。iOS 系统后台执行继续等待用户开启“后台 App 刷新”，当前不能标记完成。
- Android 系统后台真实远程模型 smoke 已改为外部配置文件加载接口：代码 / wrapper / 测试不固定真实地址、模型或密钥，`MODEL_CONFIG_FILE` 必须为仓库外 600 / 400 JSON，包含 `openai_chat` 协议、Base URL、API key 和模型名。wrapper 远程预检非 200 时在构建 / 安装前拒绝；成功后才通过 `run-as` 一次性写入独立 `backgroundmodelsmoke` 私有目录，Flutter 读取即删除明文并以 `KeyEncryptor` 加密 key。Pixel 8 真机最终远程预检通过，隔离 App READY 后旧 pid `30567` 被回收，JobScheduler 未使用 shell force，在 elapsed `112` 秒时通过 `SystemJobService` 冷启动新 pid `30907`，完成 `status=completed digest=2026-07-14 reflection=2026-07-14`；prefs 同时含 Dreaming / Reflection 最近报告与历史，`generationMode=model`，无 pending / `model_fallback`，日志和 prefs 无配置中的密钥或地址。cleanup 后远程模型隔离包与临时配置均消失，正式包 firstInstallTime / dataDir 不变、pid `31292`，跨日 job id `0` 仍 waiting，本机无 Ollama 进程或 11434 监听。配置解析 / 删除和设备 manifest 聚焦 11 项、全量稳定门禁 547 项、analyze 和 `git diff --check` 通过；后续仍禁止在本机启动或探测本地模型服务。
- 可选模型增强 Reflection v1 已落地：本地规则始终作为安全基线，模型开关默认关闭；用户显式开启后只把长度受限且经过敏感信息处理的 Dreaming / 本地反思摘要发送给默认已启用聊天模型，严格解析 JSON 并与本地结论合并。
- 模型失败、无可用模型、60 秒超时、格式异常或输出不安全时自动回退本地报告并清除 pending，不让 Dreaming 或系统后台任务因可选增强反复 retry；设置页会明确显示“本地规则”或“模型增强 + 本地规则”，结构化备份只保存开关和报告，不保存模型密钥。
- 模型聚焦组合 60 项通过；补齐模型输出 URL / 本机路径过滤，并修复本机正式 OpenAI Chat SSE 协议测试未释放 Dio / `HttpServer` 导致测试进程不退出的问题后，全量稳定门禁 517 项通过，日志无 `WARNING (drift)` / `multiple databases` / 失败标记；`flutter --no-version-check analyze --no-pub` 和 `git diff --check` 通过。
- 继续审计模型合并边界时发现：旧逻辑按“模型优先”填充最多 8 条结果，若模型违反提示返回过多条目，会挤掉本地规则安全结论；模型只重复本地内容时也会误标为模型增强成功。新增两条红灯回归后改为本地结论优先、模型最多补充 4 条、无新增安全内容时抛出格式异常并由 provider 回退本地报告。模型 / provider / 正式协议 / 设置页聚焦 40 项通过；最终全量稳定门禁 533 项通过，`flutter --no-version-check analyze --no-pub` 无问题。
- 继续复核 60 秒模型超时时发现，旧 `.timeout(Duration(seconds: 60))` 只约束相邻流事件，模型持续发送慢碎片时总时长可以无限延长。新增持续 10ms 出块、80ms 总时限红灯后，将响应收集改为单个总墙钟 Future 超时，并把 `CancelToken` 从 Reflection provider 经 `ChannelModelRelayBridge` 传播到正式 OpenAI / Claude / Gemini / Ollama 协议；超时或响应过长会主动取消上游，再安全回退本地报告。相关聚焦 23 项、最终全量稳定门禁 534 项通过，`flutter --no-version-check analyze --no-pub` 无问题。
- 自动 / 后台模型失败此前只保存普通 `generationMode=local`，下次打开设置页无法区分“未尝试模型”和“已失败回退”。新增 `model_fallback` 兼容模式，失败后只持久化回退事实、不保存错误详情；最近报告、历史、Markdown、设置页 tile 和弹窗会明确显示“模型失败回退”，手动 SnackBar 也改为依据报告事实而非当前开关推断。序列化 / provider / 设置页聚焦 47 项、最终全量稳定门禁 536 项通过，`flutter --no-version-check analyze --no-pub` 无问题。
- Android debug APK 构建通过（166MB）；iOS release `--no-codesign` Runner.app 构建通过（33.3MB、arm64），正式 Bundle ID、BGTask identifier 和 sqlite 配置保持干净。本机 mock SSE 继续证明多协议正式链路；此前真实本地 Ollama `qwen3:4b` 72 条长会话 Reflection 5 / 5 只作为历史证据保留，按当前用户约束禁止再次启动、探测或重跑本地模型。后续质量门禁只使用仓库外配置驱动的远程接口，云端外部模型和更多模型族仍需单独评估。
- Pixel 8 已补 Android WorkManager 自然调度：隔离 App 回到 Home 后不调用 `cmd jobscheduler run`，30 秒 initialDelay、36 秒由 SystemJobScheduler 自行完成 Dreaming / Reflection，prefs 无 pending；默认 force 分支同步复跑通过。两次 cleanup 后正式包 firstInstallTime / dataDir 不变，最终 pid `24389`，无隔离包和 sqlite hook 残留；最终全量稳定门禁 518 项通过。

### 0.4 2026-07-14 模型驱动画像增量分析 v1

- 新增独立、默认关闭的“使用模型辅助画像候选”开关 `user_profile_model_enabled_v1`，不与 Reflection 模型开关耦合。开启后仍先运行 `UserProfileBuilder` 本地规则，只把限长、脱敏的 Dreaming 摘要与本地候选发送给默认聊天模型；不发送原始对话。
- 模型输出必须使用 `additions[{section,value,evidence}]`，`evidence` 必须逐字对应输入中的一条安全证据；只允许偏好、目标、任务、表达风格、作息线索和关键词，最多补 6 条、单分区最多 2 条。模型不能输出基础身份事实、冲突、删除项，不能覆盖本地候选；密钥、URL、本机路径、健康 / 心理诊断、无证据内容和重复内容会被过滤。模型失败、超时、无可用模型或无安全新增时回退本地候选。
- 模型候选仍只写入 `user_profile_change_proposals_v1`，提案持久化 `local / model / model_fallback` 来源；正式 `user_profile_v1` 只有用户整条或逐项采纳后才会更新。后台 runner 回归确认系统后台模型增强后正式画像仍为空，Reflection 能读取待确认数量；设置页明确展示隐私和授权边界，结构化备份 / 恢复已加入独立开关。
- 仓库外配置驱动的真实远程质量门禁按 3 个 dayKey 连续 3 / 3 通过，attempts `[3,1,1]`，分别新增安全候选 `[2,3,4]`；本地候选全部保留，基础事实、密钥、URL、本机路径、诊断和“已修改正式画像”均未进入结果。接口首次曾超时，恢复后有界重试通过，如实保留远程可用性波动。
- Pixel 8 独立 `top.simitalk.aichat.backgroundmodelsmoke` 真机复跑：仓库外配置预检前两次 401、第三次成功；READY pid `12526` 被回收后，JobScheduler 未使用 shell force，在 elapsed `127` 秒时由 `SystemJobService` 冷启动 pid `12911`，完成 Dreaming、模型画像候选和模型 Reflection。prefs 中画像提议为 `generationMode=model`，无 `model_fallback`，正式画像不存在，日志 / prefs 无地址或 key。cleanup 后隔离包 / sqlite hook 无残留，正式包 pid `13315`、firstInstallTime `2026-07-14 00:29:02`、dataDir `/data/user/0/top.simitalk.aichat` 不变，跨日 job id `0` 仍 waiting。取证：`/tmp/simichat-android-background-dreaming-20260714233159.log`、`/tmp/simichat-android-background-dreaming-prefs-20260714233159.xml`。
- 模型画像 / provider / 后台 runner / 设置页 / 备份 / 真机 manifest 聚焦 41 项通过；最终全量稳定门禁 566 项通过，`flutter --no-version-check analyze --no-pub` 无问题，`git diff --check`、脚本语法、hook / 隔离包 / 真实远程值泄漏扫描通过。详见 `docs/archive/mobile-model-user-profile-quality-2026-07-14.md`。

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
- 支持将多个模型聚合成个人接口中转服务器，参考 Cherry Studio，对外暴露统一接口转发。当前本地 OpenAI Relay 已支持健康检查、模型列表、聊天补全、Responses API 非流式和流式生命周期事件兼容端点、CORS 预检、路由策略、审计统计和多模态安全边界。

### M2 — 记忆与上下文系统

- 聊天记录全部本地存储，默认不上云。
- 每个对话对应 1 个 Markdown 原始文件。
- 核心记忆点提取后常驻本地索引 / 内存（Key Points），每次对话带入检索结果。
- 跨对话内容支持快速检索，形成本地知识库和本地检索增强生成能力。
- 无限上下文设计：超过模型令牌限制时自动提取重要内容并压缩；发送前按模型窗口预算裁剪上下文，优先保留最新用户问题，真实接口返回超限时自动严格裁剪重试一次。
- 支持人工智能反思机制（Reflection），用于回答质量、长期偏好、用户画像和任务计划改进；本地规则始终作为安全基线，可选模型增强默认关闭并在失败时自动回退本地报告。

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
  - `lib/core/mcp/`：MCP 客户端，App 内建 / stdio / SSE 传输。
  - `lib/core/extensions/`：移动端 MCP / Skill / Agent 包协议、安装、registry 和声明式 Agent 运行计划。
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
- [x] 核心 Key Points 提取与注入 v1：明示记忆点本地提取、持久化、关键词 + 本地语义向量召回并注入系统提示词；Dreaming 中明确任务语气会归类为 `task` 记忆候选。
- [x] Dreaming 移动端系统后台代码基线 v1：手动触发记为 `manual`，前台到期记为 `foreground_due`，Android WorkManager 记为 `android_background`，iOS BGTaskScheduler 记为 `ios_background`；后台 Flutter isolate 复用正式 SQLite / SharedPreferences / provider orchestration，生成 Dreaming、待确认画像提案、Reflection 和完成通知。前台 / 后台自动路径通过 SQLite `dreaming-auto-YYYY-MM-DD` 原子 claim 跨 isolate 防重；Android 强制与自然调度真机系统 job 均已通过，iOS 已完成 `BGProcessingTask` 注册 / 调度 / 重试 / 可用性诊断，真机执行待系统开关开启后补证。
- [x] 无限上下文压缩基础策略：滚动压缩、摘要生成、令牌估算、模型窗口预算、请求前裁剪、动态压缩阈值和超限错误兜底。
- [x] Reflection 反思机制 v1：Dreaming 后始终基于本地日报、用户画像和待确认画像变更生成回应质量、未回复会话、会话追问压力、重复追问、最新任务推进、最后一问未答、敏感标题降级和最后用户问题安全片段、上下文、长期记忆、用户画像、任务推进和来源新鲜度的可解释本地安全基线；来源过期时设置页入口会提示先运行今日 Dreaming；设置页可查看 / 手动运行，保存最近 20 次反思历史，可展开审阅、按 `dayKey + sourceDigestDayKey` 精确删除单条反思、删除反馈显示来源、删除当前最近反思后自动回退并可清空最近反思报告与历史，并可控制是否把少量高优先级结论 / 行动项作为下一轮本机短期提示；可选模型增强默认关闭，显式开启后使用默认聊天模型、严格 JSON、输入输出限长与脱敏，失败回退本地报告并清除 pending；真实本地 Ollama `qwen3:4b` 72 条长会话门禁已连续 5 / 5 通过，云端外部模型和更多模型族仍待扩展验证。

### Phase 3 — 生态扩展

> 目标：平台打通，技能扩展。

- [x] 社交平台接入 v1：`ChannelAdapter` 抽象 + Telegram（长轮询）/ Discord（Gateway WebSocket）/ 飞书 / **WhatsApp / Slack / 微信公众号 / QQ**（REST + 本地 webhook 收件箱）七个 Bot + AI 应答网关，设置页配置（2026-08-07）。
- [x] 技能市场基础集成：SkillHub.cn 搜索 / 导入 / SHA-256 校验 / 系统提示词注入。
- [x] 多源技能市场 v1：`SkillMarketplaceSource` 抽象 + SkillHub 适配器 + 通用 HTTP 技能源（OpenClaw 风格 index.json）（2026-08-07）。
- [ ] 个人接口中转服务：本地 OpenAI 兼容中转核心服务已完成（`/health`、`/v1/health`、`/v1/models`、非流式 / 流式 `/v1/chat/completions`、非流式 buffered / 流式 SSE 生命周期事件 `/v1/responses`、渠道模型桥接）；设置页启动 / 停止入口、令牌生成与加密持久化、端口展示、Base URL / curl 示例复制、访问审计、并发保护、局域网开放二次确认、高级路由策略、可配置并发上限、本地脱敏用量统计、持久化脱敏审计明细、JSON 导出、CORS 预检、OpenAI 多模态内容安全兼容降级、图片 data URL 端到端透传、模型视觉能力路由、模型能力可见性与设置页 Vision 标注、远端图片 URL 安全下载透传已完成；真机长时间运行和更多客户端兼容性仍待做。
- [ ] 定时任务 → 系统日历 / 闹钟联动；Dreaming 前台到期系统通知 v1 已完成。
- [x] MCP 协议客户端基础能力：App 内建 / stdio / SSE、Tool / Resource / Prompt。
- [x] MCP 工具调用循环：人工智能 → 工具调用 → 工具结果 → 人工智能最终回复。
- [x] Android / iOS 移动端扩展包 v1：Skill、Declarative Agent、App Native MCP 的 manifest / SHA-256 / 权限 / 原子安装 / registry / quarantine / 真机 smoke；纯 JS MCP 的 iOS NodeMobile runtime 仍待纳入发布构建。
- [x] MCP App 内建 Runtime v1：`app_native` 传输在 App 进程内响应 MCP JSON-RPC，内建 `simichat.now` / `simichat.runtime_info`，移动端和 PC 端均不依赖宿主机 Node / npx / Python；MCP 市场首项 `SimiChat 内建工具` 可安装后自动连接，设置页默认新增 App 内建类型。
- [x] MCP PC Node 容器侧车 v1：新增 `tools/mcp_runtime/container/` Node SSE Runtime、`scripts/mcp_runtime_container.sh` Docker/Podman 启停脚本、`docs/runtime-manifest.example.json` 和市场项 `SimiChat Node 容器 Runtime`，PC 端 Node 环境在容器内，不依赖宿主机 node/npm/npx。
- [ ] MCP 运行时 / 旁车：Runtime 状态表、App 内启动 / 停止 / 日志、第三方 Node MCP 包白名单安装、权限治理仍待做。

### Phase 4 — 数据与同步

- [x] 本地数据导出压缩包 v1：设置页可生成 `.tar.gz`，包含 `manifest.json`、`conversations/`、`audio_transcripts/`、默认 `audio_files/`，不包含 API Key 或本机绝对路径。
- [x] 语音转写状态 / 失败脱敏导出 v1：`audio_transcripts/*.md` 明确包含 `pending` / `ready` / `empty` / `failed` 状态；STT 失败会更新 sidecar 且不泄露本机路径、密钥、令牌或 URL，导出包与 Obsidian 同步直接继承该安全稿件。
- [x] 非语音附件原文件导出 / 导入 v1：导出包新增 `attachments/`，从 SQLite 附件表复制仍可读取的图片 / PDF / 文档等非语音附件原文件，净化归档路径。
- [x] 本地聊天核心数据库备份 / 恢复 v1：导出 `structured_data/local_database.json`，恢复 sessions / messages / attachments 三张核心聊天表，并把附件 localPath 重定向到导入后的 `attachments/` / `audio_files/` 文件；默认不覆盖已有记录，不导出模型 API Key / 渠道密钥 / 本机绝对路径。
- [x] 非密钥配置表备份 / 恢复 v1：同一 `structured_data/local_database.json` 继续覆盖 folders / prompts / skills / mcp_servers / model_channels / channel_models / dreaming_jobs / dreaming_reports；不导出 `apiKeyEncrypted` 或 MCP headers，疑似含 token 的 MCP args / url 与渠道 baseUrl 会置空，恢复后的模型渠道和 MCP 默认禁用。
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
- [x] Notion 同步 v1：`NotionSyncService` 在父页面下创建子页面并写入 heading / paragraph 块，设置页批量导出（2026-08-07）。
- [x] 语雀同步 v1 + 思源同步 v1：Token 在仓库 / 笔记本下创建 markdown 文档，设置页批量导出（2026-08-07）。
- [ ] Obsidian 双向同步和更完整冲突处理仍待实现。
- [x] 云备份 v1：WebDAV（PROPFIND/PUT/GET）+ S3（AWS SigV4 + ListObjectsV2，兼容 AWS/MinIO/R2/COS）+ OneDrive 云盘（Microsoft Graph）导出包 E2E 加密上传 / 列出 / 解密恢复（用户口令不落盘），设置页入口（2026-08-07）。

### Phase 5 — 数字孪生

- [x] 用户画像分析系统 v1：从本地 Key Points 与最近 Dreaming 报告生成可解释画像，设置页可查看 / 重建 / 编辑 / 删除画像信号，并支持冲突提示、版本历史、差异对比、恢复历史版本、待确认画像变更、逐项采纳 / 拒绝和全部变更详情审阅。
- [x] 数字孪生 v1：`PersonaProfileGenerator`（画像 → 人格配置 / 替身 system prompt）+ `MediaPersonaAnalyzer`（emoji / 语音 / 图片媒体信号），设置页可预览（2026-08-07）。
- [x] 替身审计日志落库 v1：`persona_audit_logs` 表 + 授权 / 撤销 / 回复全记录 + 设置页历史查看 / 清空（2026-08-07）。
- [ ] 声音 / 图像 / 表情深度语义分析（需多模态模型）。
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
- [x] MCP 协议客户端：App 内建 / stdio / SSE、Tool / Resource / Prompt。
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
- [x] 建立移动端主链路冒烟脚本 / 记录：`scripts/smoke_mobile_main_flow.sh` + `docs/archive/mobile-main-flow-smoke-2026-06-27.md`；2026-07-02 复验 4 个 smoke 测试通过。
- [x] 建立轻量性能基线：分析、测试、代码生成、搜索索引、Dreaming、Dreaming 通知调度、用户画像、本地数据导出、安全导入、结构化备份 / 恢复、电脑端本地传输、Obsidian Vault 导出、Obsidian 增量同步、Obsidian 附件同步 / 链接重写、冲突详情界面、可选覆盖冲突策略、原始音频附件可选同步、同名附件链接精确去重、stale 文件安全清理、stale 冲突详情解释、语音转写状态 / 失败脱敏导出、聊天音频卡片转写状态读取、STT 配置加载 / 引擎创建、音频转写详情读取、TTS 配置加载 / 引擎 / 服务创建、TTS 播放停止控制、TTS 原生播放事件解析、STT/TTS 厂商预设推断、OpenAI Relay 健康检查端点、CORS 预检和 Responses API 非流式端点耗时已记录，Responses API 流式 SSE 已补局部兼容测试；真机和长会话基线仍待补。
- [x] 建立轻量安全基线：密钥字面量、日志输出、对话档案提交风险已扫描；本地数据导出压缩包、移动端系统分享、安全导入、结构化备份 / 恢复、电脑端本地传输、Obsidian Vault 导出 / 增量同步 / 附件链接重写 / 冲突详情界面 / 可选覆盖冲突策略 / 原始音频附件可选同步 / 同名附件链接精确去重 / stale 文件安全清理 / stale 冲突详情解释 / 语音转写失败脱敏 / 聊天音频卡片转写状态展示 / OpenAI 兼容 STT 配置密钥 / 音频转写详情查看复制 / OpenAI 兼容 TTS 配置密钥 / 原生播放边界 / 停止播报控制 / 播放完成事件回传、STT/TTS 厂商预设、OpenAI Relay 健康检查端点、CORS 预检、Responses API 非流式 / 流式生命周期事件端点和本地通知 ID 专项已补，桌面分享 / 云同步 / 社交通道专项仍待补。

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
  - [x] OpenAI 兼容 TTS 语音播报 v1：设置页可启用 TTS、配置 Base URL / 模型 / 音色 / 加密 API Key；AI 回复卡片提供播报按钮，按配置生成临时 mp3 / wav / opus / aac / flac 音频后通过 `simichat/audio_player` 调用 Android `MediaPlayer` / iOS `AVAudioPlayer`，原生侧限制只能播放应用私有目录内文件。
  - [x] TTS 播放停止控制 v1：播报生成中显示禁用的“正在生成语音”状态；开始播放后当前 assistant 回复显示“停止播报”，用户可主动停止原生播放并清除当前播报状态。
  - [x] TTS 播放完成事件回传 v1：Android / iOS 原生播放器在完成、停止、错误时回传终止事件，聊天页按当前音频路径自动清理“停止播报”状态，避免播放结束后 UI 仍显示播报中。
  - [x] STT/TTS 厂商预设 v1：设置页语音输入 / 语音播报弹窗提供厂商预设下拉，支持 OpenAI、Groq STT 与自定义 OpenAI 兼容配置，一键填充 Base URL、模型和音色；预设推断兼容 `/v1` 后缀。
  - [ ] 继续补更多非 OpenAI 兼容语音厂商，并完成真机长时间语音播报、真实第三方播放器 / 来电 / 闹钟音频焦点抢占、iOS 真机音频中断和来电场景复验。
- [x] 图片 / 文件附件输入基础稳定化：类型识别、8 个附件数量限制、25 MB 单文件上限、发送前存在性校验、数据库与 Markdown 归档路径保护。
- [x] 消息内本地图片缩略图预览：发送后图片附件展示缩略图、文件名、大小，完整本地路径不进入界面文本。
- [x] ChatGPT 风格多模态 Composer v1：文件多选、视频附件类型、图片参考图 / 图片编辑入口、视频生成、声音合成、声音克隆 / 声音设计复用、语音识别复用、音乐生成和统一工具菜单；通用媒体 endpoint / 模型可在设置中配置，结果作为本地图片 / 视频 / 音频消息展示。具体方案见 `docs/chat-composer-multimodal.md`。
- [ ] Android 多模态、超长内容与 Artifact（2026-08-19 执行型 PRD）：以 `docs/android-multimodal-long-content-artifact-prd.md` 为准。已完成：Phase 1 的三态 `ModelCapabilities` / provider adapter / 六类 Options、图片请求 `n` / 网络层多参考图和 xAI `duration` 基础；Phase 2 的大粘贴私有归档、`TextChunker`、会话草稿跨进程恢复、单次文本安全预算、路径 C 的持久化 `ChunkedContentTask`（`mapReduce` / `orderedTransform`、每段瞬态重试、Stop、冷启动收敛为可继续、唯一最终 assistant、聊天内工作卡、schema 14），以及路径 A 子集：已验证的 OpenAI Responses 普通文档原生 `input_file`（安全文件名、单次原始 bytes 发送，禁止正文重复入 `input_text`）。仍未完成：其它 provider 的真实 `FileTransport` / File API、服务端附件拒绝后的一次性降级、完整聊天 / 工作分段视图；六类独立任务面板的实际业务提交 / 交付；Artifact 私有存储、受限预览、版本与下载；真实云端长文本 E2E 和 Pixel 8 长文本交互 smoke。纯 document 文本附件超单次安全预算会自动创建分批任务；混合非文本附件仍明确拒绝，避免静默遗漏素材。设置页仅保存凭据和默认值；本轮不以新增音乐为验收项。`docs/android-multimodal-long-content-artifact-requirements-refinement.md` 定义交付判定、状态机、Options、A/B/C 决策、任务恢复、Artifact 边界与真机矩阵；交互基准见 `docs/chatgpt-interaction-reference.md`。
- [x] 对话级模型切换体验完善：切换记录写入当前会话时间线，切换失败回滚选择，`model_switch` 记录不进入 AI 请求上下文。

### P1 — 模型接入与个人中转

- [x] 扩展主流厂商预设清单第一版：OpenAI、Claude、Gemini、DeepSeek、通义千问 / 阿里云百炼、百度千帆 / 文心一言、讯飞星火、Kimi / Moonshot AI、SiliconFlow、Groq、Mistral AI、Together AI、Fireworks AI、xAI / Grok、Perplexity、DeepInfra、火山方舟 / 豆包、腾讯混元、OpenRouter、Ollama，可在设置页快速填充渠道，并展示 / 一键复制建议模型名、Base URL 和厂商文档链接，帮助用户在模型列表不可用或权限受限时手动添加第一个模型。
- [x] 设计并落地批量免费模型引导接入流程：设置页支持粘贴 JSON 批量导入渠道 / 模型，弹窗默认使用 `presetId=groq` 预设示例，并可从剪贴板粘贴 JSON，也可一键复制或恢复固定安全示例 JSON，API Key 加密落库，Ollama 可空 Key；导入 JSON 根结构支持单个渠道对象、渠道数组或 `channels` 数组包裹对象，单模型可用 `model` / `modelName` / `defaultModel` 或 `models` 字符串 / 对象简写，并可用 `presetId` / `providerPresetId` / `provider` / `preset` 引用内置厂商预设 ID、完整显示名称或 `/` 分隔显示名称短别名自动补渠道名、Base URL 和协议，预设匹配忽略大小写、首尾空格和斜杠两侧空格差异；未知预设等错误提示会脱敏疑似密钥 / token。
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
- [x] Dreaming 报告历史 v1：`dreaming_digest_history_v1` 保留最近 20 次有内容报告，按 `dayKey` 去重，设置页可展开审阅历史报告内容，可删除单条报告，也可清空最近报告与历史报告，并纳入结构化备份 / 恢复白名单。
- [x] Dreaming Android 系统后台调度 v1：WorkManager 一次性唯一任务、设置变化重排、成功后排下一日、失败 backoff retry、跨 isolate SQLite claim 防重、后台 Dreaming / 画像候选 / Reflection / 通知已落地并在 Pixel 8 JobScheduler 真机通过。
- [ ] Dreaming iOS 真机系统后台与高级条件：`BGProcessingTask` 代码基线已完成，当前 iPhone13 `backgroundRefreshStatus=denied`；待开启“后台 App 刷新”后补 pending task / 强制执行 / 结果持久化证据。Android 非计费网络与充电条件的阻塞 / 满足后放行均已通过，仍需跨日、长时间 Doze 和 OEM 长时间可靠性验证。
- [ ] 本地向量检索增强：Key Points 本地语义向量召回 v1 已接入聊天上下文，本地消息语义索引 v1 已接入全局搜索，并已提供用户可控开关；模型 embedding、真正向量数据库 / ANN、增量维护优化和真机长会话基线仍待实现。
- [x] 本地用户画像 v1：基于 Key Points 与最近 Dreaming 报告抽取偏好、目标、任务、基础画像、表达风格、作息线索和关键词。
- [x] 用户画像可控管理 v1：支持本地编辑 / 删除画像信号，重建画像时保留用户控制，并过滤敏感内容。
- [x] 用户画像版本历史与冲突检测 v1：本地持久化最近 20 个画像版本，重建 / 编辑 / 删除 / Dreaming 后自动记录历史，偏好冲突提示可在设置页查看。
- [x] 用户画像历史差异对比与恢复 v1：设置页展示历史版本相对当前画像的新增 / 移除摘要，并支持一键恢复历史画像快照。
- [x] Dreaming 待确认画像变更 v1：手动 Dreaming 与前台到期 Dreaming 生成本地待确认画像变更，用户采纳后才写入正式画像。
- [x] 待确认画像变更逐项采纳 / 拒绝 v1：设置页可对单条新增 / 移除画像信号单独采纳或忽略，剩余提案自动收敛，采纳单项写入画像历史。
- [x] 待确认画像变更详情审阅 v1：提案超过 4 条差异时可打开详情弹窗查看全部差异，并对详情中的任意单项采纳 / 忽略。
- [x] 本地反思机制 v1：`ReflectionService` 基于最近 Dreaming、用户画像和待确认画像变更生成回应质量、未回复会话、会话追问压力、重复追问、最新任务推进、最后一问未答、敏感标题降级和最后用户问题安全片段等可解释结论与行动项，`assistant_reflection_v1` 本地持久化，`assistant_reflection_history_v1` 保留最近 20 次反思，`assistant_reflection_prompt_enabled_v1` 控制是否注入下一轮短期提示，设置页提供“本地反思 / 自我优化”入口，可展开审阅历史反思、按 `dayKey + sourceDigestDayKey` 精确删除单条反思、删除反馈显示来源、删除当前最近反思后自动回退，并可清空最近反思报告与反思历史。
- [ ] Dreaming 模型驱动画像增量分析工作流。

### P2 — 生态扩展

- [ ] 社交通道抽象与飞书 / Telegram / Discord 优先接入方案。
- [ ] 多源技能市场接入与权限隔离。
- [ ] MCP 运行时 / 旁车容器层。
- [x] 定时任务与系统通知联动 v1：Dreaming 前台到期整理完成后推送本地通知，通知失败不影响主链路。
- [ ] 定时任务与系统日历 / 闹钟联动。
- [x] 网页搜索 / 检索增强生成 v1：`WebSearchService`（DuckDuckGo 免 Key）+ MCP 内建工具 `simichat.web_search`（2026-08-07）。
- [x] 图片生成 v1：OpenAI 兼容 `/v1/images/generations`，聊天输入框「✨」按钮生成并本地保存，图片模型可配置（2026-08-07）。
- [x] 深度链接 `ai-chat://` v1：Android / iOS 注册自定义 URL scheme，Flutter 通过 `simichat/deep_link` 处理冷启动与运行中链接；支持 home / new / settings / marketplace / session 跳转，详见 `docs/deep-linking.md`。

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
- [x] Notion 同步 v1：`NotionSyncService` 在父页面下创建子页面并写入 heading / paragraph 块，设置页批量导出（2026-08-07）。
- [x] 语雀同步 v1 + 思源同步 v1：Token 在仓库 / 笔记本下创建 markdown 文档，设置页批量导出（2026-08-07）。
- [ ] Obsidian 双向同步和更完整冲突处理仍待实现。
- [x] 用户画像结构定义 v1：`UserProfile` / `UserProfileBuilder` / `user_profile_v1` 本地持久化；`user_profile_controls_v1` 保存用户编辑 / 删除控制；`user_profile_history_v1` 保存最近画像版本；`UserProfile.conflicts` 保存偏好冲突提示；`UserProfileDiff` / `UserProfileChangeItem` 支持差异对比与逐项处理；`UserProfileChangeProposal` / `user_profile_change_proposals_v1` 支持待确认画像变更。
- [ ] 声音 / 图像 / 表情多模态画像提取。
- [x] 镜像数字人 v1：人格配置生成与替身 system prompt 模板、**替身回复显式授权（持久化 + 时间戳）**、聊天页「替身回复」入口、**替身审计日志落库**（2026-08-07）。
- [x] 数字人直播 v1：`LiveStreamScriptGenerator` 从镜像人格生成直播脚本 + RTMP 目标配置与校验 + 开播会话记录（2026-08-07）；应用内直接推流待做。

---

## 八、进度记录

> 说明：本节记录“能代表项目阶段推进”的里程碑；当前可复现的测试输出、构建结果、脚本结果和未补证边界沉淀到 `docs/verification-baseline-2026-08-08.md`。`docs/archive/verification-baseline-2026-06-27.md` 仅保留历史基线。

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
| 2026-07-07 | Dreaming 边界与下次前台整理提示 | 设置页 Dreaming 入口副标题显示“前台到期 · 非系统后台”，并根据 `dreaming_schedule_v1` 展示“下次前台整理：已关闭 / 今日 HH:mm / 现在已到期 / 明日 HH:mm”，把当前 v1 的有效边界直接暴露给用户，避免误解为系统后台夜间任务；新增 widget 回归 `dreaming tile explains foreground-only schedule boundary` 和单元回归 `dreaming schedule formats next foreground run status` | 已完成 |
| 2026-07-07 | 国产模型预设补充 | 新增百度千帆 / 文心一言 `https://qianfan.baidubce.com/v2`、讯飞星火 `https://spark-api-open.xf-yun.com/v1`、Kimi / Moonshot AI `https://api.moonshot.ai/v1`、SiliconFlow `https://api.siliconflow.cn/v1`、火山方舟 / 豆包 `https://ark.cn-beijing.volces.com/api/v3`、腾讯混元 `https://api.hunyuan.cloud.tencent.com/v1` 六个 OpenAI 兼容渠道预设；预设只填公共 Base URL / 协议 / 文档链接和建议模型名提示 / 复制辅助，并在已保存渠道的添加模型弹窗按 `protocol + baseUrl` 反推预设提供推荐模型名快速填入；不内置 API Key，不自动创建模型，仍需用户连通性测试确认账号权限 | 已完成 |
| 2026-07-07 | 全球 OpenAI 兼容模型预设补充 | 新增 Groq `https://api.groq.com/openai/v1`、Mistral AI `https://api.mistral.ai/v1`、Together AI `https://api.together.ai/v1`、Fireworks AI `https://api.fireworks.ai/inference/v1`、xAI `https://api.x.ai/v1`、Perplexity `https://api.perplexity.ai`、DeepInfra `https://api.deepinfra.com/v1/openai` 七个 OpenAI 兼容渠道预设，并提供低延迟 / 搜索增强 / 开源托管方向的建议模型名；保持只填公共 Base URL / 协议 / 文档链接，不内置 API Key、不自动创建模型 | 已完成 |
| 2026-07-07 | 批量导入预设 ID / 显示名 / 短别名填充 | `ModelChannelImportParser` 支持 `presetId` / `providerPresetId` / `provider` / `preset`，导入 JSON 可只填预设 ID、完整显示名称或 `/` 分隔显示名称短别名、用户自己的 API Key 和模型列表，自动补渠道名、Base URL 与协议；显式 name / baseUrl / protocol 仍可覆盖预设公共字段；预设匹配忽略大小写和首尾空格；未知预设等错误提示会脱敏疑似密钥 / token，不内置 API Key | 已完成 |
| 2026-06-27 | 语音 / 多模态 | 语音文件附件、私有音频归档、STT 转写 sidecar、转写状态展示、详情查看 / 复制、移动端录音、OpenAI 兼容 STT、OpenAI 兼容 TTS、播放停止、播放完成事件、STT/TTS 厂商预设 | 已完成 |
| 2026-08-18 | Android Production Release 与多模态客户端复验 | 当前工作树全量 Flutter 测试 1030 项通过、`flutter analyze` 无问题；Pixel 8 `37101FDJH0077P` 使用 `scripts/smoke_android_release_install_launch.sh` 通过 `adb install -r` 覆盖安装，`ANDROID_RELEASE_PARITY status=verified`，设备 `base.apk` 与构建 APK SHA-256 为 `cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d`，签名证书 SHA-256 为 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`；`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 不变，PID `32261`、`top.simitalk.aichat/.MainActivity` 可见。随后模型切换隔离 smoke 四个 marker 全部通过，隔离包已清理，正式包未卸载、未清空数据、未执行 `am force-stop`。本地 / loopback / fake 证据仍不替代真实云端媒体与语音 E2E | 已完成当前 Android 覆盖安装与本地真机验收；真实厂商云端能力和长任务仍待外部配置补证 |
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
| 2026-06-27 | OpenAI Relay 兼容性 | Bearer 鉴权健康检查 `/health` / `/v1/health`、浏览器 CORS 预检、非流式 buffered / 流式 SSE `/v1/responses` Responses API 兼容端点 | 已完成 |
| 2026-07-08 | MCP App 内建 Runtime v1 | 新增 `app_native` 传输与 `AppNativeMcpTransport`，在 App 进程内完成 MCP initialize / tools/list / tools/call / resources/list / resources/read；内建 `simichat.now`、`simichat.runtime_info` 和 `simichat://runtime/info`，不启动外部进程，不依赖宿主机 Node / npx / Python；`McpManager` 支持 app_native 并暴露 `ready`；MCP 市场首位 `SimiChat 内建工具` 安装后自动连接，设置页默认“App 内建（移动端/PC 直接运行）”。 | 已完成代码级自依赖基线 / 外部 Node MCP 容器侧车待补 |
| 2026-07-08 | MCP PC Node 容器侧车 v1 | 新增 `tools/mcp_runtime/container/Dockerfile`、`package.json` 和 `runtime-server.mjs`，容器基于 `node:22-alpine` 并暴露 `/health`、`/mcp/sse/:serverId`、`/mcp/messages/:connectionId`；新增 `scripts/mcp_runtime_container.sh build/start/stop/restart/status/logs`，自动选择 Docker / Podman，脚本不调用宿主机 node/npm/npx；新增 `docs/runtime-manifest.example.json` 与 MCP 市场项 `SimiChat Node 容器 Runtime`，默认本地 SSE URL `http://127.0.0.1:37651/mcp/sse/simichat-node`。 | 已完成静态和脚本门禁 / App 内生命周期管理与第三方 MCP 包白名单待补 |
| 2026-07-02 | 移动端应用身份 | Android / iOS 展示名 `SimiAIChat`，Android `applicationId` 与 iOS Bundle ID `top.simitalk.aichat`；保留历史数据格式标识 | 已完成 |
| 2026-07-02 | 对话页 Markdown / 字体 | GitHub Web 扩展、旧式图片、行内 / 块级公式、HTML audio/video 安全卡片、HTML details、旧式 details、Mermaid、Draw.io / mxGraph；字体范围 90%–120%，正文 15sp | 已完成 |
| 2026-07-03 | Markdown 渲染 v2 | 修复行内 code 被误渲染为大代码块；用户输入与 AI 输出统一使用 Markdown 渲染；补齐旧式 / Obsidian / HTML 图片、`:::mermaid`、`[mermaid]`、HTML Mermaid、`draw.io` / `mxgraph` / 原始 `mxGraphModel` 等新老格式兼容 | 已完成 |
| 2026-07-02 | 双机真机覆盖安装 | Pixel 8 通过 `adb install -r` 覆盖安装并启动；iPhone13 通过 `devicectl` 安装 release `Runner.app` 并启动；未卸载、未清数据，旧包仍保留 | 已完成 |
| 2026-07-03 | 音频附件 STT 音频接口前置转写 | audio 附件发送时先调用 OpenAI 兼容 `/v1/audio/transcriptions`：优先使用设置页 STT 配置，未配置时复用当前 `openai_chat` / `openai_response` 渠道 Base URL 与 API Key；成功后把转写结果作为普通文本发给聊天模型，不再把 audio base64 交给聊天模型 | 已完成 |
| 2026-07-03 | iOS 系统 Speech 原生识别兜底 | 在 STT 引擎链路增加 fallback：显式 STT 配置、当前 OpenAI 兼容聊天渠道音频接口均失败 / 返回空时，iOS 调用 `SFSpeechURLRecognitionRequest` 识别应用私有目录内录音；新增 `NSSpeechRecognitionUsageDescription` 权限说明、Dart MethodChannel 引擎和 fallback 引擎测试 | 已完成 |
| 2026-07-05 | 无限上下文预算控制 | 聊天发送前按 `protocol + modelName` 推断模型窗口，预留输出 token 后按 `maxInputTokens` 裁剪 system / memory / skills / MCP 工具说明和历史消息；预算模式不再固定最近 20 条，可在窗口内尽量保留更多历史，优先保留最新用户问题；上下文超限流式错误会严格裁剪重试一次，失败时保留可操作提示 | 已完成 |
| 2026-07-06 | 本地反思机制 | Dreaming 后基于本地日报、用户画像和待确认画像变更生成回应质量、上下文、长期记忆、用户画像和任务推进的可解释反思报告；设置页可查看 / 手动运行，结构化备份包含 `assistant_reflection_v1`、`assistant_reflection_history_v1` 与 `assistant_reflection_prompt_enabled_v1`；复核时修正弹窗关闭后运行反思使用父级 `WidgetRef`，并新增可关闭的反思短期提示注入、最近 20 次反思历史、长会话质量基线、短期提示预览、历史反思展开审阅 / 精确单条删除 / 当前报告回退和最近反思 / 历史清空入口，短期提示优先保留可直接改善下一轮回复的任务推进项 | 已完成 |
| 2026-07-07 | 反思来源新鲜度提示 | `ReflectionService` 在反思日期与来源 Dreaming 日期不一致时新增高优先级“来源新鲜度”结论和“先运行今日 Dreaming”行动项，设置页本地反思入口也直接展示旧来源日期和更新提示，短期提示会继承该提醒；同时新增会话级未回复识别，即使全局轮次均衡，只要某个会话有用户消息且助手 0 回复，也会生成高优先级“未回复会话”补回复行动项，避免旧日报或局部断线被当作健康上下文；新增 `reflection warns when source dreaming is older than reflection day`、`reflection tile surfaces stale dreaming source` 和 `reflection detects unanswered sessions despite balanced total turns` 红绿回归；Dreaming / Reflection 相关 31 项通过 | 已完成 |
| 2026-07-07 | 反思最后一问未答提示 | `DreamingSessionDigest` 新增 `lastMessageRole`，`DreamingService.runDailyDigest()` 会记录每个会话最后一条 original 消息角色，Markdown / JSON 保留该字段；`ReflectionService` 在会话已有助手回复但最后一条仍来自用户时生成高优先级“最后一问未答”结论，并把补最新追问行动项带入短期提示；新增 `reflection detects latest user message even when session has assistant replies` 与 Dreaming lastMessageRole JSON 回归；目标测试 `test/reflection_service_test.dart` + `test/dreaming_service_test.dart` 11 项通过，Dreaming / Reflection / 结构化备份目标 gate 40 项通过，1000 条 Dreaming 基准 `run_ms=51` / `digest_elapsed_ms=49` | 已完成 |
| 2026-07-07 | 反思会话追问压力提示 | `ReflectionService` 新增会话级追问压力启发式：即使当天全局用户 / 助手轮次均衡，只要单个会话用户消息比助手回复多 2 条及以上且已有助手回复，就生成高优先级“会话追问压力”结论，提示下次先做阶段性总结再逐项回应；同时调整本地反思生成顺序，让画像任务 / 目标跟进优先于泛化轮次和长会话建议进入短期提示，避免新诊断挤掉任务推进；新增 `reflection detects session follow-up pressure despite balanced totals` 红绿回归，`test/reflection_service_test.dart` 9 项通过 | 已完成 |
| 2026-07-07 | 反思重复追问提示 | `ReflectionService` 新增会话级重复意图启发式：从 Dreaming 会话 highlights 与 `latestUserHighlight` 中提取安全片段，归一化标点 / 空白后用包含关系和字符集合重叠识别同一会话反复追问的相近问题；命中后生成高优先级“重复追问”结论，并把“先明确状态、阻塞点和下一步”行动项带入短期提示；新增 `reflection detects repeated unresolved user intent in one session` 红绿回归，先红灯确认旧逻辑只输出“会话追问压力 / 最后一问未答”，修复后目标用例通过，Dreaming / Reflection / 结构化备份目标 gate 41 项通过 | 已完成 |
| 2026-07-07 | 反思最新任务推进提示 | `ReflectionService` 新增最新用户任务启发式：当 Dreaming 会话最后一条消息来自用户，且 `latestUserHighlight` 命中“继续推进 / 帮我 / 修复 / 验证 / 复跑 / 补 / 实现 / 看下 / 检查”等任务语气时，生成高优先级“最新任务推进”结论，并把该最新任务放入下一轮短期提示；新增 `reflection promotes latest user task when profile has no task` 红绿回归，先红灯确认旧逻辑只输出“最后一问未答 / 主题连续性”，修复后目标用例通过，Dreaming / Reflection / 结构化备份目标 gate 42 项通过 | 已完成 |
| 2026-07-07 | 反思最新任务误触发保护 | 收窄“最新任务推进”触发词，移除过宽的单字“请 / 先 / 做”，保留“请继续 / 请帮 / 继续推进 / 修复 / 验证 / 复跑 / 补 / 实现 / 看下 / 检查”等明确任务语气，避免“请问这个设置是什么意思”这类普通礼貌问题误入短期任务提示；新增 `reflection does not promote generic polite question as latest task` 红绿回归，先红灯复现误判，修复后正反两个目标用例通过，Dreaming / Reflection / 结构化备份目标 gate 43 项通过 | 已完成 |
| 2026-07-07 | Dreaming 明确任务记忆候选 | `KeyPointExtractor` 复用最新任务语气识别，把“继续推进 / 请继续 / 请帮 / 帮我 / 现在帮我 / 修复 / 验证 / 复跑 / 补 / 实现 / 看下 / 检查”等用户明确任务归类为 `task` 记忆候选，避免 Dreaming 只留下摘要而漏掉用户最新要推进的事情；新增 `dreaming service extracts latest explicit task as memory candidate` 红绿回归，专项 Dreaming / Reflection / 结构化备份 gate 44 项通过，1000 条消息基准 `run_ms=55` / `digest_elapsed_ms=52` / `memory_candidates=40` / `has_content=true`，`flutter --no-version-check analyze` 无问题 | 已完成 |
| 2026-07-07 | Dreaming SQLite job/report 基础设施 | 新增 `DreamingJobs` / `DreamingReports` Drift 表、`DreamingDao` 和 schemaVersion 7 迁移，为后续系统后台调度、可恢复 job 队列和报告表做前置；`DreamingReports.dayKey` 保持单日唯一，DAO 覆盖创建 job、running/completed/failed 状态流转、按日/最近报告读取、同日报告 upsert；同时把 `dreaming_jobs` / `dreaming_reports` 纳入 `structured_data/local_database.json` 导出 / 预览 / 恢复，避免新 SQLite 状态成为备份盲点。红灯：新增 DAO 测试先失败于缺少 `dreamingDao`，导出测试先失败于仅有 Dreaming 表时 snapshot 为 null；修复后 `test/dreaming_dao_test.dart`、`test/data_export_service_test.dart --name "dreaming jobs"` 转绿，综合 Dreaming / 数据库 / 导出门禁 40 项通过，`flutter --no-version-check analyze --no-pub`、`git diff --check` 和 hook 检查通过 | 已完成 |
| 2026-07-07 | Dreaming 运行链路写入 SQLite job/report | `runDreamingDigest()` 现在会在运行前创建 `dreaming_jobs` 记录并标记 running，手动触发写 `trigger=manual`，前台到期自动整理写 `trigger=foreground_due`；整理成功后保存 SharedPreferences 最近报告 / 历史和 Key Points 的同时，向 `dreaming_reports` upsert 当日 Markdown 报告与 digest JSON，并把 job 标记 completed；异常时会 best-effort 标记 failed 且不掩盖原始错误。红灯：`runDreamingDigest persists sqlite job and report` 先失败于 jobs 为空；修复后 `test/dreaming_provider_test.dart` 5 项通过，综合 Dreaming / DAO / 导出 / 设置页门禁 38 项通过，`flutter --no-version-check analyze --no-pub`、`git diff --check` 和 hook 检查通过 | 已完成 |
| 2026-07-07 | Dreaming 最新用户问题片段 | `DreamingSessionDigest` 新增 `latestUserHighlight`，`DreamingService.runDailyDigest()` 从每个会话最后一条用户消息提取安全问题片段，避免 highlights 只保留前三条时丢失最后追问；若真正最后一条用户消息命中密钥 / token 等敏感内容，则不会回退到更早旧消息，避免误导 Reflection；Dreaming Markdown / JSON 保留该片段，`ReflectionService` 的“最后一问未答”结论会在安全时直接展示最新追问内容；新增 `dreaming service keeps latest user highlight beyond first highlights`、`dreaming service does not backfill latest user highlight when latest is sensitive` 红绿回归，并扩展 `reflection detects latest user message even when session has assistant replies`；目标测试 `test/dreaming_service_test.dart` + `test/reflection_service_test.dart` 14 项通过 | 已完成 |
| 2026-07-07 | Dreaming 敏感会话标题降级 | `DreamingSessionDigest` 输出层新增安全标题过滤，`DreamingService.runDailyDigest()`、`DreamingDigest.toMarkdown()` 和 JSON 持久化在会话标题命中 API Key / Bearer / token / secret 等敏感模式时统一降级为“敏感会话”，避免标题泄漏密钥；旧 JSON 反序列化时也会二次过滤标题；新增 `dreaming service redacts secret-like session titles` 红绿回归，目标测试 `test/dreaming_service_test.dart` + `test/reflection_service_test.dart` 15 项通过 | 已完成 |
| 2026-07-06 | 当前基线真机覆盖安装 | 提交 `d67a6f4` 已在 Pixel 8 通过 `adb install -r` 覆盖安装并启动，iPhone13 通过 `devicectl` release 覆盖安装成功且 Runner 进程可见；本轮 Dreaming 修复后 debug 包再次在 Pixel 8 `adb install -r` 覆盖安装成功，`firstInstallTime=2026-07-02 23:29:09` 保持不变，`lastUpdateTime=2026-07-06 02:36:21`，`dataDir=/data/user/0/top.simitalk.aichat`，未卸载、未清数据 | 已完成 |
| 2026-07-06 | Pixel 8 长会话 Dreaming / Reflection 真机验证 | 使用 debug `run-as` 安全种入专用 72 条长会话并保留 DB 备份；真机可显示第 69–72 轮；修复弹窗关闭后运行 Dreaming 使用已销毁 `WidgetRef` 的问题并新增延迟 Dreaming widget 回归；修复包覆盖安装后手动 Dreaming 生成 2026-07-06 日报（1 个会话、72 条消息、36/36 用户 / 助手消息、耗时 101 ms），生成待确认画像变更和 Reflection（5 条结论、4 个行动项、历史 1 次），设置页短期提示预览可见 | 已完成 |
| 2026-07-07 | Dreaming 有效性复核与报告历史 | 复核 `DreamingService.runDailyDigest()`、`runDreamingDigest()`、`maybeRunDueDreaming()` 链路；新增 `dreaming_digest_history_v1` 持久化最近 20 次有内容日报、按 `dayKey` 去重，并加入结构化备份 / 恢复；设置页 Dreaming 弹窗现在展示历史报告保留次数、最近日期和消息覆盖，支持展开审阅历史报告 Markdown 预览，并提供“删除此报告”和“清空报告”两级删除；删除当前最近报告时会自动回退到仍保留的下一条历史，避免最近报告空洞；聚焦 Dreaming / Reflection / 结构化备份回归 31 项通过，`scripts/benchmark_dreaming.sh -r expanded` 显示 1000 条消息 `run_ms=49` / `digest_elapsed_ms=46` / `memory_candidates=40` / `has_content=true`，`flutter --no-version-check analyze` 无问题 | 已完成 |
| 2026-07-06 | Pixel 8 真实发送 / 重试 / 停止 / 搜索真机验证 | 使用本机 OpenAI 兼容 mock 服务和 `adb reverse`，通过 debug `run-as` 安全种入专用 mock 渠道、模型和会话；真机默认模型可见，真实发送触发 `/v1/chat/completions` SSE 请求并落库 assistant 回复，Reflection 短期提示进入 system prompt；重试后 mock 请求数从 1 增至 2；慢流停止后上游记录 `broken_pipe=true` 且 assistant 只保留前 2 个 chunk；历史搜索 `smoke` 可过滤到专用会话并排除长会话 | 已完成 |
| 2026-07-06 | Pixel 8 模型切换 / 切换后发送真机验证 | 复用本机 OpenAI 兼容 mock 服务和同一 smoke 会话，安全种入 `simichat-mock-a` / `simichat-mock-b` 两个模型；真机顶部菜单可从 A 切换到 B，`sessions.default_channel_model_id` 更新为 B，时间线新增 `model_switch` system 消息；切换后真实发送触发 `/v1/chat/completions` SSE 请求，mock 日志模型为 `simichat-mock-b`，assistant 回复 `MOCK-B reply 20260706` 以 B 模型落库并在 UI 显示 | 已完成 |
| 2026-07-06 | 真机集成发送 smoke 入口 | 新增 `integration_test/mobile_real_send_smoke_test.dart` 和 `scripts/smoke_device_integration_send.sh`，测试在设备内启动本地 OpenAI 兼容 SSE mock，使用内存 SQLite seed 渠道 / 模型 / 会话，并通过真实 Widget 输入与发送验证 UI → `sendMessage` → SSE → assistant 落库 → UI 展示闭环；脚本会自动临时追加并恢复 `sqlite3.source=system` hook；Pixel 8 已通过；按用户要求 iOS 真机必须使用 release，因此脚本现在会拒绝 iOS debug integration 路径并提示使用 release smoke | 已完成 Pixel 8 / iOS release 发送待补 |
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
| 2026-07-06 | Android 音频焦点基础处理 | `MainActivity.kt` 的正式原生音频播放在启动前请求 `AudioManager` 焦点；焦点丢失 / 短暂丢失时停止播放并回传既有 stopped 事件，允许 duck 时降音量、焦点恢复时还原，播放完成 / 错误 / 主动停止 / 启动失败都会释放焦点；direct-channel smoke 使用测试参数跳过焦点请求；新增静态和 MethodChannel 回归锁定产品路径不跳过焦点；真实来电 / 闹钟 / 其他播放器抢占焦点仍待真机复验 | 已完成代码级加固与 Pixel 8 smoke 复验 / 真实外部中断待补 |
| 2026-07-06 | iOS AVAudioSession 中断基础处理 | `AppDelegate.swift` 的原生播放注册 `AVAudioSession.interruptionNotification`；收到 interruption began 且当前正在播放时停止播放并复用 stopped 事件回传；播放完成 / 错误 / 主动停止 / 启动失败都会 `setActive(false, options: [.notifyOthersOnDeactivation])` 释放音频会话；新增静态回归锁定关键路径 | 已完成代码级加固与 iOS Debug 构建 / 真实来电、耳机和系统中断待补 |
| 2026-07-06 | Android release 稳定运行门禁 | 按用户要求本轮不触碰 people，仅在 Pixel 8 `37101FDJH0077P` 复验当前工作树：`./scripts/smoke_full_stability_gate.sh -r expanded` 全量 346 测试通过，`flutter --no-version-check analyze --no-pub` 无问题，`git diff --check` 无输出；`./scripts/benchmark_dreaming.sh -r expanded` 1000 条消息基准 `run_ms=57` / `digest_elapsed_ms=53` / `memory_candidates=40`；`./scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 构建 31.5MB release APK 并 `adb install -r` 覆盖安装成功，`versionName=1.0.0`、`firstInstallTime=2026-07-06 14:09:30`、`lastUpdateTime=2026-07-06 14:37:36`、`dataDir=/data/user/0/top.simitalk.aichat`；清 log 后不清数据 force-stop 再启动，release pid `32365`，按 pid 观察 25 秒 32 行日志无 Fatal / ANR，`topResumedActivity=top.simitalk.aichat/.MainActivity`；正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook | 已完成 Android release 稳定门禁 / people 未触碰 |
| 2026-07-06 | Dreaming 长会话截断可见性 | `DreamingDigest` 新增 `isTruncated` / `messageLimit`，`runDailyDigest` 通过读取 `maxMessages + 1` 探测当天消息是否超过整理上限，再只处理限定数量；Markdown / JSON 显式保留截断提示，旧 JSON 默认兼容；新增回归覆盖超过 `maxMessages` 时只处理最近 N 条、Markdown 提示和 JSON 往返；同时 `scripts/benchmark_dreaming.sh` 复用临时 `sqlite3.source=system` hook，避免 GitHub native asset 下载超时误伤基准；验证：Dreaming service 3 测试通过、1000 条消息基准 `run_ms=41` / `memory_candidates=40`、`flutter analyze --no-pub` 通过、全量 345 测试通过 | 已完成 |
| 2026-07-06 | Reflection 承接 Dreaming 截断事实 | `ReflectionReport` 新增 `sourceDigestIsTruncated` / `sourceDigestMessageLimit`，`ReflectionService` 从 `DreamingDigest` 复制来源完整性；当 Dreaming 被 `maxMessages` 截断时，Reflection 优先生成高优先级“整理完整性”结论和行动项，短期提示会提醒不要把部分日报当作当天完整画像，需分段整理或补跑更高上限后再确认长期记忆；Markdown / JSON 均保留该事实且旧数据兼容；验证：Reflection service 5 测试通过、`flutter analyze --no-pub` 通过、全量 346 测试通过 | 已完成 |
| 2026-07-06 | Dreaming 截断时保留最新上下文 | `MessageDao` 新增 `getLatestOriginalMessagesInTimeRange()`；`DreamingService` 普通日仍按升序一次读取，只有超过 `maxMessages` 时二次读取最近 N 条原始消息并反转回升序整理，避免超长日对话只保留最早内容、漏掉最新任务；Markdown 截断提示改为“只整理最近 N 条”；验证：Dreaming service 3 测试通过、1000 条消息基准 `run_ms=48` / `memory_candidates=40`、`flutter analyze --no-pub` 通过、全量 346 测试通过 | 已完成 |
| 2026-07-06 | Dreaming 已整理 / 总量缺口可见性 | `MessageDao` 新增 `countOriginalMessagesInTimeRange()`；`DreamingDigest` 新增 `totalOriginalMessageCount`，Markdown / JSON 同时记录“已整理原始消息数”和“当天原始消息总数”，旧 JSON 默认用 `originalMessageCount` 回填；`ReflectionReport` 新增 `sourceDigestTotalOriginalMessageCount`，Reflection Markdown 与短期提示显示类似 `2 / 5` 的整理缺口，避免把部分日报误当完整画像来源；验证：`./scripts/smoke_full_stability_gate.sh -r expanded` 全量 346 测试通过，`flutter --no-version-check analyze --no-pub` 通过，1000 条 Dreaming 基准 `run_ms=57` / `digest_elapsed_ms=53` / `memory_candidates=40` | 已完成 |
| 2026-07-06 | Dreaming 截断覆盖比例 UI / 通知可见 | 自动 Dreaming 完成通知 `buildDreamingDigestNotificationBody()` 新增可选 `totalOriginalMessageCount`，当前台到期整理只处理最近 N 条时通知显示 `已整理 N / 总量 条消息`；`ResponsiveShell` 自动通知传入 `digest.totalOriginalMessageCount`；设置页 Dreaming tile、报告弹窗和手动运行 SnackBar 均复用覆盖比例显示，避免用户只看到 `N 条消息` 而误判完整；验证：`flutter --no-version-check test --no-pub --no-test-assets -r expanded test/notification_service_test.dart test/settings_page_dreaming_test.dart` 11 项通过，`flutter --no-version-check analyze --no-pub` 通过 | 已完成 |
| 2026-07-06 | people 主力机 release 覆盖更新 | 在 Android release 稳定门禁、全量 348 测试、analyze、diff check 和 hook 清理检查通过后，`people` 设备变为 `available (paired)`；按用户约束只走 release 路径执行 `./scripts/smoke_ios_release_install_launch.sh BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D`，构建 `Runner.app` 33.2MB，`devicectl install app` 覆盖安装 `bundleID=top.simitalk.aichat` / `databaseSequenceNumber=6216`，`devicectl process launch` 启动 pid `64943`，`device info apps` 可见 `SimiAIChat top.simitalk.aichat 1.0.0 1`，`device info processes` 可见 `/Runner.app/Runner`；未执行卸载、未清数据，正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook；随后最终复查时 CoreDevice 又显示 `people unavailable`，未继续做交互测试 | 已完成 people release 覆盖安装 / 启动，后续交互待设备可用 |

### 8.3 最新验证基线

| 日期 | 验证项 | 结果 |
| --- | --- | --- |
| 2026-08-19 | OpenAI Responses 普通文档原生传输：路径 A 子集 | `openai_response` 已把经验证模型的 `document` 从文本抽取降级路径切换至 Responses `input_file`：上游请求一次只含用户问题的 `input_text` 与 `file_data=data:<mime>;base64,...` / 安全 `filename`，不含私有归档路径或裸文档正文。协议与 ChatProvider Dio 回环测试 20 项通过，analyze / diff check 无问题。Pixel 8 `37101FDJH0077P` 正式 Release 覆盖安装后，构建和设备 `base.apk` SHA-256 一致为 `7b51c6e768f1261d16a2f75a7c9f9bd48d3eb1a47e4d9a322aea816bbf716d28`，`firstInstallTime` / `dataDir` 不变，`lastUpdateTime=2026-08-19 21:37:17`、PID `32597`、`MainActivity` 前台，无隔离包。 | [PARITY VERIFIED]；协议回环 + 正式包安装完成；真实云端 File API E2E 与服务端拒绝降级待补 |
| 2026-08-19 | 可恢复长内容分批任务 v1：`ChunkedContentTask` 路径 C | 纯 `document` 文本附件超过单次安全预算后，用户消息和私有附件先入库，再走持久化 `mapReduce` / `orderedTransform`；中间 chunk 不进入聊天 / Markdown 档案，最终助手回复使用确定性 ID 原子交付。每段有瞬态重试，Stop 取消 token 并以 SQLite 状态裁决，reduce 晚到不会落入最终消息；冷启动 active task 收敛为 failed 并可“继续 / 从头重试”。工作卡显示进度和安全动作；缺模型/附件时保持终态，避免伪进行中。聚焦 55 项、analyze、diff check 均通过。Pixel 8 `37101FDJH0077P` Production Release 覆盖安装，设备和构建 APK SHA-256 一致为 `0cb02258c80d2604974d11dd8a542c6a4dac0068b4200661cb55955f633730b2`，签名不变，`firstInstallTime=2026-08-18 07:11:12` / `dataDir` 不变，`lastUpdateTime=2026-08-19 20:58:53`，PID `30656`、`MainActivity` 前台、无隔离包。 | 代码级完成 / 正式包已部署；真实 File API、真实云端长文 E2E、手工长文本交互 smoke、Artifact 待补 |
| 2026-08-19 | 超长文本附件单次降级防截断：`ChatProvider` 预算门禁 | 旧路径会把整份已抽取文本交给通用上下文裁剪，超窗时可能静默只发送开头。新增 `singleTextFallbackTokenBudget()`，文本附件最多使用模型最大输入预算的一半，系统提示、历史、序列化和 token 估算保留余量；超出时在新消息 / 附件落库前返回“单次安全输入预算”错误并保留 Composer 草稿，要求缩短、切换大窗口模型或等待分批任务，不伪造原生 File API。新增 half-window 与 60000 字符 `.md` 未落库 / 可重试回归；关联 34 项通过，analyze / diff check 通过。Pixel 8 正式包覆盖安装，`firstInstallTime` / `dataDir` 保持、`lastUpdateTime=2026-08-19 18:50:20`、PID `24898`、`MainActivity` 前台且无隔离包。 | 代码级完成 / 正式包已部署 / 原生文件与分批待补 |
| 2026-08-19 | 会话 Composer 草稿跨进程恢复 v1：`ChatComposerDraftStore`、`ChatPage` 生命周期保存与异步恢复 | 新增应用私有 `chat_composer_drafts_v1` 索引：按会话保存短文本、附件恢复元数据和深度思考，写入串行化并限制 50 条；不保存大粘贴原文、附件 bytes / Base64、凭据或诊断。ChatPage 先恢复进程内缓存，cold cache 再异步读取；以恢复 generation、用户编辑 generation 与活跃会话检查阻止旧读覆盖新输入，附件到达后仅重建对应 Composer。发送成功保留深度思考、清除已消费文本/附件；生命周期切出和销毁前继续保存。`ChatInputBar` 切会话不再把外部初始附件误写为空草稿。新增 Store 与 ChatPage widget 回归；草稿/附件专项 19 项、多模态聚焦 112 项通过，`flutter --no-version-check analyze --no-pub` 和 `git diff --check` 无问题。Pixel 8 已以 Production Release 覆盖安装，`firstInstallTime` / `dataDir` 保持、`lastUpdateTime=2026-08-19 18:39:12`、PID `24303`、`MainActivity` 前台且无隔离包；真实设备进程回收后的草稿恢复仍待独立交互 smoke。 | 代码级完成 / 正式包已部署 / 真机恢复待补 |
| 2026-08-19 | Android 执行型 PRD Phase 2 首段：大粘贴私有附件与分块器 | 新增 `LargePastePolicy`，只按当前 `TextEditingValue` 插入 delta 判断 16000 字符 / 64 KiB UTF-8 / 8000 Token；命中时保留 Composer 原有文本并把原始 UTF-8（含中文、Emoji、Tab、CRLF/LF、末尾换行、Markdown / 代码围栏）写到应用私有 `composer_drafts`。`PastedTextAttachmentService` 保存会话 / 草稿标识、字符 / 字节 / Token、SHA-256 和创建时间，附件卡片支持显示元数据、删除、预览、重命名和还原文本。`TextChunker` 按 H1/H2、完整代码围栏、段落、行、句子和最终安全 code-point 硬切，生成带 `batchId`、顺序、偏移、hash 和可选 overlap 的片段。验证：新增 15 项大粘贴 / 私有归档 / 分块测试通过；`flutter --no-version-check analyze --no-pub` 通过，`git diff --check` 通过。未进行 Pixel 8 或真实渠道请求；文件能力传输、文本降级、mapReduce / orderedTransform、任务持久化和跨进程草稿恢复仍未完成。 | Phase 2 基础完成 / 后续发送与恢复链路待补 |
| 2026-07-14 | 模型增强失败回退状态持久化与设置页可见 | 旧逻辑在模型失败后保存普通 `generationMode=local`，自动 / WorkManager / BGTask 路径虽然安全完成，但用户之后无法判断模型是否曾尝试失败。新增 `model_fallback` 模式并保持旧 `local` / `model` JSON 兼容；provider 捕获可选模型异常后把本地安全报告标记为回退，最近报告和历史均持久化该事实，不保存异常文本。Markdown 显示“模型失败回退”，设置页 tile 显示回退状态，弹窗展示“最近一次模型增强失败，已安全回退本地反思”；手动反馈改为读取报告模式，不会因用户后来切换开关误判旧报告。聚焦 47 项、全量稳定门禁 536 项通过，analyze 无问题。 | 自动和后台 Reflection 的模型失败事实可审计且不泄露错误详情；Dreaming / 本地反思继续成功 |
| 2026-07-14 | 模型增强 Reflection 总墙钟超时与上游取消 | 代码审计确认旧 `Stream.timeout(60s)` 会在每个流事件后重新计时，持续慢碎片响应可能让后台 Reflection 超过 60 秒甚至长期占用任务。新增 `model reflection enforces one total timeout for slow chunks`，以每 10ms 出块的流先红灯于缺少总时限收集器；修复后 80ms 总时限仍会触发 `TimeoutException` 和取消回调。`ChannelModelRelayBridge.forward()` 新增可选 `CancelToken` 并传入正式协议，provider 在 60 秒总时限、响应过长或其他异常时取消上游并继续既有本地回退。模型服务 / Relay bridge / 正式协议 / provider 聚焦 23 项、全量稳定门禁 534 项通过，analyze 无问题。 | 模型慢流不会无限拖住移动端前台或 WorkManager / BGTask Reflection；真实外部模型时延仍待质量门禁统计 |
| 2026-07-14 | 模型增强 Reflection 不覆盖本地安全基线 | 新增回归先红灯证明模型返回 8 条结论 / 行动时会占满结果并挤掉本地规则，且只重复本地内容仍会误标 `generationMode=model`。修复后合并顺序改为本地结论优先，模型最多补充 4 条且总量仍限制为 8；没有新增安全内容时触发既有本地回退，不保存伪增强报告。目标 6 项、模型 / provider / 正式协议 / 设置页聚焦 40 项、最终全量稳定门禁 533 项通过，`flutter --no-version-check analyze --no-pub` 无问题。 | 本地规则安全基线不会被异常模型输出覆盖；真实外部模型长会话质量仍待补证 |
| 2026-07-14 | Pixel 8 强制 deep idle Dreaming / Reflection 与 force smoke 稳定化 | 新增 `scripts/smoke_device_android_background_dreaming_doze.sh`，隔离包回到 Home 后执行 `cmd deviceidle force-idle`，要求调度时和结果时均为 `IDLE` / `IDLE_MAINTENANCE`、拒绝永久 idle whitelist，并在任意退出路径先 `cmd deviceidle unforce` 再恢复正式包。Pixel 8 输出 `idleStateAtSchedule=IDLE idleStateAtResult=IDLE`，37 秒完成 `status=completed digest=2026-07-14 reflection=2026-07-14`；cleanup 后 deep state `ACTIVE`、正式包 pid `27177`、firstInstallTime / dataDir 不变、无隔离包 / sqlite hook。同步定位上一轮 force 波动根因：旧脚本从全局 logcat 收集其他 App 的 WorkManager Job ID；新增红灯门禁后改为只从 `dumpsys jobscheduler` 精确匹配隔离包 `SystemJobService`，默认 force 分支复跑以 job id `0` 在 10 秒完成。新增静态门禁 2 项，最终全量稳定门禁 521 项通过，analyze 无问题。取证：`/tmp/simichat-android-background-dreaming-20260714112626.log`、`/tmp/simichat-android-background-dreaming-20260714112723.log`。 | Android 强制 deep idle 短时 smoke 与自然 / force 调度均通过；长期 Doze、OEM、跨小时跨天仍待补 |
| 2026-07-14 | 移动端 Dreaming / Reflection pending 连续失败退避复查 | 审计 `runDreamingBackgroundTask()` 时发现：已有 `assistant_reflection_pending_v1` 的后台任务再次恢复失败、且当天 Dreaming 已完成时，旧逻辑会返回 `notDue`，Android WorkManager 因而误判成功并停止退避重试。新增 `Android background retry stays pending when Reflection still fails`，先红灯得到 `Expected reflectionPending / Actual notDue`，再以最小状态标记修复；目标 4 项与全量稳定门禁 519 项通过。Pixel 8 当前默认 force 调度复跑未收到结果 marker，但不依赖 shell 强制命令的自然调度分支在 Home 后 36 秒由 SystemJobScheduler 完成 `status=completed digest=2026-07-14 reflection=2026-07-14`，正式包 `firstInstallTime` / `dataDir` 不变、pid `22864`，隔离包与临时 sqlite hook 已清理。iPhone13 release 隔离 smoke 解锁预检和 27.5MB 构建通过，但 BGTaskScheduler 仍显示 `There are no scheduled tasks`；cleanup 后正式 `top.simitalk.aichat` 存在并运行 pid `86399`。 | Android 真实自然后台链路通过，pending 连续失败会继续 retry；iOS 前台兜底可用，但系统后台仍待开启“后台 App 刷新” |
| 2026-07-14 | Pixel 8 Android WorkManager 自然调度 Dreaming / Reflection | 新增自然调度 wrapper 和可配置 smoke initialDelay，harness 补齐生产任务的非低电量 / 非低存储约束。`scripts/smoke_device_android_background_dreaming_natural.sh 37101FDJH0077P` 安装隔离包后回到 Home，不调用 `cmd jobscheduler run`；30 秒 initialDelay 后 36 秒由 SystemJobScheduler 自行输出 `status=completed digest=2026-07-14 reflection=2026-07-14`。隔离 prefs 含 Dreaming、Reflection 最近报告和历史且无 pending；随后默认 force 分支复跑通过。两次 cleanup 后正式包 `firstInstallTime=2026-07-14 00:29:02` / `dataDir=/data/user/0/top.simitalk.aichat` 不变、最终 pid `24389`，无隔离包 / sqlite hook 残留；聚焦门禁 37 项、最终全量稳定门禁 518 项通过。取证：`/tmp/simichat_android_natural_background_final.log`、`/tmp/simichat-android-background-dreaming-20260714042907.log`。 | 自然与强制系统调度均通过 / Doze、OEM、跨小时跨天仍待补 |
| 2026-07-14 | iOS BGTaskScheduler `BGProcessingTask` 代码基线、隔离 release smoke 与后台可用性诊断 | `AppDelegate` 启动完成前注册正式 task identifier，Info.plist 声明 permitted identifier / `processing`，Dart 一次性调度支持次日重排、15 分钟失败重试和 `ios_background` trigger；隔离 smoke 使用独立 bundle / task 子命名空间，并把 `Workmanager().printScheduledTasks()` 写入 READY JSON，避免 `workmanager 0.8.0` 吞掉 submit 错误后形成假成功。iPhone13 LLDB 只读复查确认 `UIApplication.backgroundRefreshStatus=1`（denied），系统未保留 pending task；新增原生 `simichat/background_refresh_status` 通道、Dart 状态映射、调度前拒绝静默成功和设置页“可用 / 已关闭 / 受限”提示。相关后台聚焦门禁 39 项通过，新增状态 / 设置页回归 23 项通过，最终全量稳定门禁 508 项通过，analyze 无问题；正式 iOS release `--no-codesign` 构建通过，Runner.app 33.3MB、arm64，产物含正式 task identifier、`processing` 和原生状态通道；正式包仍存在、隔离包和 sqlite hook 无残留。 | 代码 / 原生编译 / 失败诊断已完成；真机系统执行待开启“后台 App 刷新” |
| 2026-07-14 | Pixel 8 Android WorkManager 系统后台 Dreaming / Reflection 独立包真机 smoke | 新增 `workmanager 0.8.0`、纯 Dart 下次运行时间计算、一次性唯一任务、后台 `ProviderContainer`、正式私有 SQLite、Dreaming / 画像候选 / Reflection / 通知链、成功后次日重排和 Reflection pending retry；自动路径使用 SQLite `dreaming-auto-YYYY-MM-DD` 原子 claim，防止前台与后台 isolate 重复 job / 报告 / Reflection / 通知。Android arm64 debug APK 构建通过，合并 manifest 可见 `WorkManagerInitializer`、`SystemJobService` 和 `RescheduleReceiver`。`scripts/smoke_device_android_background_dreaming.sh 37101FDJH0077P` 只安装隔离包 `top.simitalk.aichat.backgroundsmoke`，Home 后先尝试 Android 16 namespace `androidx.work.systemjobscheduler` 命令，因最终 `workmanager 0.8.0` 使用 legacy job 自动回退到无 namespace 命令并成功强制运行系统 job，输出 `status=completed digest=2026-07-14 reflection=2026-07-14`；隔离 prefs 含 Dreaming / Reflection 最近报告与历史。cleanup 后正式包 `firstInstallTime=2026-07-14 00:29:02`、`dataDir=/data/user/0/top.simitalk.aichat` 不变、pid `12024`，无隔离包和 sqlite hook 残留。最终全量稳定门禁 499 项通过，analyze 无问题，日志无 `WARNING (drift)` / `multiple databases`；取证文件为 `/tmp/simichat-android-background-dreaming-20260714013910.log` 和 `/tmp/simichat-android-background-dreaming-prefs-20260714013910.xml`。详见 `docs/archive/mobile-android-background-dreaming-smoke-2026-07-14.md`。 | Android 系统后台真实执行已通过 / iOS 与自然调度长时间观察待补 |
| 2026-07-14 | Pixel 8 Dreaming / Reflection 失败恢复独立包真机 smoke | 新增可覆盖 Gradle applicationId、`dreaming_reflection_smoke_harness.dart`、静态 manifest 门禁和 `scripts/smoke_device_dreaming_reflection_recovery.sh`。最终安全路径只 build / adb 安装 `top.simitalk.aichat.dreamingsmoke`，内存 SQLite + 隔离 prefs；真机输出 pending `dayKey=2026-07-14 attempts=1`，Home / resumed 后 recovered `attempts=2 history=1`；cleanup 卸载隔离包、普通 release pid 可见，修正后 smoke 前后正式包 `firstInstallTime=2026-07-14 00:29:02` / `dataDir=/data/user/0/top.simitalk.aichat` 不变，稳定门禁 124 项和 analyze 通过。首次 `flutter test -d` 动态 applicationId 方案错误卸载正式包，`firstInstallTime` 从 `2026-07-07 12:51:06` 变为 `2026-07-14 00:29:02`，Pixel 8 应用私有数据丢失；LocalTransport / D2D restore 均 `-1000`，未能自动恢复，事故与防复发边界已写入独立文档。 | 最终隔离 smoke 通过 / 首次 runner 数据事故已记录且路径已禁用 |
| 2026-07-13 | 移动端 Dreaming / Reflection 直接稳定性与独立失败恢复 | 补强 `test/mobile_main_flow_smoke_test.dart`：首次启动到期、恢复前台到期、持续前台定时三条移动端路径都会解码并校验最近 Dreaming、最近 Reflection 与 Reflection 历史，要求反思有内容、历史非空且来源 Dreaming 日期一致；新增 `assistant_reflection_pending_v1`，Reflection 开始前写 pending、报告和历史成功后清除，启动 / 恢复前台 / 前台定时自动重试，旧来源先从 Dreaming 历史、再从 SQLite 按 dayKey 恢复；设置页展示来源和次数并允许清除，手动失败有明确反馈，删除来源报告同步清理，结构化备份包含 pending。移动端 `--name dreaming` 9 项通过，Reflection/Dreaming 聚焦 55 项通过，含导出 / 导入的稳定门禁 120 项通过；`flutter --no-version-check analyze --no-pub` 无问题；1000 条消息 Dreaming 基准 `run_ms=78` / `digest_elapsed_ms=74` / `memory_candidates=40`。当前仍明确是“前台到期 · 非系统后台”；系统后台调度和模型驱动反思未完成。 | 已完成移动端前台链路与 Reflection 失败恢复 / 最终智能助理目标继续推进 |
| 2026-07-08 | MCP PC Node 容器侧车静态门禁 | 验证 PC Node Runtime 容器文件不依赖宿主机 Node/npm/npx：Dockerfile 使用 `node:22-alpine`，runtime server 暴露 MCP SSE / message / tools 调用入口，脚本 `bash -n` 通过并只调用 Docker/Podman，市场项和 `docs/runtime-manifest.example.json` 均指向 `simichat-node-container` 本地 SSE。命令：`flutter --no-version-check test --no-pub --no-test-assets test/mcp_runtime_container_manifest_test.dart -r expanded`，4 项通过。 | 已完成静态和脚本门禁 / 实际 Docker build 与 App 内启动管理待补 |
| 2026-07-08 | MCP App 内建 Runtime 自依赖基线 | 验证新增 `app_native` 传输不需要 stdio command，即可完成 MCP 初始化、工具发现、`simichat.runtime_info` / `simichat.now` 调用和 `McpManager` 连接；市场首项固定为移动端可运行的 `SimiChat 内建工具`，命令为空、参数为空、说明包含“不依赖 Node”。命令：`flutter --no-version-check test --no-pub --no-test-assets test/mcp_app_native_transport_test.dart -r expanded`，4 项通过；`flutter --no-version-check analyze --no-pub` 无问题；全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 461 项通过。 | 已完成代码级验证 / 真机安装后连接 smoke 待后续补 |
| 2026-07-07 | iOS release send / retry / model switch / stop 全链路复跑：`smoke_ios_release_send.sh` | 在 iPhone13 `00008110-0016349A3A20A01E` / CoreDevice `CAFC7AFA-4565-5C8D-B724-090061D144D0` 上复跑修复后的 release send harness。验证：`scripts/smoke_ios_release_send.sh 00008110-0016349A3A20A01E` 通过，runId `ios-release-send-20260707130509`，smoke pid `80205`；发送主链路返回 `IOS release smoke reply 20260706`，请求为 `/v1/chat/completions` / `model=ios-release-smoke-model` / `lastUser=ios release send smoke`；重试链路 `retry.requestCountForInitialPrompt=2`；模型切换链路 `modelSwitch.requestModel=ios-release-smoke-model-b` 且 `timelineRecordCount=1`；停止慢流链路保留 `IOS slow chunk 1 IOS slow chunk 2` 且 `stop.requestCompleted=False`，证明取消订阅和 SSE `CancelToken` 传播已阻止上游慢流正常完成。脚本随后恢复普通 release，安装 `databaseSequenceNumber=4408`，launch pid `80206`。 | 已完成 iPhone13 release 主链路自动化补证 / 手工 UI 仍待补 |
| 2026-07-07 | 深度链接 `ai-chat://` v1 | 新增 `lib/core/deep_link/deep_link_service.dart`，解析并限制 first-party `ai-chat` 路由；Android `AndroidManifest.xml` 注册 `VIEW` / `BROWSABLE` / `ai-chat`，`MainActivity` 暴露 `simichat/deep_link`、`getInitialLink` 和 `onNewIntent`；iOS `Info.plist` 注册 URL scheme，`AppDelegate` / `SceneDelegate` 处理冷启动和运行中 URL；`ResponsiveShell` 非阻塞处理初始链接，避免影响 Dreaming / 后台恢复启动主链路；运行中设置页 / 市场页跳转改用 root Navigator 并在平台回调后让出 microtask，修复 Android `onNewIntent` 已送达但页面未入栈的问题。验证：新增 deep link parser / manifest 测试 4 项通过，`test/mobile_main_flow_smoke_test.dart` 19 项通过，全量 `flutter --no-version-check test --no-pub --no-test-assets` 388 项通过，`flutter --no-version-check analyze` 无问题，`git diff --check` 无输出；临时 `sqlite3.source=system` hook 下 Android debug APK 与 iOS Debug 无签名构建通过；正式 `pubspec.yaml` / `pubspec.lock` 未残留 hook。 | 已完成代码级与原生编译验证 / Android 与 iOS URL smoke 已补 |
| 2026-07-07 | iOS release deep link 外部 URL 真机 smoke：`release_deep_link_smoke_harness.dart`、`smoke_ios_release_deep_link.sh` | 新增 release-only deep link smoke harness：`AiChatApp` 支持注入 `NavigatorObserver`，harness 使用内存 SQLite seed 默认会话和目标会话，通过 observer 记录 `/settings` 入栈，并监听 `activeSessionIdProvider` 确认运行中 URL 切到 `ios-release-deep-link-target-session`。脚本复用 iOS release 安全模板，安装 smoke 包前先 `assert_device_unlocked_for_launch`，通过 `devicectl device process launch --payload-url ai-chat://settings` 验证冷启动 URL，再通过 `--payload-url ai-chat://session/ios-release-deep-link-target-session` 验证运行中 URL，失败会自动恢复普通 release。验证：`scripts/smoke_ios_release_deep_link.sh 00008110-0016349A3A20A01E` 在 iPhone13 / CoreDevice `CAFC7AFA-4565-5C8D-B724-090061D144D0` 通过，runId `ios-release-deep-link-20260707125808`，smoke pid `80197`，结果 `status=passed` / `activeSessionId=ios-release-deep-link-target-session` / `targetTitle=iOS Release Deep Link Target` / `elapsedMs=1266`；脚本随后恢复普通 release，安装 `databaseSequenceNumber=4392`，launch pid `80202`。 | 已完成 iPhone13 release URL 补证 |
| 2026-07-07 | Android deep link 外部 URL 真机 smoke：`mobile_deep_link_smoke_test.dart`、`smoke_android_deep_link.sh` | 新增 Android integration smoke，测试使用内存 SQLite、mock SharedPreferences 和真实 `MethodChannelSimiDeepLinkService`，脚本在收到 `SIMICHAT_DEEP_LINK_READY` 后通过 `adb shell am start -W -f 0x24000000 -a android.intent.action.VIEW -d 'ai-chat://settings' -n top.simitalk.aichat/.MainActivity` 走外部 URL intent，确认设置页打开；随后在 `SIMICHAT_DEEP_LINK_SETTINGS_OK` 后打开 `ai-chat://session/deep-link-target-session`，确认返回聊天页并切到 `Deep Link Target Smoke` 会话。首轮红灯确认 package 位置参数导致 intent resolve 失败，改为显式 component；二轮红灯确认原生 / Dart 已收到链接但普通 Navigator 未入栈，修复为 root Navigator + microtask 后通过。验证：`scripts/smoke_android_deep_link.sh 37101FDJH0077P` 通过；deep link / manifest / smoke 脚本回归 17 项通过，`test/mobile_main_flow_smoke_test.dart` 19 项通过，`flutter --no-version-check analyze` 无问题，全量 `flutter --no-version-check test --no-pub --no-test-assets` 388 项通过，`git diff --check` 无输出，正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook；随后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 Android release，31.5MB APK 覆盖安装并启动 pid `16654`，`lastUpdateTime=2026-07-07 12:51:06`。 | 已完成 Pixel 8 / iPhone13 iOS release |
| 2026-07-07 | Android airplane mode 流式取消真机 smoke 复跑：`smoke_android_network_stream_cancel.sh` | 复用已新增的 Android 网络流式取消 smoke，设置 `NETWORK_TOGGLE_MODE=airplane`。验证：`REAL_NETWORK_TOGGLE=1 NETWORK_TOGGLE_MODE=airplane scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P` 通过，测试输出 `SIMICHAT_NETWORK_STREAM_CANCEL_READY` 后脚本启用 airplane mode，应用进入 `networkStreamingInterruptedMessage` 后输出 `SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED`，脚本恢复网络，最终 `mobile network loss cancels in-flight stream on device` 1 项通过。随后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release，31.5MB APK 覆盖安装并启动 pid `8774`，`lastUpdateTime=2026-07-07 11:19:07`；复核 Pixel 8 飞行模式 disabled、Wi-Fi enabled、Active default network 为 `WIFI CONNECTED / IS_VALIDATED`；`scripts/smoke_full_stability_gate.sh -r expanded test/release_send_smoke_manifest_test.dart --name "Android network stream cancel"` 1 项通过；正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook。 | 已完成 Pixel 8 airplane mode streaming 取消 / iOS 网络切换待补 |
| 2026-07-07 | Android 物理断网流式取消真机 smoke：`mobile_network_stream_cancel_smoke_test.dart`、`smoke_android_network_stream_cancel.sh` | 新增 Android 真机物理断网 streaming cancel smoke，脚本默认 `REAL_NETWORK_TOGGLE=0` 安全拒绝，显式授权后先在线启动设备内 OpenAI Chat 慢 SSE mock，测试打印 `SIMICHAT_NETWORK_STREAM_CANCEL_READY` 后脚本断开 Wi-Fi / data，应用进入 `networkStreamingInterruptedMessage` 错误态后打印 `SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED`，脚本恢复网络，测试确认 `网络已恢复，可点“重试”继续`，SQLite 只有 1 条 user 消息且无 assistant 半截回复。首轮红灯来自过强 loopback socket 断开断言，应用状态已正确但 mock 8 秒内未观察到 socket 关闭；取消传播已有独立 SSE / 后台慢流 smoke 覆盖，本 smoke 改为聚焦物理网络事件触发 UI / 状态 / 数据库结果。验证：`bash -n scripts/smoke_android_network_stream_cancel.sh` 通过；manifest 目标测试通过；`flutter --no-version-check analyze` 无问题；`REAL_NETWORK_TOGGLE=1 scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P` 通过；随后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release，31.5MB APK 覆盖安装并启动 pid `7197`；复核 Pixel 8 飞行模式 disabled、Wi-Fi enabled、Active default network 为 `WIFI CONNECTED / IS_VALIDATED`；`./scripts/smoke_full_stability_gate.sh -r expanded` 全量 380 项通过；`git diff --check` 无输出。 | 已完成 Pixel 8 Wi-Fi / data 与 airplane 物理断网 streaming 取消 / iOS 网络切换待补 |
| 2026-07-07 | 前台网络断开取消流式请求：`ResponsiveShell`、`networkStreamingInterruptedMessage` | iOS release send 修复复跑仍被 iPhone13 安装前 unlock preflight timeout 安全拒绝，未覆盖安装 smoke 包；转向本地可验证的网络切换稳定性缺口：`ResponsiveShell` 监听 `isOnlineProvider` 从在线变离线，复用已加载 streaming 会话枚举，取消当前 active 会话和会话列表中所有 `isStreaming=true` 的流式请求，设置 `networkStreamingInterruptedMessage=网络连接断开，已停止本次生成，联网后可重试。`，并在联网恢复后只提示用户显式 `重试 / 重试全部`，不自动重发；`cancelStreaming(..., error)` 的中断错误保留 map 从后台专用扩展为通用，避免断网取消后异步 `_runAssistantResponse()` 醒来落库半截 assistant。新增 `mobile network loss cancels active streaming response` 与 `mobile network loss cancels all streaming sessions`，先红灯于断言过窄（同屏有错误条和 SnackBar action 两个 `重试`），修正后 `flutter --no-version-check test --no-pub -r expanded test/mobile_main_flow_smoke_test.dart --name "mobile network loss"` 2 项通过；配套 `test/connectivity_provider_test.dart`、`test/chat_page_offline_test.dart`、`test/release_send_smoke_manifest_test.dart` 16 项通过；`flutter --no-version-check analyze` 无问题；`./scripts/smoke_full_stability_gate.sh -r expanded` 全量 379 项通过；`git diff --check` 无输出，正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 sqlite hook。 | 已完成代码级 / 真机物理断网中 streaming 取消待补 |
| 2026-07-06 | Dreaming 销毁中途通知闸门：`_runDueDreamingIfNeeded()`、`mobile disposed shell skips dreaming notification after proposal wait` | 代码索引复查发现前台自动 Dreaming 只在 digest 返回后检查一次 `mounted`：如果页面在画像提案 / 反思等待期间被销毁，旧逻辑仍可能继续触发 Dreaming 完成通知。新增可控测试通知 hook `dreamingDigestCompleteNotifier` 与 `_GateUserProfileChangeProposalsNotifier`，先红灯复现页面销毁后 `notificationCount=1`；随后在画像提案完成后、反思完成后分别补 `if (!mounted) return`，确保销毁后的后续通知不再执行。验证：红灯目标用例失败于 `Expected: <0> Actual: <1>`；修复后目标用例 1 项通过，`test/mobile_main_flow_smoke_test.dart` 9 项通过；`flutter --no-version-check analyze` 无问题；`scripts/smoke_full_stability_gate.sh -r expanded` 全量 353 项通过（`/tmp/simichat_full_gate_current_182005.log`），未匹配 `WARNING (drift)` / `multiple databases`；`git diff --check` 无输出；正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 sqlite hook。 | 已完成 |
| 2026-07-06 | Widget 测试数据库生命周期收口：`test/widget_test.dart`、`test/widget_test_database_lifecycle_test.dart` | 理论门禁复查发现基础 widget smoke 直接使用默认 `ProviderScope(child: AiChatApp())` 会打开默认 `AppDatabase()`，在同一测试进程中可能触发 Drift 多数据库生命周期 warning；新增静态回归先红灯约束基础 widget smoke 必须使用 `AppDatabase.forTesting(NativeDatabase.memory())`、`databaseProvider.overrideWithValue(db)` 和 `addTearDown(db.close)`，修复后两个基础 widget 用例均注入可释放内存库，不再打开默认应用数据库。验证：`scripts/smoke_full_stability_gate.sh -r expanded test/widget_test_database_lifecycle_test.dart test/widget_test.dart` 3 项通过且局部输出无 Drift warning；`flutter --no-version-check analyze` 无问题；`scripts/smoke_full_stability_gate.sh -r expanded` 全量 352 项通过；复查 `/tmp/simichat_full_gate_1752.log` 未匹配 `WARNING (drift)` / `multiple databases`；`git diff --check` 无输出；正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 sqlite hook。 | 已完成 |
| 2026-07-06 | Dreaming 非前台取消定时器回归：`mobile inactive lifecycle cancels foreground dreaming timer` | 在前台周期 Dreaming 补强后，继续补对称稳定性验证：进入 `inactive` / 非 `resumed` 状态时必须取消 `_dreamingForegroundTimer`，避免应用非前台时继续跑 digest、画像提案、反思或通知等重任务；新增移动端 smoke：测试内将 timer 间隔缩短为 30ms，启动时 schedule disabled，随后触发 `AppLifecycleState.inactive` 取消 timer，再启用到期 schedule 并等待多个短周期，验证 `dreaming_digest_v1` 仍为空、待确认画像提案为空；最后关闭 schedule、dispose app 并恢复 lifecycle 到 `resumed`，防止测试污染；验证：`flutter --no-version-check test --no-pub --no-test-assets -r expanded test/mobile_main_flow_smoke_test.dart` 7 项通过，移动主流程 + Dreaming/Reflection 目标测试 26 项通过，`flutter --no-version-check analyze` 无问题，临时 sqlite hook 下全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 341 项通过，正式 `pubspec.yaml` / `pubspec.lock` 不保留 hook，`git diff --check` 无输出 |
| 2026-07-06 | Dreaming 前台持续运行定时检查：`dreamingForegroundCheckInterval`、`mobile foreground timer runs due dreaming smoke` | 代码索引确认自动 Dreaming 在补恢复前台后仍缺少“应用一直保持前台并跨过整理时间”的覆盖；本轮在 `ResponsiveShell` 内增加前台周期 `Timer`，默认每 1 分钟轻量调用 `_runDueDreamingIfNeeded()`，进入非 resumed 生命周期时取消，恢复前台时重建；新增测试用 `dreamingForegroundCheckInterval` 与 `resetDreamingForegroundCheckIntervalForTesting()`，避免长等待和测试污染；新增移动端 smoke：初始 schedule disabled，app 保持前台等待短 timer 不生成 digest，启用到期 schedule 后不走生命周期，仅靠前台 timer 生成 `dreaming_digest_v1` 和 1 条待确认画像提案；验证：`flutter --no-version-check test --no-pub --no-test-assets -r expanded test/mobile_main_flow_smoke_test.dart` 6 项通过，移动主流程 + Dreaming/Reflection 目标测试 25 项通过，`flutter --no-version-check analyze` 无问题，临时 sqlite hook 下全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 340 项通过，正式 `pubspec.yaml` / `pubspec.lock` 不保留 hook，`git diff --check` 无输出 |
| 2026-07-06 | Dreaming 前台恢复触发补强：`ResponsiveShell` 生命周期、`mobile resumed lifecycle runs due dreaming smoke` | 代码索引确认自动 Dreaming 此前只在 `ResponsiveShell.initState` 首帧调用 `_runDueDreamingIfNeeded()`，未覆盖用户一直开着 app、锁屏后恢复前台或跨过整理时间再回到应用的真实移动端场景；本轮让 `_ResponsiveShellState` 混入 `WidgetsBindingObserver`，在 `AppLifecycleState.resumed` 时再次调用 `_runDueDreamingIfNeeded()`，并在 `dispose` 移除 observer；已有 in-flight / day-key 闸门负责防重复。新增移动端 widget smoke：初始 schedule disabled 保证启动时不跑，测试内启用到期 schedule 后模拟 `inactive -> resumed`，验证恢复前台后写入 `dreaming_digest_v1` 并生成 1 条待确认用户画像提案；验证：`flutter --no-version-check test --no-pub --no-test-assets -r expanded test/mobile_main_flow_smoke_test.dart` 5 项通过，移动主流程 + Dreaming/Reflection 目标测试 24 项通过，`flutter --no-version-check analyze` 无问题，临时 sqlite hook 下全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 339 项通过，正式 `pubspec.yaml` / `pubspec.lock` 不保留 hook，`git diff --check` 无输出 |
| 2026-07-06 | Dreaming 自动运行测试隔离收口：`resetDreamingAutoRunStateForTesting()` | 复查新增进程内自动 Dreaming 闸门后发现测试隔离隐患：模拟 `markAutoRun()` 失败时 `_locallyCompletedDueDreamingDayKeys` 会留在 Dart 进程内，未来若测试复用同一天可能被误判为已完成；本轮新增 `@visibleForTesting resetDreamingAutoRunStateForTesting()` 清空 in-flight future 和本地完成 day-key，并在 `test/dreaming_provider_test.dart` 的 `setUp` / `tearDown` 中调用，避免全局闸门状态跨用例污染；验证：`flutter --no-version-check test --no-pub --no-test-assets -r expanded test/dreaming_provider_test.dart` 3 项通过，Dreaming/Reflection 目标测试 19 项通过，`flutter --no-version-check analyze` 无问题，临时 sqlite hook 下全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 339 项通过，正式 `pubspec.yaml` / `pubspec.lock` 不保留 hook，`git diff --check` 无输出 |
| 2026-07-06 | Dreaming 自动运行标记失败降级：`maybeRunDueDreaming()`、`DreamingScheduleNotifier.markAutoRun()` 边界 | 理论风险：digest 已生成并保存后，`markAutoRun()` 如果因为 SharedPreferences / 平台持久化异常抛错，旧逻辑会让 `maybeRunDueDreaming()` 整体抛出，上层 `_runDueDreamingIfNeeded()` catch 后不再执行画像提案、反思和通知；本轮将自动运行标记写入失败降级为非致命，digest 已完成时仍返回给上层继续后续链路，并在进程内记录当天已完成 key，避免同进程重复触发再次跑；新增 `_FailingMarkAutoRunScheduleNotifier` 回归测试，模拟 `markAutoRun()` 抛错时首个调用无异常且返回 1 条消息的 digest，第二次同日触发返回 `null`，同时确认 digest 已保存而 schedule marker 未持久化；验证：`flutter --no-version-check test --no-pub --no-test-assets -r expanded test/dreaming_provider_test.dart` 3 项通过，Dreaming/Reflection 目标测试 19 项通过，`flutter --no-version-check analyze` 无问题，临时 sqlite hook 下全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 339 项通过，正式 `pubspec.yaml` / `pubspec.lock` 不保留 hook，`git diff --check` 无输出 |
| 2026-07-06 | 移动端网络稳定性 v1：离线发送保护、联网恢复提示与会话隔离 | 新增 `test/chat_page_offline_test.dart`，用内存 SQLite + 可用模型 + `isOnlineProvider=false` 复现离线发送；修复 `lib/features/chat/chat_page.dart`，在非流式、非空输入时若离线则提示 `当前网络不可用，已保留输入，联网后可重试`、保留草稿并避免写入 user message；继续用 `connectivityProvider` 模拟 `none -> wifi`，当被离线阻断的草稿仍存在时提示 `网络已恢复，可发送保留的输入`；随后补会话隔离：`_blockedSendWhileOfflineSessionId` 绑定触发阻断的会话，A 会话离线阻断后切到 B 会话输入 B 草稿，联网恢复时不会误弹 A 的恢复提示，切回原会话且在线时才可提示。验证：先确认新增会话隔离测试红灯会误弹恢复提示，修复后 `scripts/smoke_full_stability_gate.sh -r expanded test/chat_page_offline_test.dart` 3 项通过；`dart format` 已运行；`flutter --no-version-check analyze` 无问题；受影响 `test/chat_page_offline_test.dart`、`test/chat_page_tts_playback_event_test.dart`、`test/mobile_main_flow_smoke_test.dart` 共 12 项通过；命令内临时 `sqlite3.source=system` 后 `scripts/smoke_full_stability_gate.sh -r expanded` 全量 351 项通过，正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook。 | 已完成 / 自动重试队列待补 |
| 2026-07-06 | 网络状态 Provider 启动探测与切换归一化 | 继续补移动端网络切换的代码级稳定性：新增可注入 `ConnectivityMonitor`，`connectivityProvider` 订阅变化流前先执行一次 `checkConnectivity()` 并发出初始状态，避免离线启动时等待变化事件期间误判在线；初始探测抛错时不让 Provider 永久停在错误态，而是保持保守默认并继续监听后续变化流；新增 `isOnlineConnectivityResults()`，空列表和仅 `none` 按离线处理，存在任意非 `none` 传输按在线处理，降低切换瞬间混合状态误判风险；回归 `test/connectivity_provider_test.dart` 先红灯确认缺少抽象 / 归一化函数，随后补红灯确认初始探测失败时旧逻辑仍停在在线/错误态，修复后覆盖空结果、`none`、Wi-Fi、`none + mobile`、fake monitor 初始离线后 Wi-Fi 恢复，以及初始探测失败后仍接收 `none` 事件。验证：`flutter --no-version-check test --no-pub -r expanded test/connectivity_provider_test.dart test/chat_page_offline_test.dart` 6 项通过；`flutter --no-version-check analyze` 无问题；受影响 `test/connectivity_provider_test.dart`、`test/chat_page_offline_test.dart`、`test/chat_page_tts_playback_event_test.dart`、`test/mobile_main_flow_smoke_test.dart` 共 16 项通过；`git diff --check` 无输出。 | 已完成代码级 / 真机网络切换待补 |
| 2026-07-06 | Android 真机网络断开 / 恢复 smoke：`scripts/smoke_android_network_restore.sh`、`integration_test/mobile_network_restore_smoke_test.dart` | 新增 Android 专用网络恢复 smoke，默认 `REAL_NETWORK_TOGGLE=0` 安全拒绝真实断网，显式 `REAL_NETWORK_TOGGLE=1` 时才通过 adb 断开 Wi-Fi / data；integration_test 使用真实 `connectivity_plus` 状态，等待 `网络已断开`，发送草稿后断言离线提示、草稿保留、SQLite 不写入 user message，打印 `SIMICHAT_NETWORK_RESTORE_READY` 后脚本恢复网络并断言 `网络已恢复，可发送保留的输入`。首次真机运行发现固定延迟恢复竞态，脚本改为监听 READY 标记；随后真机又暴露全局 floating SnackBar 在 390×844 + 软键盘场景下 `Floating SnackBar presented off screen`，网络离线 / 恢复提示改为显式 `SnackBarBehavior.fixed` 并补本地回归锁定。验证：脚本默认拒绝断网退出码 2；`bash -n scripts/smoke_android_network_restore.sh` 通过；`test/release_send_smoke_manifest_test.dart --name "Android network restore smoke has explicit safety gates"` 通过；`test/chat_page_offline_test.dart` 4 项通过；最终影响面 `test/release_send_smoke_manifest_test.dart`、`test/connectivity_provider_test.dart`、`test/chat_page_offline_test.dart`、`test/chat_page_tts_playback_event_test.dart`、`test/mobile_main_flow_smoke_test.dart` 共 21 项通过；`flutter --no-version-check analyze` 无问题；`git diff --check` 无输出；`REAL_NETWORK_TOGGLE=1 scripts/smoke_android_network_restore.sh 37101FDJH0077P` 最终通过；继续补 `NETWORK_TOGGLE_MODE=airplane` 模式并通过 `REAL_NETWORK_TOGGLE=1 NETWORK_TOGGLE_MODE=airplane scripts/smoke_android_network_restore.sh 37101FDJH0077P`，脚本启用 airplane mode，收到 READY 标记后恢复网络，补充 `adb shell cmd connectivity airplane-mode` 返回 `disabled`；两次 debug integration 后均恢复普通 release，最终 31.5MB APK 覆盖安装并启动 pid `32254`；本轮未触碰 people。 | 已完成 Pixel 8 / iOS 网络切换待补 |
| 2026-07-07 | Android 后台恢复真机 smoke：`scripts/smoke_android_background_restore.sh`、`integration_test/mobile_background_restore_smoke_test.dart` | 新增 Android 专用后台恢复 smoke，默认 `REAL_BACKGROUND_TOGGLE=0` 安全拒绝真实按 Home，显式 `REAL_BACKGROUND_TOGGLE=1` 后才通过 adb 发送 `KEYCODE_HOME` 并用 `monkey -p top.simitalk.aichat -c android.intent.category.LAUNCHER 1` 拉回前台；integration_test 输入 `mobile background restore draft 20260706` 后打印 `SIMICHAT_BACKGROUND_RESTORE_READY`，脚本收到标记后后台 / 恢复，测试确认 lifecycle 曾进入非 resumed、随后回到 `AppLifecycleState.resumed`、草稿仍显示、消息表为空且无异常。验证：默认脚本退出码 2 并提示 `Refusing to background the device`；`bash -n scripts/smoke_android_background_restore.sh` 通过；`test/release_send_smoke_manifest_test.dart --name "Android background restore smoke has explicit safety gates"` 通过；`REAL_BACKGROUND_TOGGLE=1 scripts/smoke_android_background_restore.sh 37101FDJH0077P` 通过；影响面 `test/release_send_smoke_manifest_test.dart`、`test/connectivity_provider_test.dart`、`test/chat_page_offline_test.dart`、`test/chat_page_tts_playback_event_test.dart`、`test/mobile_main_flow_smoke_test.dart` 共 22 项通过；`flutter --no-version-check analyze` 无问题；`git diff --check` 无输出；随后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release，31.5MB APK 覆盖安装并启动 pid `827`；本轮未触碰 people。 | 已完成 Pixel 8 / iOS 后台恢复待补 |
| 2026-07-07 | iOS release 后台恢复 smoke 入口：`scripts/smoke_ios_release_background_restore.sh`、`release_background_smoke_harness.dart` | 新增 release-only 后台恢复 harness 和脚本，使用 `SIMICHAT_RELEASE_BACKGROUND_SMOKE=true` 写入 Documents 结果文件，脚本等待 `SIMICHAT_RELEASE_BACKGROUND_READY` 后通过 `devicectl device process suspend` / `resume` 验证恢复，并默认失败 / 成功后恢复普通 release。实跑 `scripts/smoke_ios_release_background_restore.sh BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D` 时，people 设备在 launch 阶段返回 `FBSOpenApplicationServiceErrorDomain RequestDenied Locked`，未进入 suspend/resume 验证；脚本清理路径随后执行普通 `flutter --no-version-check build ios --release` 和覆盖安装。恢复后取证：`Runner.app` 约 32MB，`devicectl device info apps` 仍显示 `top.simitalk.aichat` / `SimiAIChat` / `1.0.0` / `bundleVersion=1`，当前未见 `Runner.app/Runner` 进程；因此该项记录为入口已完成、真机通过待设备解锁后复跑。 | 入口已完成 / people 锁屏阻塞 / 待复跑 |
| 2026-07-07 | iOS release 后台 smoke 锁屏预检加固：`assert_device_unlocked_for_launch` | 针对 people 锁屏时脚本先覆盖安装 smoke 包、再在 `devicectl process launch` 阶段失败的问题，新增安装前 launch 预检：脚本先尝试启动当前已安装普通 `top.simitalk.aichat`，如果 CoreDevice JSON 明确包含 `Locked`，则在 `simichat_release_pubspec_setup 0`、release smoke build 和 install 之前退出 2，并提示 `Refusing to install iOS background smoke build while device is locked`；非 Locked 的 launch 失败不阻塞，避免首次安装等场景被误挡。验证：先新增 manifest 约束并确认红灯失败于缺少 `assert_device_unlocked_for_launch`；修复后目标用例通过，`bash -n scripts/smoke_ios_release_background_restore.sh` 通过，`flutter --no-version-check test --no-pub -r expanded test/release_send_smoke_manifest_test.dart` 7 项通过。 | 已完成脚本安全加固 / iOS 真机后台通过仍待复跑 |
| 2026-07-07 | OpenAI Relay Responses API 流式兼容：`/v1/responses stream=true` | 针对更多 OpenAI Responses 风格客户端兼容，先红灯确认旧本地 Relay 对 `POST /v1/responses` + `stream=true` 返回 `400 unsupported_stream` 且不转发；随后复用现有 Responses input 解析、Vision 路由和并发保护，新增 `text/event-stream` 输出 `response.created`、`response.in_progress`、`response.output_item.added`、`response.content_part.added`、`response.output_text.delta` / `done`、`response.content_part.done`、`response.output_item.done`、`response.completed`、上游流式异常时的 `response.failed` 和 `data: [DONE]`，响应不回显 Bearer token / API Key / 本机路径 / 远端图片 URL / base64；继续补顶层 `item_reference` 等非文本 input item 安全降级，先红灯确认旧 parser 返回 `400`，修复后转为安全占位且不泄露原始 reference id。验证：最小 SSE 到完整生命周期事件、再到 `response.in_progress` envelope 事件、上游异常安全 `response.failed` 事件的目标用例均先红灯、修复后通过；`flutter --no-version-check test --no-pub -r expanded test/openai_compatible_relay_server_test.dart` 24 项通过。 | 已完成本地局部兼容 / 真机与第三方客户端待复验 |
| 2026-07-07 | OpenAI Relay 流式上游异常安全收口：`/v1/chat/completions` / `/v1/responses` | 针对流式请求已开始发送 SSE 后上游中途抛错的客户端兼容风险，新增 Chat Completions 流式异常红灯用例：旧实现只输出到最后一个 delta，缺少安全 `error` payload 和 `[DONE]`；修复后 `/v1/chat/completions stream=true` 输出 OpenAI 风格安全 `error` / `code=upstream_error` / `[DONE]`，`/v1/responses stream=true` 输出安全 `response.failed` / `[DONE]`，两者均不回显 Bearer token、API Key、本机路径或上游异常详情，并把审计 `code` 记为 `upstream_error` 而非 `ok`。验证：Chat / Responses 两条流式失败审计断言均先红灯后通过，`flutter --no-version-check test --no-pub -r expanded test/openai_compatible_relay_server_test.dart` 25 项通过。 | 已完成本地局部兼容 / 第三方 SDK 待复验 |
| 2026-07-07 | 后台切出取消未完成流式请求：`ResponsiveShell.didChangeAppLifecycleState()`、`cancelStreaming()` | 针对“后台未完成请求恢复”的第一层保护，新增移动端 widget 回归：当前 active 会话 `streamStateProvider` 处于 `isStreaming=true` 且有部分内容时，模拟 `AppLifecycleState.inactive` 必须清空 streaming 状态，避免应用切后台后仍悬挂生成中；继续补非当前会话 streaming 的边界，后台切出时会遍历已加载会话列表中所有仍在 streaming 的会话并逐条取消。先确认红灯失败于 `Expected: false Actual: <true>`；随后在 `ResponsiveShell.didChangeAppLifecycleState()` 的非 `resumed` 分支中读取当前 active 会话，如仍在 streaming 则调用既有 `cancelStreaming(ref, activeId, error: backgroundStreamingInterruptedMessage)`；`cancelStreaming()` 新增可选 `error` 参数，手动停止仍不显示错误，后台切出会显示 `应用进入后台，已停止本次生成，回到前台后可重试。`，复用 ChatPage 错误条的“重试 / 关闭”。继续记录 `_backgroundInterruptedSessionIds`，恢复 `resumed` 时若仍有被后台中断的会话，则弹出固定 SnackBar；单条显示 `已停止后台生成，可点“重试”继续`，多条显示 `已停止 N 个后台生成，可点“重试全部”继续`，但不自动重发，避免重复 API 调用或费用；同时写入 SharedPreferences `simichat.background_interrupted_session_ids` 列表并兼容旧单值 key `simichat.background_interrupted_session_id`，同进程恢复提示后清理 marker。新增冷启动恢复用例：预置 marker 后启动应用，自动选择当前会话后恢复错误条、弹出 `已恢复上次后台中断，可点“重试”继续`，并消费 marker；继续新增 marker 指向非当前自动选中会话用例，先红灯确认旧逻辑停在最新会话，修复后会先切回 marker 指向的既有会话再恢复错误条和冷启动重试提示；继续补 stale marker 用例，先红灯确认 marker 指向已删除 / 不存在会话时仍残留 `session-deleted-background-retry`，修复后会清理 SharedPreferences marker、保留当前正常会话且不显示后台恢复提示；随后把持久化 marker 从旧单值兼容推进到列表 key `simichat.background_interrupted_session_ids`，新增多 marker 用例先红灯确认缺少 `kBackgroundInterruptedSessionsStorageKey`，修复后冷启动会恢复多条仍存在会话的后台中断错误态、切到第一条有效待重试会话、跳过缺失会话，并清理新旧两类 marker；继续增强多条恢复提示，先红灯确认缺少 `已恢复 2 个后台中断会话，可逐个点“重试”继续` 文案，修复后多条恢复会显示数量，且切到第二条待重试会话时错误条仍可见；随后把多条恢复 action 推进为显式 `重试全部` 用户动作，先红灯确认找不到 `已恢复 2 个后台中断会话，可点“重试全部”继续` 和 `重试全部` 按钮，修复后点击会逐条触发已恢复会话的最后一条 user 消息重试；继续补 marker 列表数据卫生，先红灯确认重复 ID 会污染恢复数量，修复后读取 marker 时 trim、跳过空值并按顺序去重；继续补写入侧清洗，先红灯确认后台切出会把已有脏列表原样保留，修复后持久化前也会清洗已有列表；继续补主动重试可靠性，先红灯确认 `messagesProvider` 未预加载时 `retryLastUserMessage()` 会静默保持后台错误态，修复后改为直接查 `messageDaoProvider` 最近用户消息并进入发送路径；继续补快速切后台 / 前台时 marker 异步写入与清理的竞态，先红灯确认延迟写入会在清理后留下 `session-background-marker-race`，修复后恢复前台清理会等待 pending persist 完成再删除新旧 marker；继续补非当前会话后台流取消，先红灯确认另一个会话仍 `isStreaming=true`，修复后 active 与非 active 两条会话都会恢复为后台中断错误态，恢复前台显示 `已停止 2 个后台生成，可点“重试全部”继续`。验证：缺少 `backgroundStreamingInterruptedMessage`、缺少恢复前台提示、缺少持久化 key、同进程恢复后 marker 未消费、marker 会话未切回、stale marker 未清理、多 marker key 缺失、多条恢复数量提示缺失、重复 marker 污染数量、写入侧脏 marker 残留、主动重试依赖 provider loading、延迟 marker 写入竞态、多条恢复缺少 `重试全部` 显式用户动作、非当前 streaming 会话未取消均先红灯；修复后 `flutter --no-version-check test --no-pub -r expanded test/mobile_main_flow_smoke_test.dart` 17 项通过，`flutter --no-version-check test --no-pub -r expanded test/chat_provider_retry_test.dart` 1 项通过，`flutter --no-version-check analyze` 无问题，`git diff --check` 无输出，正式 `pubspec.yaml` / `pubspec.lock` 未保留临时 sqlite hook。 | 已完成所有已加载 streaming 会话后台取消、单会话持久化待重试 marker、列表 marker 恢复、读写侧 marker 清洗、非当前会话切回、不存在会话 marker 清理、主动重试 DAO 兜底和多会话“重试全部”显式用户授权 / 后台自动重试仍不启用 |
| 2026-07-07 | Android 后台慢流取消真机 smoke：`mobile_background_stream_cancel_smoke_test.dart`、`smoke_android_background_stream_cancel.sh` | 新增 Android 设备内真实 HTTP 慢流 smoke：integration test 启动本机 OpenAI Chat mock，UI 发送后等待真实 `/v1/chat/completions` 请求进入 `isStreaming=true` / `isWaitingForFirstToken=true`，随后注入 `AppLifecycleState.inactive` / `resumed`。旧实现先红灯失败于 `DioException [request cancelled]` 与后台恢复后异步流程继续触碰已 dispose provider；修复后在 `cancelStreaming(..., error)` 记录后台取消错误，`_runAssistantResponse()` 醒来后保持 `backgroundStreamingInterruptedMessage` 并直接返回，不再落库 assistant 半截回复。验证：`scripts/smoke_android_background_stream_cancel.sh 37101FDJH0077P` 通过；配套 `test/mobile_main_flow_smoke_test.dart` + `test/release_send_smoke_manifest_test.dart` 20 项通过，`flutter analyze` 无问题，`git diff --check` 无输出；随后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release，31.5MB APK 覆盖安装并启动 pid `22529`。 | 已完成 Pixel 8 设备内慢流取消补证 / 物理 Home 已由后台恢复 smoke 覆盖 |
| 2026-07-07 | iOS release 后台恢复复跑：`release_background_smoke_harness.dart`、`smoke_ios_release_background_restore.sh` | 在 iPhone13 `00008110-0016349A3A20A01E` 复跑 release-only 后台恢复脚本，设备解析到 CoreDevice `CAFC7AFA-4565-5C8D-B724-090061D144D0`；脚本构建带 `SIMICHAT_RELEASE_BACKGROUND_SMOKE=true` 的 release 包、覆盖安装并启动 `top.simitalk.aichat`，ready 后执行 `devicectl process suspend` / `resume`，harness 写入 `status=passed`，runId `ios-release-background-20260707100131`，launch pid `80004`，`reason=process_suspend_resume_gap`，`gapMs=3214`，`elapsedMs=4483`，marker `SIMICHAT_RELEASE_BACKGROUND_READY`；随后脚本自动恢复普通 release 包，安装 `bundleID=top.simitalk.aichat` / `databaseSequenceNumber=4312`，启动 pid `80007`。 | 已完成 iPhone13 release 进程级后台暂停 / 恢复补证；真实手动 Home / 锁屏 / 解锁和后台未完成网络请求恢复仍待测 |
| 2026-07-07 | iOS release 发送 smoke 停止链路红灯与安全加固：`cancelStreaming()`、`openSseStream()`、`release_send_smoke_harness.dart`、`smoke_ios_release_send.sh` | 在 iPhone13 复跑当前 release send harness，runId `ios-release-send-20260707100852` / `ios-release-send-20260707101242` 先红灯于 stop 慢流：mock 记录 `lastUser=ios release stop smoke`、`completed=true`、`brokenPipe=false`。修复：`cancelStreaming()` 移除 active stream subscription 后显式 `unawaited(subscription.cancel())`；`openSseStream()` 返回 cancellation-aware 字节流，下游取消且流未正常结束时传播 `CancelToken.cancel()`；release send harness 内置 `dart:io` SSE mock 设置 `request.response.bufferOutput=false` 避免小 chunk 缓冲误判；`smoke_ios_release_send.sh` 增加 launch preflight，Locked / timeout / 未证明解锁都 exit 2，安装 smoke 包后失败会 trap 恢复普通 release。验证：OpenAI Chat / release manifest / retry 聚焦测试 16 项通过，`git diff --check` 无输出，`bash -n` 两个 iOS release smoke 脚本通过，`flutter analyze` 无问题；本轮已恢复普通 release 覆盖安装到 iPhone13（`databaseSequenceNumber=4376`），但设备 Locked / preflight timeout，修复后的 release send 全链路复跑被安全拒绝，`SMOKE_SEND_EXIT_CODE=2`。 | 已完成代码级停止链路修复和脚本防污染；待设备解锁后复跑 release send / retry / model switch / stop 全链路 |
| 2026-07-07 | Android 后台慢流取消回归复验：`cancelStreaming()`、`openSseStream()`、`mobile_background_stream_cancel_smoke_test.dart` | iOS send 停止链路修复后，用 Pixel 8 复跑 Android 真实 HTTP 慢流后台取消 smoke。首轮红灯暴露 `subscription.cancel()` Future 的 `DioException [request cancelled]` 成为未处理异常，并伴随 teardown 后 `_showBackgroundInterruptedRetryPromptIfNeeded()` 读取已 dispose provider；修复为 `subscription.cancel().catchError((_) {})`、SSE wrapper 在 `CancelToken` 已取消时吞掉 `DioExceptionType.cancel`，并给恢复提示入口补 `mounted` guard。复验：`./scripts/smoke_android_background_stream_cancel.sh 37101FDJH0077P` 通过；随后 `./scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release，`app-release.apk` 31.5MB，`versionName=1.0.0`，`lastUpdateTime=2026-07-07 10:41:24`，启动 pid `4150`；正式 `pubspec.yaml` / `pubspec.lock` 未残留 sqlite system hook，`integration_test` 依赖已恢复。 | 已完成 Pixel 8 真机取消回归复验和 release 恢复 |
| 2026-07-07 | Ollama 本地模型流式取消传播：`OllamaProtocol`、`ollama_protocol_test.dart` | 代码索引确认 OpenAI Chat / Responses / Claude / Gemini 都经统一 `openSseStream()` 使用 `CancelToken`，但 Ollama 使用 `http.Client` 读取 NDJSON，旧实现忽略 `CancelToken`。新增测试先红灯：本地 HttpServer 发出首个 `message.content=partial` 后保持连接，调用 `CancelToken.cancel()` 旧实现不会结束流，失败于 `TimeoutException: cancelDone`。修复后 `OllamaProtocol` 把 `cancelToken.whenCancel` 绑定到 `client.close()`，循环中检查 `cancelToken.isCancelled`，并把取消导致的 client 异常视为正常停止。验证：`test/ollama_protocol_test.dart` 通过；多协议停止相关聚焦回归 `test/ollama_protocol_test.dart test/openai_chat_protocol_test.dart test/openai_response_protocol_test.dart test/chat_provider_retry_test.dart test/release_send_smoke_manifest_test.dart` 共 21 项通过，`flutter analyze` 无问题，`git diff --check` 无输出。 | 已完成 Ollama 停止生成本地回归 / 真实 Ollama 服务长流待后续手工复验 |
| 2026-07-07 | Android 音频焦点丢失设备 smoke：`mobile_audio_focus_loss_smoke_test.dart`、`smoke_device_integration_audio_focus_loss.sh` | 新增 Android 设备侧音频焦点丢失 smoke：integration test 生成 6.5 秒静音 WAV，走 `playFileForTesting(audioFile.path)` 的正式焦点请求路径开始播放，最初通过 debug-only `simulateAudioFocusLossForTesting` 触发 `AUDIOFOCUS_LOSS_TRANSIENT`，先红灯失败于 `MissingPluginException(No implementation found for method simulateAudioFocusLossForTesting on channel simichat/audio_player)`；随后补原生入口并验证 stopped、无 completed、无 error。本轮继续把 smoke 推进为 debug-only `requestCompetingAudioFocusForTesting`，请求独立的 `AUDIOFOCUS_GAIN_TRANSIENT` 竞争焦点来覆盖 Android `AudioManager` 焦点仲裁路径，测试结束调用 `abandonCompetingAudioFocusForTesting` 清理，release 仍由 `ApplicationInfo.FLAG_DEBUGGABLE` 限制不暴露。验证：`scripts/smoke_device_integration_audio_focus_loss.sh 37101FDJH0077P` 在 Pixel 8 通过；`flutter --no-version-check test --no-pub --no-test-assets test/microphone_permission_manifest_test.dart -r expanded` 8 项通过；competing focus integration smoke 后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release 并启动 pid `10374`。 | 已完成 Pixel 8 debug-only competing AudioFocus 补证并恢复普通 release / 真实第三方播放器、来电、闹钟抢占仍待复验 |
| 2026-07-07 | Android 外部应用音频焦点抢占 smoke：`mobile_external_audio_focus_smoke_test.dart`、`smoke_device_external_audio_focus.sh` | 新增 Pixel 8 外部包抢占焦点验证：脚本临时生成独立 helper APK `top.simitalk.aichat.audiofocusstealer` 并安装到设备；integration test 先让 SimiChat 走正式 `playFileForTesting(audioFile.path)` 焦点请求播放 9 秒静音 WAV，打印 `SIMICHAT_EXTERNAL_AUDIO_FOCUS_READY` 后脚本启动 helper，helper 从另一个包请求 `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE` 并保持 6 秒；SimiChat 收到 stopped、无 completed、无 error。脚本 cleanup 会卸载 helper、恢复 `pubspec.yaml` / `pubspec.lock`。验证：`scripts/smoke_device_external_audio_focus.sh 37101FDJH0077P` 通过；`pm list packages top.simitalk.aichat.audiofocusstealer` 为空；`git diff --check` 无输出；随后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release 并启动 pid `11520`。 | 已完成外部 helper 包系统焦点抢占自动化补证 / 真实来电、闹钟、第三方媒体播放器仍待复验 |
| 2026-07-07 | Dreaming 报告删除 / 清空同步清理 SQLite：`_clearDreamingReports()`、`_deleteDreamingReport()` | 继续收口 SQLite report 持久层一致性：先红灯确认设置页“清空报告 / 删除此报告”只清理 SharedPreferences，`dreaming_reports` 仍残留，后续回灌或导出可能恢复用户已删除报告；修复后清空报告同步调用 `DreamingDao.clearReports()`，删除单日报告同步调用 `deleteReportByDay(dayKey)`，保留当前 SharedPreferences 历史回退行为。验证：`test/settings_page_dreaming_test.dart` 12 项通过；`scripts/smoke_full_stability_gate.sh -r expanded test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 49 项通过；`flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出；`pubspec.yaml` / `pubspec.lock` 无 `sqlite3.source=system` 或 hooks 残留；本轮未触碰 people 真机。 | 已完成 |
| 2026-07-07 | Dreaming job 去重 / 恢复策略：`runDreamingDigest()`、`DreamingDao.failUnfinishedJobsByDay()` | 继续为系统后台调度铺底：先红灯确认同日并发手动触发会写入 2 个 completed job；再红灯确认崩溃遗留的 `pending` / `running` job 不会在下一次运行前收敛。修复后 `runDreamingDigest()` 按 `dayKey` 复用同一个 in-flight Future，避免同日并发重复落库；新运行前调用 `DreamingDao.failUnfinishedJobsByDay()` 把同日未完成 job 标记 failed，并保留新的 completed job / report。验证：`flutter --no-version-check test --no-pub --no-test-assets test/dreaming_dao_test.dart test/dreaming_provider_test.dart -r expanded` 12 项通过；Dreaming / 数据完整门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 52 项通过；`flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出；`pubspec.yaml` / `pubspec.lock` 无临时 sqlite hook 残留。 | 已完成代码级队列去重与崩溃残留恢复 / 系统后台调度仍待实现 |
| 2026-07-07 | Dreaming failed job 可见状态与重试入口：`latestFailedDreamingJobProvider`、设置页 Dreaming 弹窗 | 继续把 SQLite job 队列产品化：新增 `DreamingDao.getLatestUnresolvedFailedJob()`，只显示未被同日后续 completed job 覆盖的最近 failed job；设置页 Dreaming tile 增加“最近失败 YYYY-MM-DD · 可重试”，弹窗展示失败 dayKey、触发来源与错误摘要，并提供“重试最近失败”按钮，按钮按失败 dayKey 重新运行 Dreaming；`runDreamingDigest()` 成功或失败后刷新 failed job provider，重试成功后提示消失。验证：先红灯于缺少 unresolved failed job 查询和 UI 提示；修复后 `flutter --no-version-check test --no-pub --no-test-assets test/dreaming_dao_test.dart test/dreaming_provider_test.dart test/settings_page_dreaming_test.dart -r expanded` 26 项通过；Dreaming / 数据完整门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 54 项通过。 | 已完成代码级失败可见与用户重试入口 / 真正系统后台失败通知仍待实现 |
| 2026-07-07 | Dreaming failed job 未解决扫描补强：`DreamingDao.getLatestUnresolvedFailedJob()` | 先红灯构造 21 个更新的已解决 failed job 加 1 个更早未解决 failed job，确认旧默认只扫最近 20 个 failed job 会漏掉真正仍需用户处理的失败；修复后按批次分页扫描 failed job，跳过已被同日后续 completed job 覆盖的失败，直到找到未解决项或扫描完毕，避免大量历史失败导致设置页 / 启动提示误判为无失败。验证：目标用例红灯后转绿；DAO / 设置页 / provider 专项 31 项通过。 | 已完成代码级失败可见性补强 / 系统后台调度仍待实现 |
| 2026-07-07 | Dreaming failed job 清除 / 忽略入口：`DreamingDao.dismissFailedJob()`、设置页 Dreaming 弹窗 | 在已有失败查看 / 重试基础上补“清除此失败”：DAO 将 failed job 标记为 `dismissed`，`getLatestUnresolvedFailedJob()` 不再返回；设置页弹窗提供“清除此失败”，清除后入口“最近失败 YYYY-MM-DD”提示和弹窗失败卡片都会消失，避免已知失败在启动 / 前台恢复时反复提示。验证：`dreaming dialog can dismiss failed job prompt` 先红灯于找不到按钮，修复后通过；设置页 / provider / DAO 专项 30 项通过；完整 Dreaming / 通知 / 数据门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/mobile_main_flow_smoke_test.dart test/notification_service_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 90 项通过，Drift warning 扫描无输出，`pubspec.yaml` / `pubspec.lock` 无临时 hook 残留。 | 已完成代码级失败忽略入口 / 系统后台调度仍待实现 |
| 2026-07-07 | Dreaming failed job 导出 / 恢复错误脱敏：`LocalDatabaseSnapshotService`、`data_export_service_test.dart` | 继续收口本地数据导出隐私边界：先红灯确认 `structured_data/local_database.json` 的 `dreaming_jobs.error` 会原样带出 Bearer token、`sk-*`、`token=raw` 和 `/Users/...` 路径；修复后导出层用 `_safeDiagnosticString()` 替换为 `Bearer ***`、`sk-***`、`token=***`、`[本机路径]`，本机 SQLite 原始 failed job 仍保留供本地排障，导出 / 恢复只携带脱敏摘要。验证：聚焦用例红灯后转绿；`flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/data_export_service_test.dart test/data_import_service_test.dart test/structured_data_backup_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart -r expanded` 35 项通过。 | 已完成 |
| 2026-07-07 | Dreaming failed job URL 脱敏：`SettingsPage._sanitizeDreamingFailedJobError()`、`LocalDatabaseSnapshotService._safeDiagnosticString()` | 在已隐藏 Bearer / `sk-*` / token 参数 / 本机路径的基础上，继续补 URL 主体泄露边界：先红灯确认设置页 failed job 弹窗、本地数据库快照导出和旧 snapshot 恢复后仍会保留 `https://example.test/...`；修复后 HTTP(S) URL 统一替换为 `[链接]`，独立 `token=...` / `api_key=...` 仍输出为 `token=***` / `api_key=***`。验证：聚焦 3 项红灯后转绿；`flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/settings_page_dreaming_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/structured_data_backup_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart -r expanded` 51 项通过。 | 已完成 |
| 2026-07-07 | Dreaming failed job 恢复错误脱敏：`LocalDatabaseSnapshotService.restoreSnapshot()`、`data_export_service_test.dart` | 继续补齐旧导出包 / 外部包导入边界：先红灯确认手工构造的旧 snapshot 中 `dreaming_jobs.error` 带 Bearer、`sk-*`、`token=raw` 和 `/Users/...` 时，恢复会把原文写进 SQLite；修复后 `restoreSnapshot()` 写入 `DreamingJobsCompanion` 前复用 `_safeDiagnosticString()`，恢复后的 failed job 只保留脱敏诊断摘要。验证：聚焦用例红灯后转绿；导出 / 导入 / Dreaming / DAO / 结构化备份专项 36 项通过。 | 已完成 |
| 2026-07-07 | Dreaming failed job 错误摘要脱敏：`SettingsPage._formatDreamingFailedJob()`、`settings_page_dreaming_test.dart` | 失败详情继续可见，但不再泄露敏感内容：设置页 Dreaming failed job 弹窗会把 Bearer、`sk-*`、token/query 参数和 `/Users` / `/var` / `/private` 本机路径脱敏后展示。验证：`dreaming failed job error summary is sanitized` 先红灯后通过；设置页 / Dreaming / DAO 专项 28 项通过；完整 Dreaming / 通知稳定门禁 86 项通过，warning 扫描无 Drift / multiple database 警告。 | 已完成代码级失败摘要脱敏 / 历史已落库 raw error 仍仅本机保存，展示层脱敏 |
| 2026-07-07 | Dreaming 设置页手动运行失败反馈：`SettingsPage._runDreaming()`、`settings_page_dreaming_test.dart` | 手动运行失败不再把异常抛到界面测试 / 用户链路：`_runDreaming()` 捕获 `runDreamingDigest()` 异常后显示“Dreaming 失败，可到设置页重试”，直接返回，不发布半成功报告；底层 `runDreamingDigest()` 仍负责记录 failed job，用户重新打开 Dreaming 弹窗即可看到失败摘要并按失败日期重试。验证：`dreaming manual run failure shows retryable feedback` 先红灯后通过；设置页 / Dreaming / DAO 专项 27 项通过；完整 Dreaming / 通知稳定门禁 85 项通过。 | 已完成代码级手动失败反馈 / 真机手动 UI 复验待后续 |
| 2026-07-07 | Dreaming 前台到期失败本地通知：`NotificationService`、`ResponsiveShell`、`mobile_main_flow_smoke_test.dart` | 自动整理失败不再只依赖设置页或前台 SnackBar：新增失败通知正文构造和 `showDreamingDigestFailed()`，标题“Dreaming 整理失败”、正文“YYYY-MM-DD 整理失败，可到设置页重试”，不暴露异常详情；`_runDueDreamingIfNeeded()` 捕获前台到期失败后读取未解决 failed job 并通过测试可替换的 `dreamingDigestFailedNotifier` 推送，同一进程同一 dayKey 只通知一次。验证：通知文案和 `mobile due dreaming failure sends local failure notification` 均先红灯，修复后通知服务 8 项、Dreaming smoke 9 项通过；完整 Dreaming / 通知稳定门禁 84 项通过。 | 已完成代码级前台到期失败通知 / 真正系统后台调度失败通知仍待实现 |
| 2026-07-07 | Dreaming failed job 启动 / 恢复前台主动提示：`ResponsiveShell`、`mobile_main_flow_smoke_test.dart` | 把失败可见性从设置页被动入口推进到前台主动提醒：应用启动或恢复前台时，如果 `latestFailedDreamingJobProvider` 返回未解决 failed job，会显示“上次 Dreaming 失败，可到设置页重试”的固定 SnackBar，并提供“去设置”动作进入设置页查看失败详情 / 重试；同一进程同一 failed job 只提示一次。验证：`mobile startup prompts for unresolved dreaming failure` 与 `mobile resume prompts for unresolved dreaming failure` 均先红灯，修复后 `flutter --no-version-check test --no-pub --no-test-assets test/mobile_main_flow_smoke_test.dart --name "dreaming failure" -r expanded` 2 项通过；Dreaming smoke `--name dreaming` 8 项通过；Dreaming / 设置页 / DAO 专项 26 项通过；完整 Dreaming 稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/mobile_main_flow_smoke_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 75 项通过。 | 已完成代码级启动 / 前台恢复失败提示 / 真正系统后台失败通知仍待实现 |
| 2026-07-07 | Dreaming SQLite report 回灌设置页状态：`syncDreamingDigestStateFromDatabase()`、`_importLocalData()` | 新增从 SQLite `dreaming_reports.digest_json` 恢复 Dreaming provider 状态的入口：最新有效 report 会写回 `dreaming_digest_v1`，最近有内容 report 会合并到 `dreaming_digest_history_v1`；设置页本地导入成功后 best-effort 调用该入口，避免数据包已恢复 SQLite report 但 Dreaming 入口仍显示“尚未运行”。先红灯于缺少 `syncDreamingDigestStateFromDatabase()`，修复后 `syncs dreaming provider state from sqlite reports` 通过。验证：`scripts/smoke_full_stability_gate.sh -r expanded test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/settings_page_dreaming_test.dart test/structured_data_backup_test.dart` 49 项通过；`flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出；`pubspec.yaml` / `pubspec.lock` 无 `sqlite3.source=system` 或 hooks 残留；本轮未触碰 people 真机。 | 已完成 |
| 2026-07-07 | Dreaming 失败一致性保护：`runDreamingDigest()`、`dreaming_provider_test.dart` | 先红灯复现 Key Points 写入失败时旧逻辑已提前发布 `dreaming_digest_v1` / 历史报告，导致 job failed 但设置页可见半成功报告；修复为先完成 Key Points 写入、SQLite report upsert 和 job completed 标记，再发布 SharedPreferences 最新报告 / 历史。失败路径只保留 failed job 和错误信息，不写 SQLite report、不发布 SharedPreferences 脏报告。验证：单用例红灯后转绿；`scripts/smoke_full_stability_gate.sh -r expanded test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/dreaming_service_test.dart test/settings_page_dreaming_test.dart test/structured_data_backup_test.dart` 39 项通过；`flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出；`pubspec.yaml` / `pubspec.lock` 无 `sqlite3.source=system` 或 hooks 残留；本轮未触碰 people 真机。 | 已完成 |
| 2026-07-07 | iOS release 网络恢复 smoke 入口：`release_network_smoke_harness.dart`、`smoke_ios_release_network_restore.sh` | 新增 release-only 网络恢复 harness，使用 `SIMICHAT_RELEASE_NETWORK_SMOKE=true` 和 fake `ConnectivityMonitor` 在 release 包内模拟 `wifi -> none -> wifi`，验证 `isOnlineProvider` 能从在线变离线再恢复在线，并把离线 / 恢复产品文案写入 `Documents/ai_chat/release_network_smoke/ios-release-network-smoke.json`；新增 iOS 脚本会安装前执行 `assert_device_unlocked_for_launch`，Locked / timeout / 未证明解锁均在 build / install 前退出 2，release smoke 构建使用临时 `sqlite3.source=system` hook，失败或成功后默认恢复普通 release。验证：先红灯于缺少 harness / 脚本；修复后 `bash -n scripts/smoke_ios_release_network_restore.sh` 通过，`flutter --no-version-check test --no-pub -r expanded test/release_send_smoke_manifest_test.dart --name "iOS release network restore smoke"` 通过，完整 `test/release_send_smoke_manifest_test.dart` 14 项通过，`flutter --no-version-check analyze` 无问题；本轮未安装或启动 people。 | 入口已完成 / iOS 真机物理网络切换待设备可用后复跑 |
| 2026-07-07 | Android 音频焦点 suite：`smoke_android_audio_focus_suite.sh` | 新增一键 Android 音频焦点设备 suite，顺序运行 `smoke_device_integration_audio_focus_loss.sh` 与 `smoke_device_external_audio_focus.sh`，覆盖 debug-only competing AudioFocus 和独立 helper APK 外部焦点抢占两条路径；suite 结束会调用 `smoke_android_release_install_launch.sh` 恢复普通 release，失败时 trap 也会 best-effort 恢复，避免设备停留在 debug 包。验证：`scripts/smoke_android_audio_focus_suite.sh 37101FDJH0077P` 通过，最终 `app-release.apk` 31.5MB 覆盖安装成功，`lastUpdateTime=2026-07-07 11:55:53`，启动 pid `12728`；helper 包清理为空，`pubspec.yaml` / `pubspec.lock` 无 `sqlite3.source=system` 或 hooks 残留，`git diff --check` 无输出。 | 已完成 Pixel 8 一键音频焦点 suite / 真实来电、闹钟、第三方媒体播放器仍待复验 |
| 2026-07-06 | 主力机不触碰的最终稳定复核：本地门禁、Dreaming 基准、Pixel 8 真机发送 smoke、Android release 恢复、iOS release 候选构建 | 当前 `people` 在 CoreDevice 中为 `unavailable`，本轮没有在主力 iPhone 上安装或跑 smoke。先通过 `git diff --check`、`flutter --no-version-check analyze`、`scripts/smoke_full_stability_gate.sh -r expanded`（348 项通过）和 `scripts/benchmark_dreaming.sh -r expanded`（1000 条消息 `run_ms=48` / `digest_elapsed_ms=46` / `memory_candidates=40`）。随后 Pixel 8 通过 `scripts/smoke_device_integration_send.sh 37101FDJH0077P`，验证设备内 OpenAI mock 的 UI 输入 → SSE → assistant 落库 / 展示闭环；由于 Android debug integration runner 会安装 debug 包，本轮结束后立刻用 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release，`app-release.apk` 31.5MB，`adb install -r` 成功，启动 pid `4047`，20 秒后 pid 仍为 `4047`，logcat 未发现 crash；Android 测试机最终包信息为 `versionName=1.0.0`、`versionCode=1`、`dataDir=/data/user/0/top.simitalk.aichat`、`firstInstallTime=2026-07-06 15:07:44`、`lastUpdateTime=2026-07-06 15:07:44`。iOS 侧仅构建普通 release 候选，不安装到 people：`flutter --no-version-check build ios --release` 通过，产出 `build/ios/iphoneos/Runner.app` 33.2MB；构建后复查 `people` 仍为 `unavailable`，等待设备解锁 / 可用后才能执行 release 覆盖安装。正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 `sqlite3.source=system` hook。 | 已完成 Pixel 8 / people 待设备可用 |
| 2026-07-06 | 网络稳定性加固后的 Android release 覆盖安装复验 | 按用户要求继续不触碰 people 主力机，先在 Pixel 8 `37101FDJH0077P` 复验当前工作树。`scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 构建 `build/app/outputs/flutter-apk/app-release.apk` 31.5MB，`adb install -r` 覆盖安装成功，`monkey` 启动成功；包信息为 `versionCode=1`、`versionName=1.0.0`、`firstInstallTime=2026-07-06 15:07:44` 保持不变、`lastUpdateTime=2026-07-06 15:33:20` 更新、`dataDir=/data/user/0/top.simitalk.aichat`，release 进程 pid `5312` 可见。配套本地门禁：`flutter --no-version-check analyze` 无问题，受影响 11 项测试通过，全量稳定性 gate 350 项通过；本轮没有在 people 上安装或跑 smoke。 | 已完成 Pixel 8 release / people 未触碰 |
| 2026-07-06 | Dreaming 自动运行并发稳定性加固：`lib/shared/providers/dreaming_provider.dart`、`test/dreaming_provider_test.dart` | 针对启动 / 前台恢复等场景可能同时触发 `maybeRunDueDreaming()` 的理论风险，新增进程内 `_dueDreamingAutoRunInFlight` 闸门；当已有自动 Dreaming 在运行时，并发重复触发直接返回 `null`，避免重复 digest、重复画像提案、重复反思和重复通知；新增 `maybeRunDueDreaming ignores concurrent duplicate triggers` 回归测试，`Future.wait` 同时触发两次时只允许 1 个 `DreamingDigest`、另 1 个为 `null`，并确认 `lastAutoRunDayKey` 写入当天；验证：`flutter --no-version-check test --no-pub --no-test-assets -r expanded test/dreaming_provider_test.dart` 2 项通过，Dreaming/Reflection 目标测试 18 项通过，`flutter --no-version-check analyze` 无问题，临时 sqlite hook 下全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 339 项通过，正式 `pubspec.yaml` / `pubspec.lock` 不保留 hook，`git diff --check` 无输出 |
| 2026-07-06 | 主力机保护后的稳定门禁复验：`git diff --check`、`flutter --no-version-check analyze`、Dreaming/Reflection 目标测试、全量测试、Pixel 8 真机 smoke、Android / iOS 普通 release 构建 | 按用户要求不再对 `people` 主力机做实验性 smoke 安装；前置阶段仅查询已安装列表，`SimiAIChat top.simitalk.aichat 1.0.0 1` 仍可见；所有门禁通过后执行普通 release 覆盖安装和启动：`./scripts/smoke_ios_release_install_launch.sh BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D` 成功，安装 `bundleID=top.simitalk.aichat`、`databaseSequenceNumber=6208`，launch pid `64373`，app listing 与 `Runner.app/Runner` 进程均可见；`git diff --check` 无输出，正式 `pubspec.yaml` / `pubspec.lock` 不保留 `sqlite3.source=system` 临时 hook；`flutter --no-version-check analyze` 无问题；`flutter --no-version-check test --no-pub --no-test-assets -r expanded test/release_send_smoke_manifest_test.dart test/dreaming_service_test.dart test/dreaming_schedule_test.dart test/dreaming_provider_test.dart test/settings_page_dreaming_test.dart test/reflection_service_test.dart test/reflection_provider_test.dart` 18 项通过；命令内临时 hook 后全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 339 项通过；Pixel 8 复跑 `scripts/smoke_device_integration_send.sh`、`scripts/smoke_device_integration_settings.sh`、`scripts/smoke_device_integration_native_audio_player.sh`、`scripts/smoke_device_integration_long_audio_playback.sh`、`scripts/smoke_device_integration_audio_playback_replace.sh` 全部通过；`flutter --no-version-check build apk --release` 产出 `build/app/outputs/flutter-apk/app-release.apk` 78.6MB；`flutter --no-version-check build ios --release` 仅构建不安装，产出 `build/ios/iphoneos/Runner.app` 33.1MB |
| 2026-07-06 | 主力机保护后的二次真机稳定收口：全量测试、Pixel 8 真机 smoke、Android release 覆盖安装、iOS release 离线构建脚本加固 | 按用户要求继续保护 `people` 主力机，不做实验性安装；本轮仅查询 CoreDevice，`people` 当前为 `unavailable`，因此未覆盖安装主力机。先复验命令内临时 `sqlite3.source=system` 后全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded`，342 项通过，且包含 `mobile disposed shell skips dreaming follow-up work`；正式 `pubspec.yaml` / `pubspec.lock` 不保留 hook，`flutter --no-version-check analyze` 无问题，`git diff --check` 无输出。Pixel 8 复跑 `scripts/smoke_device_integration_send.sh`、`scripts/smoke_device_integration_settings.sh`、`scripts/smoke_device_integration_native_audio_player.sh`、`scripts/smoke_device_integration_long_audio_playback.sh`、`scripts/smoke_device_integration_audio_playback_replace.sh` 全部通过。清理后发现普通 release 构建会因 sqlite3 native asset 默认下载 GitHub 资产超时而失败，Android 还会因 `integration_test` dev 插件污染 release `GeneratedPluginRegistrant` 失败；已新增 `scripts/lib/release_pubspec_hook.sh` 和 `scripts/smoke_android_release_install_launch.sh`，并加固 iOS release 脚本，release 构建时临时启用 `sqlite3.source=system`、Android release 临时移除 `integration_test`，退出自动恢复 pubspec。新增 Android release 脚本已在 Pixel 8 通过：`app-release.apk` 31.4MB，`adb install -r` 成功，`versionName=1.0.0`、`dataDir=/data/user/0/top.simitalk.aichat`、`firstInstallTime=2026-07-06 13:39:58`、`lastUpdateTime=2026-07-06 13:46:31`、启动 pid `29155`；iOS 普通 release 使用临时 sqlite system hook 仅构建通过，产出 `build/ios/iphoneos/Runner.app` 33.1MB，等待 `people` 可用后再执行普通 release 覆盖安装。 | 已完成 Pixel 8 / iOS 主力机待设备可用后覆盖安装 |
| 2026-07-06 | release 构建脚本防回归测试与测试命令校正 | 在 `test/release_send_smoke_manifest_test.dart` 中新增 release smoke 脚本防回归覆盖：检查 `scripts/lib/release_pubspec_hook.sh` 具备临时 `sqlite3.source=system`、`pubspec.yaml` / `pubspec.lock` 备份恢复、Android release 临时移除 `integration_test` dev 依赖；检查 iOS install / iOS send / Android install 三个 release 脚本都 source helper、注册 `trap cleanup EXIT` 并调用恢复逻辑；检查 Android release 脚本保留 `adb install -r`、`pidof` 和 release build 路径；新增 `bash -n` 脚本语法测试。验证中复现 clean 后直接 `flutter test --no-pub --no-test-assets` 会因 Flutter 内置 `shaders/ink_sparkle.frag` 缺失失败，因此当前全量测试门禁改用“带测试资产”的 `flutter --no-version-check test --no-pub -r expanded`；同一轮命令内临时 sqlite system hook 后全量 344 项通过，`flutter --no-version-check analyze` 无问题，正式 `pubspec.yaml` / `pubspec.lock` 不保留 hook，`git diff --check` 无输出，release 脚本 `bash -n` 通过。 | 已完成 |
| 2026-07-06 | 全量稳定门禁脚本固化：`scripts/smoke_full_stability_gate.sh` | 将当前推荐全量稳定验证封装为脚本：默认执行 `flutter --no-version-check test --no-pub -r expanded`，先临时启用 `sqlite3.source=system` 避免 GitHub native asset 下载失败，退出自动恢复 `pubspec.yaml` / `pubspec.lock`；显式拒绝 `--no-test-assets`，错误信息指出 clean 测试需要 `shaders/ink_sparkle.frag` 等 Flutter 测试资产。`test/release_send_smoke_manifest_test.dart` 已覆盖该脚本 source helper、trap cleanup、恢复 hook、默认全量命令、拒绝 `--no-test-assets` 和 `bash -n`。验证：`scripts/smoke_full_stability_gate.sh -r expanded test/release_send_smoke_manifest_test.dart` 3 项通过；`scripts/smoke_full_stability_gate.sh --no-test-assets` 返回状态 2 且未留下 hook；默认 `scripts/smoke_full_stability_gate.sh` 全量 344 项通过；`flutter --no-version-check analyze` 无问题；正式 `pubspec.yaml` / `pubspec.lock` 不保留 hook；`git diff --check` 无输出；release / stability 脚本 `bash -n` 通过；`people` 仍为 unavailable，未触碰主力机。 | 已完成 |
| 2026-07-06 | Dreaming/Reflection 真机回归与全量测试：`flutter --no-version-check analyze`、命令内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test --no-pub --no-test-assets`、`flutter --no-version-check test --no-pub --no-test-assets test/settings_page_dreaming_test.dart -r expanded`、`flutter --no-version-check build apk --debug --no-pub`、`adb -s 37101FDJH0077P install -r ...`、Pixel 8 UI dump / screenshot / SharedPreferences / logcat 检查 | 静态检查无问题；局部 Dreaming 设置页 3 个 widget 测试通过，新增延迟 Dreaming 回归可复现并防止弹窗关闭后使用已销毁 `WidgetRef`；全量 330 个测试通过；正式 `pubspec.yaml` 未保留临时 sqlite3 hook；Pixel 8 修复包覆盖安装成功且不清数据，72 条长会话可见，Dreaming 生成 72 条消息日报，Reflection 生成 5 条结论 / 4 个行动项 / 1 次历史，短期提示预览可见；logcat 未再出现 disposed ref 异常 |
| 2026-07-06 | Pixel 8 真实发送 smoke：本机 mock OpenAI 服务、`adb reverse tcp:18080 tcp:18080`、debug `run-as` DB seed、UI 截图、SQLite 消息查询、mock 服务请求日志、历史搜索 UI dump | 真机默认模型 `Pixel8 local Mock OpenAI / simichat-mock` 可见；真实发送后 DB 有 user + assistant，UI 显示 `Pixel8 mock reply 20260706` 和 `147 tokens · 772ms`；mock 服务收到 `/v1/chat/completions`、`stream=true`、模型 `simichat-mock`，且 system prompt 包含本地 Reflection 短期提示；点击重试后 assistant 回复增至 2 条、请求数增至 2；慢流停止后 partial assistant 保持 27 字符，mock 记录 `broken_pipe=true`；历史搜索 `smoke` 命中 smoke 会话并排除长会话 |
| 2026-07-06 | Pixel 8 模型切换 smoke：本机 mock OpenAI 服务、`adb reverse tcp:18080 tcp:18080`、debug `run-as` DB seed、UI 菜单 / 截图、SQLite 会话与消息查询、mock 服务请求日志 | 顶部模型从 `Pixel8 local Mock OpenAI / simichat-mock-a` 切换为 `simichat-mock-b`；菜单列出 `simichat-mock`、`simichat-mock-a`、`simichat-mock-b`；DB 中 `sessions.default_channel_model_id=device-mock-model-b-20260706`，新增 1 条 `message_type='model_switch'` system 记录；切换后发送 `switch test20260706`，mock 收到 `model=simichat-mock-b`、`stream=true`、`system_has_reflection=true`，UI 显示 `MOCK-B reply 20260706` 和 `29 tokens · 461ms`，assistant 以 B 模型落库 |
| 2026-07-06 | 真机集成发送 smoke：`integration_test/mobile_real_send_smoke_test.dart`、设备内 `dart:io` OpenAI SSE mock、内存 SQLite seed、Pixel 8 真机运行、iPhone13 debug 排障 | `./scripts/smoke_device_integration_send.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_real_send_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证 `Integration Mock OpenAI / integration-mock-model`、用户输入 `device integration send`、mock 收到 `model=integration-mock-model` / `stream=true`、assistant `DEVICE integration reply 20260706` 落库并在 UI 展示；iPhone13 曾误用 CoreDevice UUID `CAFC7AFA-4565-5C8D-B724-090061D144D0` 导致 Flutter 找不到设备，脚本曾补 iOS ID 解析和旧 Runner 清理，但用户明确 iOS 必须 release，否则不能作为有效运行证明；因此 `smoke_device_integration_send.sh` 已改为遇到 iOS 设备直接退出并提示改用 release 脚本，iPhone13 debug integration 结果只保留为历史排障，不计入 iOS 通过证据 |
| 2026-07-06 | 设置页真机 smoke：`integration_test/mobile_settings_smoke_test.dart`、Pixel 8 真机运行、主题 / 字体 SharedPreferences 持久化 | `./scripts/smoke_device_integration_settings.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_settings_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证首页 `未选择模型` 状态、进入设置页、`外观` / `主题模式` / `字体大小` / `数据与档案` 可见，选择 `深色模式` 后 `theme_mode=dark`，字体缩放保存到约 120% 后 `font_scale≈1.2` 且 UI 显示 `当前: 120%`，平台 back route 可返回首页；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 复杂 Markdown 真机滚动 smoke：`integration_test/mobile_markdown_scroll_smoke_test.dart`、Pixel 8 真机运行、Mermaid / Draw.io 组件与底部哨兵 | `./scripts/smoke_device_integration_markdown_scroll.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_markdown_scroll_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证对话页加载会话 `复杂 Markdown 真机滚动 smoke`、`LatexMarkdownWidget` / `MermaidWidget` / `DrawioWidget` 进入 Widget 树、Mermaid 标题可见，并滚动到 `TAIL_SENTINEL_20260706` 底部哨兵；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | base64 语音真机发送 smoke：`integration_test/mobile_base64_audio_smoke_test.dart`、Pixel 8 真机运行、fake STT、audio sidecar 和净化后模型请求 | `./scripts/smoke_device_integration_base64_audio.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_base64_audio_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证 UI 粘贴 `data:audio/wav;base64,...` 后数据库 user message 只保留 `已接收 base64 语音` 占位且不含原始 base64 / `data:audio`，附件表新增 `fileType=audio` 的 `inline-base64-audio.wav`，fake STT 收到归档路径，`audio_transcripts/` sidecar 状态为 `ready` 且正文为 `Pixel8 voice transcript 20260706`，mock `/v1/chat/completions` 请求最后一条 user content 包含转写结果且不含原始 base64，assistant `DEVICE base64 audio reply 20260706` 落库并展示；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | OpenAI 兼容 STT 网络真机 smoke：`integration_test/mobile_stt_network_smoke_test.dart`、Pixel 8 真机运行、multipart STT 和净化后聊天请求 | `./scripts/smoke_device_integration_stt_network.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_stt_network_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`，验证 UI 粘贴 `data:audio/wav;base64,...` 后未配置独立 STT Provider 时会复用当前 `openai_chat` 渠道先请求 `/v1/audio/transcriptions`，STT mock 收到 `Authorization: Bearer network-api-key`、`multipart/form-data`、默认 `whisper-1` 和 `inline-base64-audio.wav` 文件名；sidecar 状态为 `ready` 且正文为 `Pixel8 network STT transcript 20260706`；随后 mock `/v1/chat/completions` 最后一条 user content 包含转写结果且不含原始 base64 / `data:audio`，assistant `DEVICE STT network reply 20260706` 落库并展示；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 真机录音按钮 smoke：`integration_test/mobile_voice_recording_smoke_test.dart`、Pixel 8 真机运行、Android 原生录音和 STT fallback | `./scripts/smoke_device_integration_voice_recording.sh 37101FDJH0077P` 通过，脚本先 debug 覆盖安装并 `pm grant top.simitalk.aichat android.permission.RECORD_AUDIO`，随后临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_voice_recording_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；验证聊天页麦克风按钮进入停止状态，约 1.6 秒后停止并新增 audio 附件，数据库附件为 `simichat-recording-*.m4a` 且文件大小大于 0、归档文件存在；STT mock 收到 `Authorization: Bearer voice-recorder-api-key`、`multipart/form-data`、默认 `whisper-1` 和录音文件名；sidecar 为 `ready` 且正文为 `Pixel8 real recorder transcript 20260706`；聊天请求包含转写文本且不含 `base64` 或本机归档路径，assistant `DEVICE voice recorder reply 20260706` 落库并展示；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | OpenAI 兼容 TTS 网络真机 smoke：`integration_test/mobile_tts_network_smoke_test.dart`、Pixel 8 真机运行、TTS JSON 请求和停止播报 | `./scripts/smoke_device_integration_tts_network.sh 37101FDJH0077P` 通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_tts_network_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；验证 assistant 消息 `DEVICE TTS assistant message 20260706` 的播报按钮触发 `/v1/audio/speech`，mock 收到 `Authorization: Bearer tts-network-key`、`application/json`、`model=tts-network-mock-model`、`voice=alloy`、原始输入文本和 `response_format=mp3`；返回 bytes 被写入 `tts_audio/` 临时文件且大小大于 0，fake audio player 收到播放路径，UI 显示停止播报，点击停止后回到语音播报按钮；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 原生音频播放通道真机 smoke：`integration_test/mobile_native_audio_player_smoke_test.dart`、Pixel 8 真机运行、Android `MediaPlayer` 和 stopped 事件 | `./scripts/smoke_device_integration_native_audio_player.sh 37101FDJH0077P` 当前工作树通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_native_audio_player_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；测试在应用临时目录生成 1.8 秒静音 PCM WAV，调用 `MethodChannelAudioPlayer.playFileForTesting(..., skipAudioFocusRequest: true)` 后再 `stop()`，验证收到 `AudioPlaybackEventType.stopped`，文件仍存在且大于 WAV header，并且没有 `AudioPlaybackEventType.error`；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 长音频原生播放真机 smoke：`integration_test/mobile_long_audio_playback_smoke_test.dart`、Pixel 8 真机运行、Android `MediaPlayer` 和 completed 事件 | `./scripts/smoke_device_integration_long_audio_playback.sh 37101FDJH0077P` 当前工作树通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_long_audio_playback_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；测试在应用临时目录生成 6.5 秒 24 kHz 静音 PCM WAV，调用 `MethodChannelAudioPlayer.playFileForTesting(..., skipAudioFocusRequest: true)` 后等待自然完成，7 秒左右收到 `AudioPlaybackEventType.completed`，真实等待时间大于 4 秒，文件仍存在且大于 WAV header，并且没有 `AudioPlaybackEventType.error`；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用 |
| 2026-07-06 | 真机 smoke 脚本恢复机制加固：9 个 `scripts/smoke_device_integration_*.sh`、Pixel 8 抽样复验 | 修复 `mktemp /tmp/simichat-pubspec.XXXXXX.yaml` / `mktemp /tmp/simichat-pubspec-lock.XXXXXX.lock` 为无后缀模板，避免中断后字面量 `/tmp` 文件碰撞；`./scripts/smoke_device_integration_native_audio_player.sh 37101FDJH0077P` 通过，脚本结束后 `hooks_present=False`，`git diff --check` 无输出；本轮确认未提交后台恢复 smoke 草稿，因为当前 Flutter integration lifecycle 注入会挂起测试泵 |
| 2026-07-06 | 原生音频播放替换 / 中断真机 smoke：`integration_test/mobile_audio_playback_replace_smoke_test.dart`、Pixel 8 真机运行、Android `MediaPlayer` stopped / completed 事件 | `./scripts/smoke_device_integration_audio_playback_replace.sh 37101FDJH0077P` 当前工作树通过，脚本内临时 `sqlite3.source=system` 后运行 `flutter --no-version-check test integration_test/mobile_audio_playback_replace_smoke_test.dart -d 37101FDJH0077P --no-pub -r expanded`；测试在应用临时目录生成 6.5 秒与 0.9 秒两段静音 PCM WAV，第一段通过 `playFileForTesting(..., skipAudioFocusRequest: true)` 播放约 350 ms 后启动第二段，验证第一段收到 `AudioPlaybackEventType.stopped`、第二段收到 `AudioPlaybackEventType.completed`、第一段无 completed 且全程没有 `AudioPlaybackEventType.error`；脚本结束后正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 hook 副作用，`hooks_present=False` |
| 2026-07-06 | iOS release 发送链路 smoke：`scripts/smoke_ios_release_send.sh`、release-only harness、people 真机运行 | `./scripts/smoke_ios_release_send.sh BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D` 通过，构建带 `SIMICHAT_RELEASE_SEND_SMOKE=true` 的 release 包并覆盖安装，设备内 mock OpenAI Chat SSE 收到 `/v1/chat/completions`、`model=ios-release-smoke-model`、`lastUser=ios release send smoke`，assistant 回复 `IOS release smoke reply 20260706`，取证 `result.status=passed` / `runId=ios-release-send-20260706121606`；脚本随后自动恢复普通 release 包并启动，launch pid `64165`，补充确认 `SMOKE_ARCHIVE_ABSENT`，即 smoke 临时 Markdown 档案不残留 |
| 2026-07-06 | 移动端音频焦点 / 中断代码级回归：`test/microphone_permission_manifest_test.dart`、全量测试、静态检查、Android / iOS Debug 编译 | 临时追加 `sqlite3.source=system` hook 后，`flutter --no-version-check test --no-pub --no-test-assets test/microphone_permission_manifest_test.dart test/text_to_speech_service_test.dart -r expanded` 17 个测试通过，新增静音 WAV 静态回归，并覆盖 `AudioFocusRequest` / `AudioManager` / `OnAudioFocusChangeListener` / `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` / `requestAudioFocus` / `abandonAudioFocus`，并确认正式 `playFile()` 不传 `skipAudioFocusRequest`，`AUDIO_FOCUS_DENIED` 可映射为明确中文提示，并覆盖 iOS `AVAudioSession.interruptionNotification` / interruption began 停止播放 / `notifyOthersOnDeactivation`；同样临时 hook 下全量 `flutter --no-version-check test --no-pub --no-test-assets -r expanded` 335 个测试通过；`flutter --no-version-check analyze` 无问题；临时 hook 下 `flutter --no-version-check build apk --debug --no-pub` 和 `flutter --no-version-check build ios --debug --no-codesign --no-pub` 均构建通过；不加 hook 直接 Android 构建当前会因 GitHub sqlite3 Android native asset 下载超时失败；Pixel 8 静音原生播放、长音频和替换播放三条 smoke 复验通过；测试 WAV 改为 zero-filled 静音 PCM，避免真机测试发出“嗯嗯”声；正式 `pubspec.yaml` / `pubspec.lock` 已恢复且不保留 hook |
| 2026-07-05 | 无限上下文预算控制回归：`flutter test test/model_context_budget_test.dart test/context_builder_test.dart test/chat_provider_context_limit_test.dart test/chat_provider_audio_test.dart`、`flutter analyze`、`flutter test` | 局部 18 个测试通过；覆盖模型预算推断、未知模型 8K 保守回退、旧 OpenAI 小窗口模型保守预算、长上下文模型动态提高压缩阈值、预算模式超过旧 20 条上限、小预算裁剪但保留最新用户问题、上下文超限错误识别 / 用户提示、语音转写链路未回退；静态检查无问题；全量 318 个测试通过 |
| 2026-07-03 | Markdown v2 与 iOS 系统 Speech 兜底回归：`flutter test test/markdown_rendering_test.dart`、`flutter analyze`、`flutter test`、`git diff --check`、`flutter build ios --release` | Markdown 局部 4 个测试通过，全量 305 个测试通过；行内 code 保持行内，fenced code 仍为代码块；用户输入 / AI 输出统一 Markdown 渲染；旧式 / HTML 图片、Mermaid / Draw.io 新老格式均有回归；fallback 引擎可在在线 STT 失败或空结果后继续尝试 iOS 原生 Speech；iOS release 构建成功；people iPhone 当前 `unavailable`，覆盖安装被设备离线状态阻塞 |
| 2026-06-27 | OpenAI Relay Responses API 局部测试与 benchmark：`flutter test test/openai_compatible_relay_server_test.dart test/openai_relay_benchmark.dart` | 当前 relay 局部 25 个测试通过；覆盖 `/v1/responses` buffered 输出、多模态 input 解析、`item_reference` 安全降级、`stream=true` SSE lifecycle / in_progress / failed 事件输出、Chat Completions 流内安全 error、流式失败 audit `upstream_error`、CORS 预检；历史 benchmark 中 `/v1/responses` 100 次平均约 3.14 ms |
| 2026-06-27 | OpenAI Relay benchmark 脚本：`scripts/benchmark_openai_relay.sh` | 通过；`/v1/responses` 100 次平均约 1.59 ms，健康检查约 1.91 ms，CORS 预检约 1.24 ms，聊天补全约 1.41 ms |
| 2026-07-07 | 国产模型预设局部回归：`scripts/smoke_full_stability_gate.sh -r expanded test/model_provider_preset_test.dart` | 5 个测试全部通过；先红灯确认百度千帆 / 讯飞星火、Kimi / SiliconFlow、火山方舟 / 腾讯混元预设缺失，再补 `qianfan`、`xfyun-spark`、`moonshot`、`siliconflow`、`volcengine-ark` 与 `tencent-hunyuan` 六个 OpenAI 兼容渠道预设，覆盖协议、Base URL、文档链接和 openAiCompatible 标记 |
| 2026-07-07 | 全球 OpenAI 兼容模型预设局部回归：`flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/model_provider_preset_test.dart -r expanded` | 8 个测试全部通过；新增测试先红灯确认 `groq` / `mistral` / `together` / `fireworks` 缺失，再补四个预设，覆盖 `openai_chat`、Base URL、`openAiCompatible` 和推荐模型名；本轮继续新增 `xai` / `perplexity` / `deepinfra` 红灯确认缺失，修复后补 xAI、Perplexity、DeepInfra 三个 OpenAI 兼容渠道预设，覆盖公共 Base URL、协议、`openAiCompatible` 和建议模型名 |
| 2026-07-07 | 批量渠道导入预设 ID / 显示名 / 短别名局部回归：`flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/model_channel_importer_test.dart -r expanded` | 9 个测试全部通过；新增测试先红灯确认只填 `presetId=groq` 会报“缺少 name”，修复后自动补 Groq 渠道名、Base URL、`openai_chat` 协议并保留用户自己的 API Key / 模型列表；再补大小写不敏感回归，确认 `provider=Groq` 也能匹配 `groq`；补显示名回归，确认 `provider=Mistral AI` 能匹配 `mistral`；补短别名回归，确认 `provider=Kimi` 能匹配 `Kimi / Moonshot AI`；最后补未知预设诊断脱敏，确认误填 `sk-...` 不会出现在错误消息 |
| 2026-07-07 | 批量导入单渠道对象根 JSON：`ModelChannelImportParser`、`model_channel_importer_test.dart` | 旧导入器只接受根数组或 `{"channels":[...]}`，从文档复制一个渠道对象会报“导入 JSON 必须是数组，或包含 channels 数组”；新增 `parses single channel object at root` 先红灯复现，修复后根 JSON 为单个渠道对象时按 1 个渠道解析，并继续支持 preset 自动补名称 / Base URL / 协议；设置页 helper 文案同步改为“支持渠道对象、数组或 {"channels": [...]}”。验证：聚焦红灯后转绿；批量导入 / 设置页 / 预设相关回归 `flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/model_channel_importer_test.dart test/settings_page_channel_import_test.dart test/model_provider_preset_test.dart -r expanded` 31 项通过。 |
| 2026-07-07 | 批量导入单模型字段简写：`ModelChannelImportParser`、`model_channel_importer_test.dart` | 旧导入器要求 `models` 必须是数组，复制单模型模板时 `model` 字段会被忽略、`models: "..."` 会报错；新增 `parses single model shorthand fields` 先红灯复现，修复后支持 `model` / `modelName` / `defaultModel` 单模型字段，以及 `models` 单字符串 / 单对象，设置页 helper 文案同步提示“单模型可用 model/modelName”。验证：聚焦红灯后转绿；批量导入 / 设置页 / 预设相关回归 `flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/model_channel_importer_test.dart test/settings_page_channel_import_test.dart test/model_provider_preset_test.dart -r expanded` 32 项通过。 |
| 2026-07-07 | 批量渠道导入预设显示名斜杠空格容错：`model_provider_preset.dart`、`model_channel_importer_test.dart` | 新增 `matches provider preset display name with slash spacing differences` 先红灯确认 `provider=Kimi/Moonshot AI` 会报“未知厂商预设”；修复后 `findModelProviderPreset()` 对 lookup 值统一忽略大小写、首尾空格和 `/` 两侧空格差异，`Kimi/Moonshot AI` 可匹配 `Kimi / Moonshot AI` 并自动补渠道名、Base URL 与协议。验证：红灯后转绿；`flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/model_channel_importer_test.dart test/settings_page_channel_import_test.dart test/model_provider_preset_test.dart -r expanded` 23 项通过。 |
| 2026-07-07 | 设置页厂商预设文档链接复制：`_ProviderPresetHint`、`settings_page_channel_import_test.dart` | 厂商预设提示卡片原本只展示 docsUrl，用户需要手动选中复制；新增“复制文档链接”按钮，复制 `preset.docsUrl` 并提示“文档链接已复制”，方便用户申请 API Key 或查官方模型名。新增 `provider preset hint copies provider docs link` 先红灯于找不到按钮，修复后 `test/settings_page_channel_import_test.dart` 7 项通过。 |
| 2026-07-07 | 设置页厂商预设 Base URL 复制：`_ProviderPresetHint`、`settings_page_channel_import_test.dart` | 预设提示卡片已能复制建议模型名和文档链接，但公共 Base URL 仍需用户手动选中；新增“复制 Base URL”按钮，复制 `preset.baseUrl` 并提示“Base URL 已复制”，降低手动配置和外部调试成本。新增 `provider preset hint copies provider base url` 先红灯于找不到按钮，修复后聚焦用例通过；批量导入 / 预设相关回归 `flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/settings_page_channel_import_test.dart test/model_channel_importer_test.dart test/model_provider_preset_test.dart -r expanded` 30 项通过。 |
| 2026-07-07 | 批量导入默认预设示例：`_showBatchChannelImportDialog`、`settings_page_channel_import_test.dart` | 批量导入弹窗旧默认模板仍要求用户手填 `name/baseUrl/protocol` 和示例 `api.example.com`；新增 `batch import dialog defaults to preset-based example` 先红灯确认缺少 `presetId=groq`，修复后默认 JSON 使用 `presetId: "groq"`、用户自己的 Groq Key 和推荐模型名，并把 helper 文案改为说明 `presetId/provider` 可自动补名称、Base URL 和协议。目标设置页测试 8 项通过。 |
| 2026-07-07 | 批量导入安全示例 JSON 复制：`_showBatchChannelImportDialog`、`settings_page_channel_import_test.dart` | 新增“复制示例 JSON”按钮，复制固定 `presetId: "groq"` 安全模板并提示“示例 JSON 已复制”；按钮不读取用户编辑区内容，避免用户已粘贴真实 API Key 后误复制外泄。新增 `batch import dialog copies safe preset example json` 先红灯于找不到按钮，修复后聚焦用例通过；批量导入 / 预设相关回归 `flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/settings_page_channel_import_test.dart test/model_channel_importer_test.dart test/model_provider_preset_test.dart -r expanded` 27 项通过。 |
| 2026-07-07 | 批量导入安全示例 JSON 恢复：`_showBatchChannelImportDialog`、`settings_page_channel_import_test.dart` | 新增“恢复示例”按钮，用户把导入框改坏或误粘贴真实 Key 后可恢复固定 `presetId: "groq"` 安全模板并提示“已恢复示例 JSON”；恢复动作覆盖为占位 Key，不保留编辑区真实 API Key。新增 `batch import dialog restores safe preset example json` 先红灯于找不到按钮，修复后聚焦用例通过；批量导入 / 预设相关回归 `flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/settings_page_channel_import_test.dart test/model_channel_importer_test.dart test/model_provider_preset_test.dart -r expanded` 28 项通过。 |
| 2026-07-07 | 批量导入剪贴板粘贴：`_showBatchChannelImportDialog`、`settings_page_channel_import_test.dart` | 新增“粘贴剪贴板”按钮，移动端从外部复制渠道 JSON 后可直接填入导入框；剪贴板为空时提示“剪贴板没有可粘贴的 JSON”，有内容时填入并提示“已从剪贴板粘贴 JSON”。新增 `batch import dialog pastes json from clipboard` 先红灯于找不到按钮，修复后聚焦用例通过；批量导入 / 预设相关回归 `flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 test/settings_page_channel_import_test.dart test/model_channel_importer_test.dart test/model_provider_preset_test.dart -r expanded` 29 项通过。 |
| 2026-06-27 | 模型管理局部回归：`flutter test test/channel_dao_test.dart test/settings_page_channel_import_test.dart` | 5 个测试全部通过；覆盖渠道 / 模型删除引用清理、一键测试并剔除不可用模型 |
| 2026-06-27 | 静态检查：`flutter analyze` | 无问题 |
| 2026-06-27 | 全量测试：`flutter test` | 286 个测试全部通过 |
| 2026-06-27 | 移动端 smoke：`scripts/smoke_mobile_main_flow.sh` | 4 个 smoke 全部通过，脚本内置 `flutter analyze` 无问题 |
| 2026-06-27 | Android release 真机安装：`flutter build apk --release` + `adb -s 37101FDJH0077P install -r build/app/outputs/flutter-apk/app-release.apk` + `adb shell monkey` | Pixel 8 覆盖安装成功并启动；包名 `com.aichat.ai_chat_app`，版本 `1.0.0` |
| 2026-06-27 | iOS release 真机安装：`flutter run -d 00008110-0016349A3A20A01E --release --no-resident` + `xcrun devicectl device process launch` | iPhone13 release 安装并启动成功；Bundle ID `com.aichat.aiChatApp`；未使用 debug 模式 |
| 2026-06-27 | Android 构建：`flutter build apk --debug` | 通过，生成 debug APK |
| 2026-06-27 | iOS 构建：`flutter build ios --simulator --no-codesign` | 通过，生成 simulator Runner.app |
| 2026-06-27 | 安全 / 格式复核 | `git diff --check` 无输出；生产代码目标无 `print/debugPrint`、无本机绝对路径 / 本机文件 URL；生产与文档高置信密钥字面量扫描未发现真实密钥 |
| 2026-07-02 | 应用身份 / Markdown / 字体局部测试：`flutter test test/app_identity_test.dart test/settings_provider_test.dart test/markdown_rendering_test.dart test/data_export_share_platform_test.dart test/microphone_permission_manifest_test.dart` | 13 个测试全部通过，覆盖 Android / iOS 应用身份、字体范围、扩展 Markdown、平台通道路径 |
| 2026-07-02 | 静态检查：`flutter analyze` | 无问题 |
| 2026-07-02 | 全量测试：`flutter test` | 289 个测试全部通过；同步修复 `test/dreaming_provider_test.dart` 的日期敏感断言，显式固定消息时间为 2026-06-27 |
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

> **P1 进行中补充（2026-07-14）**：Android 86400 秒跨日自然调度任务已安全进入等待，目标 dayKey `2026-07-15`、job id `0`；当前仅完成基础设施、短延迟两阶段验证、主动 cleanup 验证和真实任务调度，仍待次日独立 verify。跨日校验状态已从易失的 `/tmp` 迁移到 `.omx/state` 并恢复当前任务。非计费网络与充电约束的真机阻塞 / 满足后放行均已通过。iOS BGTaskScheduler 真机系统执行仍受设备直接确认的 `backgroundRefreshStatus=denied` 阻塞；设置页已可打开系统设置并重新检查，但系统开关开启后的任务执行尚未验证。Android 长时间 Doze、OEM 严格后台限制仍未验证。

| 优先级 | 待办 | 说明 |
| --- | --- | --- |
| P0 | 移动端真机主链路冒烟 | 已完成 Pixel 8 覆盖安装与启动、专用 72 条长会话显示、手动 Dreaming / Reflection 弹窗和短期提示预览、mock OpenAI 真实发送 / SSE 回复 / 重试 / 停止慢流 / 历史搜索 / 模型切换与切换后发送验证，并新增可重复真机集成发送、设置页、复杂 Markdown 滚动、base64 语音发送、OpenAI 兼容 STT 网络、真实录音按钮、OpenAI 兼容 TTS 网络、原生音频播放通道、长音频播放完成和播放替换 / 中断 smoke 脚本；Android 真机集成发送已通过，其余新增 smoke 当前已在 Pixel 8 通过；iPhone13 release build / install / launch / 进程可见已通过（`scripts/smoke_ios_release_install_launch.sh`，pid `79321`），iOS debug integration 不再作为有效证明；Android 原生播放已补音频焦点基础处理，iOS 原生播放已补 AVAudioSession 中断开始停止播放，二者通过代码级回归、全量测试、Android / iOS Debug 构建和 Pixel 8 三条静音原生音频 smoke 复验；iOS release 发送链路已通过 `scripts/smoke_ios_release_send.sh` 在 people 设备补证；Android Wi-Fi / data 断开 → 恢复 smoke、airplane mode 断开 → 恢复 smoke、Home 后台 → 前台恢复 smoke 已在 Pixel 8 通过；前台网络断开会取消所有已加载 streaming 会话并在联网恢复后提示显式重试 / 重试全部，代码级回归已通过，且 Android Wi-Fi / data 与 airplane mode 物理断网 streaming 取消 smoke 已在 Pixel 8 通过；iOS release 后台恢复入口 / 脚本已在 iPhone13 通过，runId `ios-release-background-20260707100131`，suspend/resume 后 `status=passed`，最终恢复普通 release 并启动 pid `80007`；iOS release 网络恢复 fake connectivity harness / 脚本入口已补，具备安装前解锁预检和普通 release 恢复路径；people 锁屏阻塞作为历史边界保留；后台切出时取消所有已加载 streaming 会话流式请求、保留错误条、恢复前台时弹出一次“可点重试 / 重试全部继续”提示，并通过 SharedPreferences 列表 marker 支持冷启动后恢复可重试提示，marker 指向非当前自动选中会话时会先切回该会话、指向不存在会话时会清理 marker，并已支持列表 marker 恢复多条待重试会话、数量提示、读写侧重复 / 空 marker 清洗、主动重试 DAO 兜底和“重试全部”显式用户动作；Android 设备内真实慢流取消 smoke 已通过，确认不会落库 assistant 半截回复；Android 音频焦点丢失 debug-only 设备 smoke 已从直接 listener 模拟推进到 competing AudioFocus 系统仲裁路径并在 Pixel 8 通过，且外部 helper APK 抢占系统音频焦点 smoke 已通过；真实来电 / 闹钟 / 第三方媒体播放器抢占仍待复验；仍需补 iOS release 手工 UI 停止 / 重试 / 模型切换、真实云端 STT / TTS 长音频、真实第三方播放器 / 来电 / 闹钟音频焦点抢占、iOS 真机音频中断、iOS 物理网络切换、iOS 后台恢复复跑和后台未完成请求真机恢复队列等交互验证 |
| P1 | Dreaming iOS 系统后台与 Android 长时间可靠性 | Android WorkManager v1 已完成代码、原生构建和 Pixel 8 JobScheduler 强制 / 自然 / 短时强制 deep idle / UI 进程死亡后跨小时自然调度真机验证；非计费网络与充电约束的阻塞 / 满足后放行均已通过；仍需 iOS BGTaskScheduler 真机执行、Android 跨日与长时间 Doze、OEM 严格后台限制 |
| P1 | 无限上下文与反思增强 | 已有模型窗口预算裁剪、动态压缩阈值、基础压缩、本地记忆、Dreaming 明确任务语气 task 记忆候选、本地反思 v1、默认关闭且失败回退本地规则的可选模型增强反思 v1、反思未回复会话提醒、反思会话追问压力提醒、反思重复追问提醒、反思最新任务推进提醒、反思最后一问未答提醒、敏感标题降级与最后用户问题安全片段、反思来源新鲜度入口提示、反思历史 v1、可关闭的反思短期提示注入、Pixel 8 72 条 seed 长会话 Dreaming/Reflection 基线、仅保留历史记录且禁止重跑的本地模型证据，以及一个外部配置驱动远程模型三个 dayKey 的 72 条长会话 3 / 3 质量门禁；仍需更多远程模型族、多日真实会话、压缩质量评估和模型驱动画像增量分析 |
| P1 | OpenAI Relay 真机 / 长时间运行 | 当前本地测试、构建和 benchmark 已过；仍需真实移动端网络、局域网、客户端兼容性验证 |
| P2 | 社交平台接入 | Telegram / Discord / 飞书 / WhatsApp / Slack / 微信公众号 / QQ Bot v1 已落地（2026-08-07，`ChannelAdapter` + `WebhookChannelAdapter` 抽象）；命令白名单仍待实现 |
| P2 | 多源 Skills 市场 | SkillHub + 通用 HTTP 技能源 v1 已落地（2026-08-07）；腾讯市场待确认开放 API |
| P3 | Notion / 语雀 / 思源 / 云备份 | Obsidian 链路较完整；Notion / 语雀 / 思源同步 v1、WebDAV / S3 / OneDrive 云盘备份 v1 已实现（2026-08-07）；双向同步待实现 |
| P3 | 数字孪生 | 用户画像 v1、人格配置 / 媒体信号 v1、替身回复显式授权与聊天入口、替身审计日志落库、数字人直播 v1（脚本 + RTMP 配置 + 会话记录）均已实现（2026-08-07）；深度语义分析与应用内推流仍待实现 |


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
| `docs/README.md` | 文档中心、权威关系、推荐阅读顺序、专题导航和维护规则 |
| `docs/current-status.md` | 当前代码状态、本轮修复、验证门禁和未完成 runtime 证据 |
| `docs/local-model.md` | Ollama 本地模型配置、`gemma4` 默认勾选、协议稳定性和故障排查 |
| `docs/verification-baseline-2026-08-08.md` | 当前静态分析、测试、构建、mock smoke 和真实 runtime 边界 |
| `docs/mobile-mcp-skills-memory-quality-2026-08-08.md` | Pixel 8 / iPhone13 移动端 MCP、Skills、记忆逻辑与真实 UI 稳定性证据 |
| `docs/mobile-mcp-skills-memory-local-device-2026-08-09.md` | Pixel 8 / iPhone13 的 MCP / Skills / 记忆纯本地真机验收：App Native MCP、真实 SQLite 重开、Key Point 隔离 key、UI 可见性 |
| `docs/mobile-node-mcp-runtime-2026-08-09.md` | 移动端纯 JS Node-Mobile MCP 运行验收：内置 runtime、stdio-compat-v1 / legacy npx adapter、拒绝外部进程 |
| `docs/MCP_BUNDLED_NODE_RUNTIME.md` | Android / iOS / PC 内置 Node Runtime 矩阵、进程边界、真机验证状态 |
| `docs/MOBILE_MCP_RUNTIME.md` | 移动端 MCP 运行时边界（App Native / 移动兼容 stdio / SSE / 内置 Node） |
| `docs/MOBILE_EXTENSIONS.md` | 移动端 MCP / Skill / Agent 扩展包安装协议与真机证据 |
| `docs/deep-linking.md` | 深度链接方案与 release 真机验证 |
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
| `docs/chat-composer-multimodal.md` | ChatGPT 风格 Composer、多文件、参考图、视频 / 音频 / 音乐生成和通用媒体接口 |
| `docs/multimodal-mode-navigation.md` | 移动端聊天 / 图片 / 视频 / 语音一级模式切换与能力驱动工作区 |

| `docs/archive/` | 2026-06-27 ~ 2026-07-14 的单次真机 / 协议 / 稳定性验证归档（33 份，主链路、Dreaming / Reflection、音频、网络、Relay 协议、测试稳定性等），均为带日期的历史证据，当前结果以 `docs/verification-baseline-2026-08-08.md` 为准 |
| `docs/dwchainless-relay-integration-2026-08-07.md` | DW Chainless 中转站预置、注册引导、一键接入、关于页鸣谢与测试记录 |
| `docs/implementation-gap-analysis-2026-08-07.md` | 所有未完成功能项的差距分析与实施计划（标注已实现 / 需真机补证 / 需外部资源） |
| `docs/requirements.md` | 产品需求总纲、核心模块、阶段规划、页面需求、隐私安全原则 |
| `docs/database.md` | SQLite / drift 表结构、DAO 职责 |
| `docs/ai-protocols.md` | OpenAI / Claude / Gemini / Ollama 等协议适配 |
| `docs/infinite-context.md` | 滚动压缩、摘要生成、令牌估算 |
| `docs/ui.md` | 历史界面设计文档 |
| `docs/MCP_RUNTIME_CONTAINERIZATION.md` | MCP 运行时 / 旁车容器化方案 |

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
| MED-6 | 已修复：通知 ID 不再固定为 0，回复通知和 Dreaming 通知统一使用 `buildStableNotificationId(namespace, key)` 生成跨运行稳定正整数 ID | 2026-06-27 Dreaming 前台到期系统通知调度 v1，`test/notification_service_test.dart` 覆盖同输入稳定、不同 namespace / key 不同、ID 范围合法 |
| MED-11 | 已修复：删除渠道 / 模型前会先清空 `sessions.defaultChannelModelId` 与 `messages.channelModelId` 引用，再删除模型和渠道，避免已有会话或消息导致删除失败 | 2026-06-27 渠道 / 模型删除引用清理，`test/channel_dao_test.dart` 与 `test/settings_page_channel_import_test.dart` 覆盖 |

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

这是一个 Flutter 全平台人工智能聊天应用；移动端展示名为 `SimiAIChat`，Android / iOS 包名为 `top.simitalk.aichat`。Dart 包名暂保留 `ai_chat_app`，主要 Dart 代码位于 `lib/`；Flutter 测试统一位于 `test/` 根目录（约定见 `test/README.md`）；真机集成测试位于 `integration_test/`；实现文档位于 `docs/`。

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
