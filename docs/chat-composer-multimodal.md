# ChatGPT 风格多模态 Composer 与媒体消息

> 最后更新：2026-08-24。图片、声音合成 / 设计 / 克隆、语音识别和视频完整任务面板已接入；顶部媒体模型与唯一 Composer 的实际发送路由已统一。TTS、声音设计、声音克隆和 STT 已在 Pixel 8 Production Release 上完成当前 SimiRouter 短音频真实 Provider E2E；图片参数和视频 / 音乐等其它媒体仍按各自证据边界单独复核。

## SimiRouter TTS 音色显示与请求值

SimiRouter `mimo-v2.5-tts` 的设置页和聊天页声音合成任务面板使用统一的可读标签：

| 显示名称 | API `voice` |
| --- | --- |
| 冰糖 | `alloy` |
| 茉莉 | `echo` |
| Mia | `nova` |
| Chloe | `shimmer` |
| 苏打 | `onyx` |
| 白桦 | `fable` |
| Milo | `milo` |
| Dean | `dean` |

界面会在名称后补充音色描述（例如“冰糖 · 活泼少女”），但 Dropdown 的真实 value
和 `/v1/audio/speech` 请求体始终使用右列原始 ID；未知 / 自定义 ID 原样展示，避免把
展示文案误发给 provider。

## 目标

对话页采用 ChatGPT 风格的单一 Composer：文本输入是主路径，`+` 工具菜单承载
文件、参考图、图片编辑、视频、语音和音乐动作；动作结果仍然回到同一条会话时间线，
不跳转到独立的“生成器”页面。AppBar 不再显示图片 / 视频 / 语音一级模式条，聊天区也
不再渲染第二套媒体输入框；用户始终在同一个底部输入框输入提示词，附件和任务参数在
发送前按所选工具自动处理。

## Composer 交互

- 输入框支持多行文本、移动端录音和多文件选择。
- 桌面端 Composer 支持一次拖入多个文件；拖入目录会被忽略，无法直接使用稳定路径的拖入内容会先写入应用临时目录，再通过 `.part -> rename` 原子提交。
- 文件选择默认允许一次选择多个文件；图片、视频、音频、PDF 和未知扩展名普通文件
  都保留为附件。未知扩展名归为 `document`，不会因为厂商格式变化而被 UI 丢弃。
- 图片作为普通附件发送时继续经过 Vision 模型门禁；新的图片生成任务面板会把用户选中的
  全部参考图按顺序发送到 `images/edits` 兼容入口，旧版未配置面板回调的 Composer 测试
  调用仍保持第一张参考图兼容行为。
- `+ → 生成图片` 会打开移动端底部任务面板：本次提示词、图片模型（名称和下拉箭头）、
  参考图、质量、宽高比、`1K / 2K / 4K` 清晰度、`width x height` 像素分辨率和生成数量均形成不可变请求快照；取消面板
  不会修改设置页默认值。质量 / 宽高比 / 清晰度 / 像素分辨率摘要本身可点击并打开单项选择抽屉，不再要求
  用户继续向下寻找“高级设置”。profile 分别把清晰度发送为 `resolution`、像素分辨率发送为 `size`；Grok 当前只声明 `resolution`，OpenAI Images profile 可分别声明两者；未配置图片模型时
  显示真实空状态并提供设置入口。
- `+ → 生成视频` 会打开一次性视频任务面板：多选参考图、独立首帧图、参考音频、时长、
  宽高比和分辨率均保存在 `VideoGenerationConfig`。提交时不把本机路径放入普通 JSON；
  失败 / 取消会保留完整角色配置供重试，成功后只清理这次实际消费的附件。
- `+` 菜单提供：图片生成、图片编辑、视频生成、声音合成、声音克隆、声音设计、生成音乐、
  深度思考和替身回复。小屏幕只把次要动作放入可滚动菜单，避免 Composer 挤压文本输入宽度。
- 图片 / 视频 / 音频的发送入口不依赖页面模式状态：普通发送走聊天模型，点击 `+` 中的
 具体媒体动作才调用对应能力模型；图片任务面板只列图片能力模型，视频 / TTS / STT
 复用设置中绑定的默认模型和渠道。
