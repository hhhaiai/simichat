# Reflection 反思机制 v1

> **文档边界**：本文是 Reflection 的实现专题和历史质量记录。当前代码、验证数量、默认模型和本地 Ollama 状态以 `current-status.md` 与 `verification-baseline-2026-08-08.md` 为准；历史质量记录不替代新的真实模型或真机验证。

> 对应模块：M2 记忆与上下文系统 / M3 Dreaming / M10 数字孪生。状态：本地启发式反思 v1、可选模型增强反思 v1、会话追问压力提醒 v1、重复追问提醒 v1、最新任务推进提醒 v1、最后一问未答提醒 v1、短期提示注入 v1、反思历史可控管理 v1、反思独立失败恢复 v1 已落地。最后更新：2026-07-14。

## 1. 目标

本地反思机制用于在 Dreaming 之后，对当天对话质量和长期智能助理状态做一次可解释复盘，帮助应用逐步优化：

- 回应质量：发现用户消息明显多于助手回复、全局无助手回复、全局轮次均衡但单个会话用户追问明显多于助手回复、单个会话用户多条消息但助手 0 回复、同一会话反复追问相近问题、会话最后一条仍是用户追问等异常节奏。
- 上下文质量：发现长会话，提示后续复查摘要、最新问题保留和上下文预算裁剪。
- 长期记忆：统计新增记忆候选，提示缺失稳定偏好 / 目标 / 任务沉淀的情况。
- 用户画像：提示待确认画像变更，避免画像候选长期不被采纳。
- 任务推进：从画像中的任务、目标、偏好或 Dreaming 关键词给出下一步行动项。
- 最新任务：当 Dreaming 保存的最后用户问题明显是任务语气时，优先把它转成下一轮短期提示，避免只保留关键词。
- 来源新鲜度：当反思日期与来源 Dreaming 日期不一致时，生成高优先级提醒，设置页入口直接显示旧来源日期并提示先运行今日 Dreaming，避免把旧日报当作当前上下文。
- 短期自我优化：把少量高优先级结论和行动项注入下一轮本机 system prompt，帮助回复优先收口问题、关注长会话上下文风险并推进任务；当行动项较多时，优先保留能直接改善下一轮回复的任务推进项，画像采纳等维护动作仍保留在完整报告中。
- 持续优化轨迹：保留最近反思历史，为后续趋势评估、质量基线和模型驱动反思提供本地依据。

## 2. 当前边界

本地启发式反思始终作为安全基线，不依赖远端模型。可选模型增强默认关闭，只有用户在设置页明确开启后，才会把经过长度限制和敏感信息处理的 Dreaming 摘要、本地反思发送给默认已启用聊天模型；模型必须返回严格 JSON，超时、无可用模型、协议失败、格式异常或内容不安全时自动保留本地报告，不让可选增强阻塞 Dreaming、残留 Reflection pending 或触发后台任务反复 retry。短期提示注入默认开启，用户可在设置页关闭；最近反思报告与历史可在同一弹窗中展开审阅、按 `dayKey + sourceDigestDayKey` 精确删除单条，删除反馈会显示来源，支持删除当前报告后回退或整体清空。

输入仅来自：

- 最近 `DreamingDigest`。
- 当前 `UserProfile`。
- 待确认画像变更数量。

输出只写入 SharedPreferences：

- `assistant_reflection_v1`：最近一次 `ReflectionReport`。
- `assistant_reflection_history_v1`：最近反思历史，当前最多保留 20 次，同一 Dreaming 日期重复运行会用最新报告替换旧报告；用户可在设置页展开审阅、按 `dayKey + sourceDigestDayKey` 精确删除单条或整体清空。
- `assistant_reflection_prompt_enabled_v1`：是否允许把本地反思行动项作为下一轮短期提示，默认开启。
- `assistant_reflection_model_enabled_v1`：是否允许调用默认聊天模型增强反思，默认关闭，必须由用户显式开启。
- `assistant_reflection_pending_v1`：反思独立失败恢复状态，只保存来源 Dreaming `dayKey`、更新时间和尝试次数，不保存底层错误、对话原文、摘要、模型配置或密钥。

结构化备份白名单已包含 `assistant_reflection_v1`、`assistant_reflection_history_v1`、`assistant_reflection_prompt_enabled_v1`、`assistant_reflection_model_enabled_v1` 和 `assistant_reflection_pending_v1`；它们和 Key Points / Dreaming / 用户画像一样属于本地智能状态，不包含模型 API Key、Bearer token、上游 Base URL、本机绝对路径或聊天原文密钥。

## 3. 数据结构

核心文件：

- `lib/core/memory/reflection_service.dart`
  - `ReflectionInsight`：单条反思结论，包含分类、文本和优先级。
  - `ReflectionReport`：日级反思报告，包含来源 Dreaming 日期、消息统计、待确认画像变更数、生成方式、反思结论和行动项；旧报告缺少 `generationMode` 时兼容为 `local`，模型增强成功时记录为 `model`，模型已尝试但失败并安全保留本地报告时记录为 `model_fallback`，不保存异常详情。当来源 Dreaming 不是反思当天时，会保留“来源新鲜度”提醒；当 Dreaming 会话摘要显示单个会话用户消息比助手回复多 2 条及以上时，会生成“会话追问压力”提醒；当 highlights 与最新用户问题中出现相近追问时，会生成“重复追问”提醒并提示先明确状态 / 阻塞点 / 下一步；当最新用户问题命中“继续推进 / 请继续 / 请帮 / 帮我 / 修复 / 验证 / 复跑 / 补 / 实现 / 看下 / 检查”等明确任务语气时，会生成“最新任务推进”提醒；普通礼貌问题如“请问这个设置是什么意思”不会触发最新任务；最后一条消息来自用户时，会生成“最后一问未答”提醒，并优先带入 Dreaming 保存的最后用户问题安全片段；若最后用户消息敏感则只保留通用提醒。
  - `ReflectionService.buildDailyReflection()`：根据 Dreaming / 画像生成反思报告。
  - `buildAssistantReflectionSystemPrompt()`：把少量高优先级结论和行动项转为短期 system prompt 片段。
  - `encodeReflectionReport()` / `decodeReflectionReport()`：最近反思本地持久化序列化。
  - `encodeReflectionReportHistory()` / `decodeReflectionReportHistory()`：反思历史本地持久化序列化。
