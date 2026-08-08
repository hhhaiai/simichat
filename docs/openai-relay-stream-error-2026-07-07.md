# OpenAI Relay 流式上游异常安全收口（2026-07-07）

## 目标

补齐本地 OpenAI Relay 在上游模型流式输出中途失败时的客户端兼容性：已经开始发送 SSE 后不能再返回普通 HTTP 错误，因此需要在流内给出安全失败事件 / 错误 payload，并以 `[DONE]` 结束，避免客户端一直等待或看到上游异常详情。

## 实现

- `lib/core/relay/openai_compatible_relay_server.dart`
  - `/v1/responses stream=true`：上游流式异常时输出 `event: response.failed`，`response.error.code=upstream_error`，随后输出 `data: [DONE]`。
  - `/v1/chat/completions stream=true`：上游流式异常时输出 OpenAI 风格 `data: {"error": ...}`，`code=upstream_error`，随后输出 `data: [DONE]`。
  - 两条流式路径都只返回安全中文摘要，不回显上游异常、Bearer token、API Key、本机路径、远端 URL、base64 或用户 prompt。
  - 两条流式路径的审计事件会把 `code` 记录为 `upstream_error`，HTTP 状态仍为已经开始 SSE 后的 200，避免用量统计把流内失败误记为 `ok`。
  - 流式请求仍不做中途模型回退，避免已经发出的 SSE chunk 与后续模型输出混在同一响应里。

## 回归测试

- `test/openai_compatible_relay_server_test.dart`
  - `POST /v1/responses streams safe failed event on upstream error`：先输出一个 delta，再模拟上游抛出包含 `sk-test` 和 `/Users/private` 的异常；断言响应包含 `response.failed`、`upstream_error`、`[DONE]`，且不包含敏感字样；审计事件记录 `code=upstream_error`、`stream=true`。
  - `POST /v1/chat/completions streams safe error on upstream failure`：先输出一个 chat delta，再模拟上游抛出包含 `sk-chat` 和 `/Users/private` 的异常；断言响应包含安全 `error` payload、`upstream_error`、`[DONE]`，且不包含敏感字样；审计事件记录 `code=upstream_error`、`stream=true`。

## 验证记录

```bash
flutter --no-version-check test --no-pub -r expanded \
  test/openai_compatible_relay_server_test.dart \
  --plain-name "POST /v1/chat/completions streams safe error on upstream failure"
flutter --no-version-check test --no-pub -r expanded \
  test/openai_compatible_relay_server_test.dart
flutter --no-version-check analyze
git diff --check
```

结果：

- 红灯：Chat Completions 流式异常用例旧实现只输出到最后一个 delta，缺少安全 `error` payload 和 `[DONE]`。
- 修复后目标用例通过。
- 继续补审计断言后，旧实现会把流内失败记录为 `ok`；修复后 Chat Completions 和 Responses 两条流式失败路径的审计 `code` 都是 `upstream_error`。
- 当前 `test/openai_compatible_relay_server_test.dart` 全文件 25 项通过。

## 边界

- 流式错误事件只表达“上游模型调用失败”，不区分 401 / 429 / 网络断开等细节，避免泄露上游状态或账户信息。
- 非流式请求仍保留候选模型回退；流式请求不做中途回退。
- 真机长时间运行和第三方 SDK 兼容仍需后续验证。
