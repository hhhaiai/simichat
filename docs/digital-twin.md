# 数字孪生 / 镜像数字人设计

> 对应模块：M10。状态：长期方案初版；本地用户画像 v1、可控管理 v1、版本历史与冲突检测 v1、历史差异对比与恢复 v1、Dreaming 待确认画像变更 v1、待确认画像变更逐项采纳 / 拒绝 v1、待确认画像变更详情审阅 v1、模型驱动画像增量分析 v1 已落地。最后更新：2026-07-14。

## 1. 目标

通过长期对话、用户主动提供资料、声音 / 图像 / 表情等多模态信息，生成一个可代理用户思维和表达风格的镜像数字人。

## 2. 输入来源

- 聊天记录。
- Dreaming 提取的 Key Points。
- 用户画像。
- 用户上传资料。
- 语音原始文件与转文字稿件。
- 图片、表情、视频片段。

## 3. 用户画像维度

```text
用户画像
- 作息模式
- 聊天风格
- 思维方式
- 常用表达
- 价值观和偏好
- 任务处理模式
- 社交关系线索
- 知识领域
- 决策偏好
```


## 4. 当前落地：本地用户画像 v1

状态：已落地，作为镜像数字人的最小本地画像基础。

### 4.1 代码入口

- `lib/core/memory/user_profile.dart`
  - `UserProfile`：本地画像结构，包含偏好、目标、任务、基础画像、表达风格、作息线索、关键词、冲突提示、更新时间、来源数量、最近 Dreaming 日期。
  - `UserProfileControls`：用户本地控制，保存画像信号隐藏与编辑规则。
  - `UserProfileHistoryEntry`：画像版本历史条目，记录版本 ID、生成时间、重建原因和完整画像快照。
  - `UserProfileDiff` / `diffUserProfiles`：对比历史画像与当前画像，输出每个画像分区的新增 / 移除摘要。
  - `UserProfileChangeItem`：单条画像差异项，标识画像分区、新增 / 移除类型和值，用于逐项采纳或忽略。
  - `UserProfileChangeProposal`：待确认画像变更提案，保存基准画像、候选画像、生成原因和生成时间。
  - `applyUserProfileChangeItem()` / `discardUserProfileChangeItem()`：分别用于把单条差异应用到正式画像，或从候选画像中剔除被忽略差异。
  - `UserProfileBuilder`：从本地 Key Points 与最近 Dreaming 报告构建画像，重建时应用用户隐藏 / 编辑规则。
  - `encodeUserProfile` / `decodeUserProfile` / `encodeUserProfileControls` / `decodeUserProfileControls` / `encodeUserProfileHistory` / `decodeUserProfileHistory`：本地 JSON 持久化编码。
- `lib/shared/providers/user_profile_provider.dart`
  - `userProfileProvider`：画像状态与 SharedPreferences 持久化。
  - `userProfileControlsProvider`：画像编辑 / 删除控制状态与 SharedPreferences 持久化。
  - `userProfileHistoryProvider`：画像版本历史状态与 SharedPreferences 持久化，最多保留最近 20 个不同画像快照。
  - `kUserProfileStorageKey = user_profile_v1`。
  - `kUserProfileControlsStorageKey = user_profile_controls_v1`。
  - `kUserProfileHistoryStorageKey = user_profile_history_v1`。
  - `kUserProfileChangeProposalsStorageKey = user_profile_change_proposals_v1`。
  - `rebuildUserProfile(reason: ...)`：设置页 / Dreaming 触发的重建入口，保存画像后同步记录版本历史。
  - `editUserProfileSignal()` / `hideUserProfileSignal()`：设置页触发的本地编辑 / 删除入口。
  - `acceptUserProfileProposalItem()` / `rejectUserProfileProposalItem()`：单条画像变更采纳 / 忽略入口；采纳会写入正式画像并记录 `accept_proposal_item` 历史，忽略只更新或删除待确认提案。
- `lib/features/settings/settings_page.dart`
  - “记忆与画像 / 用户画像 / 镜像数字人基础”入口。
  - 支持查看画像摘要、来源数量、最近 Dreaming 日期，并手动重建。
  - 支持编辑 / 删除单条画像信号，且重建后继续保留用户控制。
  - 支持查看画像冲突提示、最近版本历史、相对当前的差异摘要、清空历史和恢复历史版本。
  - 支持查看 Dreaming 生成的待确认画像变更，并整包采纳 / 忽略或逐项采纳 / 忽略；超过 4 条差异时可打开详情弹窗查看全部待确认项。

