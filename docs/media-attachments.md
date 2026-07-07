# 语音、图片与附件系统设计

> 对应模块：M8。状态：图片 / 文件附件基础稳定化、发送后图片缩略图预览、语音文件附件、消息音频卡片转写状态展示、转写详情查看 / 复制、原始语音文件私有归档、转写稿件草稿归档、转写状态标记与失败错误脱敏、可注入 STT 转写管线、OpenAI 兼容 STT 引擎与设置页配置入口、音频转写稿详情查看 / 复制、移动端麦克风权限声明、设置页语音输入状态入口、OpenAI Relay 图片 data URL 内存态透传、移动端录音按钮、Android / iOS 原生运行时权限申请、本地录音附件、音频附件发送前 STT 音频接口转写、base64 语音文本粘贴转写、iOS 系统 Speech 原生识别兜底、非语音附件原文件导出 / 导入、OpenAI 兼容 TTS 语音播报、播放停止控制、播放完成事件回传、STT/TTS 厂商预设 v1、Android / iOS 原生播放通道、Android 音频焦点基础处理与 iOS AVAudioSession 中断开始停止播放已落地；Pixel 8 已补 base64 语音真机发送 smoke、OpenAI 兼容 STT 网络 fallback smoke、真实录音按钮 smoke、OpenAI 兼容 TTS 网络 smoke、原生音频播放通道 smoke、长音频播放 smoke 和播放替换 / 中断 smoke；移动端音频焦点 / 中断加固已通过静态回归、全量 334 个测试、analyze、临时 sqlite hook 下 Android debug APK 与 iOS Debug 构建和 Pixel 8 三条原生音频 smoke 复验；direct-channel smoke 通过测试参数跳过焦点请求且已改用低振幅 WAV，真实外部音频焦点抢占和 iOS 真机音频中断场景仍待补。最后更新：2026-07-06。

## 1. 目标

- 支持移动端图片输入：相机 / 相册。
- 支持文件附件输入：图片、PDF、语音文件、普通文档。
- 支持多模态模型调用，把图片等附件传给协议层。
- 附件元数据进入本地数据库，Markdown 原始档案记录附件名称；数据导出会把仍可读取的非语音附件原文件复制到压缩包 `attachments/`。
- 语音输入当前已具备语音文件附件识别、移动端录音按钮、Android / iOS 原生运行时权限申请、本地 `.m4a` 录音附件、消息音频卡片转写状态展示、转写详情查看 / 复制、原始语音文件私有归档、转写稿件 sidecar、`pending` / `ready` / `empty` / `failed` 状态、失败错误脱敏、可注入 STT 更新管线、OpenAI 兼容 STT 自动转写、发送前 STT 音频接口转写并把转写文字注入普通聊天、base64 语音文本粘贴转写、iOS 系统 Speech 原生识别兜底、移动端麦克风权限声明、设置页配置入口、OpenAI 兼容 TTS 语音播报、AI 回复播报按钮、播放停止控制、播放完成事件回传、STT/TTS 厂商预设 v1、Android / iOS 原生播放通道、Android 音频焦点基础处理和 iOS AVAudioSession 中断开始停止播放；Pixel 8 已补 base64 语音粘贴 → audio 附件 → fake STT ready sidecar → 净化后模型请求真机 smoke，当前 OpenAI 兼容聊天渠道复用 `/v1/audio/transcriptions` 的 multipart STT 网络 smoke，以及聊天页麦克风按钮 → Android 原生录音 `.m4a` → STT → 聊天回复真机 smoke，以及 assistant 播报按钮 → `/v1/audio/speech` → 临时音频 → 停止播报真机 smoke，以及应用私有目录 WAV → Android `MediaPlayer` → stopped / completed 事件回传、播放替换 / 中断 smoke；后续仍需补更多非 OpenAI 兼容语音厂商、真实云端 STT / TTS、真实外部音频焦点抢占、iOS 真机音频中断和后台场景。

## 2. 当前实现

已落地：

