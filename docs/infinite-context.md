# 无限上下文设计

> 当前状态：滚动压缩 + 模型上下文窗口预算 + 请求前裁剪 + 超限错误兜底已落地。最后更新：2026-07-05。

## 核心思路：滚动压缩窗口

单会话可无限对话，通过分层压缩控制每次请求的 token 数。

## 上下文构建（每次发送前）

```
请求上下文 =
  [System Prompt / 记忆 / Skills / MCP 工具说明，先按系统预算截断]
  + [该会话 summary 消息，按语义时间放在 original 前]
  + [is_summarized=0 的 original 消息]
  -> 再按当前模型 maxInputTokens 从最新消息向前裁剪
```

无预算调用时保持旧行为：summary + 最近 `recentK=20` 条 original。

聊天主链路会根据 `protocol + modelName` 推断当前模型上下文窗口：

- OpenAI 兼容常见长上下文模型：按模型名识别 128K / 1M 等窗口。
- Claude：默认按 200K 预算。
- Gemini：默认按 1M 预算。
- Ollama / 未知自定义模型：保守按 8K 预算。

每次请求会预留输出 token，并只把 `maxInputTokens` 以内的内容交给模型；最近用户消息优先保留。若系统提示词、记忆、Skills、MCP 工具说明过长，会先限制系统段，避免工具说明挤爆对话内容。

## 压缩触发条件

检查未压缩 original 消息的累计 token 数：
- `SUM(tokens) WHERE is_summarized=0 AND message_type='original'`
- 设置页阈值仍作为用户下限。
- 聊天主链路会结合当前模型输入预算动态提高压缩阈值，避免 128K / 200K / 1M 模型仍被默认 2000 token 过早压缩。
- 请求前若未压缩内容已超过动态阈值，会先尝试生成 summary；如果摘要失败，仍继续走预算裁剪，不阻断发送。

## 压缩流程

```
1. 取所有未压缩 original 消息，按时间升序
2. 保留最新 10 条不压缩（保持近期上下文连贯）
3. 对剩余消息调用 AI 生成 summary：
   - 核心议题
   - 重要结论和决策
   - 人物设定、背景信息
   - 有意义的问答来龙去脉
4. 写入一条 message_type='summary' 的消息
   - summary_start_id = 第一条被压缩消息的 id
   - summary_end_id   = 最后一条被压缩消息的 id
5. 批量更新被压缩消息的 is_summarized = 1
```

## 压缩提示词模板

```
你是一个对话摘要助手。请将以下对话历史压缩为结构化摘要，保留：
1. 核心议题和背景
2. 重要结论、决策、约定
3. 人物设定（如有）
4. 关键问答的来龙去脉

对话历史：
{messages}

请用简洁的中文输出摘要，不超过 500 字。
```

## 会话议题生成

- 触发时机：第一条 AI 回复完成后，异步执行
- 提示词：`请用 10 字以内概括这段对话的核心议题，只输出标题本身`
- 结果写入 `sessions.title`

## 文件夹级别总结

- 触发：用户手动点击"总结文件夹"，或文件夹内会话数 > 10
- 逻辑：取该文件夹下所有会话的 summary 消息 → AI 生成综合摘要
- 写入 `folders.ai_summary` + 更新 `last_summarized_at`

## Token 计数

- 使用简单估算：中文字符 × 2，英文单词 × 1.3（无需精确）
- 或使用 `tiktoken` 的 Dart 移植版（如有）
- 目的是触发压缩，不需要精确到 billing 级别

## 超过模型限制时的处理

即使已经按模型名估算预算，真实接口仍可能因为厂商模型窗口变化、代理服务限制或工具说明过长而返回超限错误。聊天流式请求会识别常见错误：

- `context_length_exceeded`
- `maximum context length`
- `context window`
- `too many tokens`
- `input tokens exceed`

首次命中时会自动使用更严格输入预算裁剪较早历史并重试一次；若仍失败，界面保留可操作提示，建议切换更大上下文模型或减少长文档 / 工具说明 / 历史消息长度，不再把错误静默清空。

## 当前测试覆盖

- `test/core/model_context_budget_test.dart`：模型窗口预算、未知模型保守回退、旧 OpenAI 小窗口模型保守预算、长上下文模型动态提高压缩阈值。
- `test/core/context_builder_test.dart`：预算模式可装入超过旧 20 条上限的历史，并在小预算下保留最新用户问题。
- `test/shared/chat_provider_context_limit_test.dart`：常见上下文超限错误识别和用户提示。
