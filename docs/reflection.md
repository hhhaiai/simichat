# 本地反思机制 v1

> 对应模块：M2 记忆与上下文系统 / M3 Dreaming / M10 数字孪生。状态：本地启发式反思 v1、短期提示注入 v1、反思历史 v1 已落地。最后更新：2026-07-06。

## 1. 目标

本地反思机制用于在 Dreaming 之后，对当天对话质量和长期智能助理状态做一次可解释复盘，帮助应用逐步优化：

- 回应质量：发现用户消息明显多于助手回复、无助手回复等异常节奏。
- 上下文质量：发现长会话，提示后续复查摘要、最新问题保留和上下文预算裁剪。
- 长期记忆：统计新增记忆候选，提示缺失稳定偏好 / 目标 / 任务沉淀的情况。
- 用户画像：提示待确认画像变更，避免画像候选长期不被采纳。
- 任务推进：从画像中的任务、目标、偏好或 Dreaming 关键词给出下一步行动项。
- 短期自我优化：把少量高优先级结论和行动项注入下一轮本机 system prompt，帮助回复优先收口问题、关注长会话上下文风险并推进任务；当行动项较多时，优先保留能直接改善下一轮回复的任务推进项，画像采纳等维护动作仍保留在完整报告中。
- 持续优化轨迹：保留最近反思历史，为后续趋势评估、质量基线和模型驱动反思提供本地依据。

## 2. 当前边界

v1 是本地启发式反思，不调用远端模型，不上传云端，不读取原始密钥或文件路径。短期提示注入默认开启，用户可在设置页“本地反思 / 自我优化”关闭。

输入仅来自：

- 最近 `DreamingDigest`。
- 当前 `UserProfile`。
- 待确认画像变更数量。

输出只写入 SharedPreferences：

- `assistant_reflection_v1`：最近一次 `ReflectionReport`。
- `assistant_reflection_history_v1`：最近反思历史，当前最多保留 20 次，同一 Dreaming 日期重复运行会用最新报告替换旧报告。
- `assistant_reflection_prompt_enabled_v1`：是否允许把本地反思行动项作为下一轮短期提示，默认开启。

结构化备份白名单已包含 `assistant_reflection_v1`、`assistant_reflection_history_v1` 和 `assistant_reflection_prompt_enabled_v1`；它们和 Key Points / Dreaming / 用户画像一样属于本地智能状态，不包含模型 API Key、Bearer token、上游 Base URL、本机绝对路径或聊天原文密钥。

## 3. 数据结构

核心文件：

- `lib/core/memory/reflection_service.dart`
  - `ReflectionInsight`：单条反思结论，包含分类、文本和优先级。
  - `ReflectionReport`：日级反思报告，包含来源 Dreaming 日期、消息统计、待确认画像变更数、反思结论和行动项。
  - `ReflectionService.buildDailyReflection()`：根据 Dreaming / 画像生成反思报告。
  - `buildAssistantReflectionSystemPrompt()`：把少量高优先级结论和行动项转为短期 system prompt 片段。
  - `encodeReflectionReport()` / `decodeReflectionReport()`：最近反思本地持久化序列化。
  - `encodeReflectionReportHistory()` / `decodeReflectionReportHistory()`：反思历史本地持久化序列化。
- `lib/shared/providers/reflection_provider.dart`
  - `AssistantReflectionNotifier`：加载 / 保存 / 清空最近反思报告。
  - `AssistantReflectionPromptEnabledNotifier`：加载 / 保存短期提示注入开关，默认开启。
  - `AssistantReflectionHistoryNotifier`：加载 / 记录 / 清空最近反思历史，最多保留 20 次。
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