- `ChatInputBar` 支持移动端相机 / 相册入口，桌面端与移动端均支持文件选择。
- `PendingAttachment` 进入 `sendMessage`，附件写入 `attachments` 表。
- 多模态协议层使用 `AiMessage.attachments` 把附件路径传给模型协议。
- Markdown 原始档案记录附件名称，便于导出和人工审计。
- `attachment_policy.dart` 提供统一附件策略：类型识别、数量限制、大小限制、用户可读大小格式化。
- 发送前二次校验附件是否仍存在、是否超限，避免文件被移动后写入半残缺消息。
- `MessageBubble` 对已有本地路径的图片附件展示缩略图，非图片或路径不可用时回退文件卡片。
- `MessageBubble` 对 audio 附件展示转写状态：等待转写、转写完成、未识别到文字、转写失败；状态来自本地 `audio_transcripts/` sidecar，不展示本机路径。音频卡片可打开转写详情弹窗，展示状态和正文 / 状态说明；只有 `ready` 且有正文时提供“复制正文”。
- 图片缩略图只展示文件名和大小，不在界面或语义标签中暴露完整本地路径。
- `audio_file_archive.dart` 负责把音频附件复制到应用文档目录下的 `audio_files/<message-id>/<attachment-id>.<ext>`，避免发送后依赖外部临时路径。
- `audio_transcript_archive.dart` 负责为音频附件创建 Markdown 转写稿件，路径位于应用文档目录下的 `audio_transcripts/`；稿件会记录 `pending` / `ready` / `empty` / `failed` 状态，失败时只写入脱敏后的错误说明，不记录完整本地路径、密钥、令牌或原始厂商错误；`readDetails` 只返回可展示 / 可复制的脱敏详情，不暴露 sidecar 绝对路径。
- `audio_transcription_service.dart` 定义可注入 `SpeechToTextEngine` 和 `AudioTranscriptionService`，配置 STT 引擎后可对归档音频执行转写并覆盖更新对应 sidecar。
- `inline_base64_audio.dart` 负责识别聊天文本中的 `data:audio/...;base64,...` 或“base64 的语音字符：...”payload，校验大小和音频格式，发送前转为临时 `audio` 附件并从正文剔除原始 base64。
- `openai_speech_to_text_engine.dart` 提供 OpenAI 兼容 STT 引擎，调用 `/v1/audio/transcriptions`，限制本地音频 25 MB，校验 HTTP(S) Base URL，并把厂商失败转换为不含密钥 / 本机路径 / 原始响应正文的安全错误。
- `native_speech_to_text_engine.dart` 提供 iOS 系统 Speech 兜底引擎，通过 `simichat/native_speech_to_text` MethodChannel 调用原生 `SFSpeechURLRecognitionRequest`，仅识别应用私有目录内普通音频文件；`audio_transcription_service.dart` 的 `FallbackSpeechToTextEngine` 会在前一个 STT 引擎失败或返回空结果时继续尝试下一个引擎。
- `openai_text_to_speech_engine.dart` 提供 OpenAI 兼容 TTS 引擎，调用 `/v1/audio/speech` 生成 mp3，使用 OpenAI 兼容 `response_format: mp3` 字段，校验 HTTP(S) Base URL、模型、音色和 10 MB 响应上限，并把厂商失败转换为不含密钥 / 本机路径 / 原始响应正文的安全错误。
- `speech_provider_preset.dart` 提供 STT/TTS 厂商预设 v1：OpenAI 官方、Groq STT 与自定义 OpenAI 兼容；设置页选择预设后自动填充 Base URL、STT 模型、TTS 模型和音色，并在推断已有配置时归一 `/v1` 后缀。
- `text_to_speech_service.dart` 会将 assistant 文本压缩空白、截断到 4000 字、校验音色格式，把生成音频写入应用临时目录 `tts_audio/` 后调用播放器；`audio_player.dart` 通过 `simichat/audio_player` MethodChannel 调用原生播放。
- `audio_transcription_provider.dart` 提供 STT 配置状态和默认引擎装配：设置页启用后读取本地加密 API Key、Base URL 与模型，生成 `SpeechToTextEngine`；未配置或密钥解密失败时保持 `null`。
- `voice_recorder.dart` 定义 `VoiceRecorderPlatform` 与 `MethodChannelVoiceRecorder`，通过 `simichat/voice_recorder` 调用原生录音能力。
- 输入栏移动端展示语音按钮：点击开始录音，再次点击停止，停止后将 `.m4a` 结果添加为 `audio` 附件，随后复用现有发送、私有归档和 STT 草稿链路。
- iOS `Info.plist` 已声明 `NSMicrophoneUsageDescription` 与 `NSSpeechRecognitionUsageDescription`；`AppDelegate.swift` 使用 `AVAudioRecorder` 请求麦克风权限并录制到应用 cache，同时注册 `simichat/native_speech_to_text`，在网络 STT 不可用时通过 `SFSpeechURLRecognitionRequest` 对应用私有目录内录音做系统识别；Android `AndroidManifest.xml` 已声明 `android.permission.RECORD_AUDIO`，`MainActivity.kt` 使用 `MediaRecorder` 运行时申请权限并录制到应用 cache。
- 设置页“语音与多模态 / 语音输入”入口已从只读状态升级为配置入口：可启用 / 关闭 STT，设置 OpenAI 兼容 Base URL、模型和 API Key；API Key 加密保存在本机 SharedPreferences，不进入结构化备份、导出包、日志或聊天 Markdown。
- 设置页“语音与多模态 / 语音播报”入口支持启用 / 关闭 TTS，配置 OpenAI 兼容 Base URL、模型、音色和 API Key；API Key 同样加密本地保存，不进入结构化备份、导出包、日志或聊天 Markdown。
- AI 回复消息底部提供“语音播报”按钮；仅 assistant 非空文本展示，点击后生成临时 mp3 并调用 Android `MediaPlayer` / iOS `AVAudioPlayer` 播放，原生侧会校验文件存在且位于应用私有目录内；播报生成中显示禁用状态，播放中显示“停止播报”按钮，用户可主动停止原生播放；原生完成 / 停止 / 错误事件会带回当前音频路径，聊天页只在路径匹配当前播报时自动清理“停止播报”状态。
- Android 正式播放路径会在启动前请求音频焦点；焦点丢失或短暂丢失时停止当前播放并复用 stopped 事件回传，允许 duck 时临时降低音量、焦点恢复后恢复音量；播放完成、错误、主动停止和启动失败都会释放焦点。当前 direct-channel integration smoke 不是普通用户点击前台流，因此通过 `MethodChannelAudioPlayer.playFileForTesting(..., skipAudioFocusRequest: true)` 跳过焦点请求，只验证播放 / 停止 / 完成 / 替换事件没有被改造破坏；真实来电 / 闹钟 / 其他播放器抢占焦点仍需真机复验。
- iOS 原生播放路径会监听 `AVAudioSession.interruptionNotification`；收到 interruption began 且当前正在播放时停止播放并复用 stopped 事件回传，播放完成 / 错误 / 主动停止 / 启动失败都会 `setActive(false, options: [.notifyOthersOnDeactivation])` 释放音频会话；真实来电 / 耳机 / 系统中断和自动恢复策略仍需真机复验。
- 音频附件写入 SQLite 时使用应用私有目录归档路径；转写稿件只记录文件名、大小、状态、转写文本或脱敏错误，不记录完整本地路径。
- 音频转写稿件写入失败时进入待修复队列；STT 失败会把 sidecar 更新为 `failed`，并脱敏路径、密钥、令牌和 URL；不通过 `debugPrint` 输出音频错误细节，避免异常文本携带本地路径。
- 聊天发送链路会先对 audio 附件执行 STT 级联：优先使用设置页显式配置的 OpenAI 兼容 STT；若当前聊天渠道是 `openai_chat` / `openai_response`，继续复用当前渠道 Base URL 与 API Key 调用 `/v1/audio/transcriptions`（默认模型 `whisper-1`）；iOS 上再追加系统 Speech 原生识别兜底。取得转写文本后，把“语音转文字结果”作为普通文本注入聊天上下文，audio 原文件不再作为聊天附件 base64 发送；所有引擎都失败时只向模型注入可解释的配置 / 录音提示，避免模型臆测音频内容。
- 数据导出会查询 SQLite 附件表，将非语音附件原文件复制到 `attachments/<message-id>/<attachment-id>-<safe-file-name>`；路径片段会净化，缺失文件、符号链接、`exports/` 下文件会跳过，manifest 不记录本机绝对路径。
- 数据导入已允许恢复 `attachments/` 文件到目标应用目录，并通过 `structured_data/local_database.json` 重建附件 SQLite 元数据；导入后附件 `localPath` 会指向目标设备应用目录下的恢复文件。

