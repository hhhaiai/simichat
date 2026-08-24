# 当前项目状态

> **更新时间：2026-08-24**
>
> 本文档是当前状态的快速事实摘要。项目目标、长期待办和历史账本以根目录 `AGENTS.md` 为准；安装和使用入口以根目录 `README.md` 为准；具体实现方案以本目录专题文档为准；本次验证命令与结果以 `verification-baseline-2026-08-08.md` 为准；移动端 MCP / Skills / 记忆专项以 `mobile-mcp-skills-memory-quality-2026-08-08.md` 和 `mobile-mcp-skills-memory-local-device-2026-08-09.md` 为准；Node-Mobile 最新构建与真机边界以 `mobile-node-mcp-runtime-2026-08-09.md` 为准。

## 一、当前结论

| 范围 | 当前结论 | 证据边界 |
| --- | --- | --- |
| 默认文字模型 | 未选择、空绑定或失效绑定时从已启用 Chat 模型中回退 `gpt-5.3-codex-spark`；有效显式选择保持不变；新会话持久化同一 `channelModelId` | Pixel 8 Production Release 新建对话未开选择器即显示 `gpt-5.3-codex-spark`，真实发送 `Reply only OK` 返回 `OK`，结果标注同一模型 |
| 客户端长期上下文 | `gpt-5.3-codex-spark` 使用 128K 保守窗口、115200 最大输入、57600 压缩阈值；旧 summary 与旧原文滚动合并，最新 10 条保留原文，所有原始消息仍本地永久保存；超限后一次 65% 严格裁剪重试 | 滚动摘要、原文保留、single-flight、摘要与最新问题预算、超限识别均有代码回归；尚未用真实 spark 跨越一次完整压缩周期做事实召回质量门禁，不能称为上游无限 token |
| 图片质量 / 比例 / 清晰度 / 分辨率 | 四个摘要独立可选；`resolution` 只保存 `1K/2K/4K` 清晰度，`size` 只保存 `width x height` 像素分辨率；模型切换、校验、wire、重试和恢复均分别处理 | Widget、loopback wire、任务快照及 Pixel 8 Production Release UI 已验证两个维度独立存在。真机联合请求成功交付，但请求 `size=1536x1024` 实际得到 `1387x1134`，provider 执行像素尺寸失败；完整参数差分尚未执行 |
| Dart / Flutter 代码 | 已完成本轮本地模型修复及相关整理 | 静态分析通过 |
| 本地 Ollama 配置 | 已支持无 API Key，自动获取模型时默认勾选 `gemma4` | 设置页、模型预设、模型列表选择逻辑有回归覆盖 |
| Ollama 协议 | 已处理 NDJSON、thinking/content、取消、超时、非 200 响应和可选 Bearer 鉴权 | mock HTTP 协议测试通过 |
| 移动端 MCP | App Native、内置 Node-Mobile、标准 JSONL stdio session、SSE 生命周期和设置页入口已收口 | `test/mobile_stdio_transport_test.dart` 已覆盖真实 runtime-server 的 stdin/stdout 链路；Android Pixel 8 / iPhone13 均已通过 `SIMICHAT_MOBILE_STDIO_PROTOCOL_DEVICE_READY` |
| App Native MCP 真机运行 | 在 App 进程内完成 MCP 初始化、工具发现和 `simichat.runtime_info` / `simichat.now` 调用，不依赖外部环境 | Pixel 8 / iPhone13 各 1 项真实设备 smoke 通过 |
| Android 内置 Node MCP | APK 内置 `nodejs-mobile v18.20.4`、`arm64-v8a/libnode.so` 和 JNI bridge；MCP server 由 APK 内 Node 执行 | Pixel 8 真机 initialize、tools/list、runtime_info、echo 通过；当前只覆盖 arm64-v8a |
| PC 内置 Node MCP | App 只启动随包 Node binary，不回退宿主机 `node` / `npx` / Docker / Podman | bundled Node 真实进程 smoke 与 macOS Flutter App integration 通过；macOS/Xcode、Linux/CMake、Windows/CMake 将 binary 放入 App 安装目录；运行时输出 `SIMICHAT_DESKTOP_BUNDLED_NODE_MCP_READY` |
| Android / PC Node 文档 | 已补齐实现、生命周期、构建、平台矩阵和真实证据边界 | `docs/MCP_BUNDLED_NODE_RUNTIME.md`、`docs/runtime-manifest.example.json` |
| 移动端 Skills | 本地缓存恢复、package / entry SHA-256、原子安装、registry 重载、下载边界和搜索竞态已收口 | Pixel 8 / iPhone13 已直接安装本地 package bytes、启用并在 installer 重建后恢复；不依赖 Marketplace / HTTP |
| 移动端记忆 | Key Point、真实 SQLite 文件重开、FTS、semantic、SharedPreferences 重载、索引预热 / 修复和搜索竞态已收口 | Pixel 8 / iPhone13 纯本地真机 marker、全局搜索 UI 和各 175 项逻辑专项通过 |
| 移动端扩展包协议 | MCP / Skill / Agent 共用 manifest、SHA-256、权限 allowlist、原子安装、registry、quarantine；Skill / Agent / App Native MCP 已接入 shared provider | `test/mobile_extension_installer_test.dart` 通过；Android Pixel 8 / iPhone13 真机扩展包 smoke 均输出 `SIMICHAT_MOBILE_EXTENSIONS_APP_NATIVE_READY` |
| 内置渠道一键接入 | 选中厂商预设后名称 / Base URL / 协议由预设锁定，只保留 API Key 输入框；渠道列表与模型选择器按厂商品牌图标显示；SimiRouter 预设提示收敛为品牌、推荐模型和两个主动作 | 设置页回归测试覆盖预设锁定、隐藏字段、无地址文案与内置 H5 入口；`flutter analyze` 通过 |
| 识图 / 深度思考门禁 | 图片附件与深度思考都只路由本次请求，不永久改写会话默认模型；图片自动选当前渠道 Vision，无 Vision 时阻止并保留图片 / 输入；深度思考自动选 reasoner，无 reasoner 时阻止并保留输入；Vision 与 Reasoner 可重叠判定，短代号与上下文预算按分隔符匹配；显式 embedding 否决宽泛名称提示，reasoner 纳入聊天模型查询 | Widget / DAO / context budget 回归覆盖支持 / 不支持分支、默认模型不变、reasoner-only 渠道、embedding / 短代号误判保护、显式 Reasoner 元数据与重叠能力；OpenAI Chat `image_url` / Responses `input_image` 的 MIME + 完整 base64 loopback 回归通过 |
| SimiRouter AI 中转站 | 渠道卡收敛为未接入 / 缺 Key / 已接入紧凑三态；官网 / 获取 Key 使用内置 H5，同 origin 默认持久 WebView profile 复用 Cookie、localStorage、IndexedDB 和磁盘缓存；短生命周期预热共享 JS/CSS；Android Cookie flush、iOS 默认 data store 完成屏障及尾随 flush 竞态收口；语音接入精确识别的 mimo TTS 三模式 + mimo ASR，声音克隆 WAV 复制到 App 私有持久目录，TTS 合成阶段拒绝重复并发请求；历史大写 MIMO 配置正确回显内置预设 | 320px / 120% 字号、44px 点击目标、严格 URI、关闭 / 返回、预热 / flush、STT / TTS / 图片 / 能力路由均有 host 回归；全量基线 757 项、最终能力聚焦 123 项、Analyze、Android / iOS Release 构建通过；本轮按要求未安装或执行真机账号登录闭环 |
| 渠道额度查询 | 设置页每个非 SimiRouter 渠道的展开面板提供手动“查询额度 / 刷新”；Claude OAuth 复用 CCSwitch 使用的 `GET /api/oauth/usage`（5 小时 / 7 天窗口与重置时间），OpenAI 兼容 / new-api 复用 `/dashboard/billing/usage` + 可选 `/dashboard/billing/subscription`；不自动遍历渠道、不保存额度响应 | `test/channel_quota_client_test.dart` 3 项、设置页与额度客户端 focused 回归通过；Pixel 8 Production Release 已覆盖安装并保持正式包 `firstInstallTime` / `dataDir` 不变；真实 Claude OAuth 账号仍需用户在设置页点按“查询额度”补证 |
| 媒体模式模型选择 | 图片 / 视频 / 语音模式的顶部模型抽屉与窄屏 PopupMenu 只展示当前工作区支持能力；聊天模式仍保留完整模型目录与媒体配置快捷入口 | 模型选择器聚焦 8 项通过；Pixel 8 图片模式 UI Automator 只见 Image 图片生成模型，不见 Chat / TTS / ASR；Production Release 覆盖安装 parity verified |
| CI 跨平台构建门禁 | Flutter 源码在包构建前生成、bundled runtime 矩阵可移植、桌面与 Android 包构建可复现，跨平台 package build 门禁已收口 | CI 构建门禁通过 |
| iOS 纯 JS MCP | NodeMobile bridge、device / simulator XCFramework、App link/embed 和 iPhone13 真机链路已接入 | iPhone13 已出现 `SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY`、`SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY`、`SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY`；状态为 `runtime_verified` |
| Android 构建 | Debug / release APK 构建通过 | `build/app/outputs/flutter-apk/app-debug.apk`、`build/app/outputs/flutter-apk/app-release.apk` |
| 通用媒体任务 | 图片 / 视频 / 音乐的异步任务持久化、固定渠道模型、lease claim、进程重启恢复和本地文件 / 消息 / 附件幂等交付已落地 | schema 11、媒体恢复 / 快照 / AppBootstrap 定向测试通过；使用 fake adapter / 内存 SQLite，真实厂商媒体 E2E 和 Android 冷启动恢复仍未证明 |
| TTS / 声音设计 / 声音克隆 / STT | 单一 Composer 的四类任务面板、设置渠道绑定、typed 参数、时间线结果、失败草稿保留和 Android 播放已闭环；非 MP3 扩展名跟随 `response_format`，200 JSON/HTML 错误体不落盘；SimiRouter MP3 clone 使用实机验证的 `audio/mp3` subtype；STT `auto` 在 multipart / JSON fallback 均省略语言 | Pixel 8 Production Release 已分别完成 `mimo-v2.5-tts` MP3/WAV、`mimo-v2.5-tts-voicedesign`、WAV/MP3 `mimo-v2.5-tts-voiceclone`、`mimo-v2.5-asr` auto/zh/en 真实 Provider E2E，并完成 Android `MediaPlayer` started/completed、Audio Focus 和按钮恢复；短音频链路 `[PARITY VERIFIED]`，长音频、弱网、批量压力和 iOS Provider E2E 待补 |
| 实时语音 | ChatGPT 风格面板、OpenAI / xAI / 自定义 WebSocket 配置、Bearer / ephemeral 凭据、文本 fallback、转写与回答状态、停止 / 断开和加密配置持久化已接入；Android 原生 PCM v1 已接入 `AudioRecord` / `AudioTrack`，iOS 原生 PCM 仍待接入 | `test/realtime_voice_provider_test.dart`、`test/realtime_voice_panel_test.dart`、`test/realtime_voice_session_test.dart`、`test/realtime_pcm_audio_test.dart` 共 19 项 focused 通过；Pixel 8 `mobile_realtime_pcm_smoke_test.dart` 已验证非空 16 kHz PCM 采集、24 kHz PCM 播放和停止生命周期；不能以这些证据替代真实 Realtime WebSocket / 云端回答 |
| Rerank 重排 | `ModelCapability.rerank` 能力标记（推断先于 embedding，聊天选择器 / vision / reasoner 否决）；`lib/core/ai/rerank_client.dart` 走 `/v1/rerank`，单解析器兼容 Jina / Cohere / OpenAI 兼容线格式并按分数降序；模型测试播放按钮接入 30 秒连通性测试；添加模型对话框加 Rerank 能力与名称自动推断；Jina / Cohere 厂商预设 | `test/model_capability_test.dart`、`test/rerank_client_test.dart`、`test/model_channel_importer_test.dart` 回归通过；未做真实 Jina / Cohere 云端 E2E |
| 会话置顶 / 新对话按钮 | schema 13 新增 `sessions.is_pinned`（ALTER TABLE 迁移，快照往返向后兼容）；侧边栏"已置顶"分组置于日期分组之上，弹出菜单置顶 / 取消置顶（文件夹内会话不提供）；侧边栏新增全宽"新建对话"按钮（移动端点击后收起抽屉） | `test/sidebar_test.dart` 覆盖置顶排序、菜单翻转与新对话建会话；`media_job_persistence_test.dart` 修正 schema 硬编码后全量通过；未做真机 UI 取证 |
| 自动会话标题 | 首条回复后后台生成标题（首条用户消息概括、30 秒超时、30 字符截断、在途防重、写前复查防覆盖手动重命名）；fork 会话标题不受影响 | 代码路径容错（失败静默），未做单测；真实标题质量未验证 |
| 测试 | 当前全量 Flutter 测试 1235 项通过；默认模型、滚动摘要、图片参数 UI / wire、媒体恢复 / 快照 / AppBootstrap 和语音四能力回归均包含在内 | JSON reporter 为 `done.success=true`、0 error，随后独立 compact 再次 1235 / 1235；更早一次 compact 曾出现未定位且未复现的 `+1234 -1`，未计为通过；analyze / diff check 通过；语音四能力另有当前 SimiRouter / Pixel 8 短音频真实 E2E，不能外推到其它 Provider 或长音频压力 |
| 本机真实 Ollama | 当前未验证 | 本机没有 `ollama` 命令，`127.0.0.1:11434` 当前不可连接 |
| 真机 / 长会话 | Pixel 8 已完成默认 spark 的真实短对话；客户端滚动摘要仅完成代码门禁 | 真实 57600-token 以上长期会话、摘要冲突与事实召回仍待验证，不能由短对话、mock 或 APK 构建替代 |
| Android 16 KB page-size / 非 arm64 ABI | source ELF 与 release APK 已完成；真机 / 非 arm64 仍未完成 | 重建后的 `arm64-v8a/libnode.so` 四个 `LOAD` segment 均为 `0x4000`，release APK 全部 native library 与 ZIP 16 KB audit PASS；16 KB 真机和非 arm64 仍未支持 |
| Android Node watchdog | 已实现代码边界 | native state / exit code、single-flight、最多一次启动重试已补齐；长时间锁屏后台仍需 Foreground Service 真机证据 |