- 查看最近反思来源日期、结论数量、行动项数量、历史保留次数、Markdown 预览，以及下一轮短期 system prompt 预览。
- 在已有 Dreaming 报告后手动运行反思。
- 当尚无 Dreaming 或无可整理对话时安全提示，不生成空误导报告。
- 开启 / 关闭“用于下一轮短期提示”，控制反思行动项是否影响后续回复；开启且有可注入内容时，可直接预览将并入下一轮本机 system prompt 的片段。

## 5. 安全与隐私

- 反思内容复用用户画像安全过滤逻辑，命中 API Key、Authorization、Bearer、password、secret、token、密钥、密码、常见密钥字面量时不写入报告。
- 报告不会保存原始对话全文，只保存统计、类别化结论和经过过滤的画像信号。
- 反思失败不会影响 Dreaming、画像候选、通知或聊天主链路。
- 短期提示只包含少量过滤后的高优先级结论和行动项，不包含反思全文；发送前会和 Key Points 一起被上下文预算裁剪。
- 临时测试中为绕过本机 GitHub 下载限制使用过 `sqlite3.source=system`，该配置未写入正式 `pubspec.yaml`。

## 6. 验证

已补测试：

- `test/core/reflection_service_test.dart`
  - 生成回应质量 / 上下文 / 画像 / 行动项反思。
  - JSON 往返和 Markdown 预览。
  - secret-like 画像信号不会进入报告或短期提示。
  - 反思短期提示有标题、限量输出，并跳过 secret-like 内容。
  - 长会话质量基线：长会话 + 用户追问 + 待确认画像 + 画像任务同时出现时，报告覆盖回应质量 / 上下文 / 任务推进 / 用户画像；短期提示保留长会话风险和任务推进，完整报告保留画像采纳动作。
- `test/shared/settings_page_dreaming_test.dart`
  - 设置页反思弹窗展示下一轮短期提示预览。
- `test/shared/reflection_provider_test.dart`
  - 最近反思报告持久化 / 清空。
  - 短期提示注入开关持久化。
  - 反思历史持久化、同日去重和最多 20 次上限。
  - 从最近 Dreaming 与用户画像生成、保存反思并写入历史。
- `test/shared/settings_page_dreaming_test.dart`
  - 手动 Dreaming 后同时落盘最近反思和反思历史。
- `test/shared/chat_provider_context_limit_test.dart`
  - Key Points 与本地反思短期提示合并。
  - 关闭短期提示时仍保留 Key Points，不注入反思内容。
- `test/core/structured_data_backup_test.dart`
  - `assistant_reflection_v1`、`assistant_reflection_history_v1` 和 `assistant_reflection_prompt_enabled_v1` 进入结构化备份白名单。

2026-07-06 验证结果：

- `flutter --no-version-check analyze`：通过。
- 局部测试：当前反思 / 上下文相关 24 个通过。
- 全量 `flutter --no-version-check test --no-pub --no-test-assets`：329 个测试通过。

说明：当前本机无法解析 / 连接 GitHub 下载 `sqlite3` native asset，直接运行 `flutter test` 会被 sqlite3 hook 下载阻塞；上述测试用命令内临时 `sqlite3.source=system` 使用 macOS 系统 SQLite 完成，命令结束后已还原正式 `pubspec.yaml`。

## 7. 后续 TODO

- [ ] 模型驱动反思：在用户授权和密钥配置明确时，引入可选模型总结，继续保留本地启发式兜底。
- [x] 反思结果参与系统提示词 v1：把少量高优先级结论和行动项转为下一轮对话的短期提示，默认开启，可在设置页关闭，可解释且可被预算裁剪。
- [x] 反思历史 v1：保留最近 20 次反思版本，同一 Dreaming 日期重复运行会替换旧报告，设置页展示历史保留次数。
- [x] 长会话启发式质量基线：单元测试覆盖长会话、用户追问、待确认画像和画像任务同时出现时的报告与短期提示优先级。
- [ ] 真机长会话评估：结合长会话上下文压缩质量、用户追问率和停止 / 重试行为继续优化反思规则。
