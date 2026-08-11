# Dreaming 夜间整理机制

> **文档边界**：本文是 Dreaming 的实现专题和历史验证汇总。当前项目状态、当前测试数量和本地 Ollama 可用性以 `current-status.md` 与 `verification-baseline-2026-08-08.md` 为准；文中带日期的设备 / 外部模型记录只代表记录当日，不自动代表当前 runtime。

> 对应模块：M3。状态：本地手动整理 v1、前台到期调度 v1、Android WorkManager 系统后台调度 v1、iOS BGTaskScheduler `BGProcessingTask` 代码 / 原生注册 / 调度诊断 v1、后台充电 / 非计费网络附加条件代码与设置页 v1、Pixel 8 非计费网络和充电条件阻塞 / 满足后放行真机验证、Dreaming 报告历史 v1、本地用户画像 v1、画像版本历史与冲突检测 v1、Dreaming 待确认画像变更 v1、待确认画像变更逐项采纳 / 拒绝 v1、待确认画像变更详情审阅 v1、模型驱动画像增量分析 v1、后台 / 前台系统通知 v1、本地反思机制 v1、可选模型增强反思 v1、反思独立失败恢复 v1、重复追问提醒 v1、最新任务推进提醒 v1、明确任务语气 task 记忆候选 v1、DreamingJob / DreamingReport SQLite 表与 DAO v1、手动 / 自动运行写入 SQLite job/report v1、Dreaming 失败一致性保护 v1、SQLite report 回灌设置页状态 v1、报告删除 / 清空同步清理 SQLite v1、同日进程内与跨 isolate 去重 / 崩溃残留恢复 v1、failed job 可见状态与重试入口 v1、failed job 未解决扫描补强 v1、启动 / 恢复前台 failed job 主动提示 v1、失败通知 v1、手动运行失败反馈 v1、failed job 错误摘要脱敏 v1、failed job 清除 / 忽略入口 v1、反思短期提示注入 v1、反思历史可控管理 v1、远程模型三日 Reflection 与画像候选质量门禁已落地；iOS 真机 BGTask 系统执行、更多远程模型族和真实多日用户会话质量仍待完成。最后更新：2026-07-14。

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
- 后台附加条件可选，默认均关闭以兼容旧配置：开启“仅充电时执行”后 Android / iOS 都要求系统判定设备处于充电状态，而不是只判断电源线是否连接；开启“仅非计费网络执行”后 Android 使用 `NetworkType.unmetered`（通常为 Wi-Fi），iOS 因 `workmanager 0.8.0` / BGTaskScheduler 表达能力限制只能要求联网，无法严格保证 Wi-Fi，设置页会明确显示该边界。
- Android 使用 `workmanager 0.8.0` 注册按本地配置时间计算的一次性唯一任务；iOS 使用一次性 `BGProcessingTask`，由 `AppDelegate` 在启动完成前注册，按 Dreaming 设置时间提交最早执行日期，成功后排下一日，失败时显式排 15 分钟重试。两端均属于系统择机执行，不承诺精确到分钟，前台到期检查继续作为兜底。
- iOS 通过原生 `simichat/background_refresh_status` 通道读取 `UIApplication.backgroundRefreshStatus`。设置页会显示“可用 / 已关闭 / 受系统限制”；关闭或受限时，后台调度不会继续静默假成功，而是提示用户系统后台不可用并继续保留前台到期兜底。
- 自动整理产生内容后会推送本地系统通知，通知正文只包含整理消息数、记忆候选数和待确认画像变更数，不包含对话原文、摘要、文件路径或密钥。前台到期整理失败时会推送本地失败通知，正文只包含 dayKey 和“可到设置页重试”的引导，不包含底层错误、文件路径或密钥。
- Dreaming 摘要生成本身只读取本机 SQLite 原始消息，不上传云端、不调用远端模型；若用户另行显式开启“使用模型增强反思”，Dreaming 完成后的 Reflection 阶段才会把长度受限且经过敏感信息处理的摘要发送给默认聊天模型。手动运行完成后使用设置页 SnackBar 反馈，避免和系统通知重复。
- 最新报告保存在 SharedPreferences 的 `dreaming_digest_v1`，用于设置页展示最近整理状态；有内容报告会同步记录到 `dreaming_digest_history_v1`，最多保留最近 20 次并按 `dayKey` 去重，设置页弹窗可查看历史保留次数、日期和消息覆盖，可展开审阅历史报告 Markdown 预览，可删除单条报告，并可清空最近报告与历史报告；删除当前最近报告时会回退到仍保留的下一条历史报告。
- `runDreamingDigest()` 只在 Key Points 写入、SQLite report upsert 和 job completed 标记都成功后，才发布最新报告 / 历史到 SharedPreferences；若中途失败，会保留 failed job 和错误信息，不写入半成功报告，避免设置页展示脏 Dreaming 结果。
- 当本地导入 / 恢复写入 SQLite `dreaming_reports` 后，设置页导入成功路径会调用 `syncDreamingDigestStateFromDatabase()`，把最新有效 report 回灌到 `dreaming_digest_v1`，并把最近有内容报告合并到 `dreaming_digest_history_v1`，避免“数据已恢复但 Dreaming 入口不可见”。
- 设置页删除单条 Dreaming 报告或清空报告时，会同步清理 SQLite `dreaming_reports`，避免用户以为已删除但后续回灌 / 导出又恢复旧报告。
- 手动 `runDreamingDigest()` 按 `dayKey` 复用同日 in-flight Future；前台到期、Android WorkManager 和 iOS BGTaskScheduler 自动路径额外通过 SQLite 固定主键 `dreaming-auto-YYYY-MM-DD` 原子 claim，避免前台 isolate 与后台 isolate 同时生成重复 job、报告、Reflection 或通知。`pending` / `running` 超过 15 分钟可被后台重领，failed 可由系统后台重试路径重领，completed / dismissed 不会自动重复执行。
- 设置页会分页扫描 failed job，显示未被同日后续 completed job 覆盖的最近 failed job：入口副标题提示“最近失败 YYYY-MM-DD · 可重试”，弹窗展示触发来源与脱敏错误摘要，并提供“重试最近失败”按钮按失败日期重新运行；也可点“清除此失败”把该 failed job 标记为 `dismissed`，不再出现在入口副标题、弹窗和启动 / 前台恢复主动提示中；重试成功或手动清除后该失败提示会自动消失。错误摘要会隐藏 Bearer / sk / token 参数、HTTP(S) URL 和本机路径，避免截图或日志外泄密钥、链接与本机路径。`structured_data/local_database.json` 导出 `dreaming_jobs`、恢复旧 snapshot failed job 时也会对 `error` 二次脱敏，避免本地诊断错误随数据包外泄密钥、链接或本机路径。
- 应用启动或恢复前台时，如果本机仍存在未解决 failed job，会弹出“上次 Dreaming 失败，可到设置页重试”的 SnackBar，并提供“去设置”动作；同一进程内同一 failed job 只提示一次，避免反复打扰。
- 手动 / 前台到期 / Android 系统后台 Dreaming 有内容时都会触发 Reflection：始终先生成本地规则报告；用户显式开启模型增强时再调用默认聊天模型，严格解析并合并 JSON。模型增强失败会安全回退本地报告、清除 pending，不让后台任务因可选增强反复 retry；只有本地 Reflection 编排本身失败时才保留 pending，并由 WorkManager 下一次只恢复 Reflection、不重复 Dreaming，恢复后补发一次完成通知。
- Dreaming 已成功但 Reflection 单独失败时会保留 `assistant_reflection_pending_v1`，只记录来源 dayKey、更新时间和尝试次数；应用启动 / 恢复前台 / 前台定时检查时自动重试。pending 指向旧日期时先从 Dreaming 历史、再从 SQLite `dreaming_reports` 按 dayKey 恢复对应 digest；设置页显示待重试状态并允许清除，清空或删除来源报告会同步清理 pending。
- 调度配置保存在 SharedPreferences 的 `dreaming_schedule_v1`，包含 `enabled`、`hour`、`minute`、`requiresCharging`、`requiresUnmeteredNetwork` 和 `lastAutoRunDayKey`；设置页通过 `formatNextDreamingForegroundRun()` 和 `formatDreamingBackgroundConditions()` 展示下次前台整理状态与后台附加条件。旧 JSON 缺少新字段时默认关闭约束；同一配置键继续随结构化备份 / 恢复，不新增敏感数据。
- Android 系统后台唤醒已完成代码、原生构建和 Pixel 8 JobScheduler 真机验证；iOS BGTaskScheduler 已完成代码、原生注册、release 构建、隔离 smoke、pending request 取证和后台 App 刷新状态诊断。当前 iPhone13 原生通道明确返回 `backgroundRefreshStatus=denied`，系统真实执行需开启“后台 App 刷新”后继续补证；设置页已提供“打开系统设置”和“重新检查”，不再只显示不可操作的错误。充电 / 非计费网络条件的代码、设置页、持久化和备份已完成；Pixel 8 已证明两类条件在不满足时阻塞、满足后由系统放行并完成 Dreaming / Reflection。系统日历 / 闹钟联动仍待实现。

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
- Reflection 报告：本地规则始终生成可解释结论和行动项；模型增强开启且成功时与本地结论合并，并以 `generationMode=model` 标记。模型尝试失败时仍保存完整本地报告，但以 `generationMode=model_fallback` 记录“已安全回退”事实，不保存异常详情；最近报告保存为 `assistant_reflection_v1`。

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
  -> 本地反思生成安全基线行动项
  -> 若用户显式开启模型增强，调用默认聊天模型并严格解析 / 合并 JSON；失败回退本地报告
