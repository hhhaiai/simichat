# Dreaming 夜间整理机制

> 对应模块：M3。状态：本地手动整理 v1、前台到期调度 v1、Dreaming 报告历史 v1、本地用户画像 v1、画像版本历史与冲突检测 v1、Dreaming 待确认画像变更 v1、待确认画像变更逐项采纳 / 拒绝 v1、待确认画像变更详情审阅 v1、前台到期系统通知 v1、设置页入口前台到期边界和下次前台整理提示 v1、本地反思机制 v1、重复追问提醒 v1、最新任务推进提醒 v1、明确任务语气 task 记忆候选 v1、DreamingJob / DreamingReport SQLite 表与 DAO v1、手动 / 前台到期运行写入 SQLite job/report v1、Dreaming 失败一致性保护 v1、SQLite report 回灌设置页状态 v1、报告删除 / 清空同步清理 SQLite v1、同日 in-flight 去重与崩溃残留 job 恢复 v1、failed job 可见状态与重试入口 v1、failed job 未解决扫描补强 v1、启动 / 恢复前台 failed job 主动提示 v1、前台到期失败通知 v1、手动运行失败反馈 v1、failed job 错误摘要脱敏 v1、failed job 清除 / 忽略入口 v1、反思短期提示注入 v1、反思历史可控管理 v1 已落地；系统后台调度和模型驱动画像仍待实现。最后更新：2026-07-07。

## 1. 目标

Dreaming 是 SimiChat 的长期智能核心：在用户闲时自动整理当天对话，提取摘要、记忆、偏好、任务和用户画像线索，让人工智能越来越了解用户。

## 2. 触发方式

- 默认每天夜间运行。
- 用户可配置时间、频率、使用模型、是否仅充电时运行、是否仅 Wi-Fi。
- 移动端需遵守系统后台限制；必要时结合本地通知引导用户打开应用完成整理。

当前 v1：

