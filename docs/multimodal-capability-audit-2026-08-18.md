# 多模态能力与交互入口审计（2026-08-18）

## 1. 审计范围与结论摘要

本次只读审计覆盖以下边界：

- ChatGPT 风格单一 Composer 的移动端 `+` 工具菜单、图片生成 / 编辑 / 参考图入口；
- 视频、音乐通用异步任务入口、配置门禁、轮询、取消、保存和恢复状态；
- 语音附件、STT、TTS、声音设计、声音克隆和 Realtime 语音入口；
- OpenAI Chat、OpenAI Responses、Claude、Gemini、Ollama 协议适配器，以及 xAI 的聊天、批量 Voice 和 Realtime 入口；
- 当前仓库已有的 loopback HTTP、fake adapter、Widget、Android 真机和 iOS 真机证据，重点区分它们不能证明的内容。

**结论**：当前代码已经能证明“用户在 Composer 中可以看到并触发一组多模态动作”，也能证明部分请求序列化、配置门禁、本地媒体任务状态机和本地文件交付逻辑；它不能据此宣称所有主流厂商、所有模型、所有视频 / 音乐异步服务或所有实时语音服务都已云端可用。本轮没有使用真实厂商 API Key，也没有把 fake adapter 或 loopback HTTP 升级为云端 E2E 证据。

本轮未修改业务代码，只新增：

- `test/multimodal_capability_contract_test.dart`
- `docs/multimodal-capability-audit-2026-08-18.md`

## 2. 证据等级与判定规则

| 等级 | 本仓库中对应证据 | 能证明什么 | 不能证明什么 |
| --- | --- | --- | --- |
| A | 实际 Widget 树、用户可点击的 `ListTile` / callback、已有设备 smoke | 用户可见入口、显示条件、禁用条件、设备侧通道边界 | 厂商云端成功、具体模型能力、配额和计费行为 |
| B | loopback HTTP、协议 loopback、fake adapter、内存 / 隔离 SQLite | 请求体、响应解析、SSE / NDJSON、状态机、取消和本地持久化逻辑 | 真实域名、真实鉴权、真实模型、真实编码器和供应商状态语义 |
| C | served asset / 当前源码 / registry / preset / active 配置 | 当前部署代码宣称的路由、协议和 wiring | 注释所描述的能力已经在运行环境或云端成立 |
| D | 本仓库已有 Pixel 8 / iPhone13 记录 | 特定设备上的录音、播放、UI、生命周期和原生通道 | 把一个设备上的 harness 结果扩展为所有厂商和所有平台 |
| E | 真实厂商 API / 真实本地 Ollama 服务的完整请求-响应 | 具体供应商、具体账号、具体模型和具体编码的 E2E | 本次没有 E 级证据，因此不能在本报告中给出云端支持结论 |

判定优先使用可运行的 Widget / 网络行为和已有设备记录；源码用于解释行为。`test/multimodal_capability_contract_test.dart` 的 Composer 部分只注入回调来验证用户入口和 callback boundary，没有调用云端，也没有伪造云端响应。

## 3. Composer 用户可见入口

### 3.1 移动端入口矩阵

`lib/shared/widgets/chat_input_bar.dart:431-650` 的 `+` 菜单在小屏上使用可滚动 BottomSheet。当前回调存在时，用户可看到：

| 用户入口 | 出现条件 | 关键行为 | 证据边界 |
| --- | --- | --- | --- |
| 相机拍照 / 从相册选择 | 移动端 | 选择后归档为 Composer draft 附件 | 证明 picker 与 draft 边界，不证明后续厂商读取成功 |
| 选择文件 | 所有平台 | 支持多选图片、视频、音频、PDF 和普通文件 | 普通附件能被保存，不代表每个协议能读取每种类型 |
| 实时语音对话 | `onRealtimeVoice != null` | 打开 Realtime 面板 | 入口存在不等于 WSS 握手、服务端音频事件或长时会话成功 |
| 编辑图片 | `onEditImage != null` | 优先使用当前已选图片，否则再次选择参考图 | 证明 UI 选择和 callback 边界，不证明 `/v1/images/edits` 成功 |
| 生成图片 | 图片回调存在且输入有文本 | 无参考图走生成；有 `onGenerateImageWithAttachments` 时传出第一张图片 | 证明用户动作和参考图选择，不证明图像供应商可用 |
| 生成视频 | `onGenerateVideo != null` 且输入有文本 | 可传第一张图片作为参考图 | 配置不满足时仍显示但禁用，并展示原因 |
| 声音合成 | `onSynthesizeSpeech != null` 且输入有文本 | 走当前 TTS 配置，可对应普通合成、声音设计或声音克隆 | 入口名称容易被误读为“已经有任意声音生成能力” |
| 生成音乐 | `onGenerateMusic != null` 且输入有文本 | 走通用音乐 endpoint | 配置不满足时仍显示但禁用，并展示原因 |