### 0.6 2026-08-24 TTS、声音设计、声音克隆与语音识别最终复验

- `mimo-v2.5-tts` 的 MP3 与 WAV 均由真实 Provider 返回并写入会话；WAV 文件是 RIFF/PCM 16-bit、mono、24 kHz、2.24 秒，证明请求 `response_format=wav`、本地 `.wav` 扩展名、真实容器和 Android 解码保持一致。
- `mimo-v2.5-tts-voicedesign` 使用独立文本、声音风格、1.00x 和 MP3 生成 24 kHz / 1.968 秒结果；Android `MediaPlayer` 从 started 到 completed，播放按钮和 Audio Focus 正常收敛。
- `mimo-v2.5-tts-voiceclone` 先用 WAV 参考音频完成生成；随后对同一条此前在 `audio/mpeg` 下连续超时的 1.968 秒 MP3 做差分，改用 SimiRouter-compatible `audio/mp3` data URI 后数秒成功，生成 MP3 可完整播放。该结果排除了“参考音频过短”，将问题收窄为网关临时上传扩展名兼容。
- `mimo-v2.5-asr` 已用真实生成音频完成 `auto / zh / en` 三条路径，返回 `Voice clonistability test.`；独立“识别语音”时间线包含原 audio、ready sidecar 和 assistant 转写，audio-only 联合发送也会先识别再把语音内容交给当前 Chat 模型。
- 修复包括：TTS 非 MP3 扩展名一致、HTTP 200 JSON/HTML/text 错误体拒绝、参考音频 MIME 明确映射、SimiRouter MP3 clone subtype、STT multipart 失败后的 JSON data URI fallback，以及 `auto` 在两条 STT wire 路径均省略。
- 语音影响面 27 个测试文件 **179 / 179 通过**；最终修复聚焦 **39 / 39 通过**；完整 Flutter JSON reporter **1235 / 1235** 后独立 compact 再次 **1235 / 1235**；更早一次 compact 的 `+1234 -1` 因输出截断未形成可定位证据且后续未复现，保留为全仓库潜在 flake 边界，不把它伪装成通过。analyze 与 diff check 通过。Production Release 已在 Pixel 8 覆盖安装，APK/设备 SHA-256 均为 `c9c8eb30d4a6e96d98ed7a8f35228517c9a7f6f543f15b62d2717183b139f60c`，`ANDROID_RELEASE_PARITY status=verified`，`firstInstallTime` / `dataDir` 不变。
- 当前结论仅覆盖本次短音频、当前 Provider 配置与 Pixel 8；长文本/长音频、网络中断、并发批量、iOS Provider 播放及真实来电/闹钟/第三方播放器焦点抢占仍未完成。

