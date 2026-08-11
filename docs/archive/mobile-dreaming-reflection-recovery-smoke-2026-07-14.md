# Pixel 8 Dreaming / Reflection 失败恢复真机 Smoke（2026-07-14）

## 1. 目标

在不依赖远端模型、不使用真实聊天数据库的前提下，验证当前移动端正式生命周期链路：

1. 前台到期 Dreaming 成功生成报告。
2. Reflection 第一次执行失败时写入 `assistant_reflection_pending_v1`。
3. 应用进入 Home 后重新恢复前台。
4. `ResponsiveShell.didChangeAppLifecycleState(resumed)` 触发 pending 重试。
5. Reflection 最近报告与历史生成，pending 清除。
6. smoke 不覆盖或清理正式包 `top.simitalk.aichat` 的数据。

## 2. 最终安全实现

- Gradle 支持只在 smoke 构建时通过 `simichatApplicationId` 覆盖 applicationId；正式默认值仍为 `top.simitalk.aichat`。
- smoke applicationId 固定为 `top.simitalk.aichat.dreamingsmoke`。
- `lib/core/smoke/dreaming_reflection_smoke_harness.dart` 使用：
  - `AppDatabase.forTesting(NativeDatabase.memory())`；
  - smoke 独立包内的 SharedPreferences；
  - 第一次必定失败、第二次成功的本地 `ReflectionService`；
  - 正式 `AiChatApp` / `ResponsiveShell` 启动与 resumed 生命周期。
- 同一 harness 另提供 `SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERY_SMOKE=true` 冷启动模式：
  - 第一次启动使用隔离包私有 `AppDatabase()` 写入 completed job、SQLite report 和 Reflection pending；
  - 不写 `dreaming_digest_v1` / history，也不在第一次启动运行正式 `ResponsiveShell`；
  - 脚本强制停止旧进程后重新启动；
  - 第二个新进程通过正式启动任务从 SQLite 回灌 Dreaming 当前报告 / 历史，完成 Reflection 并清 pending；
  - 只有 digest、两类 history、Reflection 和 pending 状态全部一致时才输出 recovered marker。
- `scripts/smoke_device_dreaming_reflection_recovery.sh` 只执行 `flutter build apk`，不执行 `flutter test -d`：
  - 直接 `adb install` 独立 APK；
  - 启动后等待 pending marker；
  - Home 后重新启动 smoke 包触发 resumed；
  - 等待 recovered marker；
  - 卸载 smoke 包；
  - 重新启动正式 release；
  - 比较正式包 smoke 前后的 `firstInstallTime` 与 `dataDir`；
  - 检查 smoke 包和临时 sqlite hook 无残留。

## 3. 成功取证

设备：Pixel 8，ID `37101FDJH0077P`，Android 16 / API 36。

命令：

```bash
scripts/smoke_device_dreaming_reflection_recovery.sh 37101FDJH0077P
```

关键输出：

```text
SIMICHAT_DREAMING_REFLECTION_PENDING dayKey=2026-07-14 attempts=1
SIMICHAT_DREAMING_REFLECTION_RECOVERED dayKey=2026-07-14 attempts=2 history=1
ISOLATED_DREAMING_REFLECTION_SMOKE_OK package=top.simitalk.aichat.dreamingsmoke
NORMAL_RELEASE_RESTORED package=top.simitalk.aichat pid=31473 firstInstallTime=2026-07-14 00:29:02 dataDir=/data/user/0/top.simitalk.aichat
```

日志：

```text
/tmp/simichat-dreaming-reflection-device-20260714003349.log
```

复查：

- `top.simitalk.aichat.dreamingsmoke` 无安装残留。
- 正式包进程可见。
- 修正后的隔离 smoke 前后，正式包 `firstInstallTime=2026-07-14 00:29:02` 未变化。
- 正式包 `dataDir=/data/user/0/top.simitalk.aichat` 未变化。
- `pubspec.yaml` / `pubspec.lock` 无临时 `sqlite3.source=system` 残留。
- Android Backup transport 已恢复为 Google BackupTransportService。

