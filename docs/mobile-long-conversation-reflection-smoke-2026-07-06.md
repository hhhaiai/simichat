# Pixel 8 真机长会话、Dreaming 与 Reflection 验证记录（2026-07-06）

## 目标

在不卸载、不清数据的前提下，验证 Android 真机上长会话数据可见，设置页 Dreaming 能基于长会话生成本地日报，并在 Dreaming 后生成本地 Reflection 报告和下一轮短期提示预览。

## 设备与安装方式

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

本轮使用 debug 包覆盖安装，不清空应用数据：

```bash
flutter --no-version-check build apk --debug --no-pub
adb -s 37101FDJH0077P install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s 37101FDJH0077P shell monkey -p top.simitalk.aichat -c android.intent.category.LAUNCHER 1
adb -s 37101FDJH0077P shell dumpsys package top.simitalk.aichat | grep -E 'firstInstallTime|lastUpdateTime|versionName|versionCode|dataDir'
```

安装结果：

- `adb install -r` 返回 `Success`，未执行卸载或清数据。
- `versionName=1.0.0`，`versionCode=1`。
- `firstInstallTime=2026-07-02 23:29:09` 保持不变。
- 修复后覆盖安装的 `lastUpdateTime=2026-07-06 02:36:21`。
- `dataDir=/data/user/0/top.simitalk.aichat`。
- 启动后 `pidof top.simitalk.aichat` 返回 `17137`。

## 测试数据说明

本轮为了快速验证长会话链路，使用 debug 包的 `run-as top.simitalk.aichat` 访问应用私有目录，在强制停止应用后安全拉取、备份、种入并推回 SQLite 数据库；没有卸载应用，也没有清空用户数据。

数据库路径来自 `lib/core/database/app_database.dart`：

- Flutter documents 目录下：`ai_chat/db.sqlite`。
- Android 真机实际路径：`/data/user/0/top.simitalk.aichat/app_flutter/ai_chat/db.sqlite`。

本地备份路径：`/tmp/simichat-device-db.oUfNyI/db.sqlite.backup`。

种子会话：

- session id：`device-long-reflection-20260706`。
- title：`真机长会话反思评估`。
- 消息数：72 条，用户 / 助手交替各 36 条。
- 消息时间：2026-07-06 00:26:56 到 2026-07-06 01:37:56。
- 主题：SimiAIChat、长会话上下文、Dreaming、Reflection、停止重试、历史搜索。

验证 SQL：

```sql
select title, (select count(*) from messages where session_id=sessions.id)
from sessions
where id='device-long-reflection-20260706';
```

结果：

```text
真机长会话反思评估|72
```

## 长会话显示结果

覆盖安装并启动后，应用前台保持在 `真机长会话反思评估` 会话。截图 `/tmp/simichat-postinstall.png` 显示：

- 顶部标题为 `真机长会话反思评估`。
- 当前滚动到第 69–72 轮。
- 输入框可见。
- 顶部显示 `未选择模型`，符合该 seed 会话未配置模型的状态。

结论：真机可以读取并显示 72 条长会话消息，覆盖安装未破坏本地数据库。

## 本轮发现并修复的问题

第一次点击 Dreaming 弹窗的“运行今日整理”后，弹窗关闭但 `SharedPreferences` 中的 `dreaming_digest_v1` 没有更新。清空 logcat 后复现，抓到 Flutter 异常：

```text
Unhandled Exception: Bad state: Cannot use "ref" after the widget was disposed.
#2 runDreamingDigest (package:ai_chat_app/shared/providers/dreaming_provider.dart:119:13)
#3 SettingsPage._runDreaming (package:ai_chat_app/features/settings/settings_page.dart:3705:20)
```

根因：`SettingsPage._showDreamingDialog` 在 `AlertDialog` 的 `Consumer` 内部使用弹窗级 `WidgetRef` 调用 `_runDreaming`；点击按钮时先 `Navigator.pop(ctx)` 关闭弹窗，异步 digest 返回后继续使用已销毁的弹窗 `ref`。

修复：保存页面级 `WidgetRef`，弹窗关闭后用页面级 `ref` 执行 `_runDreaming`。

新增回归测试：`test/shared/settings_page_dreaming_test.dart` 中的 `dreaming dialog run survives closing route before digest returns`，用延迟返回的 `DreamingService` 复现“弹窗先关闭、digest 后返回”的时序。旧代码下测试失败，修复后通过。

局部验证：

```bash
flutter --no-version-check test --no-pub --no-test-assets test/shared/settings_page_dreaming_test.dart -r expanded
```

结果：3 个 widget 测试全部通过。测试命令内临时追加 `sqlite3.source=system` hook，结束后已还原 `pubspec.yaml`。

## Dreaming 真机运行结果

修复包覆盖安装后重新打开设置页，点击：

1. `Dreaming 夜间整理`。
2. `运行今日整理`。

