# AI 协议适配层

## 支持的协议

| 协议标识 | 端点 | 适用模型 |
|----------|------|----------|
| `openai_chat` | `POST /v1/chat/completions` | GPT-4o、GPT-4o mini 等 |
| `openai_response` | `POST /v1/responses` | o1、o3 等 |
| `claude` | `POST /v1/messages` | Claude 3.x / 4.x |
| `gemini` | `POST /v1beta/models/{model}:streamGenerateContent` | Gemini 系列 |

## 统一接口

```dart
abstract class AiProtocol {
  /// 流式发送，返回 token 增量流
  Stream<String> sendStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? systemPrompt,
  });
}
```

## 请求消息格式（内部统一）

```dart
class AiMessage {
  final String role;       // user | assistant | system
  final String content;
  final List<Attachment>? attachments;
}
```

## 各协议实现要点

### OpenAI Chat（`/v1/chat/completions`）

```json
{
  "model": "gpt-4o",
  "messages": [...],
  "stream": true
}
```
SSE 解析：`data: {"choices":[{"delta":{"content":"..."}}]}`

### OpenAI Response（`/v1/responses`）

```json
{
  "model": "o3",
  "input": [...],
  "stream": true
}
```
SSE 事件类型：`response.output_text.delta`

### Claude（`/v1/messages`）

```json
{
  "model": "claude-opus-4-6",
  "max_tokens": 8096,
  "messages": [...],
  "stream": true
}
```
Header：`anthropic-version: 2023-06-01`
SSE 事件类型：`content_block_delta`，`delta.text`

### Gemini

```
POST /v1beta/models/{model}:streamGenerateContent?alt=sse&key={apiKey}
```
```json
{
  "contents": [...],
  "generationConfig": {}
}
```
SSE 解析：`candidates[0].content.parts[0].text`

## 错误处理

| HTTP 状态 | 处理 |
|-----------|------|
| 401 | 提示 API Key 无效 |
| 429 | 提示超出速率限制，显示重试按钮 |
| 5xx | 提示服务异常，显示重试按钮 |
| 网络超时 | 提示网络错误，显示重试按钮 |

## SSE 流式处理

使用 `dio` + `ResponseType.stream`，逐行解析 `data:` 前缀，
遇到 `data: [DONE]` 或流结束时关闭。

## OpenAI-compatible 通用渠道

任意兼容 OpenAI `/v1/models`、`/v1/chat/completions`、`/v1/embeddings` 的服务都应优先配置为通用 OpenAI-compatible 渠道：

- Chat 模型使用 `openai_chat`，请求 `{baseUrl}/v1/chat/completions`，并强制流式输出。
- Embedding 模型使用同一渠道的模型能力标记 `embedding`，请求 `{baseUrl}/v1/embeddings`。
- 模型选择器只展示 `chat` 能力模型，避免 `BAAI/bge-m3` 等向量模型被误用于聊天。
- `/v1/models` 返回值的模型能力以服务端 metadata 为准；缺失 metadata 时根据常见 embedding 命名做保守识别。
- API Key 只允许用户在设置页录入并本地加密保存，不应把示例密钥或私钥写入源码。

示例通用配置：

| 服务 | Base URL | 协议 | 推荐模型能力 |
|------|----------|------|--------------|
| Grok compatible | `https://grok.chainlessdw.com` | `openai_chat` | chat |
| Tumuer Router | `https://router.tumuer.me` | `openai_chat` | chat + embedding |
| Fufu compatible | `https://fufu.iqach.top` | `openai_chat` | chat |