### 0.4 2026-08-24 默认模型、长上下文与图片参数 Android 最终复验

- 图片清晰度 / 像素分辨率拆分后的全量命令 `flutter --no-version-check test --no-pub --no-test-assets -j 1 -r compact` 最终 **1230 / 1230 通过**；图片参数等聚焦回归 **96 / 96 通过**，`flutter --no-version-check analyze --no-pub` 为 `No issues found`，`git diff --check` 无输出。
- `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 覆盖安装拆分后的 Production Release：`ANDROID_RELEASE_PARITY status=verified`，构建包与设备 APK SHA-256 均为 `7130a5042c01b3df99e8655dca86e8b8f47517f82e67baed824be270f544b4e9`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 不变，安装后 PID `20256`。
- 默认模型真机链路：新建对话、不点击模型选择器，顶部胶囊显示 `gpt-5.3-codex-spark`；发送 `Reply only OK`，真实结果 `OK`，结果卡标注 `SimiRouter AI 中转站 / gpt-5.3-codex-spark`。
- Production Release UI Automator 已确认图片面板中“清晰度 · 2K”和“分辨率 · 1536x1024”同时存在且均可点击；两个抽屉的选项分别为 `自动 / 1K / 2K / 4K` 与 `自动 / 1024x1024 / 1536x1024 / 1024x1536`，高级设置同步保留两个值。
- 真机在可用 `gpt-image-2` 渠道提交 `resolution=2K + size=1536x1024` 后从“正在生成图片…”进入“已生成图片”，时间线新增结果及约 1.4 MB 图片附件。下载 PNG 为 `1,447,276 bytes`、`1387x1134`，SHA-256 为 `110c1dcff303c18e881b44a8b13261f903869abc3e16cfb01706bcb924ec4396`。客户端两个字段的 UI、snapshot、loopback wire 和结果交付为 `[PARITY VERIFIED]`；真实 provider 对请求像素尺寸的执行为 `[PARITY BROKEN]`。
- 本轮只执行了 `resolution + size` 联合请求，未执行 baseline / resolution only / size only / ratio only 的完整 provider differential；不能把一次生成成功扩写为所有图片参数均被上游遵守。
- 长上下文边界：客户端滚动摘要和严格裁剪已完成代码级门禁；本轮只做了 spark 短对话 E2E，没有人为制造 57600-token 以上真实会话，长期摘要质量继续保留未验证状态。

### 0.5 2026-08-21 多模态协议联动、额度与 Android Release 最终复验

- 设置页已有渠道现在是图片、视频、TTS、声音设计、声音克隆、STT 的唯一路由来源：顶部模型、工具工作区模型、实际请求模型、Base URL、API Key 和 `channelModelId` 保持一致；切换视频 / 音乐模型时同步写入 profile、endpoint 和 task options，避免沿用上一个媒体渠道。
- 模型目录获取后的新增模型会按能力自动测试：Chat、Embedding、Rerank、图片、TTS、ASR 分别走对应探测；视频 / 音乐和需要参考输入的声音任务明确跳过并保留模型。添加确认 SnackBar 不会被自动测试提示覆盖。
- 已接入用户提供的 OpenAI-compatible 图片、xAI Grok 图片 / 视频、`/v1/audio/speech` / `/v1/audio/tasks`、`/v1/audio/transcriptions`、音色查询和账号额度协议；SimiRouter 卡片同时显示消耗额度与账号额度，失败诊断在设置页收敛为单行可读提示。
- 图片工作区只显示图片能力模型。顶部胶囊使用可缩放模型名并固定保留向下箭头；Pixel 8 真机点击图片后显示 `grok-imagine-image-lite`、图片任务标签及箭头，未见 Chat / TTS / ASR 模型。底部输入框点击后 Android 输入法正常弹出，光标和键盘布局随窗口调整。
- 最终门禁：`flutter --no-version-check analyze --no-pub` 无问题；全量 `flutter --no-version-check test --no-pub --no-test-assets` **1193 项通过**；`git diff --check` 无输出。
- Pixel 8 `37101FDJH0077P` 已通过 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 覆盖安装正式包 `top.simitalk.aichat`：`ANDROID_RELEASE_PARITY status=verified`，APK / 设备 `base.apk` SHA-256 为 `b251b5e74164f770644872c3c2d04cdeedc1b70ab40607a5eed560819f95e2e0`，签名证书 SHA-256 为 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 不变，安装后 PID `23259`；正式包未卸载、未清空数据，隔离包检查为 clean。

### 0. Android production Release 覆盖安装与模型切换真机复验（2026-08-18）

- 当前工作树通过 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 重新构建并使用 `adb install -r` 覆盖安装到 Pixel 8 `37101FDJH0077P`。
- `ANDROID_RELEASE_PARITY status=verified`；构建 APK 与设备 `base.apk` SHA-256 均为 `4c129d2ac4b9e4fbcf310f8f950081447ff58f2042f7c455f8221b25fcb34247`，签名证书 SHA-256 为 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`。
- `firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持不变；`lastUpdateTime=2026-08-18 10:02:22`，PID `25256`，前台 Activity 为 `top.simitalk.aichat/.MainActivity`。
- 模型切换隔离 smoke `scripts/smoke_device_integration_model_switch.sh 37101FDJH0077P` 已在 Pixel 8 通过：四个 marker 按顺序出现，`selectedModelId`、SQLite 会话默认模型和 `model_switch` system message 均从 `model-switch-first` 切到 `model-switch-second`；隔离包 `top.simitalk.aichat.modelswitch` 已清理，正式包 APK path / hash / `firstInstallTime` / `dataDir` 未变。
- 模型切换脚本现具备：固定当前工作树 APK 路径、`aapt` applicationId preflight、隔离包已存在时拒绝覆盖、正式 `base.apk` 完整 path / hash 保护、唯一日志和 marker 顺序 / 唯一性校验。Production Release UI Automator 同时确认展开并滚动 `+` 菜单后可见 `生成视频`、`声音合成`、`声音克隆`、`声音设计`、`生成音乐`，未配置渠道 / TTS 时各入口保持禁用并展示明确原因。上述证据是本地 / mock smoke 与 UI / SQLite 真机证据，不等同于真实 OpenAI、xAI、Gemini、Claude、视频、音乐、TTS、声音克隆或 Realtime 云端 E2E。

### 0.1 当前工作树最终 Android 覆盖安装（2026-08-18）

- 在最后一组 Composer 声音克隆参考音频优先级修改完成后，先执行完整格式、静态分析、focused 回归和全量测试，再执行 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P`。
- 本次 `adb install -r` 覆盖安装返回 `Success`；`ANDROID_RELEASE_PARITY status=verified`。构建 APK 与设备 `base.apk` SHA-256 均为 `f7d43858f7d4292eb538189c99bb631294c92ad21ac36b64907c861fb3cb1556`，签名证书 SHA-256 为 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`。
- 安装前后 `firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持不变；安装后 `lastUpdateTime=2026-08-18 11:08:00`、`versionName=1.0.0`、`versionCode=1`、PID `28329`，启动组件为 `top.simitalk.aichat/.MainActivity`。正式包未卸载、未清空数据、未执行 `am force-stop`，隔离包检查为 clean。
- 该安装 / 启动证据只证明当前 production APK 已覆盖安装并可启动，不把本地协议测试、fake adapter、loopback 或 UI 菜单证据描述为真实第三方云端媒体 / 语音 E2E。

