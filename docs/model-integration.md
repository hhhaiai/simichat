# 多模型接入与个人接口中转方案

> 对应模块：M1。状态：多模型基础接入、对话级模型切换记录、主流厂商预设第一版、连通性测试结构化结果、自动重试、最近测试历史、批量渠道导入、OpenAI 兼容个人中转基础能力、多模态内容安全兼容降级、图片 data URL 端到端透传、视觉能力路由、能力可见性与远端图片 URL 安全下载透传已落地。最后更新：2026-06-27。

## 1. 目标

- 用户只输入接口密钥即可接入主流人工智能厂商。
- 同时保存 N 个厂商 / 渠道 / 模型。
- 单个对话内可切换模型，并保留调用记录。
- 支持免费模型批量引导接入。
- 长期支持个人接口中转服务，对外暴露 OpenAI 兼容接口。

## 2. 当前基础

当前已具备：

- `model_provider_preset.dart` 提供主流模型厂商预设：OpenAI、Claude / Anthropic、Gemini / Google、DeepSeek、通义千问 / 阿里云百炼、OpenRouter、Ollama。
- 设置页添加渠道时可选择厂商预设，自动填充渠道名称、Base URL 与协议类型，用户只需输入自己的 API Key，并仍可手动调整。
- `AiProtocol` 统一协议接口。
- `AiService` 根据协议分发。
- OpenAI Chat、OpenAI Responses、Claude、Gemini、Ollama 协议适配。
- `ModelFetcher` / `ModelTester` / `ModelCapability` 基础能力。
- `ModelTestResult` 已把连通性测试结果结构化为成功 / 失败摘要 / HTTP 状态码 / 详情 / 修复建议，并对常见密钥字面量做脱敏。
- 设置页单模型测试和一键测试全部模型使用结构化结果，能明确提示认证失败、权限不足、接口或模型不存在、限速 / 额度、厂商服务异常、超时、协议不支持等问题。
- `ModelTestRetryPolicy` 对超时、HTTP 429、HTTP 5xx、连接异常等瞬时失败自动重试；认证、权限、模型不存在、协议不支持等永久配置错误不重试。
- `model_test_history_provider.dart` 使用 SharedPreferences 本地保存每个模型最近一次连通性测试结果；设置页模型行展示最近测试成功 / 失败、HTTP 状态码、重试次数和测试时间。
- 渠道与模型已落库。
- 会话级模型选择与紧凑模型选择器。
- 对话内模型切换通过 `switchConversationModel` 统一入口处理：成功后更新会话默认模型，写入 `model_switch` 系统时间线记录，并在 UI 中用紧凑提示条展示。
- 模型切换失败会回滚 `selectedModelIdProvider` 与会话默认模型，避免 UI 与 SQLite 状态不一致。
- `model_switch` 记录只用于本地时间线和 Markdown 原始档案；`ContextBuilder` 只取 `original` / `summary` 参与上下文，避免切换日志污染模型请求。

## 3. 渠道模型

建议统一抽象：

```text
模型渠道 ModelChannel
- id
- name
- baseUrl
- protocol
- encryptedApiKey
- isEnabled
- proxyConfig
- rateLimitConfig
- createdAt / updatedAt

渠道模型 ChannelModel
- id
- channelId
- modelName
- displayName
- capability: chat / vision / embedding / image / audio / reasoning
- contextWindow
- maxOutputTokens
- isDefault
```

## 4. 接入流程

1. 用户选择厂商预设或自定义 OpenAI 兼容渠道。
2. 预设自动填充渠道名称、Base URL、协议类型；用户输入接口密钥并可手动调整。
3. 保存渠道后自动尝试拉取模型列表。
4. 对模型做能力识别。
5. 用户确认添加模型。
6. 在对话模型选择器中立即可用。
7. 后续可点击连通性测试验证单个模型或一键测试全部模型。


## 5. 厂商预设第一版

当前内置预设：

