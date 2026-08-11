# Android 系统后台 Dreaming / Reflection 真机验证（2026-07-14）

## 目标

验证 SimiChat 在 Android 应用退到 Home 后，可由系统 WorkManager / JobScheduler 启动后台 Flutter isolate，在不依赖前台页面的情况下完成：

1. 读取应用私有 SQLite 当日原始消息；
2. 生成 Dreaming 报告与本地 Key Points；
3. 生成待确认画像变更；
4. 生成 Reflection 最近报告与历史；
5. 写入自动运行 marker，并发送本地完成通知；
6. 不卸载、不清理、不覆盖正式包私有数据。

## 实现边界

- 依赖：`workmanager 0.8.0`。
- 精确锁定 `0.8.0` 是为了保持现有 iOS 13 deployment target；`0.9.x` 的 Apple pod 要求 iOS 14，不能在只实现 Android 后台时无声提高 iOS 最低版本。
- Android 使用一次性唯一任务，而不是全天 15 分钟轮询。
- 正常任务名：`simichat.android.dreaming.background.v1`。
- 同日自动运行使用 SQLite 固定 job ID：`dreaming-auto-YYYY-MM-DD`。
- 前台与后台跨 isolate 通过 `DreamingDao.claimAutomaticJob()` 原子 claim 防重。
- failed 或超过 15 分钟的 pending / running job 可重领；completed / dismissed 不会重复运行。
- Reflection 单独失败返回 WorkManager retry，并保留 `assistant_reflection_pending_v1`；重试时不重复 Dreaming。
- 本地规则 Reflection 始终可离线完成，因此后台任务默认不要求网络；用户显式开启可选模型增强时，网络不可用会安全回退本地报告，不让后台任务因可选增强反复 retry。任务始终要求电量和存储空间不低；用户可额外开启“仅充电时执行”和“仅非计费网络执行”。Android 可严格映射为充电与 `NetworkType.unmetered`，iOS 充电条件可表达，但 Apple 侧网络条件只能要求联网，不能保证 Wi-Fi。
- WorkManager 是系统择机执行，不保证精确到设定分钟；前台到期检查继续作为兜底。

## 真机安全路径

设备：

```text
Pixel 8
37101FDJH0077P
Android 16 / API 36
```

正式包与隔离包：

```text
正式包：top.simitalk.aichat
隔离包：top.simitalk.aichat.backgroundsmoke
```

执行入口：

```bash
# 默认：保留原有 JobScheduler 强制触发回归
scripts/smoke_device_android_background_dreaming.sh 37101FDJH0077P

# 自然调度：不调用 cmd jobscheduler run
scripts/smoke_device_android_background_dreaming_natural.sh 37101FDJH0077P

# UI 进程死亡：等待 WorkSpec 到期后 force，验证 SystemJobService 冷启动 headless isolate
scripts/smoke_device_android_background_dreaming_process_death.sh 37101FDJH0077P

# UI 进程死亡 + 自然调度：不调用 cmd jobscheduler run，最长观察 900 秒
scripts/smoke_device_android_background_dreaming_process_death_natural.sh 37101FDJH0077P
```

脚本禁止 `flutter test -d`，只执行：

```text
flutter build apk --debug + 独立 applicationId
  -> adb install 隔离包
  -> 启动隔离 harness 并种入隔离数据库
  -> Home
  -> force 模式由 Android JobScheduler 强制触发，natural 模式等待系统自行调度
  -> logcat / SharedPreferences 取证
  -> 卸载隔离包
  -> 恢复并核对正式 release 进程
```

脚本在任何 `adb uninstall` 前强制检查：

```text
SMOKE_PACKAGE != PACKAGE_ID
SMOKE_PACKAGE 必须匹配 PACKAGE_ID.*
正式包必须已经存在；缺失时直接拒绝，不自动重装
```

不同 WorkManager Android 实现注册的 JobScheduler 形式不同：

```text
workmanager 0.9.x：Android 16 namespace = androidx.work.systemjobscheduler
workmanager 0.8.0：legacy job，无 namespace
```

脚本先尝试 Android 16 namespaced 命令：