待实现：

- 继续补更多非 OpenAI 兼容语音厂商预设和真机长时间播报 / 外部音频焦点中断场景复验。
- 录音真机长时间 / 后台中断 / 来电打断场景复验。

## 3. 附件策略

当前策略：

- 每条消息最多 `8` 个附件。
- 单个附件上限 `25 MB`。
- 图片扩展名：`jpg / jpeg / png / gif / webp / bmp`。
- 语音扩展名：`mp3 / m4a / aac / wav / flac / ogg / opus / amr`。
- PDF 单独标记为 `pdf`。
- 其他文件标记为 `document`。

原则：

- UI 选择时先校验，给用户明确错误提示。
- 发送前再次校验真实文件状态，防止选择后文件被删除 / 移动。
- 校验失败不能写入用户消息，避免 SQLite 与 Markdown 出现半残缺记录。
- 不记录完整文件内容到日志。

## 4. 数据流

```text
用户选择图片 / 语音 / 文件、在移动端点击语音按钮录音，或粘贴 base64 语音文本
  -> 若正文包含 base64 语音：sendMessage 先本地解码为临时 audio 附件并移除原始 base64
  -> 录音路径：ChatInputBar -> simichat/voice_recorder -> Android MediaRecorder / iOS AVAudioRecorder -> 应用 cache .m4a
  -> ChatInputBar / base64 解码生成 PendingAttachment
  -> attachment_policy 校验数量 / 大小 / 类型
  -> sendMessage 发送前确认文件存在并读取大小
  -> 若为 audio，发送前复制原始文件到 audio_files/<message-id>/<attachment-id>.<ext>
  -> messages 写入用户消息
  -> attachments 写入附件元数据（audio 使用应用私有目录归档 localPath）
  -> 若为 audio，创建 audio_transcripts/<message-id>/<attachment-id>.md 转写稿件草稿，状态为 pending
  -> 发送给聊天模型前执行 STT 级联：设置页 STT 配置 -> 当前 OpenAI 兼容聊天渠道 `/v1/audio/transcriptions` -> iOS 系统 Speech 原生识别兜底；有文字为 ready，空结果为 empty，失败为 failed 且错误脱敏

用户点击 assistant 回复下方“语音播报”
  -> 读取 TTS 配置和加密 API Key
  -> 调用 OpenAI 兼容 `/v1/audio/speech`，输入文本本地压缩 / 截断，音色做白名单格式校验
  -> 将 mp3 写入应用临时目录 `tts_audio/`
  -> 通过 `simichat/audio_player` 调用 Android / iOS 原生播放；原生侧只接受应用私有目录内普通文件
  -> 当前消息进入播放中状态，操作区切换为“停止播报”
  -> 用户点击停止时调用 `AudioPlayerPlatform.stop()`，停止原生播放并清理当前播报状态
  -> 原生播放完成 / 停止 / 错误时回传 `AudioPlaybackEvent`，ChatPage 校验路径匹配后自动清理播放中状态
  -> ChatPage 通过 audioTranscriptStatusProvider 读取 sidecar 状态并刷新 MessageBubble 音频卡片；用户点击音频卡片时读取 sidecar 脱敏详情并弹窗展示 / 复制
  -> MessageBubble 读取附件元数据并展示图片缩略图 / 音频卡片 / 文件卡片
  -> AiMessage.attachments 传入协议层
  -> 若 STT 成功：把转写文本作为普通 user 文本发给聊天模型，不再发送 audio base64；粘贴输入的原始 base64 也不进入聊天上下文 / Markdown
  -> 若所有 STT 引擎都不可用或失败：聊天上下文只包含安全提示，建议配置 STT 音频接口或重新录制
  -> Markdown 原始档案记录附件名称
  -> 数据导出时，非语音附件原文件复制到 attachments/<message-id>/<attachment-id>-<safe-file-name>
  -> 数据导入时，attachments/ 文件恢复到应用目录；structured_data/local_database.json 重建附件 SQLite 元数据并重定向 localPath
```