| 厂商 | 协议 | Base URL | 说明 |
| --- | --- | --- | --- |
| OpenAI | `openai_chat` | `https://api.openai.com/v1` | 官方 OpenAI API |
| Claude / Anthropic | `claude` | `https://api.anthropic.com` | Anthropic Messages API |
| Gemini / Google | `gemini` | `https://generativelanguage.googleapis.com` | Google Gemini API |
| DeepSeek | `openai_chat` | `https://api.deepseek.com/v1` | OpenAI 兼容接口 |
| 通义千问 / 阿里云百炼 | `openai_chat` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | DashScope OpenAI 兼容模式 |
| OpenRouter | `openai_chat` | `https://openrouter.ai/api/v1` | 多模型聚合平台 |
| Ollama 本地模型 | `ollama` | `http://localhost:11434` | 本地模型服务 |

设计约束：

- 预设只保存公共 Base URL、协议和文档链接，不内置任何 API Key。
- OpenAI 兼容预设允许用户编辑 Base URL，避免厂商路径调整后无法使用。
- 保存渠道后仍走现有自动获取模型 / 手动添加模型流程。
- 百度、讯飞等接口差异较大的厂商暂不硬编码不确定路径，后续在协议或 OpenAI 兼容路径验证后补充。

## 6. 免费模型引导与批量渠道导入

第一版不内置不可靠密钥，而是提供“用户自带 Key / 免费 Key 批量接入”的本地导入入口：

- 设置页 `模型渠道` 下提供 `批量导入渠道`。
- 用户粘贴 JSON，一次导入多个渠道和模型。
- API Key 只会通过 `KeyEncryptor` 加密写入本地 SQLite，不写入日志、文档或导入历史。
- 支持 OpenAI 兼容、OpenAI Responses、Claude、Gemini、Ollama。
- Ollama 本地模型允许空 Key；其他远程协议必须提供用户自己的 Key。
- Base URL 会复用 `normalizeUrl` 归一化，`localhost` / 私有 IP 默认使用 `http`，公网域名默认使用 `https`。

导入 JSON 支持两种根结构：

```json
{
  "channels": [
    {
      "name": "示例 OpenAI 兼容渠道",
      "baseUrl": "https://api.example.com/v1",
      "protocol": "openai_chat",
      "apiKey": "用户自己的 Key",
      "models": [
        {"name": "free-chat-model", "capability": "chat"},
        {"name": "free-embedding-model", "capability": "embedding"}
      ]
    }
  ]
}
```

或直接使用数组：

```json
[
  {
    "name": "Local Ollama",
    "baseUrl": "localhost:11434",
    "protocol": "ollama",
    "models": ["llama3.1"]
  }
]
```

字段约定：

| 字段 | 说明 |
| --- | --- |
| `name` / `channelName` | 渠道名称，必填 |
| `baseUrl` / `base_url` / `url` | 渠道 Base URL，必填 |
| `protocol` | 协议，默认 `openai_chat` |
| `apiKey` / `api_key` / `key` | 用户自己的 Key；非 Ollama 必填 |
| `models` | 可选，字符串数组或对象数组 |
| `models[].name/id/model/modelName` | 模型名 |
| `models[].capability/type` | `chat` 或 `embedding`，默认 `chat` |

当前未内置第三方免费源列表，避免把不稳定、违规或过期的公共密钥写进应用；后续可在此导入格式上叠加“免费模型来源说明 / 申请指引 / 稳定性等级 / 限额标签”。

## 7. 个人接口中转服务

目标：把本地多个模型聚合为统一 OpenAI 兼容接口，方便用户把 SimiChat 当作自己的本地接口中转层使用。

```text
OpenAI 兼容请求
  -> 本地 relay
  -> 路由策略：指定模型 / 默认模型 / 免费优先 / 快速优先
  -> 调用对应渠道
  -> 归一化非流式 / 流式响应
```