```bash
adb shell cmd jobscheduler run \
  -f \
  -n androidx.work.systemjobscheduler \
  top.simitalk.aichat.backgroundsmoke \
  0
```

最终锁定的 `workmanager 0.8.0` 不存在该 namespace，因此首个命令返回：

```text
Could not find job 0 in package top.simitalk.aichat.backgroundsmoke / namespace androidx.work.systemjobscheduler
```

脚本随后自动回退到 legacy 命令并成功强制运行：

```bash
adb shell cmd jobscheduler run \
  -f \
  top.simitalk.aichat.backgroundsmoke \
  0
```

自然调度入口复用同一隔离 APK 和清理逻辑，但通过编译期参数把 smoke one-off task 的 initialDelay 设为 30 秒，并补齐与生产任务相同的基础约束：

```text
NetworkType.notRequired
requiresBatteryNotLow=true
requiresStorageNotLow=true
```

启动隔离 App 后立即回到 Home，脚本只读取 WorkManager / JobScheduler 状态并等待 `SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT`，不会执行 `cmd jobscheduler run`。默认最长等待 240 秒；delay 和等待上限可通过 `SMOKE_INITIAL_DELAY_SECONDS` / `RESULT_WAIT_SECONDS` 调整。

## 真机结果

关键输出：

```text
Could not find job 0 in package top.simitalk.aichat.backgroundsmoke / namespace androidx.work.systemjobscheduler
Running job [FORCED]
SIMICHAT_ANDROID_BACKGROUND_DREAMING_READY
SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed digest=2026-07-14 reflection=2026-07-14
ISOLATED_ANDROID_BACKGROUND_DREAMING_SMOKE_OK package=top.simitalk.aichat.backgroundsmoke jobs=0
```

隔离 SharedPreferences 已确认存在：

```text
dreaming_digest_v1
assistant_reflection_v1
assistant_reflection_history_v1
```

本轮日志与偏好取证：

```text
/tmp/simichat-android-background-dreaming-20260714013910.log
/tmp/simichat-android-background-dreaming-prefs-20260714013910.xml
```

cleanup 后正式包证据：

```text
package=top.simitalk.aichat
firstInstallTime=2026-07-14 00:29:02
lastUpdateTime=2026-07-14 00:29:02
dataDir=/data/user/0/top.simitalk.aichat
pid=12024
隔离 backgroundsmoke 包无残留
临时 sqlite hook 无残留
```

## 自然调度补证

2026-07-14 在同一 Pixel 8 上复跑自然调度入口。运行前设备条件：

```text
电量：89%
AC powered：true
/data 可用空间：27GB
```

关键时间线：

```text
04:29:42.872 SIMICHAT_ANDROID_BACKGROUND_DREAMING_READY
04:30:18.842 SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed digest=2026-07-14 reflection=2026-07-14
triggerMode=natural
delaySeconds=30
elapsedSeconds=36
```

宿主执行日志中没有 `cmd jobscheduler run` 或 `Running job [FORCED]`；设备日志显示 `SystemJobService enabled` / `Created SystemJobScheduler`，随后系统自行执行 WorkManager job。隔离 SharedPreferences 包含：

```text
dreaming_digest_v1
assistant_reflection_v1
assistant_reflection_history_v1
```

并明确不存在：

```text
assistant_reflection_pending_v1
```

自然调度最终取证：

```text
/tmp/simichat_android_natural_background_final.log
/tmp/simichat-android-background-dreaming-20260714042907.log
/tmp/simichat-android-background-dreaming-prefs-20260714042907.xml
```

随后复跑默认 force 分支，继续通过 Android 16 namespace 失败后的 legacy fallback，输出：

```text
triggerMode=force
delaySeconds=600
elapsedSeconds=10
status=completed digest=2026-07-14 reflection=2026-07-14
```

force 回归取证：

```text
/tmp/simichat_android_force_background_regression.log
/tmp/simichat-android-background-dreaming-20260714042803.log
/tmp/simichat-android-background-dreaming-prefs-20260714042803.xml
```

两次 cleanup 后均确认：

```text
正式包 firstInstallTime=2026-07-14 00:29:02
正式包 dataDir=/data/user/0/top.simitalk.aichat
最终正式包 pid=24389
隔离 backgroundsmoke 包不存在
临时 sqlite hook 不存在
```