移动端的图片生成入口收在菜单内；宽屏时会出现 `generate-image-button` 主行按钮。视频、声音合成和音乐始终是菜单动作。`ChatInputBar` 还会因为 streaming、submitting、媒体任务 busy、录音中或输入为空而禁用相应动作。

### 3.2 ChatPage wiring

`lib/features/chat/chat_page.dart:1666-1697` 的普通会话 Composer 和 `:1852-1878` 的空会话 Composer 均接入了：

- `_handleGenerateImage` / `_handleGenerateImageWithAttachments`；
- `_handleGenerateVideo`；
- `_handleSynthesizeSpeech`；
- `_handleGenerateMusic`；
- `_handleEditImage`；
- `_openRealtimeVoicePanel`。

视频 / 音乐的 `videoActionDisabledReason` 和 `musicActionDisabledReason` 来自 `:1419-1436` 的当前会话模型和通用媒体配置计算，而不是仅由按钮是否有 callback 决定。因此“菜单中出现生成视频”与“当前模型、渠道和接口真的能生成视频”是两个不同事实。

### 3.3 本轮新增的入口回归

`test/multimodal_capability_contract_test.dart` 锁定了以下用户可见契约：

1. 390×844 移动尺寸下 `+` 菜单确实出现实时语音、编辑图片、生成图片、生成视频、声音合成和生成音乐；
2. 已配置回调时，图片、视频、声音合成、音乐和实时语音动作能到达各自 callback boundary；
3. 视频 / 音乐有明确 disabled reason 时仍保留入口，但 `ListTile.enabled == false` 且 `onTap == null`，不会调用 callback；
4. 能力矩阵和协议 registry 仅验证本地门禁与入口映射，不访问网络。

## 4. 图片生成、编辑和参考图

### 4.1 当前实际路由

`lib/shared/providers/chat_provider.dart:111-116` 的 `canUseChannelImageGeneration()` 只允许 `openai_chat` 和 `openai_response`。`generateImage()` / `editImage()` 在 `:1562-1697` 再次检查该门禁。

`lib/core/ai/image_generation_service.dart` 的当前请求边界是：

- 无参考图：`POST /v1/images/generations`，JSON 中包含 `model`、`prompt`、`n`、`size` 和 `response_format=b64_json`；
- 有参考图或编辑：`POST /v1/images/edits`，使用 multipart 的 `model`、`prompt`、`size` 和 `image`；
- 参考图生成复用编辑 endpoint，不把本地路径放进 JSON；
- 返回可解析 `b64_json`，或在安全的 HTTP(S) 限制下下载远端 URL；
- 生成结果写入应用私有目录，再以 assistant 图片附件回到会话。

Composer 只把已选附件中的第一张图片作为参考图；其余附件不会因为一次图片生成成功而被无条件清理。这个行为由现有 `test/chat_input_bar_image_generation_test.dart` 和本轮 Widget contract 共同锁定。

### 4.2 不应扩大的结论

- Claude、Gemini、Ollama 当前有普通聊天图片附件的序列化路径，但没有接入本项目统一的图片生成 / 编辑 user flow；
- OpenAI Chat / Responses 的图片输入能力不等于当前渠道能调用图片生成 endpoint；
- 一个模型名包含 `image`、`vision` 或 `gpt` 也不能替代实际 endpoint、Key、模型服务和返回格式验证；
- loopback 测试中的 `b64_json`、URL 下载和 multipart 成功只证明客户端 parser / serializer 与安全边界，不证明真实供应商返回相同字段。

## 5. 视频与音乐异步任务

### 5.1 能力门禁是“路由可配置”，不是“厂商已支持”