当前 v1（2026-06-27）已完成核心服务；v1.1 已补齐设置页用户可控启动入口；v1.2 已补齐访问审计、并发保护与局域网开放二次确认；v1.3 已补齐高级路由策略；v1.4 已补齐可配置并发上限与本地脱敏用量统计；v1.5 已补齐持久化脱敏审计明细与 JSON 导出；v1.6 已补齐 OpenAI 多模态 content part 安全兼容降级；v1.7 已补齐图片 data URL 端到端透传；v1.8 已补齐模型视觉能力路由；v1.9 已补齐模型能力可见性；v1.10 已补齐远端图片 URL 安全下载透传；v1.11 已补齐健康检查端点；v1.12 已补齐 CORS / 浏览器客户端兼容：

- `OpenAiCompatibleRelayServer`：本地 `HttpServer`，默认绑定 `127.0.0.1`，启动时必须提供至少 16 位本地 `relayToken`。
- 支持 `GET /health` 与 `GET /v1/health`：需要 Bearer 令牌，只返回 `status`、当前聊天并发、并发上限和远端图片下载开关，不触发模型列表、不暴露 API Key、上游 Base URL、模型 id 或本机路径。
- CORS / 浏览器客户端兼容 v1：所有响应加 `Access-Control-Allow-Origin: *`、`Cache-Control: no-store` 和 `X-Content-Type-Options: nosniff`；`OPTIONS` 预检不要求 Bearer 令牌，但只对 `/health`、`/v1/health`、`/v1/models`、`/v1/chat/completions` 返回 204，允许方法限定为 `GET / POST / OPTIONS`，允许头限定为 `authorization, content-type`。
- CORS 安全边界：预检不会返回模型列表、并发状态、令牌或用户内容；真实 `GET` / `POST` 请求仍必须携带正确 Bearer 令牌，未知路径的预检返回安全 `not_found`。
- 支持 `GET /v1/models`：返回 OpenAI 兼容模型列表，模型 id 使用本机 `ChannelModel.id`，不暴露 API Key 或上游 Base URL。
- 支持 `POST /v1/chat/completions`：解析 OpenAI 兼容 `messages`，支持 `stream=false` buffered 响应和 `stream=true` SSE 响应。
- `ChannelModelRelayBridge`：把 drift 数据库中已启用的聊天模型桥接到 relay；转发时才解密 API Key，并调用现有 `AiService.sendMessage()`。
- 多模态安全兼容降级 v1：`content` 数组中的 `text` / `input_text` / `output_text` 会转为 `AiMessage.content`；默认关闭远端图片下载时，远端 `image_url`、`file://`、`input_audio`、`file`、`input_file`、`video` 等非文本片段只写入安全占位，不读取、不下载、不把原始 URL / 路径 / 文件 id 写进 prompt。
- 图片 data URL 透传 v1：`image_url` / `input_image` 中合法的 `data:image/png|jpeg|gif|webp|bmp;base64,...` 会转为内存态 `AiMessage.attachments` 图片附件，沿现有 OpenAI Chat / OpenAI Responses / Claude / Gemini / Ollama 协议多模态链路发送给用户选择的上游模型。
- data URL 安全边界：只接受图片 MIME，base64 会规范化和校验，解码后最大 `1 MB`；不落库、不写入 Markdown、不进入审计事件 / 用量导出 / 日志；响应正文只返回模型输出，不回显图片 data URL。
- 模型视觉能力路由 v1：新增 `ModelCapability.vision`；渠道模型列表把 `chat` 与 `vision` 都视为可聊天模型，但继续排除 `embedding`；`ChannelModelRelayBridge` 会把视觉模型标记为 `supportsVision`。
- 图片请求路由边界：Relay 解析到内存态图片附件后会要求路由候选具备 `supportsVision`；直连纯文本模型会返回 OpenAI 兼容 `400` / `invalid_request_error` / `vision_model_required`，不会调用上游；别名 / 策略路由会过滤候选，仅把图片请求转发给视觉模型。
- 视觉能力识别：模型发现会根据显式 metadata（`capability` / `type` / `model_type` / `task` / `capabilities`）以及常见模型名（如 `vision`、`multimodal`、`llava`、`pixtral`、`qwen*-vl`、`gpt-4o`、`gpt-4.1`、`gemini`、`claude-3`、`claude-sonnet-4`、`claude-opus-4`）推断 vision；embedding 关键字优先，避免 `gemini-embedding` 这类模型被误判为视觉聊天模型。
- 模型能力可见性 v1：设置页手动添加模型可选择 `Chat 对话` / `Vision 视觉` / `Embedding 向量`，并提示“图片 / 多模态模型请选择 Vision”；批量导入 JSON 支持 `capability: "vision"`；模型列表使用中文能力标签。
- `/v1/models` 能力元数据：Relay 的 OpenAI 兼容模型列表在标准字段外追加脱敏 `capabilities` 与 `supports_vision`，不暴露 API Key / Base URL / 本机路径；路由别名在存在任一视觉候选时也标记 `supports_vision: true`，方便外部客户端判断 `simichat:*` 是否可承接图片请求。
- 远端图片 URL 安全下载透传 v1：设置页新增“允许下载远端图片 URL”开关，默认关闭；开启时必须二次确认风险；只处理 OpenAI `image_url` / `input_image` 中公网 HTTP(S) 图片 URL，下载成功后转为内存态 data URL 图片附件并复用现有视觉模型路由。
- 远端图片 URL 安全边界：同步 URL 检查拒绝非 HTTP(S)、空 host、userInfo、本机 / 内网 / link-local / multicast / unique-local IP、`localhost` / `*.localhost`；默认 fetcher 还会先解析 DNS 并拒绝任意不安全解析地址；请求限制 `image/jpeg` / `image/png` / `image/gif` / `image/webp` / `image/bmp`，最大 `1 MB`，默认 `3 秒`超时，不跟随重定向。
- 远端图片数据边界：远端 URL、下载后的图片 bytes / base64 只在本次请求内存态存在，不写入 SQLite、Markdown、审计明细、用量导出、结构化备份或日志；OpenAI 响应也不回显远端 URL / data URL / base64。
- 安全占位只保留规范化后的类型名，例如 `image_url`、`input_audio`；异常或疑似路径 / URL 的 `type` 会归一为 `unknown`，避免把任意字段名、远端 URL、data URL、本机路径、base64、文件 id 写进 prompt。
- `OpenAiRelayParsedMessages.omittedPartTypes` 本地统计被省略的非文本片段类型和数量；`attachedImageCount` 统计成功转为内存态附件的图片数量；这些统计不进入 OpenAI 响应和审计日志。
- 请求体默认限制 1 MB，避免本地接口被超大请求拖垮。
- 响应统一加 `Cache-Control: no-store` 和 `X-Content-Type-Options: nosniff`。
- 错误响应使用 OpenAI 兼容 `error` 结构，只返回安全摘要，不包含本机路径、令牌、渠道密钥、上游 Base URL 或原始异常详情。
- `OpenAiRelayController`：管理本地 relay 运行状态、令牌、端口和 `OpenAiCompatibleRelaySession` 生命周期。
- 设置页入口：`个人接口中转 / 本地 OpenAI Relay`，支持生成或输入至少 16 位 Bearer 令牌、启动 / 停止服务、展示 `http://127.0.0.1:<port>/v1` Base URL、说明 `/health` / `/v1/models` / `/v1/chat/completions` 路径和 CORS 兼容能力、复制 Base URL、复制 curl 示例。
- 令牌存储：令牌用 `Random.secure()` 生成，写入 SharedPreferences 前通过现有 `KeyEncryptor` 加密；结构化备份白名单不包含 `openai_relay_token_v1`，导出包不携带本地 relay 令牌。
- curl 示例默认使用 `<YOUR_RELAY_TOKEN>` 占位符，不把真实令牌复制到剪贴板。
- 访问审计 v1：`OpenAiRelayAuditEvent` 只记录方法、路径、HTTP 状态码、错误码、模型 id、是否流式、耗时和当前并发数；不记录 prompt、消息内容、Bearer 令牌、API Key、上游 Base URL 或本机路径。
- 并发保护 v1：聊天补全默认最多 4 个并发请求，超限时返回 OpenAI 兼容 `429` / `rate_limit_error` / `concurrency_limit`，并设置 `Retry-After: 1`；设置页展示本轮运行期间的处理次数、拒绝次数、并发拒绝次数和最近状态。
- 局域网开放二次确认 v1：默认仍只绑定 `127.0.0.1`；用户在设置页打开“允许局域网设备访问”并确认风险后，才会绑定 `0.0.0.0`；取消确认不改变访问范围；设置页展示局域网候选 IPv4 地址和启动后的局域网 Base URL。
- 局域网风险边界：开放局域网后，同一网络设备只要持有 Bearer 令牌即可调用本机 relay；界面明确提示只在可信网络中使用，不在公共 Wi-Fi 开启，不把令牌发给他人。
- 高级路由策略 v1：`/v1/models` 会暴露 `simichat:default`、`simichat:free`、`simichat:fast` 路由别名；请求缺省 `model` 或使用 `simichat:auto` 时按设置页选择的策略路由。
- 路由策略：支持“指定模型”（真实模型 id 直连）、“默认模型”（优先 `ChannelModel.isDefault`）、“免费优先”（优先空 Key / Ollama / Free 标识模型）、“本地 / 快速优先”（优先 Ollama、localhost、127.0.0.1、本地标识）。
- 回退策略：非流式请求在路由候选模型调用失败时，会继续尝试后续候选，成功响应的 `model` 字段写入实际命中的模型 id；所有候选失败时返回安全的 OpenAI 兼容 `502 upstream_error`，不暴露上游错误详情、API Key、prompt 或本机路径。流式请求不做中途回退，避免已经发送部分 SSE 后切换模型造成协议混乱。
- 路由策略持久化：设置页选择的路由策略写入 `openai_relay_route_strategy_v1`，但该键不进入结构化备份白名单，避免导入备份后意外改变本机中转暴露行为。
- 可配置并发上限 v1：设置页“并发上限”支持 1 / 2 / 4 / 8 / 16 / 32 个聊天请求，配置写入 `openai_relay_max_concurrent_requests_v1`；启动或运行中修改会重启 relay 并把新上限传给 `OpenAiCompatibleRelayServer`；超限仍返回安全的 OpenAI 兼容 `429 concurrency_limit`。
- 本地脱敏用量统计 v1：`OpenAiRelayUsageStats` 只累计请求总数、聊天请求数、流式请求数、成功 / 拒绝 / 未授权 / 限流 / 路由 / 上游错误次数、总耗时、平均耗时和最近状态；不记录 prompt、消息正文、Bearer 令牌、API Key、上游 Base URL、本机路径或用户原始内容。
- 用量统计持久化：统计写入 `openai_relay_usage_stats_v1`；写入采用串行队列，避免短时间多请求异步落盘乱序；用户在设置页点击“清空统计”会等待已有写入收口后删除本地统计。
- 备份边界：`openai_relay_max_concurrent_requests_v1` 与 `openai_relay_usage_stats_v1` 均不进入结构化备份白名单，避免导入备份改变本机暴露 / 负载行为或携带本机使用痕迹。
- 持久化脱敏审计明细 v1：`OpenAiRelayAuditLogEntry` 只保存最近 100 条事件，字段限定为方法、路径、HTTP 状态码、错误码、授权状态、完成时间、模型 id、是否流式、耗时和当前并发；不保存 prompt、messages、Bearer 令牌、API Key、上游 Base URL、本机路径或用户原始内容。
- 审计 model id 安全形态：写入审计事件前只保留 `A-Za-z0-9_.:-` 且不超过 160 字符的模型标识；异常请求把 `model` 伪装成 `file://`、路径或 URL 时不会进入审计明细 / 导出 JSON。
- 审计导出 v1：设置页支持“复制审计 JSON”，导出结构包含 schema、生成时间、隐私说明、`usageStats` 和 `auditLog`；适合用户自己排查本地 relay 运行情况，不自动上传、不进入云同步。
- 审计清理与备份边界：设置页支持清空审计明细；`openai_relay_audit_log_v1` 不进入结构化备份白名单，避免把本机调用痕迹随数据包迁移。

