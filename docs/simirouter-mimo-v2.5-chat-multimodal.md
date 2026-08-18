# SimiRouter `mimo-v2.5-chat` 多模态契约

## 范围与结论

本次 P0 只定义客户端的模型能力门禁，不声称 SimiRouter 上游服务已经验证通过。精确模型 ID 为 `mimo-v2.5-chat`，比较时对模型 ID、协议和已持久化能力值做大小写归一化：

- `protocol=openai_chat` 或 `protocol=openai_response`；
- persisted capability 必须是 `chat`；
- 模型 ID 必须等于 `mimo-v2.5-chat`，不接受 provider 前缀、任意 suffix 或其他包含关系。

满足上述条件时，`ModelCapability.supportsVisionModel()` 返回 Vision 可用。显式 persisted `capability=vision` 仍然是更高优先级的能力声明，可覆盖模型名 veto；这不等于为 TTS、ASR 或声音模型凭名称授予 Vision。

以下名称不会继承该例外：

- `mimo-v2.5-tts`；
- `mimo-v2.5-asr`；
- `mimo-v2.5-voiceclone`；
- `mimo-v2.5-voicedesign`；
- `prefix-mimo-v2.5-chat`；
- `mimo-v2.5-chat-preview`、`mimo-v2.5-chat-v2` 等非精确后缀。

实现位置：`lib/core/ai/model_capability.dart`。SimiRouter 的 provider preset 是 `dwchainless`，推荐模型保留原有 `gpt-4o-mini`、`deepseek-chat`、`qwen-plus`，并追加 `mimo-v2.5-chat`，实现位置为 `lib/core/ai/model_provider_preset.dart`。

## 已有 OpenAI Chat 路径可复用的部分

本任务没有修改 `lib/core/ai/openai_chat_protocol.dart`、`lib/core/ai/attachment_helper.dart` 或共享发送路由。现有 OpenAI Chat 路径已经具备以下事实：

1. `OpenAiChatProtocol.nativeAttachmentTypes` 包含 `image` 和 `audio`。
2. 图片附件会沿现有请求构造路径编码为 OpenAI Chat content part：`type=image_url`，URL 形如 `data:<mime>;base64,<payload>`。现有行为由 `test/openai_chat_protocol_test.dart` 的 image data URL 用例覆盖。
3. 因此，本 P0 只让精确的 `mimo-v2.5-chat` 通过 Vision 门禁；不会复制或改写 `image_url` 序列化逻辑。

## `text_fallback` 与 `native_file` 边界

`text_fallback` 是受限的本地 UTF-8 文本提取，不是上游文件理解能力：

- 共享发送流程仅对 `document` 附件调用 `FileContentExtractor`，提取出的实际文本只合并到本次请求上下文；文件名不会伪装成文件内容，也不会把提取文本写入持久化用户消息。
- 当前限制是单文件最多 2 MiB、最多 20,000 行、单行最多 128 KiB；空文件、二进制、非法 UTF-8 和超限内容拒绝进入模型上下文。
- PDF、Office（`doc/docx/ppt/pptx/xls/xlsx` 等）和视频不会走 text fallback；当前 extractor 会返回 `unsupportedType`，保留可重试的附件错误边界。
- `native_file` 不是本次已验证的 SimiRouter 能力。没有 SimiRouter live contract 和 Key，本任务不猜测 PDF/Office/native file 的原生识别，也没有把这些类型加入 OpenAI Chat native attachment 集合。

对应实现与事实测试：`lib/core/ai/file_content_extractor.dart`、`lib/shared/providers/chat_provider.dart`、`test/file_content_extractor_test.dart`、`test/chat_provider_attachment_routing_test.dart` 以及本任务的 `test/simirouter_mimo_chat_capability_test.dart`。

## 未验证边界

- 未使用 SimiRouter live endpoint 或 Key；未验证 `mimo-v2.5-chat` 在云端是否已上架、是否实际接受图片、配额 / 错误码 / 限流和响应质量。
- 未验证 SimiRouter 的 `openai_response` 云端兼容性；本次仅扩展本地能力选择契约。
- 未声明 PDF、Office、`native_file` 或其他原生文件识别能力。若要支持，必须先获得并验证对应上游 contract，再单独实现协议、路由和测试。

## 2026-08-19 真实上游验证（补充）

使用用户提供的 SimiRouter 测试 Key 对真实上游做了回环验证：

- `POST /v1/chat/completions`，`mimo-v2.5-chat` + 真实照片（1024px 白猫图 data URL）两次请求均正确识别图片内容（“图片里是一只白色的猫…”），图片输入被正常处理。
- 此前 1x1 像素图的“无法回答”属于模型对不可解读输入的婉拒，不是渠道不支持识图。
- 同轮验证：`/v1/models` 返回 32 个模型且无能力元数据；`mimo-v2.5-tts`（alloy/中文）与 `mimo-v2.5-asr`（auto/zh 回环转写）均通过；`gpt-image-1.5` 生成与 `/v1/images/edits` multipart 编辑通过；`/v1/videos` 路由存在（`/v1/videos/generations` 为 Invalid URL，客户端默认端点已改为 `/v1/videos`）；`/v1/realtime` 路由存在；`/v1/dashboard/billing/usage` 与 `/v1/dashboard/billing/subscription` 可用（new-api 格式）。
- 结论：P0 门禁保留；`mimo-v2.5-chat` 与新增的 `mimo-v2.5-pro-chat` 精确 Vision 例外与上游行为一致。