- 工具动作成功后清空对应文本和附件；上游失败时保留草稿，不写入半条用户消息。
- 草稿按 `sessionId` 保存 `text`、`attachments` 和 `deepThink`；切换会话时只恢复目标
  会话的快照，不能把 A 会话的附件带到 B 会话。Composer 与附件列表使用稳定的消息 / 附件
  identity key，避免列表重排时复用错误的媒体状态。
- 图片、视频、音频、PDF 和普通文件选择后立即复制到应用私有的
  `composer_drafts/<session>/` 目录；发送成功后再复制到 message-owned 目录（语音使用
  `audio_files/<message>/<attachment>`），历史消息不依赖 picker 或 cache 路径。用户移除、
  发送或媒体工具成功时只清理本次实际消费的 draft attachment IDs。
- Android 启动时调用 `image_picker` 的 `retrieveLostData()`；若系统在 picker 期间回收进程，
  恢复到的图片也会先归档到目标会话 draft 目录。没有恢复数据、插件不支持或恢复失败时不
  伪造附件，只提示用户重新选择。
- assistant 的“重新生成”携带被点击消息 ID，向前定位对应 user turn 并复用该 user 消息
  和数据库附件，不重复插入 user。生成期间 Stop 独立于发送 busy 状态，可取消 STT / 流式
  请求准备和 SSE 订阅；取消异常被收敛为已停止状态。
- 附件预览显示缩略图、文件名和大小，并支持逐项移除。声音工具拆成三个独立入口：普通
  合成消费文本，声音设计消费文本描述，声音克隆优先消费当前 Composer 第一条 `audio`
  参考附件；只有当前没有参考音频时，生产 `ChatPage` 才回退到设置中已归档的参考音频。
  provider、模式、Key、风格描述或参考音频不满足时，入口仍可见但保持禁用并显示可操作原因，
  不伪造远端能力；当前 Composer 参考音频是一次性输入，不写回持久化 TTS 配置。

## 声音工具契约

`ChatInputBar` 暴露三个独立的回调边界，动作结果仍由 `ChatPage` 的 provider-aware TTS 管线写回
当前会话：

| 入口 | 回调 | 输入 / 消费 | 本地回归 |
| --- | --- | --- | --- |
| 声音合成 | `onSynthesizeSpeech(String text)` | 文本；成功后清空文本，保留未消费附件 | `synthesize-speech-menu-item` |
| 声音克隆 | `onCloneVoice(String text, List<PendingAttachment> references)` | 优先取当前 Composer 第一条音频参考；当前无附件时由上游回退到配置参考；成功后只移除实际消费的参考附件 | `clone-voice-menu-item` |
| 声音设计 | `onDesignVoice(String text)` | 文本声音描述；成功后只清空文本，保留其它附件 | `design-voice-menu-item` |

Composer 对三个入口统一施加空文本、聊天流式、提交中、媒体任务 busy 和录音中的状态门禁。
`ChatPage` 根据 `TextToSpeechConfig` 的 provider、模式、API Key、声音风格和参考音频状态生成
独立 disabled reason；因此菜单可在未配置时展示能力，而不会误报云端可用。

当 TTS 已配置为 SimiRouter `voiceClone` 且基础请求配置有效，但设置中没有归档参考音频时，
`ChatPage` 不会提前关闭声音克隆入口：用户附加当前音频后可以执行一次性克隆；没有当前
音频时仍显示“附加参考音频”的可操作原因。

2026-08-18 Pixel 8 Production Release UI Automator 已实机看到三个入口和未配置 TTS 的禁用原因；
该次证据只证明客户端入口与状态边界。2026-08-24 已追加真实 TTS、声音设计、WAV/MP3
声音克隆生成与 Android 原生播放 E2E，详见下方“语音四能力真机验收”。

## 通用媒体接口

### 视频生成任务面板（typed v1）

视频面板不再把所有附件压缩为“第一张参考图 + `extra` Map”。`ChatPage` 将面板结果转换为
`VideoGenerationOptions`，按 `UniversalMediaConfig.videoProfileId` 选择 OpenAI / Sora、xAI /
Grok、OpenAI-compatible 或 configuredAsync profile。`referenceImages`、`firstFrameImage` 和
`referenceAudio` 是三个独立字段，`duration`、`aspectRatio`、`resolution` 由 profile 的能力
约束校验后映射到 provider wire 字段。