仍待实现：
- 真机长时间运行验证。
- 远端图片 URL 真机弱网 / DNS 变化场景复验与更强连接级 SSRF 防护评估。

## 8. 测试要求

- 协议解析单元测试。
- SSE 流式解析测试。
- 错误码保留测试：401 / 403 / 429 / 500。
- 模型列表解析测试。
- 切换模型后会话默认模型更新测试。
- 切换模型后时间线记录测试：`model_switch` 事件写入 SQLite，移动端 UI 展示提示条。
- 上下文隔离测试：`model_switch` 不进入 AI 请求上下文。
- 切换失败回滚测试：通过故障注入验证持久化失败时会恢复原 selectedModelId 和会话默认模型。
- 密钥不得进入日志的安全测试。
- 历史记录持久化测试：保存成功 / 失败结果、同模型覆盖、重启加载、敏感详情不落盘。



## 9. 连通性测试结构化结果

`ModelTester.testModelDetailed` 返回 `ModelTestResult`：

```text
ModelTestResult
- success: 是否成功
- summary: 用户可读结论
- detail: 脱敏后的原始错误摘要
- suggestion: 修复建议
- statusCode: HTTP 状态码，可为空
```

当前分类：

| 场景 | 结论 | 建议方向 |
| --- | --- | --- |
| HTTP 401 | 认证失败 | 检查 API Key 是否正确 / 过期 / 厂商不匹配 |
| HTTP 403 | 权限不足 | 检查模型权限、组织、地域、账号开通状态 |
| HTTP 404 | 接口或模型不存在 | 检查 Base URL 预设和模型名称 |
| HTTP 429 | 请求过于频繁或额度不足 | 检查限速、免费额度、账户余额 |
| HTTP 5xx | 厂商服务异常 | 稍后重试或切换模型 / 厂商 |
| 超时 | 测试超时 | 检查网络、代理、Base URL |
| 协议不支持 | 协议不支持 | 切换协议或模型能力 |
| 无有效响应 | 模型无有效响应 | 检查模型能力是否匹配 |