### 0.2 最新 Production Release 覆盖安装与模型切换隔离 smoke（2026-08-18 12:09）

- 在 Pixel 8 `37101FDJH0077P` 上再次执行 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P`。脚本重新构建当前工作树 `app-production-release.apk`，使用 `adb install -r` 覆盖安装并返回 `Success`；`ANDROID_RELEASE_PARITY status=verified`。
- 构建 APK 与设备 `base.apk` SHA-256 均为 `cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d`；签名证书 SHA-256 为 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`。
- 安装后正式包 `top.simitalk.aichat` 仍为 `versionName=1.0.0` / `versionCode=1`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持不变，`lastUpdateTime=2026-08-18 12:09:37`，PID `32261` 可见，前台组件为 `top.simitalk.aichat/.MainActivity`。正式包未卸载、未清空数据、未执行 `am force-stop`。
- 随后执行 `scripts/smoke_device_integration_model_switch.sh 37101FDJH0077P`。隔离包 `top.simitalk.aichat.modelswitch` 以 `install -r -d` 安装并在 smoke 后清理；四个 marker `SIMICHAT_MODEL_SWITCH_BASELINE`、`SIMICHAT_MODEL_SWITCH_UI_ACTION`、`SIMICHAT_MODEL_SWITCH_DB_EVIDENCE`、`SIMICHAT_MODEL_SWITCH_SMOKE_PASS` 均按顺序出现，`All tests passed` / `SMOKE_TEST_EXIT status=0`，正式包 hash、安装时间和数据目录保持不变，隔离包无残留。
- 当前工作树全量 Flutter 测试 `1030 tests passed`，`flutter --no-version-check analyze --no-pub` 为 `No issues found!`，`git diff --check` 无输出。Composer、媒体任务、STT / TTS、Gemini Live 和 Realtime PCM 的本地测试 / loopback / fake adapter 证据仍不等同于真实 OpenAI、xAI、Gemini、Claude、Ollama、图片 / 视频 / 音乐、云端语音或声音克隆 E2E。