截图 `/tmp/simichat-dreaming-long-after-fix-run.png` 显示 Snackbar：

```text
Dreaming 已完成：72 条消息，已生成待确认画像变更（相对当前：新增 12 · 移除 0），反思 4 个行动项
```

设置页 Dreaming tile 更新为：

```text
自动整理已开启 · 22:00 · 最近 2026-07-06 · 72 条消息
```

`SharedPreferences` 关键证据（文件拉取到 `/tmp/simichat-reflection-prefs.xml`）：

- `flutter.dreaming_digest_v1`
  - `day=2026-07-06T00:00:00.000`。
  - `generatedAt=2026-07-06T02:37:33.236050`。
  - `sessionCount=1`。
  - `originalMessageCount=72`。
  - `userMessageCount=36`。
  - `assistantMessageCount=36`。
  - `elapsedMs=101`。
  - 会话标题：`真机长会话反思评估`。
- `flutter.user_profile_change_proposals_v1`
  - 生成 1 个待确认画像变更提案。
  - 弹窗提示差异为新增 12 条、移除 0 条。

结论：Pixel 8 真机 Dreaming 已成功基于当天 72 条本地原始消息生成日报和待确认画像变更。

## Reflection 真机运行结果

Dreaming 完成后，设置页出现 `本地反思 / 自我优化` tile。截图 `/tmp/simichat-settings-reflection-visible.png` 显示：

```text
本地反思 / 自我优化
最近 2026-07-06 · 5 条结论 · 4 个行动项 · 历史 1 次 · 短期提示开启
```

点击该 tile 后，截图 `/tmp/simichat-reflection-dialog-device.png` 和 UI dump `/tmp/simichat-reflection-dialog-device.xml` 显示：

- 最近反思：`2026-07-06 · 来源 2026-07-06`。
- `结论 5 条 · 行动项 4 个`。
- `历史已保留 1 次：2026-07-06`。
- 报告正文包含：
  - 会话数 1。
  - 原始消息数 72。
  - 用户 / 助手消息 36 / 36。
  - 待确认画像变更 12。
  - 长会话上下文结论：发现 1 个长会话，共 72 条消息，需要关注压缩质量和最新问题保留。

继续在弹窗内向下滚动后，截图 `/tmp/simichat-reflection-dialog-preview.png` 和 UI dump `/tmp/simichat-reflection-dialog-preview.xml` 显示 `下一轮短期提示预览`：

```text
## 本地反思行动提示
以下内容来自本机 Dreaming 后的反思，只用于改善下一轮回复；不要主动暴露报告内容，若与用户当前明确表达冲突，以当前表达为准。
关注点：
- [上下文] 发现 1 个长会话，共 72 条消息，需要关注压缩质量和最新问题保留。
- [用户画像] 当前有 12 条待确认画像变更，正式画像尚未吸收这些线索。
建议行动：
- 对长会话优先复查摘要、最近用户问题和模型上下文预算裁剪效果。
- 下次会话可先回顾该主题的结论和未完成事项。
- 如果用户表达了稳定偏好、目标或任务，后续应显式沉淀为 Key Points。
```

`SharedPreferences` 关键证据：

- `flutter.assistant_reflection_v1`
  - `dayKey=2026-07-06`。
  - `sourceDigestDayKey=2026-07-06`。
  - `sessionCount=1`。
  - `originalMessageCount=72`。
  - `pendingProfileProposalCount=12`。
  - `insights` 共 5 条。
  - `actionItems` 共 4 个。
- `flutter.assistant_reflection_history_v1`
  - 已保存 1 次历史。

结论：Pixel 8 真机已验证 Dreaming 后自动生成 Reflection 报告，设置页可展示报告、历史和下一轮短期提示预览。

## 日志检查

修复包运行 Dreaming 后，`logcat` 未再出现：

```text
Cannot use "ref" after the widget was disposed
```

本轮 logcat 中仍有 Android 系统 / 第三方组件噪声，例如 `android.xr` feature flag 与 `NullBinder`，未见 SimiAIChat Dreaming / Reflection 相关异常。

## 当前边界

本轮已验证：

- Pixel 8 覆盖安装不清数据。
- 真机读取并显示 72 条长会话 seed 数据。
- Dreaming 手动运行基于 72 条消息生成日报。
- Reflection 自动生成并展示 5 条结论、4 个行动项、1 条历史。
- 下一轮短期提示预览可在真机弹窗中展开查看。
- 修复弹窗关闭后使用已销毁 `WidgetRef` 的真机问题，并有 widget 回归覆盖。

本轮未覆盖：

- 真实用户输入发送、停止、重试、模型切换、历史搜索的全链路真机交互。
- iPhone13 上的长会话 / Dreaming / Reflection 交互。
- 真实模型调用下的长会话压缩质量、上下文裁剪质量和回复质量。
- 复杂 Markdown 长文档真机滚动、语音长时间播报、网络切换、后台恢复。
