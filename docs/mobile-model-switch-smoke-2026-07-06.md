# Pixel 8 真机模型切换 / 切换后真实发送验证记录（2026-07-06）

## 目标

在不依赖外部模型 API Key、不卸载、不清数据的前提下，用本机 OpenAI 兼容 mock 服务验证 Pixel 8 真机对话页模型切换主链路：顶部模型菜单可切换、会话默认模型落库、时间线生成 `model_switch` 记录、切换后的真实发送使用新模型。

## 设备与本地服务

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

本地 mock 服务：Mac 本机 `127.0.0.1:18080`，通过 adb reverse 暴露给设备：

```bash
adb -s 37101FDJH0077P reverse tcp:18080 tcp:18080
```

mock 服务支持：

- `GET /v1/models` 返回 `simichat-mock-a`、`simichat-mock-b`。
- `POST /v1/chat/completions` SSE 流式输出。
- 按请求中的 `model` 返回不同正文：`MOCK-A reply 20260706` 或 `MOCK-B reply 20260706`。
- 请求日志写入 `/tmp/simichat_model_switch_mock_requests.jsonl`。

## 测试数据说明

本轮使用 debug 包 `run-as top.simitalk.aichat` 安全修改应用私有 SQLite 数据库，未卸载应用，未清空应用数据。

本地 DB 备份目录：`/tmp/simichat-model-switch-db.vTnYdB/`。

复用上一轮真实发送 smoke 会话，并在同一 mock channel 下补充两个模型：

- channel id：`device-mock-channel-20260706`。
- channel name：`Pixel8 local Mock OpenAI`。
- base URL：`http://127.0.0.1:18080`。
- protocol：`openai_chat`。
- model A id：`device-mock-model-a-20260706`。
- model A name：`simichat-mock-a`。
- model B id：`device-mock-model-b-20260706`。
- model B name：`simichat-mock-b`。
- session id：`device-real-send-smoke-20260706`。
- session title：`真机真实发送 smoke`。
- seed 后 session default model：`device-mock-model-a-20260706`。

种入后 DB 验证：

```text
sessions.default_channel_model_id = device-mock-model-a-20260706
channel_models:
  device-mock-model-20260706    simichat-mock    is_default=0
  device-mock-model-a-20260706  simichat-mock-a  is_default=1
  device-mock-model-b-20260706  simichat-mock-b  is_default=0
model_switch records before UI switch = 0
```

启动后 UI dump / 截图 `/tmp/simichat_model_switch_initial.png` 显示顶部会话：

```text
真机真实发送 smoke
Pixel8 local Mock OpenAI / simichat-mock-a
```

结论：真机读取到 seed 后的 A 模型，并作为当前会话默认模型展示。

## 模型菜单与 UI 切换验证

点击顶部模型下拉箭头后，UI dump 验证菜单包含：

```text
Pixel8 local Mock OpenAI
simichat-mock
simichat-mock-a
simichat-mock-b
```

点击 `simichat-mock-b` 后，UI dump / 截图 `/tmp/simichat_model_switch_after_switch.png` 显示：

```text
真机真实发送 smoke
Pixel8 local Mock OpenAI / simichat-mock-b

已切换模型：Pixel8 local Mock OpenAI / simichat-mock-a → Pixel8 local Mock OpenAI / simichat-mock-b
后续回复将默认使用 Pixel8 local Mock OpenAI / simichat-mock-b。
```

DB 验证：

```text
sessions.default_channel_model_id = device-mock-model-b-20260706
model_switch records = 1
latest model_switch channel_model_id = device-mock-model-b-20260706
```

最新 `model_switch` 记录内容为：

```text
已切换模型：Pixel8 local Mock OpenAI / simichat-mock-a → Pixel8 local Mock OpenAI / simichat-mock-b
后续回复将默认使用 Pixel8 local Mock OpenAI / simichat-mock-b。
```

结论：Pixel 8 顶部模型菜单可完成 A → B 切换；会话默认模型已落库；对话时间线生成了 `model_switch` system 记录。

## 切换后真实发送验证

切换到 B 后，在输入框发送一条测试消息。原计划输入 `switchtest20260706`，设备当前中文键盘实际落库为：

```text
switch test20260706
```

这不影响本轮目标，因为验证重点是“切换后的真实发送是否使用 B 模型”。

UI dump / 截图 `/tmp/simichat_model_switch_after_send.png` 显示：

```text
switch test20260706
Pixel8 local Mock OpenAI / simichat-mock-b
MOCK-B reply 20260706
29 tokens · 461ms
```

mock 服务请求日志：

```json
{"path":"/v1/chat/completions","model":"simichat-mock-b","stream":true,"message_count":8,"last_user":"switch test20260706","system_has_reflection":true}
```

DB 验证：

```text
sessions.default_channel_model_id = device-mock-model-b-20260706
latest user      = switch test20260706
latest assistant = MOCK-B reply 20260706
assistant.channel_model_id = device-mock-model-b-20260706
assistant tokens = 29
assistant response_ms = 461
```

结论：模型切换后，Pixel 8 真机真实发送使用了新模型 `simichat-mock-b`；请求日志、SQLite 和 UI 三方证据一致。

## 当前边界

本轮已验证：

- Pixel 8 顶部模型菜单能列出同一渠道下多个模型。
- 当前会话可从 `simichat-mock-a` 切换到 `simichat-mock-b`。
- 切换后 `sessions.default_channel_model_id` 更新为 B。
- 切换时间线生成 `message_type='model_switch'` system 消息。
- 切换后的真实发送请求使用 B 模型，assistant 回复按 B 模型落库并在 UI 展示。
- 请求仍带入本地 Reflection 短期提示。

本轮未覆盖：

- iPhone13 的模型切换 / 真实发送。
- 外部真实模型 API。
- 跨渠道切换失败回滚场景。
- 删除模型后的引用清理真机验证。
- 语音、附件、网络切换、后台恢复。
