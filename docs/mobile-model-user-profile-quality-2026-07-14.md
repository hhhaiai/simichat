# 移动端模型驱动画像增量分析与质量验证（2026-07-14）

## 1. 目标

在不破坏本地优先、用户确认和正式画像安全边界的前提下，让 Dreaming 可以使用用户已配置的远程聊天模型补充少量画像候选，并证明该链路在移动端系统后台可运行。

本轮不把模型当作画像事实来源，也不允许模型直接写正式画像。模型只作为本地规则候选之后的可选增强层。

## 2. 配置与资源边界

- 功能开关：`user_profile_model_enabled_v1`，默认关闭。
- 远程质量和真机 smoke 只从仓库外 `MODEL_CONFIG_FILE` 读取 `protocol / baseUrl / apiKey / model`。
- 配置文件必须是普通文件，权限必须为 `600` 或 `400`，只接受远程 `openai_chat`，拒绝 loopback。
- 真实地址、API Key 和模型名不写入代码、脚本、测试、文档、编译参数或 APK。
- 不启动、调用或探测 Ollama / 本地模型；远程失败只回退本地画像候选。

## 3. 实现入口

### 3.1 结构化模型画像服务

文件：`lib/core/memory/model_user_profile_service.dart`

- 输入只包含限长、脱敏的 Dreaming 摘要与本地规则画像候选。
- 输出 schema：

```json
{
  "additions": [
    {
      "section": "preferences|goals|tasks|styleSignals|scheduleSignals|keywords",
      "value": "待确认候选",
      "evidence": "逐字引用的一条输入证据"
    }
  ]
}
```

- 每条 `evidence` 必须逐字匹配输入中的一条安全证据。
- 总新增最多 6 条，每个分区最多 2 条。
- 只允许追加；本地候选始终保留，模型不能删除、覆盖或挤掉本地内容。
- 禁止 `profileFacts` 和 `conflicts`，避免模型把推断写成基础身份事实。
- 过滤密钥、令牌、URL、本机路径、健康 / 心理诊断、无证据内容、重复内容和 schema 占位值。
- 响应与提示有长度上限，网络调用有 60 秒总墙钟超时和上游取消。

### 3.2 Provider 与持久化

文件：`lib/shared/providers/user_profile_provider.dart`

- `userProfileModelEnabledProvider`：独立默认关闭开关。
- `userProfileModelEnhancerProvider`：通过用户已保存的默认聊天模型调用正式协议链路。
- `proposeUserProfileChangesWithAccess()`：先构建本地候选，开关开启且存在有效 Dreaming 时再尝试模型增强。
- 模型失败、无可用模型、超时、格式异常或无安全新增时，保留本地候选并把提议来源标为 `model_fallback`。
- `UserProfileChangeProposal.generationMode` 兼容 `local / model / model_fallback`。
- 无论来源如何，都只写 `user_profile_change_proposals_v1`；正式 `user_profile_v1` 只有用户整条或逐项采纳后才会更新。

### 3.3 后台和设置页

- `lib/core/background/dreaming_background_runner.dart` 继续复用同一画像提议入口，因此 Android WorkManager 和 iOS BGTask 编排都遵守独立开关与回退边界。
- 设置页明确说明发送范围、默认关闭、待确认属性、不能直接修改正式画像和失败回退。
- `user_profile_model_enabled_v1` 已加入结构化备份 / 恢复白名单；模型渠道 API Key 仍不导出。

## 4. 自动化验证

新增或扩展：

- `test/core/model_user_profile_service_test.dart`
- `test/shared/user_profile_provider_test.dart`
- `test/shared/dreaming_background_runner_test.dart`
- `test/shared/settings_page_user_profile_test.dart`
- `test/core/structured_data_backup_test.dart`
- `test/core/model_user_profile_live_quality_manifest_test.dart`
- `test/core/dreaming_background_device_smoke_manifest_test.dart`

覆盖：

- 安全且有证据的新增可以合并；
- 基础事实、无证据、URL、路径、密钥和诊断内容被拒绝；
- 模型不能挤掉本地候选；
- 默认关闭与独立开关持久化；
- 模型失败回退本地；
- 后台模型增强仍只产生待确认提议，正式画像不写入；
- 结构化备份恢复开关；
- 真机脚本必须验证画像提议为模型来源、无 fallback、无正式画像写入。

结果：

- 模型画像 / provider / 后台 runner / 设置页 / 备份 / manifest 聚焦 41 项通过。
- 全量稳定门禁：566 项通过。
- `flutter --no-version-check analyze --no-pub`：无问题。
- `git diff --check`、shell 语法、sqlite hook、隔离包和真实远程值仓库泄漏扫描：通过。

## 5. 真实远程质量门禁

入口：

```bash
MODEL_CONFIG_FILE=/仓库外/remote-model.json \
SIMICHAT_LIVE_PROFILE_MODEL_RUNS=3 \
./scripts/smoke_model_user_profile_live_quality.sh
```

三轮 synthetic dayKey 均通过：

| run | dayKey | elapsed | attempts | 安全新增候选 |
| ---: | --- | ---: | ---: | ---: |
| 1 | 2026-07-14 | 28.415s | 3 | 2 |
| 2 | 2026-07-15 | 35.397s | 1 | 3 |
| 3 | 2026-07-16 | 20.852s | 1 | 4 |

共同断言：

- 所有本地候选保留；
- 总新增不超过 6 条；
- 基础事实保持不变；
- sourceCount 和 digestDayKey 保持不变；
- 合成密钥、URL、本机路径、诊断内容、虚构职业和“已修改正式画像”不进入结果。

首次运行曾出现远程请求超时；接口恢复后，一轮需要三次有界尝试，其余两轮一次成功。该波动属于外部接口可用性事实，不被隐藏，也不会触发本地模型回退。

## 6. Pixel 8 系统后台真机

设备：Pixel 8，独立包 `top.simitalk.aichat.backgroundmodelsmoke`。

过程：

1. wrapper 从仓库外配置读取远程接口；预检前两次 401，第三次成功。
2. build / install 独立包，不覆盖正式 App。
3. READY pid `12526` 后回到 Home，并回收隔离 UI 进程。
4. 不调用 shell force；JobScheduler 自然冷启动新 pid `12911`。
5. elapsed `127` 秒完成：

```text
status=completed
digest=2026-07-14
reflection=2026-07-14
```

持久化断言：

- Dreaming 最近报告存在；
- Reflection 最近报告与历史存在，无 pending；
- Reflection 为 `generationMode=model`；
- 画像提议存在并为 `generationMode=model`；
- 画像提议无 `model_fallback`；
- 正式 `user_profile_v1` 不存在，证明模型未直接写正式画像；
- 日志和 prefs 不包含配置地址或 API Key。

cleanup：

- 隔离包不存在；
- 临时 sqlite hook 不存在；
- 正式包 firstInstallTime `2026-07-14 00:29:02`、dataDir `/data/user/0/top.simitalk.aichat` 不变，恢复运行 pid `13315`；
- Android 跨日任务仍为 `waiting`，未被重新调度、force、卸载或复用。

取证：

- `/tmp/simichat-android-background-dreaming-20260714233159.log`
- `/tmp/simichat-android-background-dreaming-prefs-20260714233159.xml`

## 7. 仍未完成的长期项

- Android 2026-07-15 跨日自然任务到期后的独立 verify；
- iOS 开启“后台 App 刷新”后的 BGTask 真机系统执行；
- Android 长时间 Doze 和 OEM 严格杀后台；
- 更多远程模型族与真实多日用户会话的画像质量；
- 声音、图像、表情画像与镜像数字人生成。
