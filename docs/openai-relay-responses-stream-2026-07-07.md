# OpenAI Relay Responses API 流式输出兼容（2026-07-07）

## 目标

补齐本地 OpenAI Relay `/v1/responses` 的 `stream=true` 兼容能力，提升浏览器客户端和 OpenAI Responses 风格客户端接入成功率；仍保持 Bearer 鉴权、CORS、安全响应头、审计脱敏和本地转发边界。

## 实现

- `lib/core/relay/openai_compatible_relay_server.dart`
  - `_handleResponses()` 不再拒绝 `stream=true`。
  - `_normalizeOpenAiRelayResponsesInput()` 对顶层 `input` 数组中的 `item_reference`、函数输出等非文本 item 不再整请求失败；会转成安全占位内容进入现有 content-part 降级流程，且不泄露原始 `id` / payload。
  - `stream=true` 时复用现有 Responses input 解析、远端图片安全策略、Vision 路由检查和并发限制。
  - 调用 `_writeStreamingResponse()` 输出 `text/event-stream`，本轮继续补齐更接近 Responses 客户端预期的文本输出生命周期事件：
    - `event: response.created`
    - `event: response.in_progress`
    - `event: response.output_item.added`
    - `event: response.content_part.added`
    - `event: response.output_text.delta`
    - `event: response.output_text.done`
    - `event: response.content_part.done`
    - `event: response.output_item.done`
    - `event: response.completed`
    - 上游流式异常时输出 `event: response.failed` 和 `data: [DONE]`
    - `data: [DONE]`
  - SSE 事件只输出响应 id、模型 id、增量文本、完成 / 失败状态和 token 占位统计；不回显 Bearer token、API Key、上游 Base URL、本机路径、远端图片 URL、data URL、base64 或上游原始异常。
  - 与聊天补全流式一致，流式 Responses 不做中途模型回退，避免 SSE 已输出后切换模型破坏协议；非流式 Responses 仍保留候选失败回退能力。

## 回归测试

- `test/core/openai_compatible_relay_server_test.dart`
  - 新增 `POST /v1/responses safely degrades unsupported input items`：`input` 同时包含 `input_text` 与 `item_reference` 时，旧逻辑红灯返回 `400`；修复后返回 200，上游只看到正文和 `item_reference` 安全占位，响应不包含原始 reference id。
  - 将旧的 `POST /v1/responses rejects unsupported streaming safely` 替换为 `POST /v1/responses streams Responses-compatible SSE chunks`。
  - 红灯阶段旧实现返回 `400 unsupported_stream`。
  - 修复后验证：
    - HTTP 200。
    - `Content-Type: text/event-stream`。
    - SSE 按顺序包含 `response.created`、`response.in_progress`、`response.output_item.added`、`response.content_part.added`、两段 `response.output_text.delta`、`response.output_text.done`、`response.content_part.done`、`response.output_item.done`、`response.completed`。
    - 多个 chunk 依次输出 `delta=A` / `delta=B`，完成事件汇总 `text=AB` / `output_text=AB`。
    - 输出 item / content part 使用同一个安全生成的 `msg-*` id，不回显外部 reference id。
    - SSE 最后包含 `data: [DONE]`。
    - 响应体不包含本地 Bearer token。
  - 新增 `POST /v1/responses streams safe failed event on upstream error`：上游流已输出部分 delta 后抛出包含密钥 / 本机路径字样的异常时，SSE 会输出安全 `response.failed`、`code=upstream_error` 和 `[DONE]`，不会回显异常详情。

## 验证记录

```bash
flutter --no-version-check test --no-pub -r expanded \
  test/core/openai_compatible_relay_server_test.dart \
  --plain-name "POST /v1/responses streams Responses-compatible SSE chunks"
flutter --no-version-check test --no-pub -r expanded \
  test/core/openai_compatible_relay_server_test.dart \
  --name "POST /v1/responses safely degrades unsupported input items"
flutter --no-version-check test --no-pub -r expanded \
  test/core/openai_compatible_relay_server_test.dart \
  --plain-name "POST /v1/responses streams safe failed event on upstream error"
dart format lib/core/relay/openai_compatible_relay_server.dart \
  test/core/openai_compatible_relay_server_test.dart
flutter --no-version-check test --no-pub -r expanded \
  test/core/openai_compatible_relay_server_test.dart
```

结果：

- 红灯：流式目标用例返回 `400`，证明旧实现明确拒绝 Responses 流式输出。
- 红灯：`item_reference` 兼容用例返回 `400`，证明旧 parser 对顶层 unsupported item 直接拒绝整请求。
- 修复后两个目标用例通过。
- 二次红灯：补充 item / content part 生命周期断言后，旧最小 SSE 只输出 `created` / `delta` / `completed`，目标用例在事件顺序断言处失败。
- 二次修复后目标用例通过。
- 三次红灯：继续补 `response.in_progress` 事件断言后，旧事件序列在 `response.created` 后直接进入 `response.output_item.added`，目标用例失败；修复后目标用例通过。
- 四次红灯：新增上游流式异常用例后，旧实现只输出到最后一个 delta，缺少 `response.failed` / `[DONE]`；修复后目标用例通过。
- 当前 `test/core/openai_compatible_relay_server_test.dart` 全文件 24 项通过。

## 边界

- 当前实现是本地 Relay 的 Responses SSE 文本生命周期兼容：覆盖 created、in_progress、output item、content part、文本 delta / done、完成 / 失败事件和 `[DONE]`；不在流式过程中做路由候选回退。
- `thinking` / reasoning chunk 暂不映射到 Responses 专用 reasoning 事件；如后续客户端需要，可在不泄露思考内容边界的前提下单独补协议映射。
- `item_reference` 当前只做安全占位，不会解析或恢复历史 response item；真正跨 response 状态还需要显式本地状态设计。
- 真机长时间运行、局域网客户端兼容性和更多第三方 SDK 仍需后续 smoke / 真实客户端复验。