`lib/shared/providers/chat_provider.dart:118-234` 的 `resolveUniversalMediaCapability()` 依次检查：

1. 配置读取是否完成；
2. 当前会话是否有模型；
3. Base URL 是否存在；
4. 当前渠道 API Key 是否存在；
5. 视频 / 音乐模型和 endpoint 是否存在；
6. 协议是否为 `openai_chat` 或 `openai_response`；
7. 当前模型是否为 chat-compatible，或显式声明了对应 `video` / `music` 能力。

因此当前矩阵是：

| 协议 | 通用视频 / 音乐入口门禁 | 真实含义 |
| --- | --- | --- |
| `openai_chat` | 配置完整时可用 | 可把当前聊天渠道当作一个可配置的通用媒体 HTTP 路由；不代表 OpenAI 或该中转站已为该模型开通视频 / 音乐 |
| `openai_response` | 配置完整时可用 | 同上；只证明当前产品允许复用该协议渠道 |
| `claude` | 不可用 | 当前没有统一通用视频 / 音乐 route |
| `gemini` | 不可用 | 当前没有统一通用视频 / 音乐 route |
| `ollama` | 不可用 | 当前 Ollama 入口是本地聊天 / 图片输入协议，不是本项目通用媒体 route |

Chat、Vision、Reasoner 模型可以复用显式配置好的通用 route；专用 media-only 模型需要明确能力元数据。`ModelCapability.supportsVideoModel()` / `supportsMusicModel()` 不会因为模型名包含 `video` 或 `music` 就认定其具备专用媒体能力。本次新增测试也保留了这个边界：模型名本身不是专用视频能力证据，但 chat-compatible 模型仍可能因为产品配置而使用通用 route。

### 5.2 客户端状态机能证明的内容

`lib/core/ai/universal_media_service.dart`、`lib/core/media/media_job.dart` 和 `lib/shared/providers/universal_media_provider.dart` 已包含：

- 默认图片、视频、音乐 endpoint：`/v1/images/generations`、`/v1/images/edits`、`/v1/videos/generations`、`/v1/audio/music`；
- JSON / multipart 提交、参考图、Bearer 鉴权和 CancelToken；
- `pending`、`completed`、`failed`、`expired`、`cancelled` 状态；
- provider `job_id`、xAI 风格 `request_id`、poll URL、cancel URL、content URL 和多种常见返回字段；
- 有限轮询、deadline、最大 attempts、取消、远端媒体下载和本地大小限制；
- SQLite job、lease / claim、交付 ID、进程重启后的恢复和 message / attachment 幂等交付。

现有 `test/universal_media_service_test.dart`、`test/universal_media_job_test.dart`、`test/media_job_persistence_test.dart` 和相关 provider 测试证明了这些本地行为，包括 loopback 的 OpenAI 风格任务、xAI `request_id` 形状、取消和恢复。

### 5.3 仍然缺失的供应商证据

通用客户端不能替供应商定义协议。当前没有真实证据证明：

- `/v1/videos/generations` 和 `/v1/audio/music` 的任意真实服务接受当前请求字段；
- 每个服务的状态值、轮询地址、取消语义、鉴权范围和结果 URL 生命周期与 parser 假设一致；
- 视频编码（mp4 / webm 等）、音频编码、长时任务、远端 URL 鉴权和大文件下载在真机上可用；
- xAI、OpenAI 或任意中转站的真实视频 / 音乐模型、配额、账单和内容策略已被当前 UI 配置覆盖。

所以“生成视频 / 生成音乐”目前应表述为**已经有通用异步任务入口和本地交付状态机**，不应表述为“已经支持所有主流视频 / 音乐厂商”。

## 6. STT、TTS、声音设计、声音克隆和 Realtime

### 6.1 普通语音发送是 STT-first，不是所有协议的原生音频 E2E

`lib/shared/providers/chat_provider.dart:691-721` 会为带音频附件的消息选择已配置 STT、OpenAI-compatible STT fallback，必要时加入 iOS 系统 Speech fallback。`sendMessage()` 在 `:1377-1405` 先转写音频，再用转写结果构造“以下是语音转文字结果，请根据这个语音内容回答”的上下文。

这意味着：