```

当前 v1 实际流程：

```text
设置页手动触发 / 应用前台到期触发 / Android WorkManager 后台 isolate
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
  -> 前台到期或 Android 后台自动运行后生成待确认画像变更
  -> 用户整包采纳后才写入正式 UserProfile，并以 `reason: accept_proposal` 写入最近 20 个版本历史
  -> 用户也可逐项采纳 / 忽略单条 UserProfileChangeItem；单项采纳以 `reason: accept_proposal_item` 写入画像历史，剩余提案自动收敛
  -> 提案超过 4 条差异时可打开详情弹窗查看全部待确认项，并处理卡片未展示的后续差异
  -> 运行本地 ReflectionService，按回应质量 / 未回复会话 / 会话追问压力 / 重复追问 / 最新任务推进 / 最后一问未答 / 上下文 / 长期记忆 / 用户画像 / 任务推进 / 来源新鲜度生成安全基线
  -> 模型增强开启时使用默认已启用聊天模型，输入限长 / 脱敏，输出严格 JSON；成功后与本地结论合并，失败保留本地报告
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
- 模型增强默认关闭；开启后仅发送受限、脱敏摘要，模型提示最多 12000 字符、响应最多 20000 字符，整个模型流使用一个 60 秒总墙钟时限而不是逐块重置，超时或异常会通过 `CancelToken` 取消上游。模型结果会再次过滤 token、URL、本机路径；合并时始终优先保留本地规则安全基线，模型最多补充 4 条结论 / 4 个行动项，总量仍限制为最多 8 条；模型没有新增安全内容时回退本地报告。
- 设置页弹窗关闭后手动运行 Dreaming 必须使用页面级 `WidgetRef`，不能继续使用弹窗 `Consumer` 的 `WidgetRef`；2026-07-06 Pixel 8 真机曾复现该 disposed ref 异常，已补延迟 Dreaming widget 回归。


## 6. 前台到期系统通知 v1

当前已完成的系统通知边界：

- 前台到期或 Android WorkManager 自动整理且 `DreamingDigest.hasContent == true` 时发送完成通知；设置页手动运行继续使用页面内提示，避免重复打扰。
- 通知标题固定为“Dreaming 已完成”。正文由 `buildDreamingDigestNotificationBody()` 生成，只展示统计信息：整理消息数、记忆候选数、待确认画像变更数。
- 回复完成通知和 Dreaming 通知都使用 `buildStableNotificationId(namespace, key)` 生成 FNV-1a 32-bit 正整数 ID，避免固定 ID 覆盖和 Dart `hashCode` 跨运行漂移。
- 通知失败会被捕获，不影响聊天主链路、Dreaming 报告保存、Key Points 写入或画像待确认提案保存。
- Android 已通过 WorkManager 接入系统后台并完成真机强制 JobScheduler 验证；iOS 已接入 BGTaskScheduler `BGProcessingTask` 和系统可用性诊断，当前设备关闭“后台 App 刷新”时明确降级到前台到期兜底，真机 BGTask 执行仍待系统开关开启后补证。

## 7. 用户控制