### 0.3 SimiRouter 主打完善轮（2026-08-19）

- 用用户提供的 SimiRouter 测试 Key 对真实上游完成回环验证：`/v1/models`（32 模型、无能力元数据）、chat（mimo-v2.5-chat / gpt-5.4）、TTS（mimo-v2.5-tts alloy 中文）、ASR（mimo-v2.5-asr auto/zh 回环）、生图（gpt-image-1.5 b64_json）、图片编辑（`/v1/images/edits` multipart）、`mimo-v2.5-chat` 真实照片识图、视频路由（`/v1/videos` 存在，`/v1/videos/generations` 为 Invalid URL）、`/v1/realtime` 路由、账单（`/v1/dashboard/billing/usage` + `subscription`，new-api 格式）。结论写入 `docs/simirouter-mimo-v2.5-chat-multimodal.md`。
- 修复：SimiRouter 推广卡紧凑化（logo 缩小、不再遮挡下方内容）；模型一键测试按能力分派（image→生图探测、TTS→语音探测、video/music/ASR 跳过不误删）；一键剔除改为确认对话框 + 只剔永久性失败（401/403/404/协议不支持），临时失败保留并提示；小三角测试按钮改为 40px 目标 + spinner + 防并发 + 结果图标；获取模型按名称去重、能力变化就地更新、远端下架模型提示不删；视频默认端点改为 `/v1/videos`。
- ChatGPT 风格图片交互：生成中 in-chat 占位消息（spinner / 失败可重试 / 可取消，stop 按钮路由取消）；图片气泡显式编辑按钮、查看器编辑入口、图片消息"重新生成"走图片接口（含参考图回放）；生图尺寸选择（1024/1536/auto，记住上次，编辑对话框同款）。
- 百度 CDN 图床：`BaiduCdnImageUploader`（与 imgtool.py 同协议），图片气泡/查看器手动上传按钮（复制 URL），设置开关"生成后自动上传图床"。
- 展示层：HTML 页面工件卡片（应用内 WebView 预览 + 复制 + 下载）、代码块下载按钮、Markdown 行内链接外开、搜索结果紧凑卡片样式；深度思考折叠（既有，流式/完成态均默认收起）验证保留。
- 视频生成 per-request 弹窗：显式参考图选择 + 时长 / 分辨率可选参数（extra 透传）；STT 单次语言选择（麦克风长按 auto/zh/en，一次生效）。
- SimiRouter 专属：渠道卡已接入态显示用量行（已用 / 限额 + 刷新）；Realtime 面板新增 SimiRouter 预设（`wss://api.dwchainless.com/v1/realtime`，Bearer，模型名用户填）；能力推断修正（gpt-5 全系 vision、`mimo-v2.5-pro-chat` 纳入精确 Vision 例外）。
- 门禁：全量 Flutter 测试 1121 项通过，`flutter analyze` 无问题，`git diff --check` 通过。本轮未做真机安装与 UI 取证；视频 / 音乐 / Realtime 的真实云端质量仍需真机 + 真实 Key 补证。



### 0.4 Android 真机覆盖安装与真机交互取证（2026-08-19）

