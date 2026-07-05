# Dreaming 夜间整理机制

> 对应模块：M3。状态：本地手动整理 v1、前台到期调度 v1、本地用户画像 v1、画像版本历史与冲突检测 v1、Dreaming 待确认画像变更 v1、待确认画像变更逐项采纳 / 拒绝 v1、待确认画像变更详情审阅 v1、前台到期系统通知 v1、本地反思机制 v1、反思短期提示注入 v1、反思历史 v1 已落地；系统后台调度和模型驱动画像仍待实现。最后更新：2026-07-06。

## 1. 目标

Dreaming 是 SimiChat 的长期智能核心：在用户闲时自动整理当天对话，提取摘要、记忆、偏好、任务和用户画像线索，让人工智能越来越了解用户。

## 2. 触发方式

- 默认每天夜间运行。
- 用户可配置时间、频率、使用模型、是否仅充电时运行、是否仅 Wi-Fi。
- 移动端需遵守系统后台限制；必要时结合本地通知引导用户打开应用完成整理。

当前 v1：

- 设置页“数据与档案 / Dreaming 夜间整理”支持手动运行今日整理。
- 默认整理时间为 22:00，可在设置页调整小时 / 分钟。
- 自动整理开关可配置，默认开启。
- 当前采用“前台到期触发”：到达设定时间后，用户打开应用或应用前台初始化时自动整理当天一次。
- 自动整理产生内容后会推送本地系统通知，通知正文只包含整理消息数、记忆候选数和待确认画像变更数，不包含对话原文、摘要、文件路径或密钥。
- 手动运行只读取本机 SQLite 原始消息，不上传云端，不调用远端模型；手动运行完成后使用设置页 SnackBar 反馈，避免和系统通知重复。
- 报告保存在 SharedPreferences 的 `dreaming_digest_v1`，用于设置页展示最近整理状态。
- 手动 / 前台到期 Dreaming 有内容时会触发本地反思 v1，生成 `assistant_reflection_v1`，用于设置页“本地反思 / 自我优化”展示回应质量、上下文、记忆画像、历史次数、下一步行动项和下一轮短期提示预览，并记录到 `assistant_reflection_history_v1`；若 `assistant_reflection_prompt_enabled_v1` 开启，下一轮聊天会把少量高优先级结论 / 行动项并入本机 system prompt。
- 调度配置保存在 SharedPreferences 的 `dreaming_schedule_v1`，包含 `enabled`、`hour`、`minute` 和 `lastAutoRunDayKey`。
- 系统后台唤醒、系统日历 / 闹钟联动、仅充电 / Wi-Fi 等调度条件仍待实现；当前 v1 不保证应用关闭后自动运行。

## 3. 输入

- 当天新增消息。
- 会话 Markdown 原始档案。
- 已有会话摘要。
- 已有 Key Points。
- 用户画像当前版本。

## 4. 输出

- 日摘要。
- 会话摘要更新。
- 新增或更新 Key Points。
- 用户画像增量。
- 本地用户画像 v1：设置页可基于 Key Points 与最近 Dreaming 报告重建 `user_profile_v1`；用户编辑 / 删除控制保存在 `user_profile_controls_v1`，重建时继续生效；画像历史保存在 `user_profile_history_v1`；Dreaming 后候选画像变更先保存在 `user_profile_change_proposals_v1`，支持整包采纳 / 忽略、逐项采纳 / 忽略和全部差异详情审阅。
- 待办 / 提醒候选。
- 可审阅 Dreaming 报告。
- 本地反思报告：基于 Dreaming 与用户画像生成可解释结论和行动项，保存为 `assistant_reflection_v1`。

当前 v1 输出：

- `DreamingDigest`：日期、生成时间、会话数、原始消息数、用户 / 助手消息数、耗时。
- `DreamingSessionDigest`：每个会话的标题、消息数、用户重点片段、首末消息时间。
- 关键词：从用户消息中本地提取，限制数量。
- 记忆候选：复用 `KeyPointExtractor` 从用户消息提取明示偏好 / 目标 / 任务，并写入本地 Key Points。
- Markdown 报告：`DreamingDigest.toMarkdown()` 生成可审阅日报。

## 5. 处理流程

```text
调度触发
  -> 收集当天变更
  -> 分会话摘要
  -> 跨会话归纳
  -> Key Points 提取
  -> 用户画像增量分析
  -> 冲突检测与版本历史记录
  -> 写入本地数据库
  -> 生成可查看报告
  -> 本地反思生成行动项
```

当前 v1 实际流程：

```text
设置页手动触发 / 应用前台到期触发
  -> MessageDao.getOriginalMessagesInTimeRange 读取今日 original 消息
  -> 按 session_id 分组
  -> 统计用户 / 助手消息数
  -> 从用户消息提取安全摘要片段和关键词
  -> 复用 KeyPointExtractor 生成记忆候选
  -> DreamingDigestNotifier 保存最近报告
  -> KeyPointMemoryNotifier 写入本地记忆
  -> 设置页手动运行后生成待确认 UserProfileChangeProposal，并应用用户画像编辑 / 删除控制
  -> 前台到期自动运行后也生成待确认画像变更
  -> 用户整包采纳后才写入正式 UserProfile，并以 `reason: accept_proposal` 写入最近 20 个版本历史
  -> 用户也可逐项采纳 / 忽略单条 UserProfileChangeItem；单项采纳以 `reason: accept_proposal_item` 写入画像历史，剩余提案自动收敛
  -> 提案超过 4 条差异时可打开详情弹窗查看全部待确认项，并处理卡片未展示的后续差异
  -> 运行本地 ReflectionService，按回应质量 / 上下文 / 长期记忆 / 用户画像 / 任务推进生成 `assistant_reflection_v1`
  -> 写入 `assistant_reflection_history_v1`，最多保留最近 20 次反思
  -> 若反思短期提示开关开启，下一轮聊天将少量高优先级结论 / 行动项并入本机 system prompt
  -> 自动触发且整理有内容时调用 NotificationService.showDreamingDigestComplete 推送本地完成通知
  -> 自动触发时写入 lastAutoRunDayKey，避免同一天重复自动整理
```