- Dreaming 可关闭。
- 每条记忆点可删除、禁用、降权。
- 用户可查看“为什么记住这个”。
- 上传云端或使用远端模型前必须明确提示。
- 设置页必须允许独立关闭模型增强；模型失败必须明确显示本次已回退本地反思，不得把可选模型失败伪装为 Dreaming 整体失败。

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
- 模型增强默认关闭 / 持久化、严格 JSON、提示长度、敏感输入输出过滤、默认聊天模型正式协议、本地回退、pending 清理和设置页隐私边界测试。
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
- [x] Android WorkManager 系统后台调度 v1：一次性唯一任务、设置变化重排、成功后排下一日、失败 backoff retry、后台 Flutter isolate 运行 Dreaming / 画像候选 / Reflection / 通知。
- [x] Android WorkManager 自然调度真机补证：隔离包在 Pixel 8 回到 Home 后不调用 `cmd jobscheduler run`，30 秒 initialDelay 后由 SystemJobScheduler 自行执行，36 秒完成 Dreaming / Reflection 并清除 pending；默认 force 分支同步复跑通过。
- [x] Android UI 进程被回收后的 headless 冷启动真机补证：隔离 App 调度后回到 Home，以 `am kill` 回收旧 UI pid 并确认 package 未 force-stop；等待 WorkSpec 到期后，JobScheduler 通过 `SystemJobService` 冷启动不同的新 pid 和后台 Flutter isolate，完成 Dreaming / Reflection。该证据只覆盖到期后的 forced callback，不替代自然调度时延或 OEM 长时存活观察。
- [x] Android UI 进程被回收后的自然调度真机补证：新增独立 natural wrapper，完全不调用 `cmd jobscheduler run`；Pixel 8 在旧 UI pid 消失后保留 ready JobScheduler job，系统按自身批处理节奏在 249 秒后通过 `SystemJobService` 冷启动新 pid，完成 Dreaming / Reflection 并清除 pending。专用 wrapper 默认等待 900 秒，避免 240 秒窗口误判失败。
- [x] Android UI 进程死亡后的跨小时自然调度真机补证：使用 3600 秒 initialDelay 和 7200 秒观察窗口，旧 UI pid 消失后 job 持久跨越一小时，standby bucket 从 `ACTIVE` 降到 `RARE`；到期后系统继续批处理约 12 分钟，最终在 4360 秒时冷启动不同的新 pid，完成 Dreaming / Reflection 并清除 pending。
- [ ] Android UI 进程死亡后的跨日自然调度真机补证：分离式 schedule / status / verify / cleanup 工具已落地并完成短延迟验证与主动 cleanup 验证；Pixel 8 已调度目标 dayKey `2026-07-15` 的 86400 秒任务，旧 pid `28141` 已回收，job id `0` 当前 waiting，待次日 verify。
- [x] Android 前台 / 后台跨 isolate 自动 job 防重：SQLite `dreaming-auto-YYYY-MM-DD` 原子 claim，failed / stale 可重领，completed / dismissed 不重复。
- [x] iOS BGTaskScheduler 代码 / 原生注册 / 调度诊断 v1：一次性 `BGProcessingTask`、成功后次日重排、失败 15 分钟重试、`ios_background` trigger、设置页后台 App 刷新状态和隔离 release smoke 已落地；关闭 / 受限时可打开系统设置并手动重新检查，smoke READY JSON 直接记录原生状态。
- [ ] iOS BGTaskScheduler 真机系统执行：当前 iPhone13 `backgroundRefreshStatus=denied`，待开启系统“后台 App 刷新”后验证 pending task、强制触发、Dreaming / Reflection result JSON 和持久化恢复。
- [x] 实现手动触发 Dreaming 的最小闭环：本地日报、会话摘要、关键词、记忆候选、设置页入口。
- [x] 建立 Dreaming 本地整理性能脚本：`scripts/benchmark_dreaming.sh`。
- [x] 接入前台到期调度 v1：默认 22:00、可开关、可修改运行时间、同日只自动运行一次。
- [x] 接入前台到期系统通知 v1：自动整理有内容后推送本地完成通知，通知统计整理消息数、记忆候选数和待确认画像变更数。
- [x] 接入 Dreaming 报告历史 v1：`dreaming_digest_history_v1` 保留最近 20 次有内容报告，按 `dayKey` 去重，设置页可查看历史保留次数、日期和消息覆盖，可展开审阅历史报告 Markdown 预览，可删除单条报告，删除当前报告后自动回退到下一条历史，并可清空最近报告与历史报告，随结构化本地数据备份 / 恢复。
- [x] 接入仅充电 / 非计费网络后台附加条件代码与设置页：Android 使用 WorkManager `requiresCharging` / `NetworkType.unmetered`；iOS 支持充电条件，网络条件受平台限制降级为“要求联网”；配置兼容旧 JSON 并随结构化备份恢复。
- [ ] 接入系统日历 / 闹钟联动，并补 iOS 条件验证；Pixel 8 非计费网络与充电条件的阻塞 / 满足后放行均已通过，Android 系统后台 v1 已完成，iOS BGTaskScheduler 代码基线已完成、真机系统执行待补。
- [x] 接入本地用户画像 v1：基于 Key Points 与最近 Dreaming 报告生成偏好、目标、任务、基础画像、表达风格、作息线索和关键词。
- [x] 接入明确任务语气记忆候选 v1：Dreaming 提取用户消息时可把“继续推进 / 请继续 / 请帮 / 帮我 / 现在帮我 / 修复 / 验证 / 复跑 / 补 / 实现 / 看下 / 检查”等任务语气归类为 `task`，用于后续 Key Points 与画像任务线索。
- [x] 接入用户画像可控管理 v1：Dreaming 后重建画像时保留用户编辑 / 删除控制。
- [x] 接入画像版本历史与冲突检测 v1：画像重建写入 `user_profile_history_v1`，设置页展示冲突提示与最近版本。
- [x] 接入 Dreaming 待确认画像变更 v1：手动 / 前台到期 Dreaming 生成 `user_profile_change_proposals_v1`，用户采纳后才写入正式画像。
- [x] 接入待确认画像变更逐项采纳 / 拒绝 v1：设置页可对单条新增 / 移除画像信号单独采纳或忽略，剩余提案自动收敛。
- [x] 接入待确认画像变更详情审阅 v1：提案超过 4 条差异时可查看全部待确认项，并对详情中的后续差异逐项处理。
- [ ] 接入模型驱动的画像增量分析。
- [x] 接入本地反思机制 v1：Dreaming 后生成回应质量、未回复会话、会话追问压力、重复追问、最新任务推进、最后一问未答、上下文、记忆画像、任务推进和来源新鲜度行动项，设置页可查看 / 手动运行，可查看历史保留次数和下一轮短期提示预览，可展开审阅历史反思、删除单条反思、删除当前最近反思后自动回退，可清空最近反思报告与历史，并可控制是否作为下一轮短期提示。
- [x] Pixel 8 真机长会话 Dreaming / Reflection 验证：72 条 seed 长会话可见，手动 Dreaming 生成 2026-07-06 日报和待确认画像变更，Reflection 生成 5 条结论、4 个行动项、1 次历史，短期提示预览可见；详见 `docs/archive/mobile-long-conversation-reflection-smoke-2026-07-06.md`。
- [x] Dreaming 成功后 Reflection 独立失败恢复 v1：增加 pending 标记、启动 / 恢复前台 / 前台定时重试、Dreaming 历史 / SQLite 按日来源恢复、设置页可见状态和清除入口，避免异常降级后当天反思静默缺失。
- [x] 可选模型增强 Reflection v1：默认关闭，用户显式开启后使用默认已启用聊天模型，只发送长度受限、经过敏感信息处理的摘要；严格 JSON 与本地安全结论合并，失败回退本地报告且不残留 pending。

## 10. 最新验证