- `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 重建当前工作树 release APK，`adb install -r` 覆盖安装 `Success`，`firstInstallTime=2026-08-18 07:11:12`、`dataDir` 保持不变；monkey 启动 `top.simitalk.aichat/.MainActivity` 成功。
- 真机 UI 取证（uiautomator）：设置页 SimiRouter 推广卡紧凑展示且不遮挡下方渠道列表；**用量行以真实 Key 拉取成功**（“已用 $0.16 · 未设限额”，与上游 `/v1/dashboard/billing/usage` 80141.1968 quota 换算一致）；Composer `+` 菜单包含 生成图片/生成视频/深度思考/实时语音对话 等全部入口，未配置 TTS 时声音合成/克隆禁用并展示原因。
- 真机 E2E：Composer 输入提示词 → 生成图片 → 尺寸选择 bottom sheet（1024x1024/1536x1024/1024x1536/auto）→ 发出真实请求 → 上游返回 503 → 占位消息转为“图片生成失败 + 重试”，重试路径再次请求并保持可重试；生成视频 per-request 弹窗（提示词预览 + 时长 + 分辨率 + 取消/开始生成）验证通过；logcat 无 FATAL。
- 真实图片成功生成被上游 503 阻塞（gpt-image 渠道临时不可用），成功路径的云端 E2E 仍待上游恢复后补证；iPhone13 真机本轮未连接，已通过 iOS unsigned Release 构建（90.1MB）作为编译门禁。



### 0.5 模型选择器与媒体能力标签修复（2026-08-19）

- 修复模型选择器语义标签把 `MapEntry(...)` 对象字符串拼进文案的 bug（`'$entry.key / model'` 插值错误），长字符串曾直接覆盖模型行。
- 模型选择器展示全部已配置模型：TTS / STT / 生图 / 视频等媒体模型可见并带能力标签（Audio 音频 / Image 图片生成 / Video 视频），置灰不可选；按 (渠道, 模型名) 去重，优先保留媒体能力行。
- 目录推断策略更新：中转站 `/v1/models` 无能力元数据时，按精心维护的前缀表推断媒体能力（grok-imagine-image*、grok-imagine-video、gpt-image-*、mimo-v2.5-tts*、-asr、whisper-*、wan-video 等）；请求门禁仍只信显式元数据，两层互不影响。
- 获取模型时修复历史数据：远端同名行能力就地更新；本地独有行按名称重新推断并修正 chat 误标；旧版"按能力+名称"重复行自动清理（chat 与媒体行并存时删 chat 行）。
- 真机验证（Pixel 8）：重新构建覆盖安装后触发"自动获取模型"，选择器中 grok-imagine-image-lite/quality → Image 图片生成、gpt-image-1.5/2 → Image 图片生成、grok-imagine-video → Video 视频、mimo-v2.5-tts*/asr → Audio 音频，无重复行与 MapEntry 垃圾文本。全量 1122 项测试通过。



### 0.6 媒体模型可点击配置（2026-08-19）

- 模型选择器中的媒体模型（生图 / TTS / STT / 视频 / 音乐）从置灰改为可点击：点击不再切换聊天模型，而是把该模型写入对应工具配置并提示——生图 → 图片生成配置、TTS / STT 按名称分派到语音合成 / 识别配置、视频 / 音乐 → 通用媒体接口路由。TTS / STT / 媒体 notifier 新增 `applyModel` / `applyMediaModel` 快捷 setter（只改模型名并持久化，不动其它字段）。
- 媒体行显示 tune 图标与语义提示"点击配置到对应工具"；聊天模型行为不变。
- 真机验证（Pixel 8）：点击 gpt-image-1.5 后设置 → 图片生成配置的模型已变为 gpt-image-1.5，会话默认聊天模型未变。全量 1122 项测试通过。


## 二、本轮修复逐项记录

### 0. ChatGPT 风格实时语音面板、Android 原生 PCM 与覆盖安装（2026-08-18）

- 新增 `lib/core/media/realtime_voice_models.dart`、`lib/core/media/realtime_voice_session.dart`、`lib/shared/providers/realtime_voice_provider.dart` 和 `lib/shared/widgets/realtime_voice_panel.dart`。
- `ChatInputBar` 的 `+` 菜单新增「实时语音对话」。面板支持 OpenAI / xAI / 自定义 `wss://` endpoint、模型、音色、Bearer / ephemeral 凭据、文本 fallback、输入 / 输出转写、输出音频帧统计、停止回答、断开和配置保存；token 只以加密形式落盘。
- 面板在未连接时明确提示“连接后可开启原生 PCM”；普通麦克风仍是录音文件 → STT → 聊天，不把文件录音伪装为实时流。
- 新增 `lib/core/media/realtime_pcm_audio.dart`、provider / panel 的原生音频生命周期，以及 Android `MainActivity.kt` 中 `simichat/realtime_pcm_audio` MethodChannel / EventChannel；Android 使用 16 kHz mono PCM16 `AudioRecord` 采集和 24 kHz mono PCM16 `AudioTrack` 播放，不写录音文件。
- Pixel 8 `37101FDJH0077P` 执行 `scripts/smoke_device_integration_realtime_pcm.sh`，处理权限后 `mobile_realtime_pcm_smoke_test.dart` 通过，验证原生播放、采集到非空 PCM chunk 和停止清理。
- 随后再次执行 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P`：当前 schema 11 / 媒体恢复变更构建出的 Release APK 81.8 MB，`adb install -r` 返回 `Success`；覆盖安装后 `firstInstallTime=2026-08-18 05:44:07`、`dataDir=/data/user/0/top.simitalk.aichat` 未变化，`lastUpdateTime=2026-08-18 06:50:58`，PID `9969` 可见，当前 APK SHA-256 为 `b9fd1df18479748d3b3e1a60323e213aada0ccb6a485dfd200a7da0878df3729`。
- UI Automator 取证确认启动页显示 `SimiAIChat`、`未选择模型`、`添加附件`、`语音输入`。没有外部 API Key，本轮未宣称真实 Realtime WebSocket / 视频 / 音乐 / 云端 TTS / STT E2E 成功；iOS 原生 PCM、真实云端 Realtime 和长任务媒体质量仍待补证。

### 1. Ollama API Key 可选

- `modelProtocolRequiresApiKey('ollama')` 返回 `false`。
- 设置页显示 `API Key（可选）`。
- 空密钥通过 `KeyEncryptor.decryptOrEmpty()` 读取。
- 非空密钥仍然严格解密，损坏密钥不会被静默吞掉。
- 批量导入和设置页使用同一个协议判断，避免入口之间出现不同规则。

对应文档：

- `README.md`
- `local-model.md`
- `ai-protocols.md`

对应测试：

- `test/key_encryptor_test.dart`
- `test/model_provider_preset_test.dart`
- `test/model_channel_importer_test.dart`
- `test/settings_page_ollama_test.dart`

### 2. Ollama 默认勾选 gemma4

- Ollama 自动获取模型时传入 `preferredModel: 'gemma4'`。
- 默认选择逻辑由 `ModelFetcher.defaultSelectedModelIds()` 统一实现。
- 支持 `gemma4`、`gemma4:latest` 和其他 `gemma4:*` tag 变体。
- 云端渠道没有传入首选模型，继续默认勾选全部新模型。
- Ollama 推荐模型顺序为：`gemma4`、`qwen3:4b`、`llama3.2:3b`。

对应代码：

- `lib/core/ai/model_fetcher.dart`
- `lib/features/settings/settings_page.dart`
- `lib/core/ai/model_provider_preset.dart`

对应测试：

- `test/ollama_protocol_test.dart`
- `test/model_provider_preset_test.dart`

### 3. Ollama 协议稳定性

- 连接超时：15 秒。
- 流式空闲超时：5 分钟。
- CancelToken 取消时关闭 HTTP client。
- `/api/tags` 和 `/api/chat` 均支持可选 Bearer 鉴权。
- 保留 `message.thinking` 和 `message.content`。
- malformed NDJSON 不输出完整模型响应。
- 错误正文限制长度，避免异常响应无限增长。

对应代码：

- `lib/core/ai/ollama_protocol.dart`
- `lib/core/ai/model_fetcher.dart`

### 4. 本地模型验证入口

真实服务验证入口：

```bash
ollama pull gemma4
ollama serve
OLLAMA_MODEL=gemma4 scripts/smoke_local_ollama.sh
```

脚本只验证已经运行的服务，不会自动启动、停止或修改 Ollama。

不同运行环境的 Base URL：

| 环境 | Base URL |
| --- | --- |
| macOS / Linux / Windows 桌面端 | `http://127.0.0.1:11434` |
| iOS Simulator | `http://127.0.0.1:11434` |
| Android Emulator | `http://10.0.2.2:11434` |
| Android / iOS 真机 | Ollama 主机的局域网 IP |

### 5. 内置渠道一键接入（仅填 Key）与厂商品牌图标