- `lib/core/memory/model_reflection_service.dart`
  - 构造长度受限、经过脱敏的模型提示；最大提示 12000 字符，最大响应 20000 字符。
  - 严格解析 JSON `insights` / `actionItems`，过滤密钥、token、URL 和本机路径；模型输出与本地结论合并而不是覆盖，最多保留 8 条结论和 8 个行动项。
- `lib/shared/providers/reflection_provider.dart`
  - `AssistantReflectionNotifier`：加载 / 保存 / 清空最近反思报告。
  - `AssistantReflectionPromptEnabledNotifier`：加载 / 保存短期提示注入开关，默认开启。
  - `AssistantReflectionModelEnabledNotifier`：加载 / 保存模型增强开关，默认关闭。
  - `AssistantReflectionHistoryNotifier`：加载 / 记录 / 按 `dayKey + sourceDigestDayKey` 删除单条 / 清空最近反思历史，最多保留 20 次。
  - `AssistantReflectionPendingNotifier`：加载 / 保存 / 清理待重试来源和尝试次数；损坏或非法 dayKey 会自动清理。
  - `runAssistantReflection()`：读取 Dreaming 与画像，运行前写 pending，先生成本地报告；模型增强开启时选择默认已启用聊天模型，没有默认则使用第一项。模型流最多占用 60 秒总墙钟时间，不会因持续慢碎片而逐块续期；超时、响应过长或其他异常会取消上游请求。模型增强失败时安全回退本地报告，最近反思和历史均保存成功后清除 pending。
  - `retryPendingAssistantReflection()`：启动、恢复前台和前台定时检查前重试；优先复用当前 Dreaming，来源日期不同时先从 Dreaming 历史、再从 SQLite `dreaming_reports` 按 dayKey 恢复对应 digest，避免误用更新日报。

## 4. 触发流程

```text
手动 Dreaming / 前台到期 Dreaming / Android WorkManager / iOS BGTaskScheduler 后台 Dreaming
  -> 生成 DreamingDigest
  -> 写入 Key Points
  -> 生成待确认 UserProfileChangeProposal
  -> runAssistantReflection()
  -> 写入 assistant_reflection_pending_v1
  -> 始终生成本地规则 ReflectionReport
  -> 若用户开启模型增强，调用默认聊天模型并严格解析 / 合并 JSON；失败则保留本地报告
  -> 保存 assistant_reflection_v1
  -> 记录 assistant_reflection_history_v1
  -> 清除 assistant_reflection_pending_v1
  -> 设置页展示最近反思、历史次数与行动项
  -> 若短期提示开关开启，下一轮聊天把少量高优先级结论 / 行动项并入本机 system prompt
```

Android 后台 isolate 通过 `ProviderContainer` 复用同一套 provider orchestration，不另写一套简化反思逻辑。Dreaming 成功但 Reflection 失败时，后台任务返回 retry；下一次先执行 `retryPendingAssistantReflectionWithAccess()`，只恢复 Reflection，不重复 Dreaming，并在恢复成功后补发一次完成通知。

设置页“记忆与画像 / 本地反思 / 自我优化”支持：

- 查看最近反思来源日期、来源是否过期、结论数量、行动项数量、历史保留次数、Markdown 预览，以及下一轮短期 system prompt 预览。
- 在已有 Dreaming 报告后手动运行反思。
- 当尚无 Dreaming 或无可整理对话时安全提示，不生成空误导报告。
- 反思失败时保留“反思待重试 YYYY-MM-DD”和尝试次数；手动失败显示“反思失败，已标记待重试”；应用启动 / 恢复前台时自动补跑，用户也可清除待重试状态。
- 清空反思、清空 Dreaming 报告或删除 pending 对应日期的 Dreaming 报告时同步清理 pending，避免用户主动删除后继续无来源重试。
- 开启 / 关闭“用于下一轮短期提示”，控制反思行动项是否影响后续回复；开启且有可注入内容时，可直接预览将并入下一轮本机 system prompt 的片段。
- 开启 / 关闭“使用模型增强反思”；界面明确提示默认关闭、会把受限且脱敏的摘要发送给默认聊天模型、失败自动回退本地反思。最近报告会标记“本地规则”“模型增强 + 本地规则”或“模型失败回退”；回退报告弹窗明确提示最近一次模型增强失败、本地安全结论已保存。

## 5. 安全与隐私

- 反思内容复用用户画像和 Dreaming 安全过滤逻辑，命中 API Key、Authorization、Bearer、password、secret、token、密钥、密码、常见密钥字面量时不写入报告；来源 Dreaming 会话标题命中敏感内容时只显示“敏感会话”。
- 报告不会保存原始对话全文，只保存统计、类别化结论和经过过滤的画像信号。
- 模型增强提示不发送 API Key、Bearer token、HTTP(S) URL 或本机绝对路径；提示和响应均有硬长度上限，模型返回内容再次经过严格 JSON、敏感信息和数量边界校验。合并时本地规则结论优先，模型最多补充 4 条结论 / 4 个行动项且不能挤掉本地安全基线；只重复本地内容时视为无有效增强并回退本地报告。
- 反思失败不会影响 Dreaming、画像候选、通知或聊天主链路；失败恢复 marker 不保存异常文本，只保存 dayKey、时间和次数。
- 可选模型增强失败只记录异常类型，不记录请求、URL、密钥或模型原文；失败不视为 Reflection 失败，不保留 pending，也不要求 WorkManager / BGTaskScheduler 重试。
- 短期提示只包含少量过滤后的高优先级结论和行动项，不包含反思全文；发送前会和 Key Points 一起被上下文预算裁剪。
- 临时测试中为绕过本机 GitHub 下载限制使用过 `sqlite3.source=system`，该配置未写入正式 `pubspec.yaml`。