新增自然调度 manifest / scheduler / runner / provider 聚焦门禁 37 项通过；最终 `scripts/smoke_full_stability_gate.sh -r expanded` 518 项通过，日志无 `WARNING (drift)`、`multiple databases` 或失败标记。

## 11:05 稳定性复查

后台 runner 审计新增“pending Reflection 连续失败”回归。旧逻辑在第二次恢复仍失败且当天 Dreaming 已完成时错误返回 `notDue`；红灯复现后修复为继续返回 `reflectionPending`，从而让 Android WorkManager 保持 retry、iOS 继续排 15 分钟重试。目标文件 4 项、全量稳定门禁 519 项通过。

本次 Pixel 8 默认 force 分支能定位 job id `0`，但 `cmd jobscheduler run` 后 90 秒内未出现结果 marker；脚本安全 cleanup 后正式包保持：

```text
firstInstallTime=2026-07-14 00:29:02
dataDir=/data/user/0/top.simitalk.aichat
pid=22057
```

随后立即复跑不依赖 shell 强制命令的自然调度。隔离 App 回到 Home 后，系统在 READY 后 36 秒自行执行并输出：

```text
SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed digest=2026-07-14 reflection=2026-07-14
ISOLATED_ANDROID_BACKGROUND_DREAMING_SMOKE_OK triggerMode=natural delaySeconds=30 elapsedSeconds=36
```

最终 cleanup 再次确认正式包 `firstInstallTime` / `dataDir` 不变、pid `22864`，隔离包和临时 sqlite hook 无残留。最新取证：

```text
/tmp/simichat-android-background-dreaming-20260714110533.log
/tmp/simichat-android-background-dreaming-20260714110939.log
/tmp/simichat-android-background-dreaming-prefs-20260714110939.xml
```

因此本次结论拆分为：生产依赖的 SystemJobScheduler 自然后台链路通过；`cmd jobscheduler run` force 诊断入口存在本次设备波动，不把该工具链失败扩大解释为生产后台失败。

## 强制 deep idle 与 force 入口修复

进一步复查发现 force 波动不是产品 WorkManager 任务失败，而是 smoke 脚本先从全局 logcat 匹配：

```text
WM-SystemJobScheduler: Scheduling work ID ... Job ID ...
```

该日志没有包名边界，会把同一时刻其他 App 的 WorkManager Job ID 当作 SimiChat Job ID。本轮实际观察到错误候选 `6398 6399 6400 6401`。新增红灯静态门禁后，脚本删除全局 logcat Job ID 分支，只从 `dumpsys jobscheduler` 中精确匹配：

```text
top.simitalk.aichat.backgroundsmoke/androidx.work.impl.background.systemjob.SystemJobService
```

修复后默认 force 分支复跑结果：

```text
jobs=0
triggerMode=force
elapsedSeconds=10
status=completed digest=2026-07-14 reflection=2026-07-14
```

取证：

```text
/tmp/simichat-android-background-dreaming-20260714112626.log
/tmp/simichat-android-background-dreaming-prefs-20260714112626.xml
```

新增 `scripts/smoke_device_android_background_dreaming_doze.sh`，内部使用自然调度并在隔离包回到 Home 后执行 `cmd deviceidle force-idle`。脚本要求：

- 调度时 deep state 为 `IDLE` 或 `IDLE_MAINTENANCE`；
- 隔离包不在永久 idle whitelist；
- 结果 marker 到达时仍处于 deep idle；
- 任意退出路径先执行 `cmd deviceidle unforce` 和 WAKEUP，再卸载隔离包、恢复正式包；
- 正式包 firstInstallTime / dataDir 不变化，临时 sqlite hook 不残留。

Pixel 8 最终结果：

```text
ANDROID_BACKGROUND_DREAMING_IDLE_READY state=IDLE
SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed digest=2026-07-14 reflection=2026-07-14
idleMode=force
idleStateAtSchedule=IDLE
idleStateAtResult=IDLE
delaySeconds=30
elapsedSeconds=37
```

cleanup 后：