HTTP 传输在最后一层决定编码：multipart 端点使用显式重复文件字段，JSON 端点使用 data URI；
本机绝对路径只存在于应用私有附件和任务快照，不会进入普通请求 JSON。通用媒体 worker / SQLite
任务上下文会透传完整附件角色和 typed request fields，轮询、Stop、交付和重试复用同一任务状态机。
当前自定义 profile 默认字段为 `reference_images`、`first_frame`、`reference_audio`；xAI profile
明确拒绝未声明的首帧和参考音频，不以 UI 选项伪造能力。

## 图片生成任务面板

图片任务的 UI 不再只写入 `imageGenerationConfigProvider.size`。`ChatPage` 将本次面板结果
转换为 `ImageGenerationOptions`，由 `ImageGenerationRequestAdapter` 校验并通过
`MediaRequestProviderProfile.openAiImageGeneration` 生成厂商字段。`ImageGenerationService`
的 `generateWithOptions()` 只接受模型一致的 Options，支持 `n` 多图响应、质量、宽高比、
清晰度、像素分辨率和 multipart 多参考图；本地交付使用一个 assistant 消息和多个 `image` 附件。

运行中的 `ImageGenerationTask` 保存模型、route model id、参考图路径 / 文件名集合、数量、
宽高比、清晰度、像素分辨率和质量。失败或取消后的重试复用该快照，不重新读取全局图片配置，也不静默
丢弃第二张及之后的参考图。参考图会先复制到应用私有 `generated_context/`，然后在消息事务
中写入源附件和全部生成结果。

## 语音合成任务面板

移动端 Composer 的“声音合成”入口在存在 `onOpenSpeechSynthesisTask` 时会打开本次
任务底部面板，而不是直接把设置页的默认值静默用于请求。面板提供：

- 可编辑的本次朗读文本；
- 音色选择（保留当前设置音色，并提供 provider 兼容的常用音色候选）；
- 语速滑杆和精确的 `x` 数值；xAI 使用 `0.7–1.5`，其它兼容 TTS 使用 `0.25–4`；
- 输出格式选择。xAI 只暴露 `mp3 / wav` 播放安全格式，其它兼容入口暴露
  `mp3 / wav / opus / aac / flac`。

用户提交后才调用 `synthesizeSpeechMessage()`，本次 `voice / speed / responseFormat`
作为 typed 覆盖传入，取消面板不会修改持久化 TTS 设置。OpenAI-compatible TTS 的请求体
保留 `model / voice / input / speed / response_format`；SimiRouter 的声音设计、声音克隆
仍要求显式模式和参考输入，xAI 不接收这些未声明字段。结果统一写回当前会话的
`generated_speech/` audio attachment。

当前面板已在 Pixel 8 Production Release 以 `mimo-v2.5-tts` 完成 MP3 与 WAV 真实 provider
生成、时间线写入和 Android 播放；WAV 的实际 RIFF/PCM 容器与 `.wav` 扩展名一致。长文本、
长音频、弱网和批量压力仍待单独验证，不能从本次短音频 E2E 外推。

## 声音设计与声音克隆任务面板

“声音设计”面板把朗读文本和声音风格拆成两个本次任务字段，并提供快捷风格标签。
标签通过追加方式写入风格描述，不覆盖用户已经输入的内容；语速和输出格式也只对本次
请求生效。

“声音克隆”面板只接受当前 Composer 中的音频附件或设置中已经归档且仍有效的参考音频。
面板展示文件名 / 大小，并允许在多条当前音频之间单选；界面明确标记参考音频“仅用于当前
任务”，不会因一次合成自动写入长期音色库。没有任何可用参考音频时，提交动作直接返回
“请先上传参考音频”。

两个入口均通过 `synthesizeSpeechMessage()` 的本次 `style / referenceAudioPath / speed /
responseFormat` 覆盖进入 provider，仍受 SimiRouter `voiceDesign / voiceClone` 模式和
能力门禁约束；xAI provider 不会接收未声明的声音设计 / 克隆字段。生成的 audio attachment
统一回写当前会话 `generated_speech/`，错误时保留用户草稿和参考附件。