## 5. 测试要求

- 附件类型识别测试。
- 附件大小格式化测试。
- 超数量拦截测试。
- 超大小拦截测试。
- 合法附件元数据通过测试。
- 消息气泡附件文件卡片展示测试。
- 消息气泡本地图片缩略图展示测试，验证不展示完整本地路径。
- 消息气泡音频卡片转写状态展示测试，验证只展示状态说明，不展示完整本机路径。
- 音频转写详情查看 / 复制测试：`readDetails` 只返回可复制正文或脱敏状态说明；音频卡片提供“查看 / 复制转写稿”动作且不展示完整本机路径。
- 语音附件类型识别测试。
- 原始语音文件归档测试，验证复制到应用私有目录，删除外部源文件后归档仍存在，且缺失源文件异常不携带完整外部路径。
- 语音转写稿件草稿归档测试，验证不暴露完整音频路径。
- STT 转写服务测试：假引擎返回内容时 sidecar 更新为 `ready`，空内容更新为 `empty`，引擎异常更新为 `failed` 且异常文本脱敏为统一错误或安全说明；fallback 引擎测试覆盖在线 STT 失败 / 空结果后继续尝试下一个引擎。
- 麦克风与系统语音识别权限声明测试：iOS `NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription` 与 Android `RECORD_AUDIO` 均存在。
- OpenAI 兼容 STT 引擎测试：验证 multipart 请求路径、模型字段、文件名、响应解析、HTTP(S) Base URL 校验和失败错误脱敏。
- STT 配置 Provider 测试：API Key 加密本地保存，启用后可生成引擎，结构化备份不包含 STT 密钥 / Base URL / 模型配置。
- OpenAI 兼容 TTS 引擎测试：验证 `/v1/audio/speech` JSON 请求、模型 / 音色 / 输入字段、bytes 响应、HTTP(S) Base URL 校验和失败错误脱敏。
- TTS 服务测试：空文本拒绝、长文本截断、音色格式校验、临时 mp3 写入和播放器调用。
- TTS 配置 Provider 测试：API Key 加密本地保存，启用后可生成引擎和服务，结构化备份不包含 TTS 密钥 / Base URL / 模型 / 音色配置。
- 消息气泡 TTS 测试：assistant 非空文本展示播报按钮，用户消息和空 assistant 消息不展示；播放中展示停止按钮；生成中展示禁用状态。
- TTS 播放事件测试：`AudioPlaybackEvent` 解析原生完成 / 停止 / 错误回调；聊天页收到匹配当前音频路径的完成事件后自动恢复为“语音播报”按钮，防止播放结束后 UI 误停留在“停止播报”。
- 原生音频播放通道静态测试：Android / iOS 注册 `simichat/audio_player`，并分别使用 `MediaPlayer` / `AVAudioPlayer`。
- 设置页语音输入状态与配置测试：未配置 / 已配置 STT 引擎两种状态均可展示，配置弹窗不回显明文密钥。
- 输入栏录音按钮组件测试：开始录音、停止后添加音频附件、录音中禁用发送。
- 音频附件 base64 读取测试：校验 `.m4a` 等音频会生成 base64、MIME 和格式字段。
- inline base64 语音解析测试：覆盖 `data:audio/...;base64,...`、中文 marker、非法 payload 和超大 payload，本地解析后正文不再保留原始 base64。
- base64 语音真机发送 smoke：Pixel 8 上通过 `integration_test/mobile_base64_audio_smoke_test.dart` 验证 UI 粘贴 base64 音频、audio 附件归档、fake STT ready sidecar、模型请求仅携带转写文本且不含原始 base64、SSE assistant 回复落库和展示。
- OpenAI 兼容 STT 网络真机 smoke：Pixel 8 上通过 `integration_test/mobile_stt_network_smoke_test.dart` 验证未配置独立 STT 时复用当前 `openai_chat` 渠道发起 multipart `/v1/audio/transcriptions`，sidecar ready 后再发送净化后的聊天请求。
- 真机录音按钮 smoke：Pixel 8 上通过 `integration_test/mobile_voice_recording_smoke_test.dart` 验证聊天页麦克风按钮、Android 原生 `MediaRecorder`、`.m4a` audio 附件、STT fallback、ready sidecar 和净化后聊天请求闭环。
- OpenAI 兼容 TTS 网络真机 smoke：Pixel 8 上通过 `integration_test/mobile_tts_network_smoke_test.dart` 验证 assistant 播报按钮、`/v1/audio/speech` JSON 请求、临时音频写入、播放接口调用、停止播报和 UI 状态回退。
- 原生音频播放通道真机 smoke：Pixel 8 上通过 `integration_test/mobile_native_audio_player_smoke_test.dart` 验证 Android `MediaPlayer`、低振幅应用私有目录 WAV、停止事件回传和无错误事件；该 direct-channel smoke 显式跳过音频焦点请求，避免真机测试发出明显提示音。
- Android 音频焦点回归：`test/core/microphone_permission_manifest_test.dart` 锁定原生播放器的 `AudioFocusRequest` / `AudioManager` / `OnAudioFocusChangeListener` / `requestAudioFocus` / `abandonAudioFocus` 路径；`test/core/text_to_speech_service_test.dart` 锁定正式 `playFile()` 不传测试跳过焦点参数，并覆盖 `AUDIO_FOCUS_DENIED` 无 message 时的明确中文提示；全量 334 个测试、analyze、临时 sqlite hook 下 Android debug APK / iOS Debug 构建与 Pixel 8 三条原生音频 smoke 均已通过，真实外部焦点抢占和 iOS 真机音频中断仍待复验。
- iOS 音频中断回归：`test/core/microphone_permission_manifest_test.dart` 锁定 `AVAudioSession.interruptionNotification`、`AVAudioSessionInterruptionTypeKey`、interruption began 停止播放、`setActive(false)` 和 `notifyOthersOnDeactivation`；iOS Debug `Runner.app` 已构建通过，真实设备中断仍待复验。
- 聊天音频前置转写测试：校验 audio-only 消息使用 STT 转写文本进入普通聊天，上下文不包含音频 base64；OpenAI 兼容 STT 引擎测试覆盖 multipart `/v1/audio/transcriptions` 请求；iOS 原生 Speech MethodChannel 测试覆盖 `transcribeFile` 调用和权限错误映射。
- 导出包附件完整性测试：非语音附件复制到 `attachments/`，路径净化，不泄露源目录，跳过 audio / 缺失附件。
- 导入 `attachments/` 文件恢复测试。
- 聊天核心数据库快照恢复测试：恢复 sessions / messages / attachments，并重定向附件 localPath。
- STT/TTS 厂商预设测试：验证 OpenAI / Groq / 自定义 OpenAI 兼容预设能力、`/v1` 后缀归一、设置页下拉展示和选择 Groq STT 后自动填充 Base URL / 模型。
- 后续补充：更多非 OpenAI 兼容语音厂商预设、真实移动端网络转写长音频测试、真机长时间播报和播放中断场景测试。