```text
deviceidle deep=ACTIVE
package=top.simitalk.aichat
pid=27177
firstInstallTime=2026-07-14 00:29:02
dataDir=/data/user/0/top.simitalk.aichat
隔离 backgroundsmoke 包不存在
临时 sqlite hook 不存在
```

Doze 取证：

```text
/tmp/simichat-android-background-dreaming-20260714112723.log
/tmp/simichat-android-background-dreaming-prefs-20260714112723.xml
```

新增 Doze / Job ID 静态门禁 2 项；`scripts/smoke_full_stability_gate.sh` 最终 521 项通过，`flutter --no-version-check analyze --no-pub` 无问题，`git diff --check` 无输出。

## UI 进程死亡后的 headless 冷启动

进程死亡 smoke 使用同一隔离包，不卸载、不覆盖正式包。初版自动化在旧 UI 进程消失后立即 force JobScheduler，系统虽然能为 `SystemJobService` 拉起新服务进程，但冷启动 WorkManager 重新读取到的 WorkSpec 仍处于 600 秒 initialDelay 内，后台 Dart worker 没有执行，90 秒内没有结果 marker。这个红灯说明“服务进程被拉起”不能等同于“WorkSpec 已执行”。

修正后新增：

```text
BACKGROUND_PROCESS_MODE=kill
SMOKE_INITIAL_DELAY_SECONDS=30
PROCESS_KILL_SETTLE_SECONDS=35
RESULT_WAIT_SECONDS=90
```

主脚本在 `am kill` 后要求旧 pid 完全消失、package 保持 `stopped=false`；等待 settle 后再次确认 package 未 force-stop，并从 `dumpsys jobscheduler` 精确确认隔离包 `SystemJobService` job 仍存在，之后才执行 force。`PROCESS_KILL_SETTLE_SECONDS` 必须是非负整数，默认其他 smoke 路径为 `0`，不改变既有 force / natural / Doze 行为。

2026-07-14 Pixel 8 最终结果：

```text
ANDROID_BACKGROUND_DREAMING_PROCESS_KILLED package=top.simitalk.aichat.backgroundsmoke pid=30424
ActivityManager: Start proc 30629:top.simitalk.aichat.backgroundsmoke/... for service {top.simitalk.aichat.backgroundsmoke/androidx.work.impl.background.systemjob.SystemJobService}
ANDROID_BACKGROUND_DREAMING_PROCESS_RESTARTED package=top.simitalk.aichat.backgroundsmoke before=30424 after=30629
SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed digest=2026-07-14 reflection=2026-07-14
processMode=kill pidBefore=30424 pidAfter=30629 delaySeconds=30 elapsedSeconds=47
```

cleanup 结果：

```text
deviceidle deep=ACTIVE
正式包 pid=30813
正式包 firstInstallTime=2026-07-14 00:29:02
正式包 dataDir=/data/user/0/top.simitalk.aichat
隔离 backgroundsmoke / dreamingsmoke 包不存在
临时 sqlite hook 不存在
```

取证：

```text
/tmp/simichat-android-background-dreaming-20260714115140.log
/tmp/simichat-android-background-dreaming-prefs-20260714115140.xml
```

目标 manifest 门禁 5 项通过；`scripts/smoke_full_stability_gate.sh` 全量 522 项通过；`flutter --no-version-check analyze --no-pub` 无问题；`git diff --check` 无输出。

本次只证明 WorkSpec 到期后，JobScheduler forced callback 能在 UI 进程已不存在时冷启动新的服务进程、Flutter headless isolate 和完整 Dreaming / Reflection 编排。它不替代自然调度时延、数小时 / 跨日 Doze、极低电量或 OEM 严格杀后台可靠性验证。

## UI 进程死亡后的自然调度

为消除 forced callback 的证明边界，新增：

```text
scripts/smoke_device_android_background_dreaming_process_death_natural.sh
```

固定配置：

```text
TRIGGER_MODE=natural
BACKGROUND_PROCESS_MODE=kill
SMOKE_INITIAL_DELAY_SECONDS=30
PROCESS_KILL_SETTLE_SECONDS=0
RESULT_WAIT_SECONDS=900
```