- 设置页“数据与档案 / Dreaming 夜间整理”支持手动运行今日整理；手动运行失败时会显示“Dreaming 失败，可到设置页重试”，同时保留 failed job，用户可在设置页弹窗查看失败摘要并按失败日期重试。
- 默认整理时间为 22:00，可在设置页调整小时 / 分钟。
- 自动整理开关可配置，默认开启。
- 当前采用“前台到期触发”：到达设定时间后，用户打开应用或应用前台初始化时自动整理当天一次；设置页入口副标题会明确显示“前台到期 · 非系统后台”，并显示“下次前台整理：已关闭 / 今日 HH:mm / 现在已到期 / 明日 HH:mm”，避免误认为应用被系统杀死后仍会自动运行。
- 自动整理产生内容后会推送本地系统通知，通知正文只包含整理消息数、记忆候选数和待确认画像变更数，不包含对话原文、摘要、文件路径或密钥。前台到期整理失败时会推送本地失败通知，正文只包含 dayKey 和“可到设置页重试”的引导，不包含底层错误、文件路径或密钥。
- 手动运行只读取本机 SQLite 原始消息，不上传云端，不调用远端模型；手动运行完成后使用设置页 SnackBar 反馈，避免和系统通知重复。
- 最新报告保存在 SharedPreferences 的 `dreaming_digest_v1`，用于设置页展示最近整理状态；有内容报告会同步记录到 `dreaming_digest_history_v1`，最多保留最近 20 次并按 `dayKey` 去重，设置页弹窗可查看历史保留次数、日期和消息覆盖，可展开审阅历史报告 Markdown 预览，可删除单条报告，并可清空最近报告与历史报告；删除当前最近报告时会回退到仍保留的下一条历史报告。
- `runDreamingDigest()` 只在 Key Points 写入、SQLite report upsert 和 job completed 标记都成功后，才发布最新报告 / 历史到 SharedPreferences；若中途失败，会保留 failed job 和错误信息，不写入半成功报告，避免设置页展示脏 Dreaming 结果。
- 当本地导入 / 恢复写入 SQLite `dreaming_reports` 后，设置页导入成功路径会调用 `syncDreamingDigestStateFromDatabase()`，把最新有效 report 回灌到 `dreaming_digest_v1`，并把最近有内容报告合并到 `dreaming_digest_history_v1`，避免“数据已恢复但 Dreaming 入口不可见”。
- 设置页删除单条 Dreaming 报告或清空报告时，会同步清理 SQLite `dreaming_reports`，避免用户以为已删除但后续回灌 / 导出又恢复旧报告。
- `runDreamingDigest()` 按 `dayKey` 复用同日 in-flight Future，防止手动入口 / 前台入口并发触发时重复写入多个 completed job；新运行开始前会把同日遗留的 `pending` / `running` job 标记为 failed，给后续系统后台调度提供可恢复的队列状态。
- 设置页会分页扫描 failed job，显示未被同日后续 completed job 覆盖的最近 failed job：入口副标题提示“最近失败 YYYY-MM-DD · 可重试”，弹窗展示触发来源与脱敏错误摘要，并提供“重试最近失败”按钮按失败日期重新运行；也可点“清除此失败”把该 failed job 标记为 `dismissed`，不再出现在入口副标题、弹窗和启动 / 前台恢复主动提示中；重试成功或手动清除后该失败提示会自动消失。错误摘要会隐藏 Bearer / sk / token 参数、HTTP(S) URL 和本机路径，避免截图或日志外泄密钥、链接与本机路径。`structured_data/local_database.json` 导出 `dreaming_jobs`、恢复旧 snapshot failed job 时也会对 `error` 二次脱敏，避免本地诊断错误随数据包外泄密钥、链接或本机路径。
- 应用启动或恢复前台时，如果本机仍存在未解决 failed job，会弹出“上次 Dreaming 失败，可到设置页重试”的 SnackBar，并提供“去设置”动作；同一进程内同一 failed job 只提示一次，避免反复打扰。
- 手动 / 前台到期 Dreaming 有内容时会触发本地反思 v1，生成 `assistant_reflection_v1`，用于设置页“本地反思 / 自我优化”入口和弹窗展示回应质量、未回复会话、会话追问压力、重复追问、最新任务推进、最后一问未答、上下文、记忆画像、来源新鲜度、历史次数、下一步行动项和下一轮短期提示预览，可展开审阅历史反思、按 `dayKey + sourceDigestDayKey` 精确删除单条反思、删除反馈显示来源、删除当前最近反思后自动回退，也可清空最近反思报告与历史，并记录到 `assistant_reflection_history_v1`；若 `assistant_reflection_prompt_enabled_v1` 开启，下一轮聊天会把少量高优先级结论 / 行动项并入本机 system prompt。
- 调度配置保存在 SharedPreferences 的 `dreaming_schedule_v1`，包含 `enabled`、`hour`、`minute` 和 `lastAutoRunDayKey`；设置页通过 `formatNextDreamingForegroundRun()` 把这些字段转换为可读的下次前台整理状态。
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