## 独立语音识别任务面板

Composer 的“识别语音”入口只在上游提供识别回调时出现，并要求当前草稿中至少有一个
`audio` 附件。任务面板允许在多条音频之间单选，并选择 `自动 / 中文 / 英文`；没有音频
时显示“先通过选择文件附加语音文件”，不会伪造空转写。

提交后 `recognizeSpeechMessage()` 使用当前配置的 STT engine 和既有
`AudioTranscriptionService`，把原始文件以一次性任务输入写入 transcript archive，再将
“识别语音：文件名”用户消息和完整 assistant 转写消息写回当前会话。语言通过
`sttLanguageOverrideProvider` 只影响本次调用，成功或失败后都会清除 override。STT 未配置、
文件失效、响应为空或 provider 错误时不写半成功消息。

## 语音四能力真机验收（2026-08-24）

| 能力 | 模型 / 输入 | 实际结果 | Android 结果 |
| --- | --- | --- | --- |
| TTS | `mimo-v2.5-tts`；冰糖/alloy；1.00x；MP3 与 WAV | 两种格式均生成 assistant audio；WAV 为 RIFF/PCM 16-bit、mono、24 kHz、2.24 秒 | MP3/WAV 均 started，停止或自然完成后按钮恢复并释放 Audio Focus |
| 声音设计 | `mimo-v2.5-tts-voicedesign`；独立文本与“温柔”风格；MP3 | 生成 24 kHz、1.968 秒 MP3，并保留正确的声音设计时间线语义 | `MediaPlayer` 完整播放，completed 后恢复入口 |
| 声音克隆 | `mimo-v2.5-tts-voiceclone`；分别使用 WAV 与 MP3 参考 | WAV 成功；同一 1.968 秒 MP3 在旧 `audio/mpeg` 下连续超时，改为 `audio/mp3` 后数秒成功 | 两种克隆结果均为可播放 MP3，started/completed 与 Audio Focus 闭环 |
| STT | `mimo-v2.5-asr`；真实生成音频；`auto / zh / en` | 三种语言选择均成功，回环结果为 `Voice clonistability test.`；独立时间线和 audio-only 联合发送均闭环 | 原 audio、ready sidecar、assistant 转写可见；成功发送后清理已消费语音草稿 |

为避免“请求成功但附件不可播放”，TTS 落盘前同时验证响应类型和内容前缀：HTTP 200 的
JSON / HTML / text 错误体直接拒绝；保存扩展名与本次 `response_format` 一致。参考音频 data URI
按文件扩展名映射 MIME；MP3 对当前 SimiRouter legacy clone 使用实机确认的 `audio/mp3` subtype，
避免网关把临时上传命名为 `.mpeg` 后任务长期 pending。STT 先发送 multipart，只在 400 / 415 /
422 时回退 JSON data URI；`auto` 在两条路径均不发送 `language`，中文 / 英文发送 `zh / en`。

代码门禁：语音影响面 27 个测试文件 179 / 179 通过，最终修复聚焦 39 / 39 通过，完整 Flutter
JSON reporter 1235 / 1235（`done.success=true`、0 error）后独立 compact 再次 1235 / 1235；
analyze 与 diff check 通过。
Production Release 的 APK/设备 SHA-256 一致为
`c9c8eb30d4a6e96d98ed7a8f35228517c9a7f6f543f15b62d2717183b139f60c`，安装保持正式包
`firstInstallTime` 与 `dataDir` 不变。未覆盖边界为长音频、弱网/断网、连续并发、iOS Provider
播放和真实来电/闹钟/第三方播放器焦点抢占。

`lib/core/ai/universal_media_service.dart` 提供视频 / 音乐的通用客户端：

- Base URL 和 Bearer Key 复用当前聊天渠道，避免重复保存密钥。
- endpoint、模型名可以在“设置 → 图片生成 → 视频 / 音乐 / 通用媒体接口”替换；默认
  为 `/v1/videos/generations` 与 `/v1/audio/music`。