- 内置渠道（厂商预设）一键接入：选中预设后名称、Base URL、协议由预设锁定，表单只保留 API Key 输入框；切换回“自定义渠道”才显示完整可编辑字段。
- 编辑已匹配内置预设的渠道时同样进入锁定模式，下拉框可切回自定义配置，不影响已有自定义改动。
- 渠道列表、模型选择器和预设提示卡按厂商显示独立图标（如 DeepSeek 闪电、Groq 快闪、硅基流动内存芯片、火山方舟火山），不再让所有 OpenAI 兼容渠道共用同一个协议图标。

对应代码：

- `lib/core/ai/protocol_icons.dart`
- `lib/features/settings/settings_page.dart`
- `lib/shared/widgets/model_selector.dart`

对应测试：

- `test/settings_page_font_scale_test.dart`（预设锁定后只留 API Key）
- `test/settings_page_ollama_test.dart`（Ollama 预设无 Key、名称 / Base URL 隐藏）
- `test/settings_page_dwchainless_test.dart`（一键接入锁定 dwchainless 预设）

### 6. SimiRouter AI 中转站品牌升级

- `dwchainless` 预置渠道显示名改为「SimiRouter AI 中转站」；Base URL、官网、注册地址保持 `api.dwchainless.com` 不变，`id` 保持 `dwchainless`，旧配置与批量导入不受影响。
- 新增品牌 logo `assets/branding/simirouter.png`（`pubspec.yaml` 注册）；渠道列表、模型选择器、预设提示卡与关于页鸣谢均优先显示真实 logo，无 logo 的厂商回退 Material 图标。
- 推广卡片已进一步收敛：未接入显示一句定位和「获取 Key / 一键接入 / 官网」；缺 Key 显示「补充 Key」；已接入只显示状态和「管理 / 官网」。六项营销标签不再常驻设置页首屏；三个操作在 320px / 120% 字号下保持单排、整卡小于 170px、按钮点击高度至少 44px。
- 设置页出现时用短生命周期隐藏 WebView 预热官网资源，后续官网 / 注册页复用系统 WebView 资源缓存和登录 profile；H5 主帧仅允许同 host / port HTTPS 且拒绝 userInfo，非主帧验证码 / iframe 不被误拦，拒绝跳转时给用户明确反馈。
- 登录态由系统 WebView 默认持久 profile 原样维护；Android 关闭 / 后台时显式 `CookieManager.flush()`，iOS 使用 `WKWebsiteDataStore.default()`。重复 flush 会合并，关闭最多等待 2 秒；不再手工序列化认证 Cookie，避免丢失 Secure / HttpOnly / SameSite / expires 等安全属性；当前线上 bundle 的账号资料缓存位于同 origin localStorage。

对应代码：

- `lib/core/ai/model_provider_preset.dart`（`logoAsset` 字段）
- `lib/core/ai/protocol_icons.dart`（`getChannelLogoAsset`）
- `lib/features/settings/settings_page.dart`（推广卡片、渠道 tile、提示卡、鸣谢）
- `lib/shared/widgets/model_selector.dart`
- `lib/shared/widgets/in_app_h5_page.dart`、Android `MainActivity.kt`、iOS `AppDelegate.swift`（默认持久 profile 与原生 flush）

对应测试：

- `test/settings_page_dwchainless_test.dart`（卡片按钮、一键接入锁定、已接入 / 缺 Key 状态、鸣谢）
- `test/model_provider_preset_test.dart`（logoAsset 断言）
- `test/settings_page_channel_import_test.dart`、`test/mobile_main_flow_smoke_test.dart`（卡片变高后的滚动适配）

### 7. Rerank 协议落地、会话置顶与新对话入口（2026-08-18）

- 多对话 / openai / claude / gemini / grok 与生图 / 视频 / 音乐 / TTS / STT / 向量化经核查均已存在：多对话 = Sessions 表 + 侧边栏历史列表；Grok 维持 xAI 预设走 OpenAI 兼容协议，不新增独立协议代码（用户决策）。
- Rerank 完整落地：`ModelCapability` 新增 `rerank` 能力（normalize / 名字推断 / 聊天选择器否决 / vision+reasoner 否决 / 标签），推断顺序先于 embedding（`bge-reranker` / `gte-rerank` 同时命中 embedding 前缀）；`RerankClient` 走 `/v1/rerank`，单解析器兼容 Jina / Cohere / OpenAI 兼容线格式并按分数降序；模型测试播放按钮接入 30 秒连通性测试；添加模型对话框加 Rerank 能力与名称自动推断；新增 Jina / Cohere 预设（Jina 无 `/v1/models`，预设描述注明手动添加）。
- 会话置顶：schema 13 新增 `sessions.is_pinned`（ALTER TABLE 迁移即时无损；快照 export / restore 往返，旧快照默认 false）；`SessionDao.setPinned` 与 `getAllSessions` 置顶优先排序；侧边栏"已置顶"分组置于日期分组之上，弹出菜单置顶 / 取消置顶（文件夹内会话不提供置顶入口）。
- 侧边栏图标行下新增全宽"新建对话"按钮（移动端点击后收起抽屉）；AppBar "+" 保留。
- 自动标题精修：空标题也触发；在途防重；写前复查防覆盖手动重命名；改用首条用户消息（400 字截断）；30 秒总超时；30 字符截断；fork 会话标题不受影响。
- `media_job_persistence_test` 修正两处 schema 硬编码：期望版本 11→13；模拟 v8 老库时移除 v8 后新增的 `capabilities` / `is_pinned` 列，避免迁移重复加列（v12 引入 capabilities 时该隐患已存在，本轮一并修复）。

对应代码：

- `lib/core/ai/model_capability.dart`、`lib/core/ai/rerank_client.dart`（新建）
- `lib/core/ai/model_tester.dart`、`lib/core/ai/model_provider_preset.dart`（Jina / Cohere 预设）
- `lib/core/database/tables.dart`、`app_database.dart`（schema 13）、`dao/session_dao.dart`
- `lib/shared/widgets/sidebar.dart`（置顶分组 / 新对话按钮）
- `lib/shared/providers/chat_provider.dart`（标题精修）
- `lib/core/archive/local_database_snapshot.dart`（`is_pinned` 往返）
- `lib/features/settings/settings_page.dart`（Rerank 能力下拉 + 名称自动推断）

对应测试：

