# 无限上下文设计

## 核心思路：滚动压缩窗口

单会话可无限对话，通过分层压缩控制每次请求的 token 数。

## 上下文构建（每次发送前）

```
请求上下文 =
  [System Prompt]
  + [该会话所有 summary 消息，按 created_at 升序]
  + [最近 K 条 is_summarized=0 的 original 消息]
```

K 默认 20 条，可配置。

## 压缩触发条件

检查未压缩 original 消息的累计 token 数：
- `SUM(tokens) WHERE is_summarized=0 AND message_type='original'`
- 超过阈值（默认 2000，可在设置中调整）时触发压缩

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
