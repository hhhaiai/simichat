# 本地反思机制 v1

> 对应模块：M2 记忆与上下文系统 / M3 Dreaming / M10 数字孪生。状态：本地启发式反思 v1、会话追问压力提醒 v1、重复追问提醒 v1、最新任务推进提醒 v1、最后一问未答提醒 v1、短期提示注入 v1、反思历史可控管理 v1 已落地。最后更新：2026-07-07。

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

v1 是本地启发式反思，不调用远端模型，不上传云端，不读取原始密钥或文件路径。短期提示注入默认开启，用户可在设置页“本地反思 / 自我优化”关闭；最近反思报告与历史可在同一弹窗中展开审阅、按 `dayKey + sourceDigestDayKey` 精确删除单条，删除反馈会显示来源，支持删除当前报告后回退或整体清空。

输入仅来自：

- 最近 `DreamingDigest`。
- 当前 `UserProfile`。
- 待确认画像变更数量。

输出只写入 SharedPreferences：

- `assistant_reflection_v1`：最近一次 `ReflectionReport`。
- `assistant_reflection_history_v1`：最近反思历史，当前最多保留 20 次，同一 Dreaming 日期重复运行会用最新报告替换旧报告；用户可在设置页展开审阅、按 `dayKey + sourceDigestDayKey` 精确删除单条或整体清空。
- `assistant_reflection_prompt_enabled_v1`：是否允许把本地反思行动项作为下一轮短期提示，默认开启。

结构化备份白名单已包含 `assistant_reflection_v1`、`assistant_reflection_history_v1` 和 `assistant_reflection_prompt_enabled_v1`；它们和 Key Points / Dreaming / 用户画像一样属于本地智能状态，不包含模型 API Key、Bearer token、上游 Base URL、本机绝对路径或聊天原文密钥。

## 3. 数据结构

核心文件：

- `lib/core/memory/reflection_service.dart`
  - `ReflectionInsight`：单条反思结论，包含分类、文本和优先级。
  - `ReflectionReport`：日级反思报告，包含来源 Dreaming 日期、消息统计、待确认画像变更数、反思结论和行动项；当来源 Dreaming 不是反思当天时，会保留“来源新鲜度”提醒；当 Dreaming 会话摘要显示单个会话用户消息比助手回复多 2 条及以上时，会生成“会话追问压力”提醒；当 highlights 与最新用户问题中出现相近追问时，会生成“重复追问”提醒并提示先明确状态 / 阻塞点 / 下一步；当最新用户问题命中“继续推进 / 请继续 / 请帮 / 帮我 / 修复 / 验证 / 复跑 / 补 / 实现 / 看下 / 检查”等明确任务语气时，会生成“最新任务推进”提醒；普通礼貌问题如“请问这个设置是什么意思”不会触发最新任务；最后一条消息来自用户时，会生成“最后一问未答”提醒，并优先带入 Dreaming 保存的最后用户问题安全片段；若最后用户消息敏感则只保留通用提醒。
  - `ReflectionService.buildDailyReflection()`：根据 Dreaming / 画像生成反思报告。
  - `buildAssistantReflectionSystemPrompt()`：把少量高优先级结论和行动项转为短期 system prompt 片段。
  - `encodeReflectionReport()` / `decodeReflectionReport()`：最近反思本地持久化序列化。
  - `encodeReflectionReportHistory()` / `decodeReflectionReportHistory()`：反思历史本地持久化序列化。
- `lib/shared/providers/reflection_provider.dart`
  - `AssistantReflectionNotifier`：加载 / 保存 / 清空最近反思报告。
  - `AssistantReflectionPromptEnabledNotifier`：加载 / 保存短期提示注入开关，默认开启。
  - `AssistantReflectionHistoryNotifier`：加载 / 记录 / 按 `dayKey + sourceDigestDayKey` 删除单条 / 清空最近反思历史，最多保留 20 次。
  - `runAssistantReflection()`：读取最近 Dreaming 与画像，生成并保存反思。

## 4. 触发流程

```text
手动 Dreaming / 前台到期 Dreaming
  -> 生成 DreamingDigest
  -> 写入 Key Points
  -> 生成待确认 UserProfileChangeProposal
  -> runAssistantReflection()
  -> 保存 assistant_reflection_v1
  -> 记录 assistant_reflection_history_v1
  -> 设置页展示最近反思、历史次数与行动项
  -> 若短期提示开关开启，下一轮聊天把少量高优先级结论 / 行动项并入本机 system prompt
```

设置页“记忆与画像 / 本地反思 / 自我优化”支持：

