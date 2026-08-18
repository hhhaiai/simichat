# ChatGPT 风格多模态 Composer 与媒体消息

> 最后更新：2026-08-18。Pixel 8 production Release 覆盖安装、模型切换隔离 smoke、Composer 声音工具 UI、图片 / 媒体 / 语音回归已复核；真实供应商云端媒体与语音质量仍以外部配置后的独立 E2E 为准。

## 目标

对话页采用 ChatGPT 风格的单一 Composer：文本输入是主路径，`+` 工具菜单承载
文件、参考图、图片编辑、视频、语音和音乐动作；动作结果仍然回到同一条会话时间线，
不跳转到独立的“生成器”页面。

## Composer 交互

- 输入框支持多行文本、移动端录音和多文件选择。
- 桌面端 Composer 支持一次拖入多个文件；拖入目录会被忽略，无法直接使用稳定路径的拖入内容会先写入应用临时目录，再通过 `.part -> rename` 原子提交。
- 文件选择默认允许一次选择多个文件；图片、视频、音频、PDF 和未知扩展名普通文件
  都保留为附件。未知扩展名归为 `document`，不会因为厂商格式变化而被 UI 丢弃。
- 图片作为普通附件发送时继续经过 Vision 模型门禁；图片生成动作会把已选第一张图片
  作为参考图发送到 `images/edits` 兼容入口。
- `+` 菜单提供：图片生成、图片编辑、视频生成、声音合成、声音克隆、声音设计、生成音乐、
  深度思考和替身回复。小屏幕只把次要动作放入可滚动菜单，避免 Composer 挤压文本输入宽度。
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
该证据只证明客户端入口与状态边界，不替代真实 TTS、声音克隆或声音设计供应商 E2E。

## 通用媒体接口

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