- 用户可以录音、粘贴 base64 音频或选择音频附件；
- 音频归档和 transcript sidecar 是独立本地能力；
- 普通聊天用户链路的主要证明是 STT 成功后把文本交给模型，而不是每个协议都直接消费原生音频；
- `OpenAiChatProtocol` 虽然能序列化 native `input_audio` part，但不能把该 serializer loopback 测试误读为真实用户链路已经完成云端原生音频 E2E；
- `OpenAiResponseProtocol` 对音频附件明确抛出 unsupported，当前路径依赖先转写；
- Claude、Gemini 等协议对音频的处理取决于协议 serializer 和模型端能力，不能从普通附件入口推断所有 Claude / Gemini 模型都支持音频。

### 6.2 OpenAI-compatible STT / xAI batch Voice

`lib/core/media/openai_speech_to_text_engine.dart` 使用 multipart `/v1/audio/transcriptions` 并携带模型；`lib/core/media/xai_speech_to_text_engine.dart` 是独立的 xAI REST adapter，使用 `/v1/stt`，默认 multipart `file` 上传，不人为加入 `model` 字段。xAI adapter 代码和现有 `test/xai_speech_to_text_engine_test.dart` 证明的是请求构造、大小限制、响应解析和错误处理，不证明真实 xAI 账号 / 模型可用。

### 6.3 TTS、声音设计和声音克隆

`ChatInputBar` 的“声音合成”字幕已明确写出普通合成、声音设计和声音克隆，但入口本身只接收文本。具体模式来自 `lib/core/media/speech_provider_preset.dart` 与 `lib/shared/providers/text_to_speech_provider.dart`：

- `mimo-v2.5-tts`：普通合成；
- `mimo-v2.5-tts-voicedesign`：要求 `style` 风格描述；
- `mimo-v2.5-tts-voiceclone`：要求存在可读 WAV 参考音频，保存时复制到应用私有目录；
- xAI batch TTS 使用独立 `/v1/tts`，请求字段是 `text`、`voice_id`、`language`，不使用 OpenAI 的 `model` / `input` / `voice` / `response_format`；xAI 自定义声音需要单独的 `/v1/custom-voices` 流程，当前 batch TTS adapter 不代替该流程。

因此“声音克隆入口存在”只证明本地设置表单、参考 WAV 前置条件和请求 builder；不证明克隆质量、供应商声音创建、声音身份绑定或长音频结果已经在真实服务上通过。

### 6.4 设置文案是容易误读的边界

`lib/features/settings/settings_page.dart:4393-4418` 和 `:5209-5233` 的部分静态文案仍写成“OpenAI 兼容 STT / TTS”，但 preset 和 provider 已包含 xAI。运行时 `SpeechToTextConfig.providerLabel` / `TextToSpeechConfig.providerLabel` 可以显示 `xAI STT` / `xAI TTS`，所以静态设置文案与活体 provider 状态并不完全一致。本轮受写入范围限制没有改业务代码；该差异已在本报告记录，不能把静态文案作为 xAI 协议不存在的证据。

### 6.5 Realtime 入口

`lib/shared/providers/realtime_voice_provider.dart` 和 `lib/core/media/realtime_voice_session.dart` 分开支持：

- OpenAI Realtime：默认 `wss://api.openai.com/v1/realtime`；
- xAI Realtime：默认 `wss://api.x.ai/v1/realtime`；
- 自定义 Realtime：由用户提供 WSS endpoint、模型和 token；
- 文本 fallback、PCM 输入 / 输出、取消当前回答和 session 状态。

`test/realtime_voice_session_test.dart` 与 `test/realtime_pcm_audio_test.dart` 证明了协议事件归一化、取消和平台边界；`integration_test/mobile_realtime_pcm_smoke_test.dart` 证明了 Android 原生 PCM capture / playback 通道可以产生数据。当前仍没有真实 OpenAI / xAI WSS session 的真机长时 E2E，也没有 iOS 真机 PCM 和真实服务端音频事件证据。

`lib/shared/widgets/realtime_voice_panel.dart:9-13` 的静态注释仍写着缺少原生 PCM capture，但当前源码已有 `realtime_pcm_audio.dart` 和 Android integration smoke。这是 stale comment，不能推翻较高等级的运行时 / integration 证据；它也说明源码注释不是能力证明。