该入口不调用 `cmd jobscheduler run`。隔离 App 完成调度、返回 Home 后，以 `am kill` 回收 UI 进程；package 必须保持 `stopped=false`，JobScheduler job 必须继续存在。随后只轮询结果 marker，等待 Android 按自身批处理策略执行。

前两次诊断分别使用 180 秒和 240 秒观察窗口，均在结果到达前退出。任务等待期间实时 `dumpsys jobscheduler` 显示：

```text
Service: top.simitalk.aichat.backgroundsmoke/androidx.work.impl.background.systemjob.SystemJobService
Requires: batteryNotLow=true
Satisfied: BATTERY_NOT_LOW STORAGE_NOT_LOW DEVICE_NOT_DOZING BACKGROUND_NOT_RESTRICTED WITHIN_QUOTA
Standby bucket: ACTIVE
Restricted due to: none
Job state: ready
```

因此 job 没有丢失，也不是电量、存储、Doze、后台限制或 quota 约束失败，而是系统没有承诺在 30 秒 initialDelay 后立即调度。最终把观察窗口扩大到 900 秒后通过，实际时间线：

```text
ANDROID_BACKGROUND_DREAMING_PROCESS_KILLED pid=2639
ANDROID_BACKGROUND_DREAMING_NATURAL_WAIT jobs=0 delaySeconds=30
ActivityManager: Start proc 4668 ... for service {.../androidx.work.impl.background.systemjob.SystemJobService}
SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed digest=2026-07-14 reflection=2026-07-14
ANDROID_BACKGROUND_DREAMING_PROCESS_RESTARTED before=2639 after=4668
triggerMode=natural processMode=kill elapsedSeconds=249
```

隔离 SharedPreferences 包含：

```text
dreaming_digest_v1
assistant_reflection_v1
assistant_reflection_history_v1
```

并且不存在 `assistant_reflection_pending_v1`。cleanup 后：

```text
deviceidle deep=ACTIVE
正式包 pid=4980
正式包 firstInstallTime=2026-07-14 00:29:02
正式包 dataDir=/data/user/0/top.simitalk.aichat
隔离包不存在
临时 sqlite hook 不存在
```

取证：

```text
/tmp/simichat-android-background-dreaming-20260714122709.log
/tmp/simichat-android-background-dreaming-prefs-20260714122709.xml
```

目标 manifest 门禁 6 项、`scripts/smoke_full_stability_gate.sh` 全量 523 项和 `flutter --no-version-check analyze --no-pub` 通过。

本结果证明 UI 进程消失后，无 shell force 的 Android 自然调度仍能冷启动完整 Dreaming / Reflection 链路；同时也证明 initialDelay 不是精确执行时间。900 秒是 smoke 观察上限，不是产品 SLA，也不能替代跨小时、跨日、极低电量或 OEM 严格后台限制验证。

## UI 进程死亡后的跨小时自然调度

在短时 natural process-death 通过后，继续复用同一入口，不增加新产品代码或专用调度逻辑：

```bash
LOG_PATH=/tmp/simichat-android-background-dreaming-hourly-20260714.log \
PREFS_PATH=/tmp/simichat-android-background-dreaming-hourly-20260714.xml \
SMOKE_INITIAL_DELAY_SECONDS=3600 \
RESULT_WAIT_SECONDS=7200 \
scripts/smoke_device_android_background_dreaming_process_death_natural.sh \
  37101FDJH0077P
```

运行前 Pixel 8 状态：

```text
AC powered=true
battery level=80
deep=ACTIVE
正式包 pid=4980
隔离包不存在
临时 sqlite hook 不存在
```

隔离 App 调度后返回 Home，旧 pid `6444` 被回收。等待期间定期只读 `dumpsys jobscheduler`，没有启动隔离 App、没有 force job、没有改变 standby bucket。关键状态演进：

```text
约 5 分钟：bucket=ACTIVE，只有 TIMING_DELAY 未满足
约 44 分钟：bucket 自然降到 RARE，其他约束仍满足
约 55 分钟：最早执行时间剩余约 4 分钟
约 60 分钟：TIMING_DELAY 已满足，job_state=ready
到期后约 12 分钟：系统实际启动 SystemJobService
```

最终结果：