- 2026-07-15 02:34：补系统后台通知副作用隔离。旧 `runDreamingBackgroundTask()` 在 Dreaming / Reflection 已完成持久化后直接等待完成通知；若系统通知插件异常，会把成功任务继续抛给 WorkManager 当作失败并触发无意义重试。Dreaming 本身失败时，失败通知异常也会掩盖应返回的 `failed` 状态。新增“完成通知失败不破坏 durable result”和“失败通知失败仍保留 failed result”两条回归，均先红灯；修复后统一通过 `_runOptionalNotification()` 捕获通知异常，只记录异常类型而不记录错误正文。完成通知失败仍返回 `completed`，completed job、Dreaming / Reflection 持久化和 pending 清理不变；失败通知失败仍返回 `failed` 并保留 failed job。background runner 8 项、Dreaming / Reflection / 通知 / 后台调度聚焦 50 项通过；提交前完整稳定门禁 569 项和 analyze 通过，`git diff --check` 无输出。Android 跨日 job id `0` 仍为 `waiting`，未被扰动。
- 2026-07-14 23:50：新增 iOS 后台 App 刷新只读状态脚本，不构建、不安装、不卸载，只启动正式 App 后用 LLDB 读取 `UIApplication.backgroundRefreshStatus` 并校验 App identity。iPhone13 实时结果仍为 `raw=1 status=denied`，因此没有重复运行必然失败的 release BGTask smoke。状态 / 脚本 / 原生通道聚焦 7 项通过；取证 `/tmp/simichat-ios-background-refresh-status-20260714235035.log`，详见 `docs/archive/mobile-ios-background-dreaming-smoke-2026-07-14.md`。
- 2026-07-14 23:35：模型驱动画像增量分析 v1 完成远程质量与 Pixel 8 系统后台闭环。独立默认关闭开关只发送限长、脱敏的 Dreaming / 本地候选；模型新增必须带逐字证据，只能追加最多 6 条待确认候选，基础事实、删除 / 覆盖、密钥、URL、路径、诊断和无证据内容均被拒绝，失败回退本地候选。远程三个 dayKey 质量门禁 3 / 3 通过，attempts `[3,1,1]`、安全新增 `[2,3,4]`。Pixel 8 独立包 READY pid `12526` 被回收后，JobScheduler 未使用 shell force，在 elapsed `127` 秒时冷启动 pid `12911`，完成 Dreaming、`generationMode=model` 画像提议和模型 Reflection；正式画像未写入，无 fallback / pending / 地址或 key 泄漏。cleanup 后正式包 pid `13315`、firstInstallTime / dataDir 不变，隔离包和 hook 无残留，跨日 job 继续 waiting；最终全量 566 项通过。详见 `docs/archive/mobile-model-user-profile-quality-2026-07-14.md`。
- 2026-07-14 22:57：非流式远程 Reflection 正式路径已在 Pixel 8 系统后台复验。首次预检临时 401 时在构建前安全退出；预检增加 3 次有界重试后，第二次运行 attempt 2 成功。独立包 READY pid `8925` 被回收，JobScheduler 自然等待 elapsed `324` 秒后以新 pid `10117` 冷启动，完成 `digest=2026-07-14 reflection=2026-07-14`；prefs 含 Dreaming / Reflection 当前与历史，`generationMode=model`，无 pending / fallback，地址与 key 无泄漏。cleanup 后正式包 pid `10528`、firstInstallTime / dataDir 不变，隔离包和 hook 无残留，跨日 job 继续 waiting；最终全量 557 项通过。取证见 `docs/archive/mobile-remote-model-reflection-quality-2026-07-14.md`。
- 2026-07-14 22:40：远程模型三日长会话 Reflection 质量门禁完成。旧 live gate 的 loopback / 本地模型默认值已移除，现只读取仓库外 600 / 400 `MODEL_CONFIG_FILE` 并拒绝 loopback。真实 SSE 两组三轮分别出现 1 次和 2 次空 content/thinking，正式 `openai_chat` Reflection 因此改为非流式单次响应，普通聊天 SSE 和其他协议不变；真实 `<think>` + 重复 JSON 输出通过平衡对象解析兼容，安全过滤不放宽。2026-07-14 / 15 / 16 三个 synthetic dayKey 的 72 条长会话 3 / 3 通过，attempts `[2,1,1]`，本地 5 / 4 均保留、最终 8 / 8，无合成密钥 / URL / 路径或虚假完成。聚焦 38 项、全量 557 项和 analyze 通过；跨日 job 仍 waiting，正式包 pid `5438`。详见 `docs/archive/mobile-remote-model-reflection-quality-2026-07-14.md`。
- 2026-07-14 22:06：完成 21:56 SQLite-only 新进程恢复补丁的最终复核。恢复脚本与跨日脚本 `bash -n` 通过；Dreaming / Reflection device manifest、provider、background runner 聚焦 32 项通过；全量稳定门禁 550 项通过；`flutter --no-version-check analyze --no-pub`、`git diff --check`、sqlite hook 残留和外部模型真实地址 / key 仓库扫描均通过。Pixel 8 正式包 pid `5438`、firstInstallTime / dataDir 不变，SQLite-only 与远程模型隔离包均不存在，跨日 job id `0` 仍为 `waiting`。本轮未启动、调用或探测任何 Ollama / 本地模型，后续模型验证仅从仓库外 600 / 400 配置文件读取远程接口。
- 2026-07-14 21:56：Pixel 8 新增 SQLite-only Dreaming / Reflection 真机冷启动恢复证据。扩展既有隔离 harness 的可选模式，第一次启动用独立 `top.simitalk.aichat.dreamingsqlitesmoke` 私有 `AppDatabase()` 只写 completed job、SQLite report 和 `assistant_reflection_pending_v1`，不写 Dreaming 当前 / 历史；READY 时旧 pid `5157`。脚本 `am force-stop` 确认旧进程消失后重新启动，第二个新 pid `5263` 通过正式 `ResponsiveShell` 启动任务从 SQLite 回灌 `dreaming_digest_v1` 与 history，随后完成 Reflection 当前 / 历史并清 pending，输出 `dreamingHistory=1 reflectionHistory=1`。设备 prefs 复查四项报告 key 均存在、pending 不存在；cleanup 后隔离包和 sqlite hook 无残留，正式包 pid `5438`、firstInstallTime / dataDir 不变，Android 跨日 job id `0` 仍 `waiting`。取证位于 `/tmp/simichat-dreaming-reflection-device-20260714215600.log` 和 `/tmp/simichat-dreaming-reflection-prefs-20260714215600.xml`。
- 2026-07-14 21:38：补 pending Reflection 从 SQLite report 恢复时的 Dreaming 状态回灌。旧 `_retryPendingAssistantReflection()` 能从 `dreaming_reports.digest_json` 解码目标 digest 并完成 Reflection，但 digest 只存在于局部变量，不会进入 `dreaming_digest_v1` / history；后台 runner 随后可能找不到 Reflection 的来源 digest，无法发完成通知，设置页也可能出现“Reflection 已恢复但 Dreaming 来源不可见”。在既有按 dayKey 恢复测试中加入 history 断言，先红灯为 `Actual: []`；修复后 SQLite 恢复的 digest 总是写入 Dreaming history，仅当当前 digest 为空或比恢复项更旧时才更新当前 digest，避免旧 pending 覆盖更新的报告。另新增“当前 digest 缺失时发布 SQLite digest”和“后台 runner 回灌 digest 后完成 Reflection / 通知”两项回归。Reflection provider + background runner 18 项、移动端聚焦 20 项和全量稳定门禁 550 项通过，analyze 无问题；Android 跨日 job id `0` 仍为 `waiting`。
- 2026-07-14 21:28：补 Dreaming 跨存储持久化顺序门禁。审计发现旧 `_runDreamingDigest()` 在 SQLite report upsert 后先把 job 标记 `completed`，再写 `dreaming_digest_v1` 和历史；若 SharedPreferences 写入异常，或后台进程在两层存储之间退出，系统可能留下“SQLite 已完成但移动端 provider/UI 没有报告”的静默完成状态，同日自动任务随后会直接采用 completed job 而不再补齐状态。新增 `runDreamingDigest does not complete job before provider state is durable`，先红灯得到 `Expected failed / Actual completed`；修复后先保存 digest 与历史，最后才 `markJobCompleted()`。现在 provider 写入异常会把 job 标记 failed 并保留 SQLite report 供诊断 / 重试，进程直接退出则 job 保持未完成并可由 stale claim 恢复，不再产生不可重试的静默 completed。`dreaming_provider_test.dart` 11 项、Dreaming / background runner / DAO / Reflection / 移动端聚焦 22 项和最终全量稳定门禁 548 项通过，analyze 无问题；Android 跨日 job id `0` 仍为 `waiting`。
- 2026-07-14 21:21：iPhone13 重新变为可用后，隔离 release BGTask Dreaming / Reflection smoke 再次通过解锁预检、签名构建（27.5MB）、安装和 READY；设备原生状态仍为 `backgroundRefreshStatus=denied`，`BGTaskScheduler` 返回 `There are no scheduled tasks`，因此脚本在 LLDB 模拟前安全拒绝，未把“能够启动隔离 App”误报为后台执行成功。本轮同时补齐失败 cleanup 的正式 App 身份守卫：脚本现在必须比较 smoke 前后的正式 App 名称、bundle、版本和 build 行，变化即失败；manifest 回归先红后绿，真机失败清理路径复跑未触发身份变化错误。cleanup 后仅正式 `top.simitalk.aichat` 保留，隔离 bundle、临时工程替换和 sqlite hook 均无残留；Android 跨日 job id `0` 继续保持 `waiting`。iOS 系统后台执行仍需用户开启“后台 App 刷新”后复跑，当前只证明拒绝与恢复路径稳定。
- 2026-07-14：Android 系统后台 Dreaming → 远程模型增强 Reflection 的安全隔离 smoke 已通过 Pixel 8 真机。入口使用纯外部配置文件驱动：`scripts/smoke_device_android_background_dreaming_real_model.sh` 不包含接口地址、模型名或密钥默认值，只接受仓库外 `MODEL_CONFIG_FILE`；JSON 必须包含 `protocol=openai_chat`、`baseUrl`、`apiKey`、`model` 且权限为 600 / 400。wrapper 远程预检通过后构建独立 `top.simitalk.aichat.backgroundmodelsmoke`，通过 `run-as` 把配置写入隔离应用私有目录；Flutter 首次启动读取后立即删除明文配置，API key 只以 `KeyEncryptor` 加密形式进入隔离数据库。真机 READY 后旧 pid `30567` 被回收，JobScheduler 未使用 shell force，在 elapsed `112` 秒时通过 `SystemJobService` 冷启动新 pid `30907`，完成 `status=completed digest=2026-07-14 reflection=2026-07-14`；prefs 含 Dreaming / Reflection 最近报告与历史，`generationMode=model`，无 pending / `model_fallback`，日志和 prefs 不含配置中的密钥或地址。cleanup 后隔离包与临时配置消失，正式包 identity 不变、pid `31292`，跨日 job id `0` 仍 waiting，本机无 Ollama 进程或 11434 监听。配置解析 / 删除和设备 manifest 聚焦 11 项、全量稳定门禁 547 项通过，analyze 无问题。
- 2026-07-14：历史上的真实本地模型 Reflection 长会话门禁曾完成。批量采样先确认 Qwen3 0.6B 会产生尾逗号、错位 / 缺失闭合、全角右括号、`nextStep` / `nextAction` object 和 schema 占位内容；解析器只对这些已证实模式做保守兼容，仍保留严格安全过滤。随后在统一 `AiProtocol` 增加默认关闭的 `jsonResponse` 提示，Reflection 正式调用链传到 Ollama 时使用 `format=json`、`think=false`、`temperature=0`，不改变普通聊天；Ollama request body 已由本机 `HttpServer` 回归直接验证。live gate 同时修正旧数据本地规则已占满 8 条结论 / 8 个行动项、导致模型永远无补充空间的问题，改为仍有 72 条消息但本地基线为 5 / 4 的长会话。真实 `qwen3:4b` 当时首次通过后再连续复跑 5 次，全部通过，单次约 14.7–14.9 秒，最终均合并为 8 条结论 / 8 个行动项，保留全部本地安全基线，不包含测试密钥、URL、本机路径，也没有把 Android 跨日、iOS 后台刷新或模型门禁写成虚假完成。该结果只作为历史证据保留；按当前用户约束禁止再次启动、探测或重跑本地模型，后续只使用仓库外配置驱动的远程接口。最终全量稳定门禁 544 项通过，analyze 无问题。
- 2026-07-14：补跨日验证状态持久性和充电条件放行证据。真实 86400 秒 job 仍在 Pixel 8 `waiting`，但 `/tmp` 状态文件提前消失，导致独立 `status / verify / cleanup` 失去入口；新增红灯回归后把跨日状态默认迁移到仓库私有 `.omx/state/android-background-dreaming-cross-day.state`，schedule 自动创建目录，文件保持 0600，当前任务已按设备 JobScheduler、正式包 identity 和账本证据恢复，独立 status 再次可用。另用 `top.simitalk.aichat.chargingdiagnosticsmoke` 验证系统 `JobInfo` 为 `Requires: charging=true`：未充电时 `CHARGING` 未满足且严格运行被拒绝，切换为 `get-battery-charging=true` 后约束转为满足，未使用 `-f`，300 秒 initialDelay 到期后由 JobScheduler 自然执行，elapsed `322` 秒完成 Dreaming / Reflection；正式包 firstInstallTime / dataDir 不变，battery mock、隔离包和 sqlite hook 均已恢复。模型解析、跨日脚本和全仓最终稳定门禁 538 项通过，analyze 无问题，`git diff --check` 无输出。
- 2026-07-14：iOS BGTask 阻塞诊断与用户恢复入口继续加固。新增 `openIosAppSettings()` 和原生 `openAppSettings` MethodChannel 分支，使用 `UIApplication.openSettingsURLString` 打开当前 App 系统设置；Dreaming 弹窗在后台 App 刷新 denied / restricted 时显示“打开系统设置”和“重新检查”。隔离 smoke READY JSON 新增 `backgroundRefreshStatus`，脚本在系统未保留 pending task 时直接打印原生状态。TDD 先红灯于方法、按钮和字段缺失，修复后 iOS 状态 / release manifest / 设置页聚焦 27 项通过；iPhone13 release 真机复跑通过解锁预检、27.5MB 构建、安装、启动和 READY，输出 `backgroundRefreshStatus=denied` 与 `There are no scheduled tasks`，从设备直接证明 blocker；cleanup 后仅正式 `top.simitalk.aichat` 存在并运行 pid `86792`，无隔离 bundle / sqlite hook。新增 1 项测试后全量稳定门禁 531 项通过，analyze 无问题。该项仍需用户在系统设置开启后台 App 刷新后复跑，不能把可操作诊断当作 BGTask 执行成功。
- 2026-07-14：补 Dreaming / Reflection 系统后台附加条件 v1。先以测试红灯确认 `DreamingScheduleConfig` 不包含充电 / 网络字段、调度客户端不接收完整配置、Android / iOS WorkManager 约束固定为无网络 / 不充电；随后增加 `requiresCharging` / `requiresUnmeteredNetwork`，旧 JSON 默认关闭，设置页移动端弹窗可配置并立即重排，入口显示当前附加条件，结构化备份 / 恢复保留字段。Android 映射为 `requiresCharging` 与 `NetworkType.unmetered`；iOS 映射充电条件，网络选择映射为 `NetworkType.connected` 并在 UI 明确“不能保证 Wi-Fi”。移动端 390x844 widget 路径、配置 / 调度 / 平台约束 / 备份聚焦 36 项通过；新增真机约束脚本静态门禁后全量稳定门禁 530 项通过；`flutter --no-version-check analyze --no-pub` 无问题。
- 2026-07-14：Pixel 8 后台附加条件真机 smoke 使用两个独立包，未覆盖正在等待的 `backgroundsmoke`。充电包 `top.simitalk.aichat.chargingconstraintsmoke` 在系统 `get-battery-charging=false` 时显示 `Requires: charging=true` / `Unsatisfied constraints: CHARGING`，`jobscheduler run -s` 被拒绝；设备虽 `AC powered=true`，但系统充电策略仍报告非充电，shell battery status 模拟也不更新 JobScheduler 判定，因此没有用 `-f` 绕过条件，充电放行保持未完成。网络包 `top.simitalk.aichat.networkconstraintsmoke` 在关闭 Wi-Fi 后显示 CONNECTIVITY 未满足并被严格拒绝；恢复 `WIFI + NOT_METERED + VALIDATED` 后同一 `run -s` 放行，66 秒完成 `digest=2026-07-14 reflection=2026-07-14`，prefs 含 Dreaming / Reflection 最近报告与历史且无 pending。cleanup 后 Wi-Fi 恢复、battery mock reset、正式包 pid `5380`、firstInstallTime / dataDir 不变、无约束隔离包 / sqlite hook；跨日 job id `0` 仍 waiting。证据：`/tmp/simichat-android-dreaming-constraint-suite-20260714145948.log`、`/tmp/simichat-android-dreaming-network-host-20260714145948.log`、`/tmp/simichat-android-dreaming-network-20260714145948.xml`。
- 2026-07-14：Android 跨日 Dreaming / Reflection 分离式 smoke 基础设施已落地并安排真实任务。先红灯确认旧 harness 没有 `scheduledMessageAt` 且缺少跨日入口；修复后 seed 消息 `created_at` 写为 `now + initialDelay`，确保次日执行能进入目标日期 Dreaming 窗口。主脚本新增受控 `BACKGROUND_DETACH_AFTER_SCHEDULE=1`：只允许 natural + kill，调度后写 0600 shell-safe 状态文件，保留隔离包 / JobScheduler job，但 cleanup 仍立即恢复 `pubspec.yaml` / `pubspec.lock`、正式包进程和 identity。新增 `smoke_device_android_background_dreaming_cross_day.sh` 的 schedule / status / verify / cleanup；30 秒自测证明 schedule 退出后独立 verify 可读取 Dreaming / Reflection、识别新 pid 并清理，提前 verify 返回 3 不误清理；600 秒任务主动 cleanup 也通过。目标门禁 7 项、全量稳定门禁 524 项和 analyze 通过。随后 Pixel 8 正式调度 86400 秒任务：旧 pid `28141` 消失，expectedDayKey `2026-07-15`，job id `0` waiting；状态已从易失 `/tmp` 迁移并恢复到 `.omx/state/android-background-dreaming-cross-day.state`。正式包 firstInstallTime / dataDir 不变、deep `ACTIVE`、无 sqlite hook。该项仍为进行中，不能在次日 verify 前标记跨日通过。
- 2026-07-14：Pixel 8 UI 进程死亡后的跨小时无 force 自然调度已通过。复用 `smoke_device_android_background_dreaming_process_death_natural.sh`，以环境变量设置 `SMOKE_INITIAL_DELAY_SECONDS=3600`、`RESULT_WAIT_SECONDS=7200`；隔离 App 回到 Home 后旧 pid `6444` 被回收，JobScheduler job 在整个等待期保持存在，前 55 分钟只有 `TIMING_DELAY` 未满足，电量 / 存储 / Doze / 后台限制 / quota 约束均满足，standby bucket 从 `ACTIVE` 自然降到 `RARE`。一小时到期后 job 进入 ready，系统继续批处理约 12 分钟，最终在 elapsed `4360` 秒时为 `SystemJobService` 冷启动新 pid `24325`，输出 `status=completed digest=2026-07-14 reflection=2026-07-14`；prefs 含 Dreaming、Reflection 最近报告与历史且无 pending。cleanup 后 `deep=ACTIVE`、正式包 pid `24737`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook；最终全量稳定门禁 523 项和 analyze 通过。取证为 `/tmp/simichat-android-background-dreaming-hourly-20260714.log`、`/tmp/simichat-android-background-dreaming-hourly-20260714.xml` 和 `/tmp/simichat-android-background-dreaming-hourly-host-20260714.log`。该结果把 Android 证据从数分钟推进到跨小时，但仍不替代跨日、长时间 Doze 或 OEM 严格后台限制。
- 2026-07-14：Pixel 8 UI 进程死亡后的无 shell force 自然调度已通过。新增 `scripts/smoke_device_android_background_dreaming_process_death_natural.sh` 和静态门禁；先红灯确认入口不存在，再落地 `TRIGGER_MODE=natural`、`BACKGROUND_PROCESS_MODE=kill`、30 秒 initialDelay。前两次 180 / 240 秒观察窗口未收到结果，但实时 `dumpsys jobscheduler` 证明 job 未丢失、`Standby bucket=ACTIVE`、电量 / 存储 / 后台 / quota 约束满足并进入 ready；扩大到 900 秒观察后，旧 pid `2639` 消失，系统未收到任何 `cmd jobscheduler run`，在 READY 后 249 秒为 `SystemJobService` 冷启动新 pid `4668`，输出 `status=completed digest=2026-07-14 reflection=2026-07-14`。隔离 prefs 含 Dreaming、Reflection 最近报告与历史且无 pending；cleanup 后 `deep=ACTIVE`、正式包 pid `4980`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook。专用 wrapper 默认等待已通过红灯转绿锁定为 900 秒；目标门禁 6 项、最终全量稳定门禁 523 项和 analyze 通过。该结果证明进程死亡后的自然系统调度可恢复，但 249 秒实际延迟也说明不能用 30 秒 initialDelay 推导精确执行时间，更不替代跨小时 / 跨日 Doze 或 OEM 长期观察。取证为 `/tmp/simichat-android-background-dreaming-20260714122709.log` 和 `/tmp/simichat-android-background-dreaming-prefs-20260714122709.xml`。
- 2026-07-14：Pixel 8 UI 进程死亡后的 WorkManager headless 冷启动 smoke 已通过。新增 `BACKGROUND_PROCESS_MODE=kill`、`PROCESS_KILL_SETTLE_SECONDS` 和 `scripts/smoke_device_android_background_dreaming_process_death.sh`；先红灯确认脚本缺少 WorkSpec 到期等待，再把 wrapper 调整为 30 秒 initialDelay、旧 pid 消失后等待 35 秒，并再次确认 package 未 stopped、精确 JobScheduler job 仍存在。真机旧 pid `30424` 被 `am kill` 回收，`ActivityManager` 为 `top.simitalk.aichat.backgroundsmoke/androidx.work.impl.background.systemjob.SystemJobService` 冷启动新 pid `30629`，后台 Flutter isolate 输出 `status=completed digest=2026-07-14 reflection=2026-07-14`；cleanup 后 `deep=ACTIVE`、正式包 pid `30813`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook。目标 manifest 门禁 5 项、最终全量稳定门禁 522 项、analyze 和 `git diff --check` 通过。此前 kill 后立即 force 的红灯只拉起服务进程但 WorkSpec 尚未到期，不能误报任务执行成功；本次也不把 forced callback 扩大为自然调度时延、数小时 / 跨日 Doze 或 OEM 杀后台证明。取证为 `/tmp/simichat-android-background-dreaming-20260714115140.log` 和 `/tmp/simichat-android-background-dreaming-prefs-20260714115140.xml`。
- 2026-07-14：Pixel 8 强制 deep idle Dreaming / Reflection 短时 smoke 已通过。新增 `scripts/smoke_device_android_background_dreaming_doze.sh`，隔离包回到 Home 后强制进入 deep idle，调度与完成 marker 两个时点均校验为 `IDLE` / `IDLE_MAINTENANCE`，拒绝永久 idle whitelist，cleanup 无论成功失败都先 `deviceidle unforce` 再恢复正式包。本轮结果 `idleStateAtSchedule=IDLE idleStateAtResult=IDLE elapsedSeconds=37`，Dreaming / Reflection 均为 `2026-07-14`；正式包 firstInstallTime / dataDir 不变、最终 pid `27177`，无隔离包 / sqlite hook。同步修复 force smoke 从全局 logcat 误抓其他 App Job ID 的问题，改为只从 `dumpsys jobscheduler` 精确匹配隔离包，force 分支复跑 job id `0`、10 秒完成。新增静态门禁 2 项，最终全量稳定门禁 521 项通过，analyze 无问题。该证据只覆盖短时强制 deep idle，不替代数小时 / 跨日 / OEM 长期观察。
- 2026-07-14：后台 Reflection pending 连续失败退避缺口已修复。新增 `Android background retry stays pending when Reflection still fails`，先红灯确认第二次反思仍失败时旧 runner 返回 `notDue`，修复后保持 `reflectionPending`，让 Android WorkManager 返回 retry、iOS 排 15 分钟重试；目标文件 4 项、全量稳定门禁 519 项通过。Pixel 8 同轮默认 force shell 触发未收到结果 marker，但不调用 shell 强制命令的自然调度在 Home 后 36 秒由 SystemJobScheduler 完成 Dreaming / Reflection，正式包 identity / dataDir 不变且无隔离包 / sqlite hook 残留。iPhone13 隔离 release smoke 解锁预检和构建通过，但系统仍未保留 BGTask pending request，真机系统执行继续等待开启“后台 App 刷新”。
- 2026-07-14：Pixel 8 Android WorkManager 自然调度补证通过。新增 `scripts/smoke_device_android_background_dreaming_natural.sh`，复用隔离包 / 正式包 identity 保护 / sqlite hook 恢复，并让 smoke initialDelay 可配置；harness 补齐生产任务的 `requiresBatteryNotLow` / `requiresStorageNotLow` 基础约束。设备回到 Home 后未调用任何 `cmd jobscheduler run`，`READY` 后 36 秒由 SystemJobScheduler 自行输出 `status=completed digest=2026-07-14 reflection=2026-07-14`，隔离 prefs 含 Dreaming / Reflection 最近报告和历史且无 pending；随后默认 force 分支复跑通过。两次 cleanup 后正式包 firstInstallTime / dataDir 不变，最终 pid `24389`，无隔离包和 sqlite hook 残留；最终全量稳定门禁 518 项通过。取证见 `/tmp/simichat_android_natural_background_final.log`、`/tmp/simichat-android-background-dreaming-20260714042907.log` 和 `docs/archive/mobile-android-background-dreaming-smoke-2026-07-14.md`。
- 2026-07-14：可选模型增强 Reflection v1 已落地。新增严格 JSON / 输入输出脱敏 / 长度边界服务、`generationMode` 兼容、默认聊天模型正式协议调用、默认关闭的设置页开关、失败本地回退和结构化备份白名单。模型聚焦组合 60 项通过；补齐模型输出 URL / 本机路径过滤，并修复本机协议测试 Dio / `HttpServer` 资源未释放后，全量稳定门禁 517 项通过，日志无 Drift / 多数据库 / 失败标记；analyze 和 `git diff --check` 通过。Android debug APK 166MB、iOS release `--no-codesign` Runner.app 33.3MB arm64 构建成功，正式包名、BGTask identifier 和 sqlite 配置保持干净。后续已进一步补真实本地 Ollama `qwen3:4b` 72 条长会话连续 5 / 5 质量门禁；云端外部模型和更多模型族仍需单独验证。
- 2026-07-14：iOS BGTaskScheduler `BGProcessingTask` 代码基线、隔离 release smoke 和系统可用性诊断已落地。`AppDelegate` 在启动完成前注册 `top.simitalk.aichat.dreaming.processing`，Info.plist 声明 `BGTaskSchedulerPermittedIdentifiers` / `processing`，Dart 调度成功后排下一日、失败时排 15 分钟重试，并以 `ios_background` 写入正式 SQLite trigger。隔离 smoke 使用独立 bundle / task 子命名空间，READY JSON 会调用 `Workmanager().printScheduledTasks()` 验证系统真实 pending request，避免 `workmanager 0.8.0` 吞掉 submit 错误后形成假成功。iPhone13 只读 LLDB 查询两次确认 `UIApplication.backgroundRefreshStatus=1`（denied），系统未保留 pending task；设置页因此新增可用 / 已关闭 / 受限状态和前台兜底反馈。相关聚焦门禁 39 项通过，新增状态 / 设置页回归 23 项通过，最终全量稳定门禁 508 项通过，analyze 无问题；正式 iOS release `--no-codesign` 构建通过，Runner.app 33.3MB、arm64，产物包含正式 BGTask identifier、`processing` background mode 和原生状态通道。真机 BGTask 执行待开启系统“后台 App 刷新”后继续。
- 2026-07-14：Android WorkManager 系统后台 Dreaming / Reflection v1 已落地。新增纯 Dart 下一次运行时间计算、一次性唯一任务、后台 `ProviderContainer`、正式私有 SQLite、完成 / 失败通知、成功后次日重排和 Reflection pending retry；前台 / 后台自动路径使用 SQLite `dreaming-auto-YYYY-MM-DD` 原子 claim 防跨 isolate 重复。最终精确锁定 `workmanager 0.8.0` 以保持 iOS 13 deployment target；Android arm64 debug APK 与 iOS release `--no-codesign` 构建通过，合并 Android manifest 可见 `WorkManagerInitializer` / `SystemJobService` / `RescheduleReceiver`。Pixel 8 独立包 `top.simitalk.aichat.backgroundsmoke` 在 Home 后先尝试 Android 16 namespaced JobScheduler 命令，因 `0.8.0` 使用 legacy job 自动回退到无 namespace 命令并成功强制触发真实 WorkManager job，输出 `status=completed digest=2026-07-14 reflection=2026-07-14`；隔离 prefs 包含 Dreaming 和 Reflection 最近报告 / 历史，cleanup 后正式包 firstInstallTime / dataDir 不变、pid `12024`，无隔离包和 sqlite hook 残留。最终全量稳定门禁 499 项通过，analyze 无问题，日志无 `WARNING (drift)` / `multiple databases`。取证文件为 `/tmp/simichat-android-background-dreaming-20260714013910.log`、`/tmp/simichat-android-background-dreaming-prefs-20260714013910.xml`，详见 `docs/archive/mobile-android-background-dreaming-smoke-2026-07-14.md`。
- 2026-07-14：Pixel 8 `37101FDJH0077P` 通过独立包 Dreaming / Reflection 失败恢复真机 smoke。最终安全路径只构建并安装 `top.simitalk.aichat.dreamingsmoke`，使用内存 SQLite 和隔离包 SharedPreferences；第一次反思失败输出 `SIMICHAT_DREAMING_REFLECTION_PENDING dayKey=2026-07-14 attempts=1`，Home 后重新恢复前台输出 `SIMICHAT_DREAMING_REFLECTION_RECOVERED dayKey=2026-07-14 attempts=2 history=1`。cleanup 卸载隔离包、恢复普通 release 进程，正式包在修正后 smoke 前后 `firstInstallTime=2026-07-14 00:29:02`、`dataDir=/data/user/0/top.simitalk.aichat` 未变化；代码稳定门禁 124 项通过，analyze 无问题。首次尝试的 `flutter test -d` 动态 applicationId 路径错误卸载了正式包并导致 Pixel 8 应用私有数据丢失，系统 LocalTransport / D2D 恢复均返回 `-1000`，已废弃并以静态门禁禁止复用；详见 `docs/archive/mobile-dreaming-reflection-recovery-smoke-2026-07-14.md`。
- 2026-07-13：补 Reflection 独立失败恢复 v1。`runAssistantReflection()` 在生成前写 `assistant_reflection_pending_v1`，最近反思和历史均保存后清除；启动 / 恢复前台 / 前台定时检查会调用 `retryPendingAssistantReflection()`，来源非当前最新 Dreaming 时先从 Dreaming 历史、再从 SQLite report 按 dayKey 恢复。设置页显示来源、尝试次数和清除入口，手动失败反馈“反思失败，已标记待重试”；清空 / 删除来源报告同步清理 pending；pending 进入结构化备份白名单。聚焦 55 项通过，含数据导出 / 导入的完整稳定门禁 120 项通过，`flutter --no-version-check analyze --no-pub` 无问题。
- 2026-07-13：补强移动端 Dreaming / Reflection 直接回归证据。`test/mobile_main_flow_smoke_test.dart` 的首次启动到期、恢复前台到期、持续前台定时三条路径现在都会解码并校验 `dreaming_digest_v1`、`assistant_reflection_v1` 和 `assistant_reflection_history_v1`，要求反思有内容、历史非空且 `sourceDigestDayKey` 与本次 Dreaming `dayKey` 一致。`--name dreaming` 移动端 smoke 9 项通过；Dreaming / Reflection / 通知 / 设置页 / 上下文注入 / SQLite / 结构化备份稳定门禁 93 项通过；`scripts/benchmark_dreaming.sh -r expanded` 的 1000 条消息基准为 `run_ms=78`、`digest_elapsed_ms=74`、`memory_candidates=40`。
- 2026-07-07：`scripts/smoke_full_stability_gate.sh -r expanded test/reflection_service_test.dart test/dreaming_service_test.dart test/reflection_provider_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/structured_data_backup_test.dart` 通过 44 项，覆盖手动整理、前台到期、并发防重、报告历史、设置页下次前台整理状态、设置页历史展示 / 展开审阅 / 单条删除 / 最近报告回退 / 清空、结构化备份、服务、敏感标题降级、会话最后消息角色、最新用户问题安全片段、敏感最后用户消息不回退、明确任务语气进入 `task` 记忆候选、会话追问压力、重复追问、最新任务推进、普通礼貌问题不误触发最新任务、最后一问未答、反思历史展开审阅 / 精确单条删除 / 当前报告回退和反思链路。
- 2026-07-07：`scripts/benchmark_dreaming.sh -r expanded` 通过，1000 条消息 `run_ms=55`、`digest_elapsed_ms=52`、`memory_candidates=40`、`has_content=true`。
- 2026-07-07：设置页 Dreaming 入口已明确“前台到期 · 非系统后台”边界，并展示“下次前台整理”状态；新增 `dreaming tile explains foreground-only schedule boundary` widget 回归和 `dreaming schedule formats next foreground run status` 单元回归。
- 2026-07-07：新增 `DreamingJobs` / `DreamingReports` Drift 表、`DreamingDao` 和 schemaVersion 7 迁移；新增 `test/dreaming_dao_test.dart` 覆盖 job lifecycle、最近报告读取和同日报告 upsert；`structured_data/local_database.json` 已包含 `dreaming_jobs` / `dreaming_reports` 导出 / 恢复，`test/data_export_service_test.dart --name "dreaming jobs"` 通过。
- 2026-07-07：`runDreamingDigest()` 已接入 SQLite job/report：运行前创建 job 并标记 running，成功后 upsert 当日 report 并标记 completed，前台到期触发来源为 `foreground_due`；新增 `runDreamingDigest persists sqlite job and report` 回归，`test/dreaming_provider_test.dart` 5 项通过。
- 2026-07-07：补 Dreaming 失败一致性保护：先用 `runDreamingDigest failure marks job failed without publishing stale report` 红灯复现 Key Points 写入失败时旧逻辑会提前发布 `dreaming_digest_v1`；修复后只有 durable 阶段完成才发布最新报告 / 历史，失败仅保留 failed job，不写 SQLite report / SharedPreferences 脏报告；`scripts/smoke_full_stability_gate.sh -r expanded test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/dreaming_service_test.dart test/settings_page_dreaming_test.dart test/structured_data_backup_test.dart` 通过 39 项，`flutter --no-version-check analyze --no-pub` 无问题。
- 2026-07-07：补 SQLite report 回灌设置页状态：新增 `syncDreamingDigestStateFromDatabase()`，导入成功后会从 `dreaming_reports.digest_json` 恢复 `dreaming_digest_v1` 和 `dreaming_digest_history_v1`；新增 `syncs dreaming provider state from sqlite reports` 红灯回归并转绿。验证：Dreaming / 导入专项 `scripts/smoke_full_stability_gate.sh -r expanded test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/settings_page_dreaming_test.dart test/structured_data_backup_test.dart` 通过 49 项，`flutter --no-version-check analyze --no-pub` 无问题。
- 2026-07-07：补 Dreaming 报告删除 / 清空与 SQLite 持久层一致性：先红灯确认设置页清空 / 删除只清 SharedPreferences，SQLite `dreaming_reports` 仍残留；修复后 `_clearDreamingReports()` 调用 `DreamingDao.clearReports()`，`_deleteDreamingReport()` 调用 `deleteReportByDay(dayKey)`。验证：`test/settings_page_dreaming_test.dart` 12 项通过；Dreaming / 数据专项 `scripts/smoke_full_stability_gate.sh -r expanded test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 49 项通过，`flutter --no-version-check analyze --no-pub` 无问题。
- 2026-07-07：补 Dreaming job 去重 / 恢复策略：先红灯确认同日并发 `runDreamingDigest()` 会产生 2 个 completed job、崩溃残留 `pending` / `running` 不会自动收敛；修复后按 `dayKey` 复用 in-flight Future，并由 `DreamingDao.failUnfinishedJobsByDay()` 在新运行前把同日未完成 job 标记 failed。验证：`flutter --no-version-check test --no-pub --no-test-assets test/dreaming_dao_test.dart test/dreaming_provider_test.dart -r expanded` 12 项通过；Dreaming / 数据完整门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 52 项通过；`flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出；`pubspec.yaml` / `pubspec.lock` 无临时 sqlite hook 残留。
- 2026-07-07：补 Dreaming failed job 可见状态与重试入口：新增 `DreamingDao.getLatestUnresolvedFailedJob()` 与 `latestFailedDreamingJobProvider`，设置页入口 / 弹窗显示最近未解决 failed job 并提供“重试最近失败”；重试成功后同日后续 completed job 会覆盖失败提示。验证：先红灯于缺少 unresolved failed job 查询和 UI 提示；修复后 `flutter --no-version-check test --no-pub --no-test-assets test/dreaming_dao_test.dart test/dreaming_provider_test.dart test/settings_page_dreaming_test.dart -r expanded` 26 项通过；Dreaming / 数据完整门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 54 项通过。
- 2026-07-07：补 Dreaming failed job 启动 / 前台恢复主动提示：新增移动端 smoke 红灯 `mobile startup prompts for unresolved dreaming failure` 与 `mobile resume prompts for unresolved dreaming failure`，应用启动或恢复前台时若存在未解决 failed job，会显示“上次 Dreaming 失败，可到设置页重试”并可点“去设置”进入设置页查看失败详情 / 重试；同一进程同一 failed job 只提示一次。验证：聚焦 `flutter --no-version-check test --no-pub --no-test-assets test/mobile_main_flow_smoke_test.dart --name "dreaming failure" -r expanded` 2 项通过；Dreaming smoke `--name dreaming` 8 项通过；Dreaming / 设置页 / DAO 专项 26 项通过；完整 Dreaming 稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/mobile_main_flow_smoke_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 75 项通过。
- 2026-07-07：补 Dreaming 前台到期失败本地通知：新增 `buildDreamingDigestFailedNotificationBody()` 和 `NotificationService.showDreamingDigestFailed()`，失败通知标题为“Dreaming 整理失败”，正文为“YYYY-MM-DD 整理失败，可到设置页重试”，不暴露底层错误详情；`_runDueDreamingIfNeeded()` 捕获前台到期整理失败后读取最近未解决 failed job 并通过 `dreamingDigestFailedNotifier` 推送，同一进程同一 dayKey 只通知一次。验证：`buildDreamingDigestFailedNotificationBody 失败通知不暴露底层错误详情，只引导用户去设置页重试` 先红灯后通过；`mobile due dreaming failure sends local failure notification` 先红灯后通过；完整 Dreaming / 通知稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/mobile_main_flow_smoke_test.dart test/notification_service_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 84 项通过。
- 2026-07-07：补 Dreaming 设置页手动运行失败反馈：新增 `dreaming manual run failure shows retryable feedback`，先红灯确认 `_runDreaming()` 会把 `runDreamingDigest()` 异常抛到 Flutter 测试框架且无用户提示；修复后手动运行失败显示“Dreaming 失败，可到设置页重试”，不崩溃、不写半成功报告，并保留最近未解决 failed job 供设置页查看 / 重试。验证：聚焦用例通过；设置页 / Dreaming / DAO 专项 `flutter --no-version-check test --no-pub --no-test-assets test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart -r expanded` 27 项通过；完整 Dreaming / 通知稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/mobile_main_flow_smoke_test.dart test/notification_service_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 85 项通过。
- 2026-07-07：补 Dreaming failed job URL 脱敏：新增设置页 failed job 摘要、snapshot 导出和 snapshot 恢复三处断言，先红灯确认错误摘要仍会显示 `https://example.test/...`；修复后 `_sanitizeDreamingFailedJobError()` 与 `_safeDiagnosticString()` 统一把 HTTP(S) URL 替换为 `[链接]`，独立 token / api_key 参数继续脱敏为 `token=***` / `api_key=***`。验证：聚焦 3 项红灯后转绿；设置页 / 导出 / 导入 / Dreaming / DAO / 结构化备份专项 51 项通过。
- 2026-07-07：补 Dreaming failed job 恢复错误脱敏：新增 `restores dreaming failed job errors as sanitized diagnostics`，先红灯确认旧导出包 / 外部包导入时 `dreaming_jobs.error` 会把 Bearer、`sk-*`、`token=raw` 和 `/Users/...` 原样写入 SQLite；修复后 `restoreSnapshot()` 写入 job 前复用 `_safeDiagnosticString()`，恢复后的 failed job 只保留脱敏诊断摘要。验证：聚焦用例红灯后转绿；导出 / 导入 / Dreaming / DAO / 结构化备份专项 36 项通过。
- 2026-07-07：补 Dreaming failed job 未解决扫描：新增 `dreaming dao scans past resolved failures for unresolved job`，先红灯确认默认只扫最近 20 个 failed job 时会漏掉更早但仍未解决的失败；修复后 `getLatestUnresolvedFailedJob()` 分页扫描 failed job，跳过同日后续 completed 已覆盖项。验证：目标用例红灯后转绿；DAO / 设置页 / provider 专项 31 项通过。
- 2026-07-07：补 Dreaming failed job 清除 / 忽略入口：新增 `DreamingDao.dismissFailedJob()` 和设置页“清除此失败”按钮，先红灯确认弹窗没有清除入口；修复后 failed job 标记为 `dismissed`，`getLatestUnresolvedFailedJob()` 返回 null，入口“最近失败 YYYY-MM-DD”和弹窗失败卡片消失。验证：目标用例红灯后转绿；设置页 / provider / DAO 专项 30 项通过；完整 Dreaming / 通知 / 数据门禁 90 项通过，Drift warning 扫描无输出，`pubspec.yaml` / `pubspec.lock` 无临时 sqlite hook 残留。
- 2026-07-07：补 Dreaming failed job 导出 / 恢复错误脱敏：新增 `exports dreaming failed job errors without leaking secrets or paths`，先红灯确认本地数据库快照导出的 `dreaming_jobs.error` 会原样泄露 Bearer、`sk-*`、`token=raw` 和 `/Users/...` 路径；修复后 `LocalDatabaseSnapshotService` 导出层使用 `_safeDiagnosticString()` 将错误摘要脱敏为 `Bearer ***`、`sk-***`、`token=***`、`api_key=***`、`[本机路径]`。验证：聚焦用例红灯后转绿；导出 / 导入 / Dreaming / DAO / 结构化备份专项 35 项通过。
- 2026-07-07：补 Dreaming failed job 错误摘要脱敏：新增 `dreaming failed job error summary is sanitized`，先红灯确认设置页 failed job 弹窗会直接显示 Bearer token、`sk-*`、`token=raw` 和 `/Users/...` 本机路径；修复后 `_formatDreamingFailedJob()` 只展示脱敏摘要（如 `Bearer ***`、`[本机路径]`、`token=***`），避免失败截图 / 屏幕共享泄露密钥或本机路径。验证：聚焦用例通过；设置页 / Dreaming / DAO 专项 28 项通过；完整 Dreaming / 通知稳定门禁 `scripts/smoke_full_stability_gate.sh -r expanded test/mobile_main_flow_smoke_test.dart test/notification_service_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/dreaming_dao_test.dart test/data_export_service_test.dart test/data_import_service_test.dart test/dreaming_service_test.dart test/structured_data_backup_test.dart` 86 项通过，warning 扫描 `WARNING (drift)|multiple databases` 无输出。
- 2026-07-07：`flutter --no-version-check analyze` 无问题。
