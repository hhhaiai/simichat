# 渠道额度查询

## 入口

设置 → 渠道 → 展开渠道。每个非 SimiRouter 渠道显示“查询额度”；查询是手动触发，不会在打开设置页时遍历所有渠道，也不会把响应写入 SQLite、备份或聊天记录。

## CCSwitch / Claude OAuth

CCSwitch 使用 Anthropic OAuth 用量接口：

```text
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <OAuth token>
anthropic-beta: oauth-2025-04-20
```

SimiChat 将渠道加密 API Key 字段作为 OAuth token，解析 `five_hour`、`seven_day`、`seven_day_opus`、`seven_day_sonnet` 等窗口的 `utilization` 和 `resets_at`。`utilization` 同时兼容 0–1 比例和 0–100 百分比。

## OpenAI 兼容 / new-api

```text
GET <baseUrl>/dashboard/billing/usage
GET <baseUrl>/dashboard/billing/subscription   # 可选
Authorization: Bearer <API key>
```

`total_usage` 按 new-api 约定以 `500000 quota = 1 USD` 换算；无额度接口、鉴权失败、限流和超时会显示可重试的中文错误，不会回显响应正文或密钥。

## 账号额度（CCSwitch / new-api）

设置页的 SimiRouter 卡片同时提供“消耗额度”和“账号额度”。账号额度使用当前渠道
的同一 Base URL 与 Token 请求：

```text
GET <baseUrl 去掉末尾 /v1>/api/user/self
Authorization: Bearer <token>
New-Api-User: <用户 ID，未配置时为 1>
Content-Type: application/json
```

响应支持直接对象或 `data` 包裹对象，兼容 `quota` / `balance` /
`remaining_quota`、`used_quota`、`id` 和 `username` 等字段。查询失败不会覆盖上一次
成功快照，也不会把 Token、响应正文或账号敏感字段写入聊天记录、导出包或日志。

## 验证

```bash
flutter --no-version-check test --no-pub --no-test-assets --concurrency=1 \
  test/channel_quota_client_test.dart test/simirouter_billing_client_test.dart
```