## 6. 验证

已补测试：

- `test/reflection_service_test.dart`
  - 生成回应质量 / 上下文 / 画像 / 行动项反思。
  - 全局轮次均衡但单个会话没有助手回复时，生成高优先级“未回复会话”结论和补回复行动项。
  - 全局轮次均衡但单个会话用户消息比助手回复多 2 条及以上时，生成高优先级“会话追问压力”结论和阶段性总结行动项。
  - 同一会话 highlights 与 `latestUserHighlight` 出现相近追问时，生成高优先级“重复追问”结论，并把明确状态、阻塞点和下一步的行动项带入短期提示。
  - 最新用户问题命中任务语气且画像尚无任务时，生成高优先级“最新任务推进”结论，并把该任务带入短期提示；普通礼貌问题不会误触发最新任务。
  - 会话已有助手回复但最后一条消息仍来自用户时，生成高优先级“最后一问未答”结论和补最新追问行动项；若 Dreaming 提供最后用户问题安全片段，结论会直接包含该片段；敏感最后用户消息不会回退旧片段。
  - 来源 Dreaming 早于反思日期时，生成高优先级“来源新鲜度”结论和“先运行今日 Dreaming”行动项，并进入短期提示。
  - 设置页本地反思入口会直接展示旧来源日期和“先运行今日 Dreaming”提示。
  - JSON 往返和 Markdown 预览。
  - secret-like 画像信号不会进入报告或短期提示。
  - 反思短期提示有标题、限量输出，并跳过 secret-like 内容。
  - 长会话质量基线：长会话 + 用户追问 + 待确认画像 + 画像任务同时出现时，报告覆盖回应质量 / 上下文 / 任务推进 / 用户画像；短期提示保留长会话风险和任务推进，完整报告保留画像采纳动作。
- `test/settings_page_dreaming_test.dart`
  - 设置页反思弹窗展示下一轮短期提示预览。
  - Dreaming 弹窗关闭后 digest 才返回时仍能使用页面级 `WidgetRef` 保存报告，避免真机上使用已销毁弹窗 `WidgetRef`。
- `test/reflection_provider_test.dart`
  - 最近反思报告持久化 / 清空。
  - 短期提示注入开关持久化。
  - 反思历史持久化、同日同来源去重、精确删除同日不同来源中的单条报告和最多 20 次上限。
  - 从最近 Dreaming 与用户画像生成、保存反思并写入历史。
  - 反思失败保留 pending、重试成功清除 pending、非法 marker 自动清理、同一来源尝试次数持久化。
  - pending 指向旧 Dreaming 时从 SQLite 按 dayKey 恢复正确报告，不误用当前最新 Dreaming。
  - 模型增强开关默认关闭并持久化；模型增强成功写入 `generationMode=model`，失败自动回退本地报告并清除 pending。
- `test/model_reflection_service_test.dart`
  - 严格 JSON 解析、模型 / 本地结论合并、敏感输出过滤、无安全内容拒绝、提示 12000 字符上限和密钥脱敏。
- `test/model_reflection_protocol_integration_test.dart`
  - 使用本机 `HttpServer`、正式 `openai_chat` SSE 协议和内存 SQLite 渠道配置验证默认模型请求、流式 JSON 响应、模型报告持久化和 pending 清理；该测试不代表真实外部模型质量证明。
- `test/settings_page_dreaming_test.dart`
  - 手动 Dreaming 后同时落盘最近反思和反思历史。
  - 设置页展开审阅历史反思、删除当前最近反思后回退到下一条历史，同日不同来源报告不会被误删。
  - 设置页展示 pending 来源和尝试次数、允许清除；手动反思失败给出可重试反馈；删除来源 Dreaming 或清空报告同步清除 pending。
- `test/mobile_main_flow_smoke_test.dart`
  - 移动端启动时恢复已有 pending。
  - 自动 Dreaming 成功但 Reflection 首次失败后，恢复前台会重试并生成最近反思与历史。
- `test/dreaming_background_runner_test.dart`
  - Android / iOS 后台 runner 会持久化 Dreaming 与 Reflection。
  - Reflection 首次失败后只重试 Reflection，不重复生成同日 Dreaming。
  - 已有 pending 再次恢复失败且当天 Dreaming 已完成时仍返回 `reflectionPending`，确保 WorkManager / BGTaskScheduler 继续失败退避，而不是误报 `notDue`。
- `test/chat_provider_context_limit_test.dart`
  - Key Points 与本地反思短期提示合并。
  - 关闭短期提示时仍保留 Key Points，不注入反思内容。
- `test/structured_data_backup_test.dart`
  - `assistant_reflection_v1`、`assistant_reflection_history_v1`、`assistant_reflection_prompt_enabled_v1`、`assistant_reflection_model_enabled_v1` 和 pending 进入结构化备份白名单，模型密钥仍不进入备份。

2026-07-14 模型增强验证结果：