安全约束：

- 结构化详情会移除常见 `Bearer ...`、`sk-...`、`AIza...` 字面量。
- 设置页只显示摘要和建议，不主动输出 API Key。
- 批量测试仍逐个模型串行执行，避免对厂商接口造成突发压力。



## 10. 连通性测试自动重试策略

`ModelTester.testModelDetailed` 默认使用 `ModelTestRetryPolicy`，目标是提高主动连通性测试在临时网络波动、限速或厂商短暂异常下的稳定性，同时避免对明显配置错误进行无意义重试。

```text
ModelTestRetryPolicy
- maxAttempts: 默认 2，最多执行 1 次自动重试
- initialDelay: 默认 500ms
- backoffFactor: 默认 2
```

会自动重试的失败：

- HTTP 408 / 409 / 425 / 429。
- HTTP 5xx 厂商服务异常。
- 测试超时。
- 常见连接异常：SocketException、ClientException、connection reset / closed / refused、network unreachable、connection failed。

不会自动重试的失败：

- HTTP 401 认证失败。
- HTTP 403 权限不足。
- HTTP 404 接口或模型不存在。
- 协议不支持 / 模型能力不匹配等明确配置错误。

结果呈现：

- `ModelTestResult.attempts` 记录实际尝试次数。
- `compactMessage` 在发生重试后追加 `已重试 N 次`。
- 历史记录同步保存 `attempts`，设置页模型行也展示重试次数，便于用户判断失败是否已经自动恢复过。