## 6. 近期 TODO

- [x] 附件类型识别、数量限制、大小限制。
- [x] 发送前校验附件存在性，避免半残缺消息。
- [x] 附件策略单元测试。
- [x] 消息气泡展示附件文件卡片：文件名、类型图标、大小。
- [x] 消息气泡展示本地图片缩略图，保留文件名 / 大小且不暴露完整本地路径。
- [x] 语音文件附件识别、原始语音文件应用私有目录归档、音频卡片展示、转写稿件 Markdown 草稿归档。
- [x] STT 可注入服务管线：配置引擎后自动转写归档音频并更新转写 sidecar。
- [x] 语音转写稿件状态与失败脱敏：导出 / Obsidian 同步读取的 `audio_transcripts/*.md` 明确包含 `pending` / `ready` / `empty` / `failed`，失败原因不泄露本机路径、密钥、令牌或 URL。
- [x] 消息音频卡片展示转写状态：本地 sidecar 更新后刷新卡片状态，便于用户在聊天里直接看到“等待转写 / 转写完成 / 未识别到文字 / 转写失败”。
- [x] 音频转写稿详情查看 / 复制：音频卡片可打开转写详情，`ready` 正文可复制，失败 / 空结果只展示脱敏状态说明，不暴露 sidecar 绝对路径。
- [x] 移动端麦克风权限声明：iOS `NSMicrophoneUsageDescription`、Android `RECORD_AUDIO`。
- [x] 设置页“语音与多模态 / 语音输入”状态入口：展示权限声明、STT 引擎状态和语音文件附件临时路径说明。
- [x] OpenAI 兼容 STT 引擎与配置入口：设置页保存启用状态、Base URL、模型和加密 API Key，发送 / 录制语音后自动调用 `/v1/audio/transcriptions` 更新转写 sidecar。
- [x] 移动端录音按钮与原生运行时权限申请：Android `MediaRecorder` / iOS `AVAudioRecorder` 录制 `.m4a`，停止后添加为音频附件。
- [x] 音频附件发送前 STT 音频接口转写：发送语音时优先调用显式 STT 配置，未配置时复用当前 OpenAI 兼容聊天渠道调用 `/v1/audio/transcriptions`；成功后把转写文本作为普通聊天内容发送，不再把 audio base64 交给聊天模型。
- [x] base64 语音文本粘贴转写：支持 `data:audio/...;base64,...` 和“base64 的语音字符：...”输入，先解码为临时音频附件再走 STT 级联，原始 base64 不入库、不进 Markdown、不进模型上下文。
- [x] base64 语音真机发送 smoke：Pixel 8 通过 UI 粘贴 base64 音频、audio 附件归档、fake STT ready sidecar、净化后模型请求和 SSE 回复闭环；详见 `docs/mobile-base64-audio-smoke-2026-07-06.md`。
- [x] OpenAI 兼容 STT 网络真机 smoke：Pixel 8 通过复用当前 `openai_chat` 渠道调用 multipart `/v1/audio/transcriptions`、ready sidecar、净化后聊天请求和 SSE 回复闭环；详见 `docs/mobile-stt-network-smoke-2026-07-06.md`。
- [x] 真机录音按钮 smoke：Pixel 8 通过聊天页麦克风按钮、Android 原生录音、audio 附件归档、STT fallback、ready sidecar、净化后聊天请求和 SSE 回复闭环；详见 `docs/mobile-voice-recording-smoke-2026-07-06.md`。
- [x] OpenAI 兼容 TTS 网络真机 smoke：Pixel 8 通过 assistant 播报按钮、TTS JSON 请求、临时音频写入、播放接口调用、停止播报和 UI 状态回退闭环；详见 `docs/mobile-tts-network-smoke-2026-07-06.md`。
- [x] 原生音频播放通道真机 smoke：Pixel 8 通过应用私有目录 WAV、Android `MediaPlayer`、停止事件回传和无错误事件闭环；详见 `docs/mobile-native-audio-player-smoke-2026-07-06.md`。
- [x] iOS 系统 Speech 原生识别兜底：在线 STT 失败或返回空结果后，通过 `simichat/native_speech_to_text` 调用 `SFSpeechURLRecognitionRequest` 识别应用私有目录内录音；权限说明、路径边界和 MethodChannel 错误映射已测试。
- [x] 附件导出复制非语音原文件到 `attachments/`，并支持安全导入恢复文件和 SQLite 附件元数据。
- [x] OpenAI 兼容 TTS 语音播报：assistant 回复一键播报、临时 mp3、Android / iOS 原生播放通道、TTS API Key 本地加密配置。
- [x] TTS 播放停止控制：播报生成中禁用状态、播放中停止按钮、停止后清理当前播报状态。
- [x] TTS 播放完成事件回传：Android / iOS 原生播放器完成 / 停止 / 错误事件回传，聊天页按当前音频路径自动清理播报状态。
- [x] STT/TTS 厂商预设 v1：OpenAI 官方、Groq STT、自定义 OpenAI 兼容；设置页语音输入 / 语音播报弹窗可选择预设并自动填充 Base URL、模型和音色。
- [x] Android 音频焦点基础处理：正式原生播放前请求焦点，焦点丢失停止播放，允许 duck 时降低音量并在恢复时还原；代码级回归、analyze、Pixel 8 静音原生音频 smoke、debug-only competing AudioFocus smoke、独立 helper APK 外部焦点抢占 smoke 和一键音频焦点 suite 已通过；direct-channel smoke 仍显式跳过焦点请求，真实来电 / 闹钟 / 第三方媒体播放器抢占仍待复验。详见 `docs/mobile-audio-focus-hardening-2026-07-06.md`。
- [x] iOS AVAudioSession 中断基础处理：监听 interruption began，当前播放中会停止并回传 stopped，播放完成 / 错误 / 主动停止 / 启动失败释放音频会话；代码级回归和 iOS Debug 构建已通过，真实来电 / 耳机 / 系统中断仍待补。详见 `docs/mobile-audio-focus-hardening-2026-07-06.md`。
- [ ] 继续补更多非 OpenAI 兼容语音厂商，并完成真机长时间播报、真实外部音频焦点抢占、iOS 真机音频中断和后台场景复验。