- 请求支持 JSON；带参考图的视频请求使用 multipart `image` 字段。
- 响应支持直接二进制、`b64_json` / `base64`、data URI、`url` / `video_url` /
  `audio_url` / `content_url` 等常见结构。远端 URL 仅允许 HTTP(S)，下载后受大小上限
  约束并保存到应用私有目录。
- 需要长时间异步轮询的厂商可以返回任务 ID；客户端会把提交结果持久化为 `pending` /
  `running` 媒体任务，保存 provider job ID、轮询地址、deadline 和提交时的
  `channelModelId`，不会把只含 job ID 的响应伪装成已完成媒体。
- `AppBootstrap` 在首帧后启动一次恢复 coordinator。恢复时先等待媒体 notifier 从 SQLite
  完成恢复，再用 lease 原子 claim 任务，按持久化的渠道模型重新解密 API Key 并继续有限轮询。
  轮询得到媒体后，只有 `.part -> rename` 文件写入、用户 / assistant 消息和附件事务全部提交，
  才把任务标记为 `completed`；重复启动、进程竞争和交付重试复用同一组消息 / 附件 ID。
- 这套生产状态机、快照字段和本地交付通过 fake adapter / 内存 SQLite 测试；真实厂商异步
  任务协议、远端 URL 长时间可用性、视频编码兼容性和音乐质量仍需配置真实服务后在真机验证。

## 能力与本地落库

| 能力 | 调用入口 | 会话附件类型 | 本地目录 |
| --- | --- | --- | --- |
| 图片生成 | `/v1/images/generations` | `image` | `generated_images/` |
| 参考图 / 图片编辑 | `/v1/images/edits` | `image` | `generated_images/` |
| 视频生成 | 可配置 endpoint | `video` | `generated_videos/` |
| 声音合成 | `/v1/audio/speech` | `audio` | `generated_speech/` |
| 声音克隆 / 声音设计 | SimiRouter mimo TTS 模式 | `audio` | `generated_speech/` |
| 语音识别 | `/v1/audio/transcriptions` 或 iOS Speech 兜底 | `audio` sidecar | `audio_transcripts/` |
| 音乐生成 | 可配置 endpoint | `audio` | `generated_music/` |

结果先以临时 `.part` 文件写入，成功后原子改名，再在一个数据库事务中写入 user
提示消息、assistant 结果消息和附件元数据。异步媒体任务的 SQLite 状态、固定渠道模型、
交付 ID、源附件元数据和相对路径会随结构化快照导出 / 恢复；API Key、媒体二进制和本机
绝对路径不会进入快照。消息附件导出 / 导入沿用既有的安全路径净化和应用私有目录重定向规则。

## 渠道协议兼容补充（2026-08-21）

- 图片生成 / 编辑使用已选择渠道的 Base URL、加密 API Key 和图片能力模型；Grok Imagine
  模型按网关约定发送 `response_format=url`，编辑请求使用 JSON `image.url` data URI，其他
  OpenAI 兼容模型保留 multipart `/v1/images/edits`。
- xAI 视频 profile 固定使用 `/v1/videos/generations` 提交、`request_id` 轮询
  `/v1/videos/{request_id}`；`/v1/videos/extensions` 和 `/v1/videos/edits` 的 request-id
  路径不会错误地拼到 `extensions` / `edits` 下。参考图在 JSON 边界编码为 data URL，不能把
  本机路径直接发给网关。
- TTS 首选 `/v1/audio/speech`；网关返回 404/405 时才按同一请求体回退到
  `/v1/audio/tasks`。设置页“从当前渠道获取音色”调用 `/v1/tts/voices?model=...`，兼容
  字符串数组、`voices` / `data` 包裹对象和 `id` / `voice_id` 字段。
- STT 首选 multipart `/v1/audio/transcriptions`；网关因内容类型返回 400/415/422 时，使用
  同一渠道的 JSON `url=data:audio/...;base64,...` 兼容路径重试。`auto` 语言在 multipart
  请求中省略，在 JSON 兼容路径中按协议保留。
- 设置中绑定媒体模型后只保存稳定的 `channelModelId`；手动改写模型名会清除旧绑定，避免
  新模型错误复用旧渠道的 Base URL / API Key。应用启动时会恢复已保存的创作模式并自动选择
  第一个已配置的同能力模型。