安全降级：

- `model_switch`、`summary` 等非原始消息不进入整理。
- 命中 API Key、Authorization、password、secret、token、密钥、密码、常见密钥字面量的内容不生成 highlight / 记忆候选。
- 报告只保存在本机，不写日志、不外发。
- 反思报告和短期提示复用画像安全过滤，命中 API Key、Authorization、Bearer、password、secret、token、密钥、密码、常见密钥字面量时不写入报告或提示。


## 6. 前台到期系统通知 v1

当前已完成的系统通知边界：

- 只在“前台到期自动整理”且 `DreamingDigest.hasContent == true` 时发送完成通知；设置页手动运行继续使用页面内提示，避免重复打扰。
- 通知标题固定为“Dreaming 已完成”。正文由 `buildDreamingDigestNotificationBody()` 生成，只展示统计信息：整理消息数、记忆候选数、待确认画像变更数。
- 回复完成通知和 Dreaming 通知都使用 `buildStableNotificationId(namespace, key)` 生成 FNV-1a 32-bit 正整数 ID，避免固定 ID 覆盖和 Dart `hashCode` 跨运行漂移。
- 通知失败会被捕获，不影响聊天主链路、Dreaming 报告保存、Key Points 写入或画像待确认提案保存。
- 本能力不是系统后台定时任务：如果应用被系统杀死或从未被打开，当前 v1 不保证到点自动运行。

## 7. 用户控制

- Dreaming 可关闭。
- 每条记忆点可删除、禁用、降权。
- 用户可查看“为什么记住这个”。
- 上传云端或使用远端模型前必须明确提示。

## 8. 测试要求

- 手动触发测试。
- 调度配置默认值、开关、时间归一化测试。
- 到期后自动整理一次、同日不重复自动整理测试。
- 空数据安全退出测试。
- 敏感内容不进入摘要 / 记忆候选测试。
- 本地报告持久化测试。
- 记忆候选写入 Key Points 测试。
- 同一天重复运行的幂等测试。
- 画像更新不覆盖用户手工设置测试。
- Dreaming 后画像候选变更写入待确认提案测试。
- 用户整包采纳 / 忽略画像变更测试。
- 用户逐项采纳 / 忽略画像变更测试。
- 待确认画像变更详情弹窗展示全部差异并处理卡片未展示项测试。
- 偏好冲突提示测试。
- Dreaming 前台到期完成通知正文测试。
- Dreaming 后本地反思报告和反思历史落盘测试。
- 反思短期提示合并 / 关闭开关测试。
- 反思历史持久化、同日去重和上限测试。
- 反思报告敏感内容过滤测试。
- 通知 ID 稳定性、命名空间隔离和合法范围测试。
- 后台任务耗时与电量影响评估。
- 1000 条消息本地整理性能基线。

## 9. 近期 TODO

- [ ] 设计 DreamingJob 表。
- [ ] 设计 DreamingReport 表。
- [ ] 移动端后台调度能力调研。
- [x] 实现手动触发 Dreaming 的最小闭环：本地日报、会话摘要、关键词、记忆候选、设置页入口。
- [x] 建立 Dreaming 本地整理性能脚本：`scripts/benchmark_dreaming.sh`。
- [x] 接入前台到期调度 v1：默认 22:00、可开关、可修改运行时间、同日只自动运行一次。
- [x] 接入前台到期系统通知 v1：自动整理有内容后推送本地完成通知，通知统计整理消息数、记忆候选数和待确认画像变更数。
- [ ] 接入系统后台定时调度、系统日历 / 闹钟联动、仅充电 / Wi-Fi 条件。
- [x] 接入本地用户画像 v1：基于 Key Points 与最近 Dreaming 报告生成偏好、目标、任务、基础画像、表达风格、作息线索和关键词。
- [x] 接入用户画像可控管理 v1：Dreaming 后重建画像时保留用户编辑 / 删除控制。
- [x] 接入画像版本历史与冲突检测 v1：画像重建写入 `user_profile_history_v1`，设置页展示冲突提示与最近版本。
- [x] 接入 Dreaming 待确认画像变更 v1：手动 / 前台到期 Dreaming 生成 `user_profile_change_proposals_v1`，用户采纳后才写入正式画像。
- [x] 接入待确认画像变更逐项采纳 / 拒绝 v1：设置页可对单条新增 / 移除画像信号单独采纳或忽略，剩余提案自动收敛。
- [x] 接入待确认画像变更详情审阅 v1：提案超过 4 条差异时可查看全部待确认项，并对详情中的后续差异逐项处理。
- [ ] 接入模型驱动的画像增量分析。
- [x] 接入本地反思机制 v1：Dreaming 后生成回应质量、上下文、记忆画像和任务推进行动项，设置页可查看 / 手动运行，可查看历史保留次数和下一轮短期提示预览，并可控制是否作为下一轮短期提示。