```text
ANDROID_BACKGROUND_DREAMING_PROCESS_KILLED pid=6444
ANDROID_BACKGROUND_DREAMING_NATURAL_WAIT jobs=0 delaySeconds=3600
ActivityManager: Start proc 24325 ... for service {.../androidx.work.impl.background.systemjob.SystemJobService}
SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed digest=2026-07-14 reflection=2026-07-14
ANDROID_BACKGROUND_DREAMING_PROCESS_RESTARTED before=6444 after=24325
triggerMode=natural processMode=kill delaySeconds=3600 elapsedSeconds=4360
```

`4360` 秒即约 72 分 40 秒。这个结果由 3600 秒最小延迟和约 760 秒系统批处理延迟组成，进一步证明 initialDelay 不是精确触发时间。

隔离 prefs 包含 Dreaming、Reflection 最近报告和历史，不存在 `assistant_reflection_pending_v1`。cleanup 后：

```text
deep=ACTIVE
正式包 pid=24737
正式包 firstInstallTime=2026-07-14 00:29:02
正式包 dataDir=/data/user/0/top.simitalk.aichat
隔离包不存在
临时 sqlite hook 不存在
```

取证：

```text
/tmp/simichat-android-background-dreaming-hourly-20260714.log
/tmp/simichat-android-background-dreaming-hourly-20260714.xml
/tmp/simichat-android-background-dreaming-hourly-host-20260714.log
```

本轮结束后 `scripts/smoke_full_stability_gate.sh` 全量 523 项通过，`flutter --no-version-check analyze --no-pub` 无问题。

本轮证明范围是“UI 进程死亡后跨小时自然调度仍可完成 Dreaming / Reflection”。它不等同于跨日、长时间强制 Doze、设备重启恢复或 OEM 严格后台限制证明。

## 跨日分离式 schedule / verify

长达一天的 smoke 不能依赖当前终端持续运行，也不能让临时 sqlite 构建 hook 在仓库保留一天。因此新增：

```text
scripts/smoke_device_android_background_dreaming_cross_day.sh
```

支持：

```bash
# 调度并退出；恢复正式包与仓库，仅保留隔离 job 和状态文件
scripts/smoke_device_android_background_dreaming_cross_day.sh schedule 37101FDJH0077P

# 只读查看 job / pid / prefs 状态
scripts/smoke_device_android_background_dreaming_cross_day.sh status

# 结果尚未完成时退出 3 且不清理；完成后验证并清理
scripts/smoke_device_android_background_dreaming_cross_day.sh verify

# 任意时间主动撤销隔离任务并恢复正式包
scripts/smoke_device_android_background_dreaming_cross_day.sh cleanup
```

主脚本的 detached 模式只允许：

```text
TRIGGER_MODE=natural
BACKGROUND_PROCESS_MODE=kill
BACKGROUND_DETACH_AFTER_SCHEDULE=1
```

状态文件通过 `umask 077` 和 shell `printf %q` 写入，不包含用户聊天或接口密钥，只记录设备、包名、正式包 identity、旧 pid、job id、时间和证据路径。schedule 退出时 cleanup 会恢复 `pubspec.yaml` / `pubspec.lock`、启动正式包，但在明确 detached 状态下保留隔离包与 JobScheduler job。

为保证跨日任务实际有可整理内容，harness 不再让 seed 消息固定属于启动日，而是写入：

```text
scheduledMessageAt = DateTime.now() + initialDelay
```

并更新 SQLite `messages.created_at`。这样次日执行时，消息属于目标 dayKey，不会因为跨日边界返回 `notDue`。

短延迟自测：

- 30 秒 schedule 成功退出，正式包立即恢复，状态文件权限 0600；
- status 显示旧 pid 消失、job waiting；
- 提前 verify 返回 3，不卸载隔离包；
- 系统自然执行后独立 verify 得到 Dreaming / Reflection / history、无 pending，新 pid 不同于旧 pid并完成清理；
- 另调度 600 秒任务后立即执行 cleanup，隔离包、job 和状态文件均清除，正式包恢复。

验证：目标静态门禁 7 项、全量稳定门禁 524 项、analyze 通过。

真实跨日任务已在 Pixel 8 调度：