## 消息体展示

- 图片：本地缩略图，点击放大，长按进入图片编辑。
- 视频：本地 `video_player` 预览、播放 / 暂停、进度拖动；解码失败时回退到文件卡片，
  不让整个消息列表崩溃。
- 音频：文件名、大小、转写状态、播放 / 停止按钮；已配置的音频转写详情仍可查看和
  复制。声音合成和音乐生成都复用该卡片。
- PDF / 文档 / 未知格式：安全文件卡片；模型协议不支持直接读取时只向模型注入安全的
  “不支持该类型附件”提示，不把本地路径写入日志或 Markdown。
- assistant 文本继续使用统一 Markdown 富内容渲染，支持图片、HTML audio/video、
  Mermaid、Draw.io、公式和折叠块。
- 图片可点击放大、长按进入编辑并下载；视频支持播放 / 暂停、进度拖动和下载；音频
  与音乐支持播放 / 停止、转写详情和下载；PDF / 普通文件提供下载卡片。下载成功提示
  只展示安全文件名，不展示设备绝对路径。

## 边界与验证

- 单条消息仍最多 8 个附件，单文件默认 25 MB；生成视频结果单独限制为 100 MB，音乐
  结果限制为 25 MB。
- 只有用户主动点击媒体工具才会外发文件或调用生成接口；普通聊天附件仍遵循当前
  Vision / STT 能力门禁。
- 单元 / Widget 测试覆盖视频扩展名识别、通用接口二进制与 base64 响应、参考图
  multipart、无 Key 快速失败、Composer 工具菜单和视频消息卡片。
- 真实厂商的异步任务、视频编码兼容性和音乐长音频播放仍需使用仓库外配置在真机上
  单独验证，不在离线测试中伪造成功结果。

## 2026-08-21 图片任务面板验证记录

- `flutter --no-version-check analyze --no-pub`、`git diff --check` 通过。
- 图片服务 typed wire、图片任务状态、Composer 全部参考图回调和多模态入口聚焦回归通过；
  当前聚焦图片相关测试 **43 项通过**。
- 尚未以真实云端凭据在 Pixel 8 上完成图片模型切换、2K / 多图 / 多参考图真实请求和视觉
  结果质量 E2E；Release 覆盖安装待本轮执行。

## 2026-08-21 视频任务面板验证记录

- `test/chat_input_bar_video_tools_test.dart` 覆盖 `+ → 生成视频` 面板、多参考图、首帧图、
  参考音频字段和成功后的附件消费；`test/media_request_options_test.dart` 与
  `test/universal_media_service_test.dart` 覆盖 profile 字段校验、多个 data URI、首帧 / 音频
  分离和本机路径不泄露。
- 全量 `flutter --no-version-check test --no-pub --no-test-assets -r json` **1179 项可见测试通过**
  （含 202 项隐藏测试），`flutter --no-version-check analyze --no-pub` 与 `git diff --check` 通过。
- Pixel 8 `37101FDJH0077P` 已覆盖安装最新 Production Release，`ANDROID_RELEASE_PARITY
  status=verified`，APK / 设备 hash `4465ffa1f164e30fe97873c7f193b57fd6dc7023657bbcb04223f4c21a954f1c`，
  签名 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，PID `31119`，
  `firstInstallTime` / `dataDir` 保持不变。
- 真实视频 provider 账号、长轮询、编码兼容性和生成质量仍待仓库外配置；本地 wire 回环不作为云端成功证明。

## 2026-08-18 最终验证记录

- `dart format`、`flutter --no-version-check analyze --no-pub`、`git diff --check` 通过。
- Composer / ChatPage / 图片 / 草稿 / 消息附件 focused 回归 **42 项通过**；完整
  `flutter --no-version-check test --no-pub --no-test-assets -r compact` **1016 项通过**。