- `test/model_capability_test.dart`（rerank 推断 / 否决 / 标签）
- `test/rerank_client_test.dart`（新建，三种线格式 + 排序 + 异常）
- `test/model_channel_importer_test.dart`（rerank 能力导入保留）
- `test/sidebar_test.dart`（新对话建会话、置顶分组排序、置顶 / 取消置顶）
- `test/media_job_persistence_test.dart`（schema 硬编码修正）

## 三、当前验证门禁

```bash
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
flutter --no-version-check build apk --debug
git diff --check
bash -n scripts/smoke_local_ollama.sh
```

本次结果详见：

```text
docs/verification-baseline-2026-08-08.md
```

移动端 MCP / Skills / 记忆专项结果：

```text
docs/mobile-mcp-skills-memory-quality-2026-08-08.md
```

内置 Node Runtime 专项：

```text
docs/MCP_BUNDLED_NODE_RUNTIME.md
```

当前已复现的专项命令：

```bash
SIMICHAT_MCP_RUNTIME_PORT=37651 ./scripts/smoke_bundled_node_runtime.sh
```

移动端扩展包协议与安装器：

```text
docs/MOBILE_EXTENSIONS.md
lib/core/extensions/
lib/shared/providers/mobile_extension_provider.dart
test/mobile_extension_installer_test.dart
```

预期输出：

```text
SIMICHAT_DESKTOP_BUNDLED_NODE_PROCESS_READY
```

## 四、尚未完成的真实证据

以下项目不能仅凭当前测试标记为已完成：

- 本机真实 `gemma4` 权重是否已安装并能完成推理；
- 首次加载模型的耗时和首 token 延迟；
- 长上下文、Dreaming、Reflection 的本地模型质量；
- Android Emulator、Android 真机、iOS Simulator、iOS 真机的真实网络访问；
- 移动端后台、锁屏、系统资源限制和长时间运行；
- 模型内存 / 显存占用和并发容量。
- Android / iOS 扩展管理页面的真实文件选择器 UI、应用重启后的扩展 registry 恢复和发布包升级回滚仍需单独补证。
- Android Pixel 8 与 iPhone13 已完成扩展包运行时 smoke：Skill SHA-256、启用、Agent `gemma4` plan、App Native MCP initialize / tools/list / tools/call、Agent 卸载均通过；尚未覆盖文件选择器 UI 和真实发布包升级恢复。
- iOS `runtime=node-mobile` 纯 JS MCP 的长时间运行、后台资源限制、升级恢复和更多非 arm64 发布设备仍需单独补证；本轮 iPhone13 的 framework / health / tools/list / tools/call 已通过。

这些项目必须在真实环境中补证，并在新的带日期验证记录中记录，不修改历史验证文档的原始结论。

## 五、当前工作树边界

本轮内置 Node Runtime 变更包含 Android native bridge、PC bundled runtime controller、
manifest、准备 / smoke 脚本、集成测试和文档；Android native library 使用 Git LFS。
平台构建生成的 macOS SwiftPM / CocoaPods 文件不属于本功能源变更，提交前应清理并
在 `git diff --check` 后确认工作树边界。工作树状态不能直接等同于“可发布提交”。

整理文档时只新增或更新入口、状态和专题说明，不删除未跟踪实现文件，不把静态测试结果写成真机成功。

## 2026-08-23 顶部媒体模型与 Composer 发送路由修复

- 修复顶部选择 `mimo-v2.5-tts` 等媒体模型后，活动会话和空会话的唯一 Composer 仍直接调用普通 `_handleSend` 的问题。两个生产发送入口现在统一读取 `creationModeProvider`、`voiceCreationToolProvider` 和对应能力状态，按图片、视频、TTS / ASR、声音设计 / 克隆、音乐或普通 Chat 分派。
- TTS 请求仍通过当前配置绑定的模型和 `/v1/audio/speech`（必要时 `/v1/audio/tasks`）发送；生成音频消息的 `channelModelId` 优先保存 TTS 配置的绑定 ID，时间线模型展示不再回退到旧文字 Chat 模型。
- 已通过 `flutter --no-version-check analyze --no-pub` 与媒体 / Composer 聚焦回归；真实 TTS 服务端音频质量和 Android 真机发送仍需使用已配置渠道单独复测。

## 2026-08-23 SimiRouter TTS 音色映射

- 设置页与聊天页 TTS 任务面板统一显示八种人类可读名称：冰糖/alloy、茉莉/echo、Mia/nova、Chloe/shimmer、苏打/onyx、白桦/fable、Milo/milo、Dean/dean。
- 下拉项的内部 value 和请求体保持原始 `voice` ID（`alloy`、`echo`、`nova`、`shimmer`、`onyx`、`fable`、`milo`、`dean`）；未知 / 自定义音色 ID 原样显示，不会被中文标签替换。
- `speech_provider_preset_test.dart` 覆盖八组映射、大小写归一化和自定义 ID 回退；设置页回归覆盖展开音色下拉后八项均可见。

## 2026-08-22 联合语音与统一 Composer 进展

- 已实现 audio + typed text 的单次聊天编排：发送前读取当前绑定 ASR / STT（默认 `mimo-v2.5-asr`）转写，转写成功后和文字合并到同一条 user message，再调用当前 Chat 模型；ASR 失败会阻止 Chat 请求并保留草稿。
- 同一条消息保留 audio attachment 与 transcript sidecar；重试复用已完成 sidecar，成功发送后 Composer 清除已消费语音附件。
- AppBar 的图片 / 视频 / 语音一级模式条和聊天区常驻媒体工作区已移除；文本、图片、视频、
  音频均从唯一底部 Composer 输入，媒体任务通过 `+` 菜单和发送前 bottom sheet 自动处理。
- Artifact 卡片编辑入口固定在右下角；HTML 可视化编辑支持点击文本组件、修改文字和 CSS 颜色；
  保存回调会回写当前时间线卡片草稿，返回后再次打开仍使用修改后的内容。
- 本轮已通过 `flutter --no-version-check analyze --no-pub`、全量 Flutter 测试 **1196 项**、
  `git diff --check` 和联合语音 / 附件清理 / Artifact 聚焦测试。
- Android release hook 已修复 stale `integration_test` registrant；Pixel 8 `37101FDJH0077P`
  已使用 `adb install -r` 覆盖安装正式包，`ANDROID_RELEASE_PARITY status=verified`，APK
  SHA-256 `2aabaa02d53df163451bdaa20f32a73c0d918d84c98542f4b770563b3ae051e4`，
  `firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 不变，
  启动 PID `31254`；真实 ASR / Chat 云端质量仍待外部凭据补证。