安全与性能约束：

- 重试只发生在用户主动点击单模型测试或一键测试全部时，不会后台主动请求厂商。
- 批量测试仍逐个模型串行执行，避免并发压测厂商接口。
- 永久错误不重试，避免错误 API Key 或错误模型名造成额外请求。

## 11. 连通性测试历史记录

`ModelTestHistoryNotifier` 负责把用户主动触发的单模型测试、批量模型测试结果保存为本地最近状态。

```text
ModelTestHistoryItem
- modelId / modelName
- channelId / channelName
- success
- summary
- suggestion
- statusCode
- testedAt
```

当前策略：

- 存储位置：SharedPreferences，key 为 `model_test_history_v1`。
- 保存粒度：每个 `modelId` 只保留最近一次结果；同一模型新结果覆盖旧结果。
- 数量上限：最多保留 100 条，避免设置数据无限增长。
- 写入入口：
  - 设置页单模型“测试连接”完成后写入。
  - “一键测试全部”逐个模型测试完成后写入每个模型的结果。
- 展示入口：设置页渠道展开后的模型行副标题展示 `最近测试：成功/失败摘要 · HTTP 状态 · MM-DD HH:mm`。
- 清理入口：删除模型时清理该模型历史；删除渠道时清理该渠道下历史。

安全约束：