### 4.2 输入与输出

输入：

- 本地 `KeyPointMemoryItem`。
- 最近 `DreamingDigest.memoryCandidates`。
- 最近 `DreamingDigest.keywords`。

输出：

```text
UserProfile
- preferences：偏好
- goals：目标
- tasks：任务
- profileFacts：基础画像事实
- styleSignals：表达风格
- scheduleSignals：作息线索
- keywords：关键词
- conflicts：偏好冲突提示
- sourceCount：来源记忆数
- updatedAt：更新时间
- digestDayKey：最近 Dreaming 日期
```

### 4.3 安全边界

- v1 全程本地执行，不上传云端，不调用远端模型。
- 用户对画像信号的编辑 / 删除只写入本机 `user_profile_controls_v1`，不会外发。
- 命中 API Key、Authorization、password、secret、token、密钥、密码、常见密钥字面量的内容不进入画像。
- 设置页不展示完整本地路径、附件内容、语音原文大段正文或敏感配置。
- 用户编辑后的画像内容同样经过敏感字段过滤；包含 API Key、Authorization、password、secret、token、密钥、密码等内容不会保存为有效画像控制。
- 画像历史只保存最近 20 个不同快照，全部在本机 SharedPreferences 中，不外发。
- 恢复历史版本只写回本机 `user_profile_v1`，并追加一条 `restore_history` 历史记录，便于审计；不会触发外部模型或云同步。
- Dreaming 生成的画像变化先写入 `user_profile_change_proposals_v1`，不会直接覆盖正式画像；只有用户采纳后才写入 `user_profile_v1` 并记录 `accept_proposal` 或 `accept_proposal_item` 历史。
- 冲突检测 v1 仅基于“喜欢 / 不喜欢 / 不要 / 讨厌 / 避免”等偏好线索做启发式提示，不自动覆盖用户意图。
- 当前画像仅作为个性化参考，不能视为已经具备“代理用户思维”或“数字人直播”能力。
- 后续代理用户回复、同步、对外发送内容前必须明确授权并可审计。

### 4.4 验证

- `test/user_profile_test.dart`：画像维度抽取、敏感内容跳过、编辑 / 删除控制、偏好冲突检测、画像差异对比、单项差异应用 / 忽略、画像 / 控制 / 历史 JSON 往返。
- `test/user_profile_provider_test.dart`：画像本地持久化与清除、编辑 / 删除控制持久化、待确认画像变更提案 / 采纳 / 拒绝、待确认画像变更逐项采纳 / 忽略、恢复历史快照、历史最多 20 条与清空。
- `test/settings_page_user_profile_test.dart`：设置页查看、重建、编辑、删除画像、历史写入、差异展示、恢复历史版本、整包采纳待确认画像变更、逐项采纳 / 忽略待确认画像变更、详情弹窗展示全部待确认项并处理卡片未展示项。
- `scripts/benchmark_user_profile.sh`：1000 条 Key Points + 画像控制构建性能基线。


### 4.5 版本历史与冲突检测 v1

状态：已落地。

- `UserProfile.conflicts` 保存偏好冲突提示，当前基于正向偏好和负向偏好关键词交集做本地启发式检测。
- `UserProfileHistoryEntry` 记录每次重建后的完整画像快照、原因和时间，原因包括 `manual_rebuild`、`dreaming`、`edit_signal`、`hide_signal`、`clear_controls`。
- `user_profile_history_v1` 最多保留最近 20 个不同画像快照，避免无限增长。
- 设置页展示“冲突提示”和“版本历史”，支持清空历史。
- Dreaming 手动运行后会以 `reason: dreaming` 重建画像并写入历史，便于后续做差异审阅和用户确认。


### 4.6 历史差异对比与恢复 v1

状态：已落地。

- 历史版本卡片展示“相对当前：新增 N · 移除 M”，并列出前两个有变化的画像分区。
- 差异分区覆盖偏好、目标、任务、基础画像、表达风格、作息线索、冲突提示和关键词。
- 用户可在设置页点击“恢复此版本”，将历史快照写回当前本地画像。
- 恢复动作会追加 `restore_history` 历史记录，形成可审计闭环。
- 恢复不会清除用户编辑 / 删除控制；后续重新构建画像时仍会应用当前控制规则。


### 4.7 Dreaming 待确认画像变更 v1

状态：已落地。

