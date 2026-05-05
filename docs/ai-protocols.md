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