```text
state=/tmp/simichat-android-background-dreaming-cross-day.state
old pid=28141
job id=0
delaySeconds=86400
expectedDayKey=2026-07-15
job state=waiting
```

证据路径：

```text
/tmp/simichat-android-background-dreaming-cross-day-20260714141810.log
/tmp/simichat-android-background-dreaming-cross-day-20260714141810.xml
```

调度后正式包 pid `28280`，firstInstallTime / dataDir 不变，deep `ACTIVE`，仓库无 sqlite hook。当前只能记录“已安全调度”，必须等待次日执行：

```bash
scripts/smoke_device_android_background_dreaming_cross_day.sh verify
```

只有 verify 确认目标日期 Dreaming、Reflection 最近报告 / 历史、无 pending 并完成隔离包清理后，才能标记跨日验证通过。

最终依赖状态验证：

```text
workmanager / workmanager_android / workmanager_apple / workmanager_platform_interface = 0.8.0
Android arm64 debug APK 构建通过
iOS release --no-codesign 构建通过，Runner.app 33.3MB
全量稳定门禁 499 项通过
flutter analyze：No issues found
全量日志无 WARNING (drift)，无 multiple databases
```

全量门禁日志：

```text
/tmp/simichat_android_background_dreaming_full_gate_final.log
```

## 后台附加条件真机验证

新增安全入口：

```bash
scripts/smoke_device_android_background_dreaming_constraints.sh 37101FDJH0077P
```

脚本使用两个与正式包、跨日等待包都不同的隔离包：

```text
top.simitalk.aichat.chargingconstraintsmoke
top.simitalk.aichat.networkconstraintsmoke
```

每条路径都先等待 30 秒 initialDelay，再使用 `cmd jobscheduler run -s`；`-s` 要求全部真实约束满足，不允许像 `-f` 一样绕过技术约束。

Pixel 8 结果：

- 充电条件：`Requires: charging=true`，系统 `get-battery-charging=false` 时 CHARGING 位于 Unsatisfied constraints，严格运行被拒绝，证明阻塞有效。设备虽显示 `AC powered=true`，但当前充电策略返回 `status=4` / 非 charging；`cmd battery set status 2` 也未更新 JobScheduler 充电判定，因此本轮没有使用 `-f` 绕过，充电满足后的放行仍未证明。
- 非计费网络条件：关闭 Wi-Fi 后 CONNECTIVITY 不满足，严格运行被拒绝；恢复 `WIFI + NOT_METERED + VALIDATED` 后严格运行输出 `Running job`，66 秒完成 `status=completed digest=2026-07-14 reflection=2026-07-14`。隔离 prefs 含 `dreaming_digest_v1`、`assistant_reflection_v1`、`assistant_reflection_history_v1` 和 `requiresUnmeteredNetwork=true`，无 Reflection pending。
- cleanup 后 battery mock reset、Wi-Fi 恢复为开启、deep `ACTIVE`、正式包 pid `5380`，两个约束隔离包均卸载，仓库无 sqlite hook；原跨日 `backgroundsmoke` 包和 job id `0` 仍为 waiting，0600 状态文件未变。

证据：

```text
/tmp/simichat-android-dreaming-constraint-suite-20260714145948.log
/tmp/simichat-android-dreaming-charging-host-20260714145948.log
/tmp/simichat-android-dreaming-network-host-20260714145948.log
/tmp/simichat-android-dreaming-network-20260714145948.log
/tmp/simichat-android-dreaming-network-20260714145948.xml
/tmp/simichat-full-stability-constraints-device-20260714.log
```

新增真机约束脚本静态门禁后，全量稳定门禁 530 项通过，`flutter --no-version-check analyze --no-pub` 无问题。

## 尚未证明

- iOS BGTaskScheduler 系统后台 Dreaming；
- 充电条件满足后的真机放行；非计费网络条件阻塞 / 放行和充电条件阻塞已通过；
- 跨天与长时间 Doze、极低电量、OEM 严格后台限制，以及跨天自然调度可靠性；短时强制 deep idle 和 UI 进程死亡后的跨小时自然调度已通过；
- 模型驱动 Reflection 与真实模型长会话质量。