- 22:57 非流式远程 Reflection 正式路径完成 Pixel 8 后台复验。首次远程预检返回 401，wrapper 在 build 前安全退出；新增最多 3 次有界重试后，复跑 attempt 1 为 401、attempt 2 成功。隔离包 READY pid `8925` 被回收，JobScheduler 自然等待 elapsed `324` 秒后由 `SystemJobService` 冷启动 pid `10117`，生成 `generationMode=model` 的 2026-07-14 Reflection。Dreaming / Reflection 当前与历史均存在，无 pending / `model_fallback`，日志和 prefs 无配置地址 / key。cleanup 后正式包 pid `10528`、firstInstallTime / dataDir 不变，隔离包 / sqlite hook 无残留，跨日 job 仍 waiting；最终全量 557 项通过。详见 `docs/archive/mobile-remote-model-reflection-quality-2026-07-14.md`。
- 22:40 完成远程模型三个 dayKey 的 72 条长会话质量门禁。旧 live quality 工具的 loopback / 本地模型默认路径已删除，只允许从仓库外 600 / 400 `MODEL_CONFIG_FILE` 加载远程 `openai_chat`。真实 SSE 两组三轮分别出现 1 次和 2 次空 content/thinking，正式 OpenAI-compatible Reflection 改用非流式单次响应，普通聊天 SSE 与其他协议不变；真实非流式输出包含 `<think>`、首个 JSON 和重复 fenced JSON，解析器用字符串 / 转义感知的平衡对象扫描只取首个可解析对象，既有安全过滤不放宽。2026-07-14 / 15 / 16 三轮严格质量断言 3 / 3 通过，耗时 27.744 / 29.701 / 14.554 秒，attempts `[2,1,1]`，本地 5 / 4 全部保留并合并为 8 / 8，无合成密钥 / URL / 路径和虚假完成；第一轮一次临时 401 说明接口可用性仍有波动。聚焦 38 项、全量 557 项、analyze / diff / hook / 泄漏扫描通过，跨日 job 仍 waiting，正式包 pid `5438`。详见 `docs/archive/mobile-remote-model-reflection-quality-2026-07-14.md`。
- 22:06 完成 21:56 SQLite-only 新进程恢复补丁最终复核：恢复 / 跨日脚本语法通过，Dreaming / Reflection device manifest、provider、background runner 聚焦 32 项通过，全量稳定门禁 550 项通过；`flutter --no-version-check analyze --no-pub`、`git diff --check`、sqlite hook 和真实远程配置仓库泄漏扫描均通过。Pixel 8 正式包 pid `5438`、firstInstallTime / dataDir 不变，隔离包均不存在，跨日 job id `0` 保持 `waiting`。本轮未启动、调用或探测 Ollama / 本地模型；后续模型 Reflection 只允许从仓库外 600 / 400 配置文件读取远程接口。
- Pixel 8 已把 pending Reflection 的 SQLite 回灌从单元 / runner 测试推进到新进程真机闭环。独立 `dreamingsqlitesmoke` 第一次 pid `5157` 只保存 SQLite completed report 和 pending，不保存 Dreaming provider 状态；`am force-stop` 后第二次 pid `5263` 经正式移动端启动任务恢复 Dreaming 当前 / history，生成 Reflection 当前 / history 并清 pending，marker 为 `dreamingHistory=1 reflectionHistory=1`。设备 prefs 复查四项报告 key 存在且 pending 不存在；cleanup 后正式包 pid `5438`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook，Android 跨日任务仍 waiting。该证据直接覆盖“后台进程死亡、SharedPreferences Dreaming 丢失、仅 SQLite report 可用”的移动端恢复场景。
- pending Reflection 的 SQLite 来源恢复现在会同步修复 Dreaming provider/UI。旧路径从 `dreaming_reports.digest_json` 得到 digest 后只把它作为局部参数生成 Reflection，不写 `dreaming_digest_v1` 或 history；后台 runner 因此可能返回只有 Reflection、没有 digest 的 completed 结果，也不会发送完成通知。新增 history 断言先红灯为 `Actual: []`；修复后恢复项必进 history，当前 digest 为空或更旧时才更新，既保证来源可见，又不让旧 pending 覆盖较新的 Dreaming。新增无当前 digest 和全新后台 `ProviderContainer` 两条恢复回归，证明 SQLite report → digest/history → Reflection → 清 pending → 完成通知闭环；provider / runner 18 项、移动端聚焦 20 项和全量稳定门禁 550 项通过，analyze 无问题。
- Dreaming 的跨存储完成顺序已加固，避免 Reflection 被一个“SQLite job 已 completed、但 digest provider 未发布”的静默状态永久跳过。旧实现先 `markJobCompleted()` 再保存 digest / history；新增故障注入测试先红灯确认 provider 保存失败后 job 仍错误显示 completed，修复后把 completed 移到两项 provider 持久化之后。异常时 job 进入 failed，直接进程退出时 job 保持未完成并可被 stale claim 重试，因此后续画像提议和 Reflection 仍有恢复入口；`dreaming_provider_test.dart` 11 项、聚焦 22 项和全量稳定门禁 548 项通过，analyze 无问题。
- iPhone13 在 21:21 可用状态下重新执行隔离 release BGTask smoke，解锁预检、签名构建、安装和 READY 均成功，但原生 `backgroundRefreshStatus` 仍为 `denied`，系统没有保留 pending task，因此没有产生 iOS 系统后台 Reflection 结果，不能标记为完成。本轮把 smoke cleanup 从“只确认正式 App 仍存在”加固为“必须与运行前的名称、bundle、版本和 build 身份完全一致”，manifest 测试先红后绿，真机失败路径复跑后隔离 bundle、临时工程替换和 sqlite hook 均已清理，正式 App 身份守卫未触发。iOS 前台到期 / 手动 Reflection 仍可用；系统后台闭环继续等待用户开启“后台 App 刷新”后复跑。
- 远程模型真机 smoke 已改为配置文件加载接口，不在代码、脚本、测试或编译参数中固定真实地址、模型和密钥。运行时配置示例结构为 `{"protocol":"openai_chat","baseUrl":"https://example.test","apiKey":"replace-me","model":"remote-model"}`，文件必须位于仓库外并设置为 600 / 400；执行方式为 `MODEL_CONFIG_FILE=/绝对路径/config.json ./scripts/smoke_device_android_background_dreaming_real_model.sh <device-id>`。wrapper 先远程预检，成功后才把同一配置一次性写入独立 APK 私有目录；App 读取后立即删除明文文件并加密保存 key。Pixel 8 READY 后回收旧 pid `30567`，系统未使用 shell force，在 elapsed `112` 秒时由 JobScheduler 冷启动新 pid `30907`，完成远程模型增强 Reflection；持久化报告为 `generationMode=model`，无 pending / `model_fallback`，日志和 prefs 无配置密钥或地址。cleanup 后正式包 identity 不变、pid `31292`，远程模型隔离包和临时配置均消失，跨日 job 仍 waiting，本机未运行任何本地模型服务。配置解析 / 删除与 smoke manifest 聚焦 11 项、全量稳定门禁 547 项通过，analyze 无问题。该证据证明 Android 系统后台可调用配置中的真实远程模型，但不替代更多模型族、长会话质量和长期 OEM 后台可靠性门禁。
- 模型回退可见性补强：自动 / 后台模型失败旧实现只保存 `local`，无法在下一次打开设置页时区分“未尝试模型”和“失败回退”。新增 `model_fallback` 序列化兼容，provider 在可选模型异常后保存带回退模式的本地报告和历史，Markdown / tile / 弹窗明确显示回退，且不保存异常详情。聚焦 47 项、全量稳定门禁 536 项通过，analyze 无问题。
- 历史上的真实本地模型兼容性与质量门禁曾完成一条基线。Qwen3 0.6B 批量采样暴露尾逗号、错位 / 缺失闭合、全角右括号、`nextStep` / `nextAction` action object 和 schema 占位内容；解析器只对这些已证实模式做保守修复并继续执行密钥、URL、本机路径、长度和本地安全基线过滤。旧 live gate 的本地报告已经占满 8 条结论 + 8 个行动项，模型按“不覆盖本地基线”规则永远没有补充空间，已修正为仍有 72 条消息但本地基线为 5 / 4 的长会话。协议层新增默认关闭的 `jsonResponse` 提示，Reflection 正式路径对 Ollama 使用 `format=json`、`think=false`、`temperature=0`，普通聊天不变。本机真实 `qwen3:4b` 当时连续 5 / 5 通过，单次约 14.7–14.9 秒，最终 8 / 8，保留本地结论且没有敏感信息或虚假完成结论。该结果只作为历史证据保留；按当前用户约束禁止再次启动、探测或重跑本地模型，后续只使用仓库外配置驱动的远程接口。最终全量稳定门禁 544 项通过，analyze 无问题。
- 模型总超时补强：旧 `Stream.timeout(60s)` 是相邻事件超时，慢模型持续发送碎片时可无限延长。新增每 10ms 出块、80ms 总时限回归，修复后使用单个 Future 总墙钟超时，并将 `CancelToken` 从 Reflection provider 传播到 Relay bridge 和正式模型协议；超时 / 响应过长 / 异常主动取消上游后安全回退本地。相关聚焦 23 项、全量稳定门禁 534 项通过，analyze 无问题。
- 模型合并安全基线补强：新增红灯用例证明旧逻辑会让模型返回的 8 条内容挤掉本地结论，并把重复本地内容误标为模型增强；修复后本地结论优先、模型最多补充 4 条、无新增内容时进入既有本地回退。目标 6 项、模型 / provider / 正式协议 / 设置页聚焦 40 项、最终全量稳定门禁 533 项通过，`flutter --no-version-check analyze --no-pub` 无问题。
- 模型增强默认关闭，设置页隐私边界、默认聊天模型选择、严格 JSON、60 秒超时、提示 / 响应长度上限、敏感内容过滤、模型失败回退本地报告、pending 清理和结构化备份已落地。
- 模型 Reflection 聚焦组合 60 项通过；补齐模型输出 URL / 本机路径过滤，并修复端到端协议测试未清理 Dio / `HttpServer` 资源导致测试进程不退出的问题后，全量稳定门禁 517 项通过，日志无 `WARNING (drift)`、`multiple databases` 或失败标记。
- `flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出；正式 `pubspec.yaml` / `pubspec.lock` 无临时 sqlite hook。
- Android debug APK 构建通过，产物 `build/app/outputs/flutter-apk/app-debug.apk` 为 166MB；iOS release `--no-codesign` 构建通过，`build/ios/iphoneos/Runner.app` 为 33.3MB、arm64，正式 Bundle ID 和 BGTask identifier 保持不变。
- 当前已同时具备本机 mock SSE 多协议闭环和真实本地 Ollama `qwen3:4b` 72 条长会话 5 / 5 质量证明；该证据仍不替代云端外部模型和更多模型族的 JSON 合规、时延、事实准确性、行动项可执行性与敏感信息边界验证。

2026-07-13 验证结果：

- 移动端首次启动到期、恢复前台到期、持续前台定时三条 Dreaming 路径已补 Reflection 直接断言：从 SharedPreferences 解码最近 Dreaming、最近反思和反思历史，要求反思有内容、历史非空，并验证 `sourceDigestDayKey` 与触发它的 Dreaming `dayKey` 一致。
- `flutter --no-version-check test --no-pub --no-test-assets test/mobile_main_flow_smoke_test.dart --name dreaming -r expanded`：9 项通过。
- `scripts/smoke_full_stability_gate.sh -r expanded test/mobile_main_flow_smoke_test.dart test/notification_service_test.dart test/reflection_service_test.dart test/dreaming_service_test.dart test/reflection_provider_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/chat_provider_context_limit_test.dart test/dreaming_dao_test.dart test/structured_data_backup_test.dart`：93 项通过。
- Reflection 独立失败恢复落地后，加入数据导出 / 导入回归的稳定门禁通过 120 项；`flutter --no-version-check analyze --no-pub` 无问题。

2026-07-14 真机验证结果：

- 模型驱动画像增量分析 v1 已接入同一 Dreaming 后台编排，但使用独立默认关闭开关。开启后模型只补充有逐字证据的待确认候选，不能写正式画像；失败回退本地候选，不影响后续 Reflection。远程配置质量门禁 3 / 3 通过，Pixel 8 独立包在 UI 进程被回收后由 JobScheduler 自然冷启动，127 秒完成 Dreaming、模型画像候选和模型 Reflection；Reflection 报告能读取待确认画像数量，画像提议为 `generationMode=model`，正式画像未写入。详见 `mobile-model-user-profile-quality-2026-07-14.md`。

- Dreaming / Reflection 系统后台附加条件代码闭环已落地：`dreaming_schedule_v1` 新增默认关闭的 `requiresCharging` / `requiresUnmeteredNetwork`，设置变化会重排完整 Dreaming → Reflection 后台任务。Android 可要求充电和 `NetworkType.unmetered`；iOS 可要求充电，但 Apple 侧插件只能把网络条件表达为“要求联网”，设置页明确提示无法保证 Wi-Fi。配置兼容旧 JSON、随结构化备份恢复，移动端 390x844 设置路径和平台约束聚焦门禁通过；新增真机约束门禁后全量稳定门禁 530 项和 analyze 通过。
- Pixel 8 已补非计费网络和充电条件完整闭环。关闭 Wi-Fi 后，网络约束 job 的 CONNECTIVITY 不满足，严格 `jobscheduler run -s` 被拒绝；恢复 `WIFI + NOT_METERED + VALIDATED` 后严格放行，后台 Dreaming 完成后 Reflection 同步持久化，输出 `digest=2026-07-14 reflection=2026-07-14` 且无 pending。充电诊断 job 的系统 `JobInfo` 明确要求 `charging=true`，未充电时 `CHARGING` 未满足且严格运行被拒绝；切换为系统 charging 后约束转为满足，未使用 `-f`，initialDelay 到期后自然完成 Dreaming / Reflection。跨日隔离 job 保持 waiting，正式包和设备网络 / battery mock 已恢复。
- Android 跨日 Reflection 验证已进入真实等待阶段，但尚未标记完成。旧 harness 的 seed 消息属于启动日，次日执行可能得到 `notDue`；本轮改为按 initialDelay 写入预定执行日时间，并新增可分离 schedule / status / verify / cleanup。30 秒两阶段自测证明调度命令退出、正式包与仓库恢复后，系统仍能自然执行，独立 verify 读取 Reflection 最近报告 / 历史、确认无 pending 并清理；提前 verify 返回 3，600 秒未到期任务主动 cleanup 通过。全量稳定门禁 524 项和 analyze 通过。Pixel 8 当前真实跨日任务 expectedDayKey `2026-07-15`、旧 pid `28141`、job id `0` waiting；因 `/tmp` 状态提前消失，脚本默认状态已迁移并恢复到 `.omx/state/android-background-dreaming-cross-day.state`，待次日 verify 后才能形成跨日 Reflection 完成证据。
- Pixel 8 已补 UI 进程死亡后的跨小时自然 Reflection：隔离任务设置 3600 秒 initialDelay，旧 pid `6444` 消失后 JobScheduler job 跨越一小时持久存在，standby bucket 从 `ACTIVE` 降到 `RARE`，其余约束持续满足；到期后系统继续批处理，elapsed `4360` 秒时通过 `SystemJobService` 冷启动新 pid `24325`，完成 `digest=2026-07-14 reflection=2026-07-14`。最近反思 / 历史已持久化且无 pending；cleanup 后 deep state `ACTIVE`、正式包 pid `24737`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook；最终全量稳定门禁 523 项和 analyze 通过。该结果证明 Reflection 可跨小时等待并在 UI 进程消失后自然恢复，但仍不替代跨日、长时间 Doze 或 OEM 后台限制。
- Pixel 8 已补 UI 进程被回收后的无 shell force 自然调度：新增 natural process-death wrapper，旧 pid `2639` 被回收后 JobScheduler job 保持 `ACTIVE` bucket、约束满足并进入 ready；系统按自身批处理节奏在 249 秒后为 `SystemJobService` 冷启动新 pid `4668`，后台 Flutter isolate 完成 `digest=2026-07-14 reflection=2026-07-14`，最近反思 / 历史持久化且无 pending。180 / 240 秒窗口会误判该轮失败，专用 wrapper 因此默认观察 900 秒；cleanup 后 deep state `ACTIVE`、正式包 pid `4980`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook；最终全量稳定门禁 523 项和 analyze 通过。该结果证明 Reflection 能在 UI 进程消失后由自然系统调度恢复，但不提供精确时延保证，也不替代跨小时 / 跨日 Doze 或 OEM 长期可靠性。
- iPhone13 同日重新执行隔离 release BGTask smoke：设备 launch preflight、27.5MB release 构建、安装和 READY 文件均通过；增强后的 READY JSON 由原生通道直接记录 `backgroundRefreshStatus=denied`，同时 `scheduledTasks` 为 `[BGTaskScheduler] There are no scheduled tasks`。这把 blocker 从推断升级为设备直接证据。设置页在 denied / restricted 时新增“打开系统设置”和“重新检查”；cleanup 已卸载隔离 bundle、恢复工程 / sqlite 配置并重新启动正式 `top.simitalk.aichat` pid `86792`。因此 iOS 系统后台 Reflection 仍未获得完成证据，待开启系统开关后复跑。
- Pixel 8 已补 UI 进程被回收后的 WorkManager headless 冷启动：隔离 App 调度后回到 Home，旧 pid `30424` 被 `am kill` 回收且 package 未进入 stopped；等待 30 秒 WorkSpec initialDelay 到期后，JobScheduler 为 `SystemJobService` 冷启动不同的新 pid `30629`，后台 Flutter isolate 完成 `digest=2026-07-14 reflection=2026-07-14`，Reflection 最近报告 / 历史持久化且无 pending。cleanup 后 deep state `ACTIVE`、正式包 pid `30813`、firstInstallTime / dataDir 不变，无隔离包 / sqlite hook；目标门禁 5 项、全量稳定门禁 522 项和 analyze 通过。该结果证明到期后的 forced callback 可从无 UI 进程状态恢复反思，不等同于自然调度时延、数小时 / 跨日 Doze 或 OEM 杀后台可靠性。
- iOS 已完成 `BGProcessingTask` 原生注册、Dart 一次性调度、15 分钟失败重试、`ios_background` trigger 和隔离 release smoke；后台 runner 回归证明 iOS trigger 会写入正式 Dreaming / Reflection 编排。隔离 READY JSON 进一步读取系统 pending requests，避免 `workmanager 0.8.0` 吞掉 submit 错误后误报成功。当前 iPhone13 `UIApplication.backgroundRefreshStatus=1`（denied），因此系统没有保留 pending task；设置页已新增“iOS 后台 App 刷新已关闭 / 受限 / 可用”状态及前台兜底反馈，真机后台 Reflection 执行待系统开关开启后补证。
- Pixel 8 独立包 `top.simitalk.aichat.backgroundsmoke` 在 Home 后先尝试 Android 16 namespaced `JobScheduler` 命令，最终 `workmanager 0.8.0` 使用 legacy job，脚本自动回退到无 namespace 命令并强制运行真实 WorkManager job；后台 Flutter isolate 输出 `SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed digest=2026-07-14 reflection=2026-07-14`，隔离 prefs 同时存在 `assistant_reflection_v1` 和 `assistant_reflection_history_v1`。正式包 firstInstallTime / dataDir 不变、最终 pid `12024`，隔离包和临时 sqlite hook 均已清理；最终全量稳定门禁 499 项通过，analyze 无问题，详见 `docs/archive/mobile-android-background-dreaming-smoke-2026-07-14.md`。
- 同一 Pixel 8 已补不调用 `cmd jobscheduler run` 的自然调度：隔离 App 回到 Home 后，30 秒 initialDelay、36 秒由 SystemJobScheduler 自行完成 Dreaming / Reflection；prefs 同时存在最近反思与历史且没有 `assistant_reflection_pending_v1`。随后默认 force 分支继续复跑通过；两次 cleanup 后正式包 identity 不变、最终 pid `24389`，无隔离包 / sqlite hook 残留；最终全量稳定门禁 518 项通过。
- 后台 runner 自动化覆盖 Reflection 首次失败、pending 保留、WorkManager retry 第二次恢复、只保留一个 `dreaming-auto-2026-07-14` job 和只发送一次完成通知。
- Pixel 8 独立包 `top.simitalk.aichat.dreamingsmoke` 使用正式 `AiChatApp` 生命周期、内存 SQLite 和隔离 SharedPreferences，验证第一次 Reflection 失败写 pending，Home 后恢复前台自动重试并生成 1 条历史，最终清除 pending。
- 真机 marker：`SIMICHAT_DREAMING_REFLECTION_PENDING dayKey=2026-07-14 attempts=1`、`SIMICHAT_DREAMING_REFLECTION_RECOVERED dayKey=2026-07-14 attempts=2 history=1`。
- 修正后的 smoke 不执行 `flutter test -d`，只 build / adb 安装独立 APK；cleanup 后无 smoke 包和 sqlite hook 残留，普通 release 进程可见，正式包 firstInstallTime / dataDir 不变。
- 加入 smoke manifest / app identity 的稳定门禁 124 项通过，analyze 无问题。
- 首次动态 applicationId + `flutter test -d` 方案错误卸载正式包并导致 Pixel 8 应用私有数据丢失；LocalTransport / D2D 恢复均失败，已记录事故并禁止复用，详见 `docs/archive/mobile-dreaming-reflection-recovery-smoke-2026-07-14.md`。
- 本轮继续审计后台 pending 失败恢复：新增回归先稳定复现“第二次 Reflection 仍失败却返回 `notDue`”，修复后返回 `reflectionPending`，目标文件 4 项通过；`scripts/smoke_full_stability_gate.sh` 全量 519 项通过。
- Pixel 8 当前默认 force shell 触发分支未收到完成 marker，但自然调度分支在 Home 后 36 秒由 SystemJobScheduler 自行完成 Dreaming / Reflection，输出 `status=completed digest=2026-07-14 reflection=2026-07-14`；正式包 identity / dataDir 不变，隔离包和 sqlite hook 无残留。该结果证明生产依赖的自然系统调度仍可用，同时保留 force 工具链本次波动为诊断事实。
- iPhone13 当前解锁预检、隔离 release 构建 / 安装 / 启动均通过，但 READY JSON 仍为 `There are no scheduled tasks`；正式包已恢复并运行。系统后台执行仍受“后台 App 刷新”未开启阻塞，前台启动 / 恢复 / 定时兜底不受影响。
- Pixel 8 新增强制 deep idle 短时验证：隔离包在 `idleStateAtSchedule=IDLE` 和 `idleStateAtResult=IDLE` 两个时点均处于深度 idle，37 秒后仍生成 Dreaming 与 Reflection 并清除 pending；脚本拒绝永久 idle whitelist，并在 cleanup 中恢复 `ACTIVE`、正式包和 sqlite 配置。该结果证明当前 WorkManager 编排在短时强制 deep idle 下可完成反思，不等同于数小时 / 跨日 / OEM 长期可靠性。
- Android force smoke 上一轮波动根因已定位为脚本从全局 logcat 误收其他 App 的 WorkManager Job ID；修复后只从 `dumpsys jobscheduler` 精确匹配隔离包，force 分支 job id `0`、10 秒完成。最终全量稳定门禁 521 项通过，`flutter analyze --no-pub` 无问题。

2026-07-07 验证结果：

- `scripts/smoke_full_stability_gate.sh -r expanded test/reflection_service_test.dart test/dreaming_service_test.dart test/reflection_provider_test.dart test/settings_page_dreaming_test.dart test/dreaming_provider_test.dart test/structured_data_backup_test.dart`：44 项通过，覆盖反思来源新鲜度、旧 Dreaming 短期提示、设置页入口旧来源可见性、单会话未回复识别、会话追问压力识别、重复追问识别、最新任务推进识别、普通礼貌问题不误触发最新任务、最后一问未答识别、明确任务语气进入 Dreaming `task` 记忆候选、Dreaming 会话最后消息角色与最新用户问题 JSON 往返、敏感标题降级、敏感最后用户消息不回退、Dreaming / Reflection 联动和设置页反思弹窗。

2026-07-06 验证结果：

- `flutter --no-version-check analyze`：通过。
- 局部 Dreaming 设置页测试：`flutter --no-version-check test --no-pub --no-test-assets test/settings_page_dreaming_test.dart -r expanded`，3 个通过。
- 全量 `flutter --no-version-check test --no-pub --no-test-assets`：330 个测试通过。
- Pixel 8 真机验证：修复后 debug 包 `adb install -r` 覆盖安装且不清数据；72 条 seed 长会话可见；手动 Dreaming 生成 2026-07-06 日报（72 条消息）；Reflection 生成 5 条结论、4 个行动项、1 次历史；设置页短期提示预览可展开查看。详见 `docs/archive/mobile-long-conversation-reflection-smoke-2026-07-06.md`。

说明：当前本机无法解析 / 连接 GitHub 下载 `sqlite3` native asset，直接运行 `flutter test` 会被 sqlite3 hook 下载阻塞；上述测试用命令内临时 `sqlite3.source=system` 使用 macOS 系统 SQLite 完成，命令结束后已还原正式 `pubspec.yaml`。

## 7. 后续 TODO

- [x] 反思独立失败恢复 v1：Dreaming 已成功但 `runAssistantReflection()` 失败时持久化不含敏感信息的 pending 标记；应用启动 / 恢复前台 / 前台定时检查会重试，设置页显示来源与尝试次数并允许清除；来源不是当前最新 Dreaming 时先从 Dreaming 历史、再从 SQLite 按 dayKey 恢复对应报告。
- [x] 可选模型增强反思 v1：默认关闭，用户显式开启后使用默认已启用聊天模型；只发送长度受限、经过敏感信息处理的 Dreaming / 本地反思摘要，严格解析 JSON，与本地安全结论合并，失败自动回退本地报告并清除 pending。
- [x] 反思结果参与系统提示词 v1：把少量高优先级结论和行动项转为下一轮对话的短期提示，默认开启，可在设置页关闭，可解释且可被预算裁剪。
- [x] 反思历史 v1：保留最近 20 次反思版本，同一 Dreaming 日期重复运行会替换旧报告，设置页展示历史保留次数，可展开审阅历史反思，可按 `dayKey + sourceDigestDayKey` 精确删除单条反思，删除反馈显示来源，删除当前最近反思后自动回退，并可清空最近反思报告与历史。
- [x] 来源新鲜度提醒 v1：反思日期与来源 Dreaming 日期不一致时，设置页入口、报告和短期提示会提醒先运行今日 Dreaming。
- [x] 未回复会话提醒 v1：即使当天总用户 / 助手轮次均衡，只要某个会话有用户消息且助手 0 回复，也会生成高优先级补回复提醒。
- [x] 会话追问压力提醒 v1：即使全局用户 / 助手轮次均衡，只要单个会话用户消息比助手回复多 2 条及以上，也会生成阶段性总结和逐项回应提醒。
- [x] 重复追问提醒 v1：同一会话 Dreaming highlights 与最新用户问题出现相近追问时，会生成高优先级“重复追问”提醒，并提示先明确状态、阻塞点和下一步。
- [x] 最新任务推进提醒 v1：最新用户问题命中明确任务语气时，会生成高优先级“最新任务推进”提醒，并把该任务放入下一轮短期提示；普通礼貌问题不会误触发。
- [x] 最后一问未答提醒 v1：Dreaming 会话摘要记录最后一条消息角色和最后用户问题安全片段；当会话已有助手回复但最后一条仍是用户消息时，报告和短期提示会提醒先回应最新追问，并在安全时展示最新追问片段；若最后用户消息敏感则不回退旧内容。
- [x] 长会话启发式质量基线：单元测试覆盖长会话、用户追问、待确认画像和画像任务同时出现时的报告与短期提示优先级。
- [x] Pixel 8 seed 长会话 Dreaming / Reflection 基线：72 条消息、5 条结论、4 个行动项和短期提示预览已真机验证。
- [x] 真实本地模型长会话质量历史基线：Ollama `qwen3:4b` 72 条长会话结构化 Reflection 曾连续 5 / 5 通过，本地安全基线、敏感信息过滤和虚假完成边界均通过；该结果只保留为历史证据，按当前用户约束禁止再次启动、探测或重跑本地模型，后续只使用仓库外配置驱动的远程接口。
- [ ] 云端外部模型和更多模型族长会话质量评估：一个仓库外配置驱动的 OpenAI-compatible 远程模型已在三个 dayKey 的 72 条长会话上 3 / 3 通过；仍需更多远程模型族、多日真实用户会话、上下文压缩质量、用户追问率、时延和停止 / 重试行为评估。
