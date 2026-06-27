# 社交平台接入方案

> 对应模块：M5。状态：初版。最后更新：2026-06-27。

## 1. 目标

把飞书、Telegram、WhatsApp、QQ、微信、Discord、Slack 等外部聊天平台抽象为“频道”，让 SimiChat 可以接收外部消息、调用人工智能和工具、再把回复发回对应平台。

## 2. 参考方向

- OpenClaw / 龙虾：社交平台接入能力参考。
- Cherry Studio：频道化连接器和配置体验参考。

## 3. 频道抽象

```text
SocialChannel
- id
- type: telegram / discord / feishu / slack / wechat / qq / whatsapp
- displayName
- authState
- permissions
- isEnabled
- defaultAgentId
- defaultModelId

ExternalConversationBinding
- channelId
- externalConversationId
- localSessionId
- syncMode
```

## 4. 消息流

```text
外部 webhook / 轮询
  -> 鉴权校验
  -> 消息归一化
  -> 映射本地会话
  -> 进入聊天管线
  -> 回复写回外部平台
  -> 原始消息进入本地记忆候选
```

## 5. 权限边界

- 区分个人账号接入和机器人 / 工作空间接入。
- 不默认读取历史消息。
- 不默认写入外部平台。
- 每个频道配置可见权限、发送权限、自动回复权限。

## 6. 优先级

1. Telegram：接口开放，适合先做闭环。
2. Discord：机器人生态成熟。
3. 飞书 / Slack：企业通道。
4. 微信 / QQ / WhatsApp：权限和平台限制更多，后续评估。

## 7. 测试要求

- 鉴权失败不处理消息。
- 重复 webhook 幂等。
- 外部消息与本地会话映射正确。
- 自动回复开关生效。
- 敏感数据不写日志。