- 查看最近反思来源日期、来源是否过期、结论数量、行动项数量、历史保留次数、Markdown 预览，以及下一轮短期 system prompt 预览。
- 在已有 Dreaming 报告后手动运行反思。
- 当尚无 Dreaming 或无可整理对话时安全提示，不生成空误导报告。
- 开启 / 关闭“用于下一轮短期提示”，控制反思行动项是否影响后续回复；开启且有可注入内容时，可直接预览将并入下一轮本机 system prompt 的片段。

## 5. 安全与隐私

- 反思内容复用用户画像和 Dreaming 安全过滤逻辑，命中 API Key、Authorization、Bearer、password、secret、token、密钥、密码、常见密钥字面量时不写入报告；来源 Dreaming 会话标题命中敏感内容时只显示“敏感会话”。
- 报告不会保存原始对话全文，只保存统计、类别化结论和经过过滤的画像信号。
- 反思失败不会影响 Dreaming、画像候选、通知或聊天主链路。
- 短期提示只包含少量过滤后的高优先级结论和行动项，不包含反思全文；发送前会和 Key Points 一起被上下文预算裁剪。
- 临时测试中为绕过本机 GitHub 下载限制使用过 `sqlite3.source=system`，该配置未写入正式 `pubspec.yaml`。

## 6. 验证

已补测试：

- `test/core/reflection_service_test.dart`
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
- `test/shared/settings_page_dreaming_test.dart`
  - 设置页反思弹窗展示下一轮短期提示预览。
  - Dreaming 弹窗关闭后 digest 才返回时仍能使用页面级 `WidgetRef` 保存报告，避免真机上使用已销毁弹窗 `WidgetRef`。
- `test/shared/reflection_provider_test.dart`
  - 最近反思报告持久化 / 清空。
  - 短期提示注入开关持久化。
  - 反思历史持久化、同日同来源去重、精确删除同日不同来源中的单条报告和最多 20 次上限。
  - 从最近 Dreaming 与用户画像生成、保存反思并写入历史。
- `test/shared/settings_page_dreaming_test.dart`
  - 手动 Dreaming 后同时落盘最近反思和反思历史。
  - 设置页展开审阅历史反思、删除当前最近反思后回退到下一条历史，同日不同来源报告不会被误删。
- `test/shared/chat_provider_context_limit_test.dart`
  - Key Points 与本地反思短期提示合并。
  - 关闭短期提示时仍保留 Key Points，不注入反思内容。
- `test/core/structured_data_backup_test.dart`
  - `assistant_reflection_v1`、`assistant_reflection_history_v1` 和 `assistant_reflection_prompt_enabled_v1` 进入结构化备份白名单。

2026-07-07 验证结果：

- `scripts/smoke_full_stability_gate.sh -r expanded test/core/reflection_service_test.dart test/core/dreaming_service_test.dart test/shared/reflection_provider_test.dart test/shared/settings_page_dreaming_test.dart test/shared/dreaming_provider_test.dart test/core/structured_data_backup_test.dart`：44 项通过，覆盖反思来源新鲜度、旧 Dreaming 短期提示、设置页入口旧来源可见性、单会话未回复识别、会话追问压力识别、重复追问识别、最新任务推进识别、普通礼貌问题不误触发最新任务、最后一问未答识别、明确任务语气进入 Dreaming `task` 记忆候选、Dreaming 会话最后消息角色与最新用户问题 JSON 往返、敏感标题降级、敏感最后用户消息不回退、Dreaming / Reflection 联动和设置页反思弹窗。

2026-07-06 验证结果：

- `flutter --no-version-check analyze`：通过。
- 局部 Dreaming 设置页测试：`flutter --no-version-check test --no-pub --no-test-assets test/shared/settings_page_dreaming_test.dart -r expanded`，3 个通过。
- 全量 `flutter --no-version-check test --no-pub --no-test-assets`：330 个测试通过。
- Pixel 8 真机验证：修复后 debug 包 `adb install -r` 覆盖安装且不清数据；72 条 seed 长会话可见；手动 Dreaming 生成 2026-07-06 日报（72 条消息）；Reflection 生成 5 条结论、4 个行动项、1 次历史；设置页短期提示预览可展开查看。详见 `docs/mobile-long-conversation-reflection-smoke-2026-07-06.md`。

说明：当前本机无法解析 / 连接 GitHub 下载 `sqlite3` native asset，直接运行 `flutter test` 会被 sqlite3 hook 下载阻塞；上述测试用命令内临时 `sqlite3.source=system` 使用 macOS 系统 SQLite 完成，命令结束后已还原正式 `pubspec.yaml`。

## 7. 后续 TODO

- [ ] 模型驱动反思：在用户授权和密钥配置明确时，引入可选模型总结，继续保留本地启发式兜底。
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
- [ ] 真实模型长会话质量评估：结合上下文压缩质量、用户追问率和停止 / 重试行为继续优化反思规则。