## 7. OpenAI / xAI / Gemini / Claude / Ollama 入口矩阵

`lib/core/ai/ai_service.dart:11-23` 当前 registry 只有五个字符串协议：`openai_chat`、`openai_response`、`claude`、`gemini`、`ollama`。

| 品牌 / 入口 | 当前实际 adapter / 序列化 | 当前多模态边界 | 不能宣称 |
| --- | --- | --- | --- |
| OpenAI Chat | `openai_chat`；图片 `image_url` data URL，协议层可构造 native audio part | 图片输入、STT-first 普通语音链路、OpenAI-compatible 图片 / 通用媒体路由 | 当前所有 OpenAI 模型都支持视频、音乐、原生音频或当前字段组合 |
| OpenAI Responses | `openai_response`；图片 `input_image` data URL，音频明确不支持 | 图片输入和配置后的通用媒体 route | Responses 音频原生输入已通过；也不能把图片输入等同图片生成 |
| Claude | `claude`；图片 Anthropic base64 image block；不支持类型转安全文本 | 普通聊天图片 serializer | Claude 图片生成、视频、音乐或任意音频输入已接通 |
| Gemini | `gemini`；图片 / 音频构造 `inlineData`，其他类型转安全文本 | 请求序列化和 SSE 解析 | 当前 Gemini 模型 / endpoint 实际接受这些 modality，尤其不能推断视频 / 音乐生成 |
| Ollama | `ollama`；图片写入 `images` base64，NDJSON 流 | 本地 Ollama / 兼容服务聊天和图片输入 serializer | Ollama 提供云端视频 / 音乐；也不能把本地协议 loopback 视为某个模型的实际视觉效果 |
| xAI Chat | 没有 `xai` 独立 chat adapter；`xAI / Grok` preset 使用 `openai_chat` 和 `https://api.x.ai/v1` | OpenAI-compatible Chat preset；batch Voice 和 Realtime 是另两条独立入口 | 存在独立 xAI Chat adapter，或 xAI Chat preset 自动证明 xAI Voice / Video / Music 全部可用 |
| xAI Voice | `xai` provider profile；batch STT `/v1/stt`、TTS `/v1/tts`；Realtime 为独立 WSS | 已有专属 REST / WSS 配置和 serializer 边界 | batch REST serializer 已证明真实 WSS、custom voices、长时流式和所有声音能力 |

本轮 contract test 直接断言五个 registry adapter 的类型，并断言 `AiService.getProtocol('xai')` 为 unknown；同时断言 xAI preset 的 `protocol == openai_chat`。这个断言的目的不是否定 xAI 支持，而是防止把“兼容入口”误读为“独立协议和全量厂商能力”。

## 8. 最容易被误读的“支持主流功能”表述

| 容易出现的表述 | 当前更准确的表述 |
| --- | --- |
| “支持 OpenAI、xAI、Gemini、Claude、Ollama 多模态” | 已注册五个聊天协议，并实现了各协议的部分附件序列化；不同协议支持的 modality、用户发送路径和生成入口不同 |
| “支持图片生成和图片编辑” | 已实现 OpenAI-compatible `images/generations` / `images/edits` 客户端与 Composer 入口；尚未证明每个配置服务都实现这两个 endpoint |
| “支持视频和音乐生成” | 已实现可配置通用 endpoint、异步任务状态机、轮询、取消和本地交付；尚未证明任意真实视频 / 音乐供应商的协议、编码和质量 |
| “支持 xAI” | xAI Chat 通过 `openai_chat` preset；xAI batch Voice 使用专属 REST；xAI Realtime 使用独立 WSS；这三条能力不能相互替代 |
| “支持声音克隆” | 设置页有声音克隆模式、WAV 参考音频私有归档和请求 builder；真实 custom voice 创建、供应商质量和长期稳定性未验证 |
| “实时语音已完成” | 已有 Realtime UI、session protocol、取消、文本 fallback 和 Android PCM 通道；真实 OpenAI / xAI WSS、iOS PCM 和长时云端会话未验证 |
| “模型名是 sora / video / music 就能生成” | 通用 route 需要配置；专用媒体能力需要显式 metadata；模型名本身不是充分证据 |
| “网络测试通过” | 当前多数网络测试是 loopback HTTP 或 fake adapter，只证明客户端协议与状态机，不证明外部供应商 |
| “真机 smoke 通过” | 证明特定设备上的录音、播放、UI 或原生通道路径；不扩展为所有厂商云端 E2E |