- 历史记录不保存 API Key、Base URL、请求内容、响应正文或 `ModelTestResult.detail` 原始错误详情。
- 保存字段只包含用户可读摘要、建议、状态码和测试时间。
- 写入前仍对常见 `Bearer ...`、`sk-...`、`AIza...` 字面量做二次脱敏。

性能影响：

- 仅用户主动测试后写入一小段 JSON；不会在应用启动时发起网络请求。
- 设置页读取 SharedPreferences 后只按 `modelId` 做 Map 查询，模型列表展示成本可忽略。

## 12. 对话级模型切换设计

当前切换路径：

```text
用户在 AppBar / 设置页选择模型
  -> switchConversationModel
  -> 更新 sessions.default_channel_model_id
  -> 插入 messages.message_type = model_switch 的 system 记录
  -> 消息列表展示 ModelSwitchNotice
  -> Markdown 原始档案异步追加该系统记录
  -> 后续 sendMessage 默认使用新的会话模型
```

关键约束：

- 切换记录是本地时间线事件，不应作为用户/助手对话内容发送给模型。
- 切换失败时回滚本地选择，避免顶部模型显示与会话默认模型不一致。
- 记录中只保存模型显示名和目标模型 id，不包含 API Key、Base URL 或请求内容。
- 目前已覆盖移动端 AppBar 菜单切换；设置页模型选择也复用同一入口。

## 13. 近期 TODO

- [x] 增加 OpenAI / Claude / Gemini / DeepSeek / 通义千问 / OpenRouter / Ollama 预设渠道第一版。
- [ ] 百度 / 讯飞等接口差异较大的厂商路径验证后补充预设。
- [x] 渠道连通性测试结果结构化展示。
- [x] 模型连通性测试最近历史记录与设置页状态展示。
- [x] 模型连通性测试失败自动重试策略。
- [x] 免费模型引导文档与导入格式。
- [x] OpenAI 兼容本地中转核心服务 v1：`OpenAiCompatibleRelayServer` + `ChannelModelRelayBridge`，支持模型列表、非流式 / 流式聊天补全、Bearer 鉴权和安全错误响应。
- [x] OpenAI 兼容本地中转设置页启动入口、令牌生成 / 加密持久化、启动 / 停止、端口展示和隐藏真实令牌的 curl 示例。
- [x] OpenAI 兼容本地中转访问审计与并发保护 v1：脱敏审计事件、默认 4 并发、超限 429、设置页摘要。
- [x] OpenAI 兼容本地中转局域网开放二次确认 v1：默认仅本机访问，确认风险后才开放局域网，取消不改变状态，设置页展示候选地址。
- [x] OpenAI 兼容本地中转高级路由策略 v1：路由别名、缺省 model 选路、默认模型 / 免费优先 / 本地快速优先、非流式失败回退和设置页策略选择。
- [x] OpenAI 兼容本地中转可配置并发上限与本地脱敏用量统计。
- [x] OpenAI 兼容本地中转持久化访问日志脱敏明细与审计导出。
- [x] OpenAI 兼容本地中转多模态安全兼容降级与图片 data URL 端到端透传。
- [x] OpenAI 兼容本地中转模型视觉能力路由。
- [x] OpenAI 兼容本地中转模型能力可见性与设置页 Vision 标注。
- [x] OpenAI 兼容本地中转远端图片 URL 安全下载透传。