- `DreamingDigest`：日期、生成时间、会话数、已整理原始消息数、当天原始消息总数、用户 / 助手消息数、截断标记、整理上限、耗时。
- `DreamingSessionDigest`：每个会话的安全标题、消息数、用户重点片段、首末消息时间、最后一条消息角色和最后一条用户消息的安全片段；若标题或最后一条用户消息命中敏感内容过滤，标题会降级为“敏感会话”，最新用户片段不回退旧消息。
- 关键词：从用户消息中本地提取，限制数量。
- 记忆候选：复用 `KeyPointExtractor` 从用户消息提取明示偏好 / 目标 / 任务，并写入本地 Key Points；“继续推进 / 请继续 / 请帮 / 帮我 / 现在帮我 / 修复 / 验证 / 复跑 / 补 / 实现 / 看下 / 检查”等明确任务语气会归类为 `task` 记忆候选。
- Markdown 报告：`DreamingDigest.toMarkdown()` 生成可审阅日报。
- 报告历史：`dreaming_digest_history_v1` 本地保存最近 20 次有内容报告，按 `dayKey` 去重，设置页可展开审阅最近历史、删除单条报告并清空全部报告；删除当前最近报告时自动回退到下一条历史；结构化备份 / 恢复白名单包含该键。
- 设置页入口、最近报告、手动运行提示和自动完成通知都必须展示截断时的 `已整理 / 当天总量`，不能只显示已整理数量。

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
  -> MessageDao.countOriginalMessagesInTimeRange 统计今日 original 消息总数
  -> 未超过上限时 MessageDao.getOriginalMessagesInTimeRange 升序读取今日 original 消息
  -> 超过上限时 MessageDao.getLatestOriginalMessagesInTimeRange 读取最近 N 条并反转回升序
  -> 按 session_id 分组
  -> 统计用户 / 助手消息数
  -> 从用户消息提取安全摘要片段、最后一条用户消息安全片段和关键词；若最后用户消息敏感则该片段留空
  -> 复用 KeyPointExtractor 生成记忆候选
  -> DreamingDigestNotifier 保存最近报告
  -> DreamingDigestHistoryNotifier 记录有内容报告，最近 20 次、同 dayKey 覆盖旧项
  -> KeyPointMemoryNotifier 写入本地记忆
  -> 设置页手动运行后生成待确认 UserProfileChangeProposal，并应用用户画像编辑 / 删除控制
  -> 前台到期自动运行后也生成待确认画像变更
  -> 用户整包采纳后才写入正式 UserProfile，并以 `reason: accept_proposal` 写入最近 20 个版本历史
  -> 用户也可逐项采纳 / 忽略单条 UserProfileChangeItem；单项采纳以 `reason: accept_proposal_item` 写入画像历史，剩余提案自动收敛
  -> 提案超过 4 条差异时可打开详情弹窗查看全部待确认项，并处理卡片未展示的后续差异
  -> 运行本地 ReflectionService，按回应质量 / 未回复会话 / 会话追问压力 / 重复追问 / 最新任务推进 / 最后一问未答 / 上下文 / 长期记忆 / 用户画像 / 任务推进 / 来源新鲜度生成 `assistant_reflection_v1`
  -> 写入 `assistant_reflection_history_v1`，最多保留最近 20 次反思
  -> 若反思短期提示开关开启，下一轮聊天将少量高优先级结论 / 行动项并入本机 system prompt
  -> 自动触发且整理有内容时调用 NotificationService.showDreamingDigestComplete 推送本地完成通知
  -> 自动触发时写入 lastAutoRunDayKey，避免同一天重复自动整理