## 9. 已验证内容与本轮命令

### 9.1 本轮新增测试

文件：`test/multimodal-capability-contract_test.dart`

覆盖四个聚焦用例：

1. 移动端 Composer 全量多模态入口和 callback boundary；
2. 视频 / 音乐 disabled reason 的可见性与禁用行为；
3. OpenAI Chat / Responses、Claude / Gemini / Ollama 的通用媒体能力矩阵；
4. 五个聊天协议 registry 和 xAI `openai_chat` preset 映射。

该测试没有 `UniversalMediaService` fake adapter，也没有 loopback server；Widget 用例只使用本地回调计数器，故其结论限定为用户入口 / 能力门禁，不是云端 E2E。

已执行：

```bash
dart format test/multimodal_capability_contract_test.dart
flutter --no-version-check test --no-pub --no-test-assets \
  test/multimodal_capability_contract_test.dart -r expanded
```

结果：`4 tests passed`。

### 9.2 已有专项证据索引

- Composer / 图片入口：`test/chat_input_bar_image_generation_test.dart`；
- OpenAI Chat / Responses 图片和音频 serializer：`test/openai_chat_protocol_test.dart`、`test/openai_response_protocol_test.dart`；
- Claude / Gemini / Ollama 附件 serializer：`test/claude_protocol_test.dart`、`test/gemini_protocol_test.dart`、`test/ollama_protocol_test.dart`；
- 图片 HTTP / multipart / URL parser：`test/image_generation_service_test.dart`；
- 视频 / 音乐异步任务、xAI `request_id`、轮询、取消和响应形状：`test/universal_media_service_test.dart`、`test/universal_media_job_test.dart`；
- SQLite media job claim / 恢复：`test/media_job_persistence_test.dart`；
- xAI batch STT / TTS：`test/xai_speech_to_text_engine_test.dart`、`test/xai_text_to_speech_engine_test.dart`、`test/xai_speech_provider_test.dart`；
- Realtime session / PCM：`test/realtime_voice_session_test.dart`、`test/realtime_pcm_audio_test.dart`、`integration_test/mobile_realtime_pcm_smoke_test.dart`。

## 10. 仍未验证的真实云端或真实服务能力

以下项目在本次审计中明确保持 **未验证**：

1. 真实 OpenAI Chat / Responses 图片输入、图片生成、图片编辑、音频行为和当前模型版本的完整请求-响应；
2. 真实 xAI OpenAI-compatible Chat、xAI batch STT / TTS、Realtime WSS、custom voices 以及其视频 / 音频任务；
3. 真实 Gemini 多模态模型、真实 Claude vision / audio 模型和模型级别的 modality 差异；
4. 真实 Ollama 服务上的视觉模型、模型加载、GPU / CPU 性能、图片大小和本地服务异常恢复；
5. 任意真实视频 / 音乐供应商的异步创建、状态字段、轮询、取消、重启恢复、远端 URL、编码兼容和长时间任务；
6. 真实 STT / TTS 长音频、语言识别、内容长度、输出编码、音频播放兼容性，以及声音设计 / 声音克隆的实际质量；
7. OpenAI / xAI Realtime 的真实 WSS 音频事件、服务端 VAD、长时上下文、断线重连、iOS 原生 PCM 和真实设备音频中断；
8. 不同中转站对 `images/*`、视频 / 音乐 endpoint、Bearer Key、`request_id` 和 `Content-Type` 的实际兼容性；
9. 真实账号的配额、限流、账单、模型权限、地区限制和供应商错误字段是否符合当前 UI 的可诊断边界。

## 11. 下一步验证路径

如需把某一项升级为“真实支持”，应在仓库外提供单独的真实配置，并按厂商和能力逐项记录：请求 URL、鉴权方式、脱敏请求体、原始状态 / 响应字段、媒体 MIME / 编码、轮询和取消结果、真机保存 / 播放结果。应分别验证 OpenAI、xAI、Gemini、Claude、Ollama 及视频 / 音乐服务，不能用一个 OpenAI-compatible loopback 结果替代整张矩阵。