## 4. SQLite-only 冷启动恢复取证

为验证后台进程死亡后只有 SQLite report 和 Reflection pending 存在的恢复路径，使用单独隔离包：

```bash
SMOKE_SQLITE_RECOVERY=1 \
SMOKE_PACKAGE=top.simitalk.aichat.dreamingsqlitesmoke \
  scripts/smoke_device_dreaming_reflection_recovery.sh 37101FDJH0077P
```

第一次启动只落持久化状态：

```text
SIMICHAT_DREAMING_REFLECTION_SQLITE_READY dayKey=2026-07-14
pid=5157
```

脚本执行 `am force-stop`，确认旧 pid 消失，再启动同一隔离包。第二个新进程输出：

```text
SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERED dayKey=2026-07-14 dreamingHistory=1 reflectionHistory=1
ISOLATED_DREAMING_REFLECTION_SQLITE_RECOVERY_OK package=top.simitalk.aichat.dreamingsqlitesmoke before=5157 after=5263
```

设备端 SharedPreferences 取证：

```text
dreaming_digest_v1=present
dreaming_digest_history_v1=present
assistant_reflection_v1=present
assistant_reflection_history_v1=present
assistant_reflection_pending_v1=absent
```

日志与 prefs：

```text
/tmp/simichat-dreaming-reflection-device-20260714215600.log
/tmp/simichat-dreaming-reflection-prefs-20260714215600.xml
```

cleanup 后：

```text
NORMAL_RELEASE_RESTORED package=top.simitalk.aichat pid=5438 firstInstallTime=2026-07-14 00:29:02 dataDir=/data/user/0/top.simitalk.aichat
isolated_package_absent=true
sqlite_hook_absent=true
Android cross-day job_0_state=waiting
```

该结果证明当前移动端正式启动链可在全新进程中完成：

```text
SQLite dreaming_report + Reflection pending
→ Dreaming 当前报告 / 历史回灌
→ Reflection 当前报告 / 历史
→ pending 清除
```

## 5. 首次 runner 事故与数据影响

首次尝试使用了：

```text
ORG_GRADLE_PROJECT_simichatApplicationId=top.simitalk.aichat.dreamingsmoke
flutter test -d 37101FDJH0077P integration_test/...
```

虽然 Gradle 产物使用了独立 applicationId，但 Flutter integration runner 仍根据工程默认包元数据卸载了正式包 `top.simitalk.aichat`。脚本检测到正式包消失后自动重装并启动 release，但 `firstInstallTime` 从：

```text
2026-07-07 12:51:06
```

变为：

```text
2026-07-14 00:29:02
```

这证明发生了卸载 / 重装，而不是覆盖安装。重新启动后的界面为空白新会话状态，说明原应用私有数据未随安装恢复。

已尝试恢复：

- Android LocalTransport restore set token `1`：`restoreFinished: -1000`，`NO_PM_METADATA_RECEIVED`。
- D2D restore set token `3928618e282d5704`：`restoreFinished: -1000`，`TRANSPORT_ERROR_DURING_START_RESTORE`。
- `/sdcard/Download` 与 `/sdcard/Documents` 未发现可用 SimiChat 导出包。
- 本机用户目录未发现可识别的 SimiChat `.tar.gz` / 数据库备份。

因此本轮无法从系统或可访问导出文件自动恢复首次 runner 删除前的 Pixel 8 应用私有数据。后续如果用户在其他位置保留过 SimiChat 导出包，需要通过应用“导入数据”入口恢复。

## 6. 防复发约束

- Dreaming / Reflection 真机 smoke 禁止再使用 `flutter test -d` 搭配动态 applicationId。
- 必须使用“build 独立 APK → adb 安装 → logcat 取证 → 卸载独立包”路径。
- smoke 前后必须比较正式包 `firstInstallTime` 与 `dataDir`。
- smoke cleanup 必须卸载独立包并启动正式 release。
- 任一正式包状态变化均视为 smoke 失败，不得标记通过。