```

安全降级：

- `model_switch`、`summary` 等非原始消息不进入整理。
- 超过单次整理上限时，报告必须显式记录“已整理 / 当天总量”和“只整理最近 N 条”，Reflection 也必须继承该缺口事实。
- 前台到期自动通知和设置页手动运行 SnackBar 也必须展示 `N / 总量` 覆盖比例，避免通知层误导。
- 命中 API Key、Authorization、password、secret、token、密钥、密码、常见密钥字面量的内容不生成 highlight / 记忆候选。
- 报告只保存在本机，不写日志、不外发。
- 反思报告和短期提示复用画像安全过滤，命中 API Key、Authorization、Bearer、password、secret、token、密钥、密码、常见密钥字面量时不写入报告或提示。
- 设置页弹窗关闭后手动运行 Dreaming 必须使用页面级 `WidgetRef`，不能继续使用弹窗 `Consumer` 的 `WidgetRef`；2026-07-06 Pixel 8 真机曾复现该 disposed ref 异常，已补延迟 Dreaming widget 回归。


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
- 敏感内容不进入摘要 / 记忆候选 / 会话标题 / 最新用户片段测试。
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
- 反思历史持久化、同日去重、上限、设置页展开审阅、按 `dayKey + sourceDigestDayKey` 精确单条删除、删除反馈来源显示、删除当前报告后的最近反思回退和清空最近反思 / 历史测试。
- 反思报告敏感内容过滤测试。
- 来源 Dreaming 早于反思日期时的设置页入口来源新鲜度和短期提示测试。
- 全局轮次均衡但单个会话没有助手回复时的未回复会话测试。
- 全局轮次均衡但单个会话用户追问明显多于助手回复时的会话追问压力测试。
- 同一会话 highlights 与最新用户问题出现相近追问时的重复追问测试。
- 最新用户问题命中任务语气且画像无任务时的最新任务推进测试，以及普通礼貌问题不误触发最新任务测试。
- 明确任务语气进入 Dreaming `task` 记忆候选测试。
- 会话已有助手回复但最后一条仍是用户消息时的最后一问未答测试。
- 多轮用户消息超过 highlights 上限时仍保留最后用户问题安全片段，并让 Reflection 使用该片段；最后用户消息为敏感内容时不回退旧片段。
- Dreaming 弹窗关闭后 digest 才返回的异步时序测试。
- Dreaming 报告历史持久化、同日去重、上限、设置页展开审阅、单条删除、删除当前报告后的最近报告回退和清空报告测试。
- 通知 ID 稳定性、命名空间隔离和合法范围测试。
- 后台任务耗时与电量影响评估。
- 超长日对话超过 `maxMessages` 时保留最近消息、记录当天总量，并在 Reflection 短期提示中暴露 `已整理 / 总量` 缺口。
- Dreaming 截断时设置页最近报告、运行完成提示和通知正文显示 `已整理 / 总量` 覆盖比例。
- 1000 条消息本地整理性能基线。

## 9. 近期 TODO

- [x] 设计 DreamingJob 表：`dreaming_jobs` 记录 `dayKey`、计划时间、触发来源、消息上限、状态、开始 / 完成时间和错误信息，作为系统后台调度 job 队列前置。
- [x] 设计 DreamingReport 表：`dreaming_reports` 记录 `dayKey`、关联 job、生成时间、Markdown、digest JSON、消息统计、记忆候选数和截断状态；`dayKey` 单日唯一，随本地数据库快照导出 / 恢复。
- [x] 接入 Dreaming 运行链路写入 SQLite：手动运行为 `manual` job，前台到期自动整理为 `foreground_due` job；成功后写入 completed job 与当日报告，失败时记录 failed job，并阻止半成功报告发布到 SharedPreferences。
- [x] 接入 SQLite report 回灌设置页状态：导入 / 恢复本地数据库后，可从 `dreaming_reports.digest_json` 重建最新 Dreaming 报告和最近历史。
- [x] 接入报告删除 / 清空持久层同步：设置页删除单条报告或清空报告时同步调用 `DreamingDao.deleteReportByDay()` / `clearReports()`。
- [x] 接入 Dreaming job 去重 / 恢复策略：同一 `dayKey` 的 in-flight 运行会复用同一个 Future；新运行前会把同日 `pending` / `running` 残留 job 标记 failed，避免重复 completed job 和 stale running 状态阻塞后续调度。
- [x] 接入 Dreaming failed job 可见状态与重试入口：设置页显示最近未解决 failed job，弹窗展示错误摘要，并允许用户按失败 dayKey 重新运行。
- [x] 接入 Dreaming failed job 未解决扫描补强：查询最近失败时会分页跳过已解决 failed job，避免历史 resolved failed job 超过首批数量后漏掉更早仍未解决的失败。
- [x] 接入 Dreaming failed job 启动 / 前台恢复主动提示：应用启动或恢复前台时会提示上次 Dreaming 失败，并可一键进入设置页重试。
- [x] 接入 Dreaming 前台到期失败通知：自动整理失败时推送本地失败通知，失败正文脱敏，只引导用户到设置页重试。
- [x] 接入 Dreaming 手动运行失败反馈：设置页手动运行失败时不抛异常、不静默，显示可重试提示并保留 failed job。
- [x] 接入 Dreaming failed job 错误摘要脱敏：设置页失败弹窗不直接显示 Bearer / sk / token 参数、HTTP(S) URL 和本机路径。
- [x] 接入 Dreaming failed job 导出 / 恢复错误脱敏：本地数据库 snapshot 导出或恢复 `dreaming_jobs.error` 时只保留脱敏诊断摘要。
- [x] 接入 Dreaming failed job 清除 / 忽略入口：设置页弹窗可把失败 job 标记为 `dismissed`，清除后入口失败提示、弹窗失败卡片和启动 / 前台恢复主动提示都会消失。
- [ ] 移动端后台调度能力调研。
- [x] 实现手动触发 Dreaming 的最小闭环：本地日报、会话摘要、关键词、记忆候选、设置页入口。
- [x] 建立 Dreaming 本地整理性能脚本：`scripts/benchmark_dreaming.sh`。
- [x] 接入前台到期调度 v1：默认 22:00、可开关、可修改运行时间、同日只自动运行一次。
- [x] 接入前台到期系统通知 v1：自动整理有内容后推送本地完成通知，通知统计整理消息数、记忆候选数和待确认画像变更数。
- [x] 接入 Dreaming 报告历史 v1：`dreaming_digest_history_v1` 保留最近 20 次有内容报告，按 `dayKey` 去重，设置页可查看历史保留次数、日期和消息覆盖，可展开审阅历史报告 Markdown 预览，可删除单条报告，删除当前报告后自动回退到下一条历史，并可清空最近报告与历史报告，随结构化本地数据备份 / 恢复。
- [ ] 接入系统后台定时调度、系统日历 / 闹钟联动、仅充电 / Wi-Fi 条件。
- [x] 接入本地用户画像 v1：基于 Key Points 与最近 Dreaming 报告生成偏好、目标、任务、基础画像、表达风格、作息线索和关键词。
- [x] 接入明确任务语气记忆候选 v1：Dreaming 提取用户消息时可把“继续推进 / 请继续 / 请帮 / 帮我 / 现在帮我 / 修复 / 验证 / 复跑 / 补 / 实现 / 看下 / 检查”等任务语气归类为 `task`，用于后续 Key Points 与画像任务线索。
- [x] 接入用户画像可控管理 v1：Dreaming 后重建画像时保留用户编辑 / 删除控制。
- [x] 接入画像版本历史与冲突检测 v1：画像重建写入 `user_profile_history_v1`，设置页展示冲突提示与最近版本。
- [x] 接入 Dreaming 待确认画像变更 v1：手动 / 前台到期 Dreaming 生成 `user_profile_change_proposals_v1`，用户采纳后才写入正式画像。
- [x] 接入待确认画像变更逐项采纳 / 拒绝 v1：设置页可对单条新增 / 移除画像信号单独采纳或忽略，剩余提案自动收敛。
- [x] 接入待确认画像变更详情审阅 v1：提案超过 4 条差异时可查看全部待确认项，并对详情中的后续差异逐项处理。
- [ ] 接入模型驱动的画像增量分析。
- [x] 接入本地反思机制 v1：Dreaming 后生成回应质量、未回复会话、会话追问压力、重复追问、最新任务推进、最后一问未答、上下文、记忆画像、任务推进和来源新鲜度行动项，设置页可查看 / 手动运行，可查看历史保留次数和下一轮短期提示预览，可展开审阅历史反思、删除单条反思、删除当前最近反思后自动回退，可清空最近反思报告与历史，并可控制是否作为下一轮短期提示。
- [x] Pixel 8 真机长会话 Dreaming / Reflection 验证：72 条 seed 长会话可见，手动 Dreaming 生成 2026-07-06 日报和待确认画像变更，Reflection 生成 5 条结论、4 个行动项、1 次历史，短期提示预览可见；详见 `docs/mobile-long-conversation-reflection-smoke-2026-07-06.md`。

## 10. 最新验证

- 2026-07-07：`scripts/smoke_full_stability_gate.sh -r expanded test/core/reflection_service_test.dart test/core/dreaming_service_test.dart test/shared/reflection_provider_test.dart test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/structured_data_backup_test.dart` 通过 44 项，覆盖手动整理、前台到期、并发防重、报告历史、设置页下次前台整理状态、设置页历史展示 / 展开审阅 / 单条删除 / 最近报告回退 / 清空、结构化备份、服务、敏感标题降级、会话最后消息角色、最新用户问题安全片段、敏感最后用户消息不回退、明确任务语气进入 `task` 记忆候选、会话追问压力、重复追问、最新任务推进、普通礼貌问题不误触发最新任务、最后一问未答、反思历史展开审阅 / 精确单条删除 / 当前报告回退和反思链路。
- 2026-07-07：`scripts/benchmark_dreaming.sh -r expanded` 通过，1000 条消息 `run_ms=55`、`digest_elapsed_ms=52`、`memory_candidates=40`、`has_content=true`。
- 2026-07-07：设置页 Dreaming 入口已明确“前台到期 · 非系统后台”边界，并展示“下次前台整理”状态；新增 `dreaming tile explains foreground-only schedule boundary` widget 回归和 `dreaming schedule formats next foreground run status` 单元回归。
- 2026-07-07：新增 `DreamingJobs` / `DreamingReports` Drift 表、`DreamingDao` 和 schemaVersion 7 迁移；新增 `test/core/dreaming_dao_test.dart` 覆盖 job lifecycle、最近报告读取和同日报告 upsert；`structured_data/local_database.json` 已包含 `dreaming_jobs` / `dreaming_reports` 导出 / 恢复，`test/core/data_export_service_test.dart --name "dreaming jobs"` 通过。
- 2026-07-07：`runDreamingDigest()` 已接入 SQLite job/report：运行前创建 job 并标记 running，成功后 upsert 当日 report 并标记 completed，前台到期触发来源为 `foreground_due`；新增 `runDreamingDigest persists sqlite job and report` 回归，`test/shared/dreaming_provider_test.dart` 5 项通过。
- 2026-07-07：补 Dreaming 失败一致性保护：先用 `runDreamingDigest failure marks job failed without publishing stale report` 红灯复现 Key Points 写入失败时旧逻辑会提前发布 `dreaming_digest_v1`；修复后只有 durable 阶段完成才发布最新报告 / 历史，失败仅保留 failed job，不写 SQLite report / SharedPreferences 脏报告；`scripts/smoke_full_stability_gate.sh -r expanded test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart test/core/data_export_service_test.dart test/core/dreaming_service_test.dart test/shared/settings_page_dreaming_test.dart test/core/structured_data_backup_test.dart` 通过 39 项，`flutter --no-version-check analyze --no-pub` 无问题。
- 2026-07-07：补 SQLite report 回灌设置页状态：新增 `syncDreamingDigestStateFromDatabase()`，导入成功后会从 `dreaming_reports.digest_json` 恢复 `dreaming_digest_v1` 和 `dreaming_digest_history_v1`；新增 `syncs dreaming provider state from sqlite reports` 红灯回归并转绿。验证：Dreaming / 导入专项 `scripts/smoke_full_stability_gate.sh -r expanded test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart test/core/data_export_service_test.dart test/core/data_import_service_test.dart test/core/dreaming_service_test.dart test/shared/settings_page_dreaming_test.dart test/core/structured_data_backup_test.dart` 通过 49 项，`flutter --no-version-check analyze --no-pub` 无问题。
- 2026-07-07：补 Dreaming 报告删除 / 清空与 SQLite 持久层一致性：先红灯确认设置页清空 / 删除只清 SharedPreferences，SQLite `dreaming_reports` 仍残留；修复后 `_clearDreamingReports()` 调用 `DreamingDao.clearReports()`，`_deleteDreamingReport()` 调用 `deleteReportByDay(dayKey)`。验证：`test/shared/settings_page_dreaming_test.dart` 12 项通过；Dreaming / 数据专项 `scripts/smoke_full_stability_gate.sh -r expanded test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart test/core/data_export_service_test.dart test/core/data_import_service_test.dart test/core/dreaming_service_test.dart test/core/structured_data_backup_test.dart` 49 项通过，`flutter --no-version-check analyze --no-pub` 无问题。
- 2026-07-07：补 Dreaming job 去重 / 恢复策略：先红灯确认同日并发 `runDreamingDigest()` 会产生 2 个 completed job、崩溃残留 `pending` / `running` 不会自动收敛；修复后按 `dayKey` 复用 in-flight Future，并由 `DreamingDao.failUnfinishedJobsByDay()` 在新运行前把同日未完成 job 标记 failed。验证：`flutter --no-version-check test --no-pub --no-test-assets test/core/dreaming_dao_test.dart test/shared/dreaming_provider_test.dart -r expanded` 12 项通过；Dreaming / 数据完整门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart test/core/data_export_service_test.dart test/core/data_import_service_test.dart test/core/dreaming_service_test.dart test/core/structured_data_backup_test.dart` 52 项通过；`flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出；`pubspec.yaml` / `pubspec.lock` 无临时 sqlite hook 残留。
- 2026-07-07：补 Dreaming failed job 可见状态与重试入口：新增 `DreamingDao.getLatestUnresolvedFailedJob()` 与 `latestFailedDreamingJobProvider`，设置页入口 / 弹窗显示最近未解决 failed job 并提供“重试最近失败”；重试成功后同日后续 completed job 会覆盖失败提示。验证：先红灯于缺少 unresolved failed job 查询和 UI 提示；修复后 `flutter --no-version-check test --no-pub --no-test-assets test/core/dreaming_dao_test.dart test/shared/dreaming_provider_test.dart test/shared/settings_page_dreaming_test.dart -r expanded` 26 项通过；Dreaming / 数据完整门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart test/core/data_export_service_test.dart test/core/data_import_service_test.dart test/core/dreaming_service_test.dart test/core/structured_data_backup_test.dart` 54 项通过。
- 2026-07-07：补 Dreaming failed job 启动 / 前台恢复主动提示：新增移动端 smoke 红灯 `mobile startup prompts for unresolved dreaming failure` 与 `mobile resume prompts for unresolved dreaming failure`，应用启动或恢复前台时若存在未解决 failed job，会显示“上次 Dreaming 失败，可到设置页重试”并可点“去设置”进入设置页查看失败详情 / 重试；同一进程同一 failed job 只提示一次。验证：聚焦 `flutter --no-version-check test --no-pub --no-test-assets test/smoke/mobile_main_flow_smoke_test.dart --name "dreaming failure" -r expanded` 2 项通过；Dreaming smoke `--name dreaming` 8 项通过；Dreaming / 设置页 / DAO 专项 26 项通过；完整 Dreaming 稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/smoke/mobile_main_flow_smoke_test.dart test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart test/core/data_export_service_test.dart test/core/data_import_service_test.dart test/core/dreaming_service_test.dart test/core/structured_data_backup_test.dart` 75 项通过。
- 2026-07-07：补 Dreaming 前台到期失败本地通知：新增 `buildDreamingDigestFailedNotificationBody()` 和 `NotificationService.showDreamingDigestFailed()`，失败通知标题为“Dreaming 整理失败”，正文为“YYYY-MM-DD 整理失败，可到设置页重试”，不暴露底层错误详情；`_runDueDreamingIfNeeded()` 捕获前台到期整理失败后读取最近未解决 failed job 并通过 `dreamingDigestFailedNotifier` 推送，同一进程同一 dayKey 只通知一次。验证：`buildDreamingDigestFailedNotificationBody 失败通知不暴露底层错误详情，只引导用户去设置页重试` 先红灯后通过；`mobile due dreaming failure sends local failure notification` 先红灯后通过；完整 Dreaming / 通知稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/smoke/mobile_main_flow_smoke_test.dart test/core/notification_service_test.dart test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart test/core/data_export_service_test.dart test/core/data_import_service_test.dart test/core/dreaming_service_test.dart test/core/structured_data_backup_test.dart` 84 项通过。
- 2026-07-07：补 Dreaming 设置页手动运行失败反馈：新增 `dreaming manual run failure shows retryable feedback`，先红灯确认 `_runDreaming()` 会把 `runDreamingDigest()` 异常抛到 Flutter 测试框架且无用户提示；修复后手动运行失败显示“Dreaming 失败，可到设置页重试”，不崩溃、不写半成功报告，并保留最近未解决 failed job 供设置页查看 / 重试。验证：聚焦用例通过；设置页 / Dreaming / DAO 专项 `flutter --no-version-check test --no-pub --no-test-assets test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart -r expanded` 27 项通过；完整 Dreaming / 通知稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/smoke/mobile_main_flow_smoke_test.dart test/core/notification_service_test.dart test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart test/core/data_export_service_test.dart test/core/data_import_service_test.dart test/core/dreaming_service_test.dart test/core/structured_data_backup_test.dart` 85 项通过。
- 2026-07-07：补 Dreaming failed job URL 脱敏：新增设置页 failed job 摘要、snapshot 导出和 snapshot 恢复三处断言，先红灯确认错误摘要仍会显示 `https://example.test/...`；修复后 `_sanitizeDreamingFailedJobError()` 与 `_safeDiagnosticString()` 统一把 HTTP(S) URL 替换为 `[链接]`，独立 token / api_key 参数继续脱敏为 `token=***` / `api_key=***`。验证：聚焦 3 项红灯后转绿；设置页 / 导出 / 导入 / Dreaming / DAO / 结构化备份专项 51 项通过。
- 2026-07-07：补 Dreaming failed job 恢复错误脱敏：新增 `restores dreaming failed job errors as sanitized diagnostics`，先红灯确认旧导出包 / 外部包导入时 `dreaming_jobs.error` 会把 Bearer、`sk-*`、`token=raw` 和 `/Users/...` 原样写入 SQLite；修复后 `restoreSnapshot()` 写入 job 前复用 `_safeDiagnosticString()`，恢复后的 failed job 只保留脱敏诊断摘要。验证：聚焦用例红灯后转绿；导出 / 导入 / Dreaming / DAO / 结构化备份专项 36 项通过。
- 2026-07-07：补 Dreaming failed job 未解决扫描：新增 `dreaming dao scans past resolved failures for unresolved job`，先红灯确认默认只扫最近 20 个 failed job 时会漏掉更早但仍未解决的失败；修复后 `getLatestUnresolvedFailedJob()` 分页扫描 failed job，跳过同日后续 completed 已覆盖项。验证：目标用例红灯后转绿；DAO / 设置页 / provider 专项 31 项通过。
- 2026-07-07：补 Dreaming failed job 清除 / 忽略入口：新增 `DreamingDao.dismissFailedJob()` 和设置页“清除此失败”按钮，先红灯确认弹窗没有清除入口；修复后 failed job 标记为 `dismissed`，`getLatestUnresolvedFailedJob()` 返回 null，入口“最近失败 YYYY-MM-DD”和弹窗失败卡片消失。验证：目标用例红灯后转绿；设置页 / provider / DAO 专项 30 项通过；完整 Dreaming / 通知 / 数据门禁 90 项通过，Drift warning 扫描无输出，`pubspec.yaml` / `pubspec.lock` 无临时 sqlite hook 残留。
- 2026-07-07：补 Dreaming failed job 导出 / 恢复错误脱敏：新增 `exports dreaming failed job errors without leaking secrets or paths`，先红灯确认本地数据库快照导出的 `dreaming_jobs.error` 会原样泄露 Bearer、`sk-*`、`token=raw` 和 `/Users/...` 路径；修复后 `LocalDatabaseSnapshotService` 导出层使用 `_safeDiagnosticString()` 将错误摘要脱敏为 `Bearer ***`、`sk-***`、`token=***`、`api_key=***`、`[本机路径]`。验证：聚焦用例红灯后转绿；导出 / 导入 / Dreaming / DAO / 结构化备份专项 35 项通过。
- 2026-07-07：补 Dreaming failed job 错误摘要脱敏：新增 `dreaming failed job error summary is sanitized`，先红灯确认设置页 failed job 弹窗会直接显示 Bearer token、`sk-*`、`token=raw` 和 `/Users/...` 本机路径；修复后 `_formatDreamingFailedJob()` 只展示脱敏摘要（如 `Bearer ***`、`[本机路径]`、`token=***`），避免失败截图 / 屏幕共享泄露密钥或本机路径。验证：聚焦用例通过；设置页 / Dreaming / DAO 专项 28 项通过；完整 Dreaming / 通知稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/smoke/mobile_main_flow_smoke_test.dart test/core/notification_service_test.dart test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/dreaming_dao_test.dart test/core/data_export_service_test.dart test/core/data_import_service_test.dart test/core/dreaming_service_test.dart test/core/structured_data_backup_test.dart` 86 项通过，warning 扫描 `WARNING (drift)|multiple databases` 无输出。
- 2026-07-07：`flutter --no-version-check analyze` 无问题。
