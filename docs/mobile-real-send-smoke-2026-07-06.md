# Pixel 8 真机真实发送 / 重试 / 停止 / 历史搜索验证记录（2026-07-06）

## 目标

在不依赖外部模型 API Key、不卸载、不清数据的前提下，用本机 OpenAI 兼容 mock 服务验证 Pixel 8 真机聊天主链路：模型可用、真实发送、SSE 流式回复、重试、停止慢流、历史搜索。

## 设备与本地服务

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

本地 mock 服务：Mac 本机 `127.0.0.1:18080`，通过 adb reverse 暴露给设备：

```bash
adb -s 37101FDJH0077P reverse tcp:18080 tcp:18080
```

mock 服务支持：

- `GET /v1/models`。
- `POST /v1/chat/completions` 非流式 JSON。
- `POST /v1/chat/completions` SSE 流式输出。
- 慢流版本每约 0.9 秒输出一个 chunk，用于停止测试。

## 测试数据说明

本轮使用 debug 包 `run-as top.simitalk.aichat` 安全修改应用私有 SQLite 数据库，未卸载应用，未清空应用数据。

本地 DB 备份目录：`/tmp/simichat-real-send-db.XGDVpu/`。

种入内容：

- channel id：`device-mock-channel-20260706`。
- channel name：`Pixel8 local Mock OpenAI`。
- base URL：`http://127.0.0.1:18080`。
- protocol：`openai_chat`。
- API Key：仅本轮本地 mock 用的假 key，以应用既有加密格式写入；不是外部真实密钥。
- model id：`device-mock-model-20260706`。
- model name：`simichat-mock`。
- session id：`device-real-send-smoke-20260706`。
- session title：`真机真实发送 smoke`。
- session default model：`device-mock-model-20260706`。

启动后截图 `/tmp/simichat-real-send-launch.png` 显示：

- 顶部标题：`真机真实发送 smoke`。
- 顶部模型：`Pixel8 local Mock OpenAI / simi...`。
- 空会话引导和输入框可见。

结论：真机读取到本地 mock 模型，且会话默认模型已生效。

## 真实发送验证

输入框通过 adb 输入一条测试消息并点击发送。由于设备当前中文键盘会把 adb 空格转义输入处理成候选 / 字面字符，本轮实际用户消息中包含 `%20` 和少量中文候选字；这不影响链路验证，因为目标是验证真实发送和模型响应闭环。

DB 验证：

```sql
select role, substr(content,1,160), channel_model_id
from messages
where session_id='device-real-send-smoke-20260706'
order by created_at;
```

结果包含：

```text
user|Pixel8％20real％20你的％20沙摩柯％2020260706 ...|
assistant|Pixel8 mock reply 20260706: received Pixel8...|device-mock-model-20260706
```

UI 截图 `/tmp/simichat-real-send-after-send2.png` 显示：

- 用户消息气泡可见。
- assistant 回复正文 `Pixel8 mock reply 20260706: received ...` 可见。
- 回复下方展示 `147 tokens · 772ms`。
- 回复模型标注为 `Pixel8 local Mock OpenAI / simichat-mock`。

mock 服务日志显示设备发起了真实请求：

- path：`/v1/chat/completions`。
- model：`simichat-mock`。
- `stream=true`。
- 请求中包含 system prompt 和用户消息。
- system prompt 中包含本机 Reflection 短期提示片段，说明前一轮 Dreaming / Reflection 生成的短期提示已经进入真实发送上下文。

结论：Pixel 8 真机真实发送、SSE 流式回复、消息落库和 UI 展示均通过。

## 重试验证

点击 assistant 回复下方重试按钮后，DB 中同一会话新增一组用户 / assistant 消息：

```text
user|Pixel8...|
assistant|Pixel8 mock reply 20260706: received Pixel8...|device-mock-model-20260706
user|Pixel8...|
assistant|Pixel8 mock reply 20260706: received Pixel8...|device-mock-model-20260706
```

mock 服务请求数从 1 增加到 2。

结论：Pixel 8 真机重试按钮会重新发送上一条用户消息，并再次通过同一模型渠道生成 assistant 回复。

## 停止慢流验证

将 mock 服务切换为慢流版本后，输入无空格 ASCII：

```text
stoptest20260706
```

发送后约 1.2 秒点击输入框右侧停止按钮。

DB 立即显示第三轮消息：

```text
user|stop test20260706|
assistant|SLOW Pixel8 chunk 1 chunk 2|device-mock-model-20260706
```

继续等待约 6 秒后再次检查，assistant 内容长度仍为 27，未继续增长为完整 8 个 chunk。mock 服务日志记录：

```text
broken_pipe=true
```

结论：Pixel 8 真机停止按钮能够中断慢速 SSE 连接；当前实现会保留停止前已收到的部分 assistant 回复，这是现有行为，需要后续产品判断是否要标记“已停止 / 部分回复”或改为丢弃部分回复。

## 历史搜索验证

打开移动端抽屉后，历史列表显示：

- `真机真实发送 smoke`，时间 `07-06 02:58`。
- `真机长会话反思评估`，时间 `07-06 01:37`。

在搜索框输入并提交 `smoke` 后，UI dump 验证：

```text
contains smoke session True
contains long session False
```

截图 `/tmp/simichat-real-send-history-search-committed.png` 对应该状态。

结论：真机历史搜索可按标题过滤到本轮 smoke 会话，并排除不匹配的长会话。

## 日志检查

本轮 `logcat` 未见 SimiAIChat 相关 Flutter / Dio / OpenAI 异常。日志中存在 Android 系统噪声，例如 Nearby / NullBinder / BestClock，与本应用发送链路无直接关系。

## 当前边界

本轮已验证：

- Pixel 8 真机默认模型读取和展示。
- 本地 OpenAI 兼容 mock 模型的真实发送。
- SSE 流式 assistant 回复落库和 UI 展示。
- Reflection 短期提示已进入真实发送 system prompt。
- assistant 回复重试。
- 慢流停止会断开上游连接，并保留部分回复。
- 历史搜索按标题过滤。

本轮未覆盖：

- 真机模型切换到另一个模型。
- iPhone13 的手工真实发送 / 重试 / 停止 / 搜索；可重复集成发送 smoke 已在 iPhone13 通过，见 `docs/mobile-device-integration-send-smoke-2026-07-06.md`。
- 外部真实模型 API。
- 语音、附件、网络切换、后台恢复。
- 停止后的产品语义优化，例如是否显示“已停止”状态、是否保留 / 丢弃 partial assistant。