- 手动 Dreaming 和前台到期 Dreaming 结束后，会基于最新 Key Points / Dreaming 报告构建候选画像。
- 候选画像不会直接覆盖当前正式画像，而是保存为 `UserProfileChangeProposal`。
- 待确认提案保存在 `user_profile_change_proposals_v1`，最多保留最近 10 个不同候选画像。
- 设置页展示提案差异摘要，用户可以“采纳变更”或“忽略变更”。
- 采纳后写回 `user_profile_v1`，并追加 `accept_proposal` 版本历史。
- 忽略后仅删除待确认提案，不修改正式画像。


### 4.8 待确认画像变更逐项采纳 / 拒绝 v1

状态：已落地。

- `UserProfileDiff.items` 会把每个画像分区的新增 / 移除差异展开为 `UserProfileChangeItem`。
- 设置页待确认提案卡片新增“逐项确认”，最多展示前 4 条差异项；每项提供“采纳此项”和“忽略此项”。
- 采纳单项时：
  - 将该单项差异应用到当前正式画像。
  - 写入 `user_profile_v1`。
  - 追加 `accept_proposal_item` 画像历史。
  - 用采纳后的画像更新提案 `baseProfile`，剩余差异自动减少；没有剩余差异时删除提案。
- 忽略单项时：
  - 不修改正式画像。
  - 从候选画像中移除该差异；若忽略的是“移除”项，则把被移除值补回候选画像。
  - 没有剩余差异时删除提案。
- 本能力用于把 Dreaming 的画像更新从“整包同意 / 整包拒绝”推进到“可逐条审阅”，降低误写入用户画像的风险。


### 4.9 待确认画像变更详情审阅 v1

状态：已落地。

- 提案卡片默认只展示前 4 条差异，避免设置页弹窗过长。
- 当待确认项超过 4 条时，卡片显示“查看全部 N 项”。
- 点击后打开“待确认画像变更详情”弹窗：
  - 展示提案摘要和生成时间。
  - 展示全部 `UserProfileChangeItem`，包括卡片未展示的后续差异。
  - 每一项仍可单独“采纳此项”或“忽略此项”。
  - Provider 变化后弹窗会实时刷新；若提案已处理完毕，显示“该待确认画像变更已处理完毕”。
- 本能力补齐“提案较大时无法逐项处理后续差异”的生产可用性缺口。

### 4.10 模型驱动画像增量分析 v1

状态：已落地，默认关闭。

- 设置页提供独立“使用模型辅助画像候选”开关，持久化为 `user_profile_model_enabled_v1`，不复用 Reflection 模型开关。
- 开启后仍先生成本地规则候选；模型只接收限长、脱敏的 Dreaming 摘要与本地候选，不接收原始对话。
- 模型返回的每一条新增候选必须包含逐字匹配的安全证据；仅允许偏好、目标、任务、表达风格、作息线索和关键词。
- 模型最多补 6 条、每个分区最多 2 条；不能删除、覆盖或挤掉本地候选，不能生成基础身份事实或冲突项。
- 密钥、URL、本机路径、健康 / 心理诊断、无证据推断、重复项和 schema 占位内容全部拒绝。
- 模型失败、超时、无可用模型、格式异常或没有安全新增时回退本地候选，不影响 Dreaming / Reflection 完成。
- 提案记录 `local / model / model_fallback` 来源，但无论来源如何都只进入 `user_profile_change_proposals_v1`；用户整条或逐项采纳前，模型不能写入 `user_profile_v1`。
- 开关进入结构化备份白名单，但模型渠道 API Key 仍不导出。
- 真实远程配置质量门禁连续 3 / 3 通过；Pixel 8 系统后台自然冷启动同时完成 Dreaming、模型画像候选和模型 Reflection，正式画像保持未写入。完整证据见 `mobile-model-user-profile-quality-2026-07-14.md`。

## 5. 镜像数字人阶段

1. **资料蒸馏版**：用户提供资料，生成基础 persona。
2. **对话学习版**：长期聊天后自动更新画像。
3. **任务代理版**：在明确授权下代理回复、整理、提醒。
4. **多模态表达版**：声音、图像、表情生成。
5. **直播版**：长期方向，需要额外安全和授权设计。

## 6. 安全边界

- 不能默认冒充用户对外发送内容。
- 代理行为必须有清晰授权。
- 高风险操作必须二次确认。
- 用户可查看、编辑、删除画像。
- 画像导出和云同步必须加密且明确授权。

## 7. 测试要求

- 画像提取结果可解释。
- 删除记忆后画像可重算或标记失效。
- 代理回复必须标记来源。
- 敏感画像字段默认不外发。