- Pixel 8 `37101FDJH0077P` 执行 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P`：
  production Release APK 81.9 MB，`adb install -r` 返回 `Success`，`ANDROID_RELEASE_PARITY
  status=verified`；构建 APK 与设备 `base.apk` SHA-256 均为
  `f7d43858f7d4292eb538189c99bb631294c92ad21ac36b64907c861fb3cb1556`，
  `firstInstallTime` / `dataDir` 保持不变，安装后 `lastUpdateTime=2026-08-18 11:08:00`、
  PID `28329`、前台组件为 `top.simitalk.aichat/.MainActivity`。
- 该验证证明当前客户端 Release 已构建、覆盖安装并启动；真实云端图片生成、参考图 / 图片编辑、
  视频 / 音乐生成、TTS / STT、声音克隆 / 声音设计和 Realtime WSS 仍需实际凭据与服务配置后单独 E2E。

## 2026-08-22 联合语音发送与统一 Composer

- 语音识别工作区不再把“发送语音”当成孤立识别任务：当草稿中存在 audio attachment 时，底部发送按钮先调用设置中绑定的 ASR / STT 模型（默认 `mimo-v2.5-asr`），再把转写结果和输入框文字合并为同一条用户消息交给当前 Chat 模型。
- 联合消息的时间线正文包含原始文字和转写结果，原始音频附件仍挂在同一条 user message 上；成功发送后 `ChatInputBar` 按本次 stable ID 清除顶部语音草稿。转写失败不会发送 Chat 请求，输入文字和音频仍保留以便重试；成功的 sidecar transcript 在重试时复用，避免重复消耗 ASR 额度。
- 图片 / 视频 / 语音创作工作区只保留能力参数和模型状态提示，输入统一使用底部一个 Composer；底部发送按钮根据当前模式和模型能力自动进入图片、视频、TTS / ASR 或聊天编排，不再渲染第二个大输入框。
- Artifact 卡片右下角提供“编辑”入口。HTML 工作台进入可视化编辑后可点击页面文本组件，修改组件文字和 CSS 颜色并应用到当前本地草稿；源码模式仍可直接编辑 Markdown / HTML。

## 2026-08-23 顶部模型与实际任务路由一致

- 顶部模型胶囊切换到图片、视频、TTS / ASR、声音设计 / 克隆或音乐模型后，底部唯一 Composer 不再绕过任务状态调用普通 Chat。活动会话和空会话都经过统一创建模式路由，发送时使用当前 `creationModeProvider` 与 `voiceCreationToolProvider`。
- TTS 生成的时间线消息使用 TTS 配置的 `channelModelId` 记录实际媒体模型；会话的默认 Chat 模型只负责媒体任务编排所需的会话上下文，不覆盖生成结果的模型元数据。

验证：`test/chat_provider_attachment_routing_test.dart` 联合语音 + 文字回环、`test/chat_input_bar_voice_tools_test.dart` 发送后附件清理、Artifact 卡片入口和现有多模态聚焦测试通过；真实云端 ASR / Chat 质量与 Pixel 8 本轮 Release E2E 需继续补证。

## 2026-08-24 图片清晰度与像素分辨率拆分

- 图片任务面板顶部“质量 / 宽高比 / 清晰度 / 分辨率”摘要是四个独立 `ActionChip`。`1K / 2K / 4K` 只属于清晰度；`1024x1024 / 1536x1024 / 1024x1536` 只属于像素分辨率。选择、模型切换清理、字段校验、失败重试和冷启动恢复均分别保存。
- `ImageGenerationOptions.resolution` 与 wire `resolution` 保存清晰度档位；`ImageGenerationOptions.size` 与 wire `size` 保存像素分辨率。`MediaModelCapability.supportedResolutions` 与 `supportedSizes`、`ModelCapabilities.supportedImageResolutions` 与 `supportedImageSizes` 同样拆分；profile 未声明的字段不得发送。
- 上一轮把 `2K` 通过 OpenAI profile 错误序列化成 `size=2K`，因此当时“高 / 16:9 / 2K”成功生成只能证明任务被接受，不能证明 `resolution` 或 `size` 协议正确。
- 拆分后的 Pixel 8 Production Release 已同时显示可点击的“清晰度 · 2K”和“分辨率 · 1536x1024”；联合任务成功交付，但请求 `resolution=2K + size=1536x1024` 的下载 PNG 实际为 `1387x1134`。因此客户端字段拆分和交付链路已验证，provider 对像素尺寸的执行已确认不一致；baseline / resolution only / size only / ratio only 仍待逐项差分。
