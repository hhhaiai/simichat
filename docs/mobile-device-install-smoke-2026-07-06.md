# 移动端真机覆盖安装与启动记录（2026-07-06）

## 目标

在不卸载、不清数据的前提下，把当前提交 `d67a6f4 feat: add local assistant reflection loop` 覆盖安装到在线真机，确认移动端基础安装 / 启动链路仍可用，为后续真机长会话、Dreaming 和 Reflection 质量评估做前置基线。

## 设备状态

`flutter --no-version-check devices` 检测到：

- Pixel 8：`37101FDJH0077P`，Android 16 API 36，可用。
- iPhone13：`00008110-0016349A3A20A01E`，iOS 26.5，可用。
- `people`、`biao的iPhone`、`iPhone-cqs` 当前为无线不可用或 `unavailable`，本轮不作为验证设备。

## Android Pixel 8

命令：

```bash
flutter --no-version-check build apk --debug
adb -s 37101FDJH0077P install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s 37101FDJH0077P shell dumpsys package top.simitalk.aichat | grep -E 'firstInstallTime|lastUpdateTime|versionName|versionCode|dataDir'
adb -s 37101FDJH0077P shell monkey -p top.simitalk.aichat -c android.intent.category.LAUNCHER 1
adb -s 37101FDJH0077P shell pidof top.simitalk.aichat
adb -s 37101FDJH0077P shell dumpsys window | grep -E 'mCurrentFocus|top.simitalk.aichat'
```

结果：

- `flutter build apk --debug` 成功，产物：`build/app/outputs/flutter-apk/app-debug.apk`。
- `adb install -r` 返回 `Success`，未执行卸载或清数据。
- 包信息：
  - `versionCode=1`
  - `versionName=1.0.0`
  - `firstInstallTime=2026-07-02 23:29:09`
  - `lastUpdateTime=2026-07-06 02:17:48`
  - `dataDir=/data/user/0/top.simitalk.aichat`
- `monkey` 启动成功。
- `pidof top.simitalk.aichat` 返回 `15642`。
- `dumpsys window` 显示当前焦点包含 `top.simitalk.aichat/top.simitalk.aichat.MainActivity`。

结论：Pixel 8 当前提交覆盖安装并启动成功，应用数据目录保持同一包名目录，未清数据。

## iPhone13

命令：

```bash
flutter --no-version-check build ios --release
xcrun devicectl device install app --device 00008110-0016349A3A20A01E build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device 00008110-0016349A3A20A01E top.simitalk.aichat
xcrun devicectl device info apps --device 00008110-0016349A3A20A01E
xcrun devicectl device info processes --device 00008110-0016349A3A20A01E
```

结果：

- `flutter build ios --release` 成功，产物：`build/ios/iphoneos/Runner.app`，大小约 `33.0MB`。
- `devicectl device install app` 成功：
  - `bundleID: top.simitalk.aichat`
  - `installationURL: file:///private/var/containers/Bundle/Application/14463BF7-4A98-4004-8227-F7A0271DF996/Runner.app/`
  - `databaseUUID: D546E20B-9FCA-4BBB-A2B6-CBC0B3A56823`
  - `databaseSequenceNumber: 4168`
- `devicectl device process launch` 已发起但长时间未返回，本轮手动中断。
- 后续 `device info apps` 可见：`SimiAIChat top.simitalk.aichat 1.0.0 1`。
- 后续 `device info processes` 可见 Runner 进程：`78854 /private/var/containers/Bundle/Application/.../Runner.app/Runner`。

历史结论：iPhone13 当时 release 覆盖安装成功，安装后存在 Runner 进程；`devicectl process launch` 命令未正常返回。后续已用 `scripts/smoke_ios_release_install_launch.sh` 复验 release launch 成功。

## 当前边界

本轮只验证安装与启动 / 进程可见性，不覆盖：

- 长会话真实滚动、发送、停止、重试。
- 真机 Dreaming 手动运行和本地反思弹窗交互。
- 语音长时间播报、来电 / 音频焦点中断。
- 网络切换、后台恢复、Relay 长时间运行。

## 下一步

1. 在 Pixel 8 上做真实长会话输入 / 滚动 / 历史搜索 / 设置页反思弹窗检查。
2. 在 iPhone13 上复核 `devicectl process launch` 卡住原因，必要时用设备侧手动启动或 Xcode Instruments 辅助确认前台状态。
3. Dreaming + Reflection 真机质量评估已在 Pixel 8 上补充完成：72 条 seed 长会话可见，手动 Dreaming 生成 digest，Reflection 生成报告并展示短期提示预览；详见 `docs/mobile-long-conversation-reflection-smoke-2026-07-06.md`。


## iPhone13 release 脚本复验（2026-07-06）

根据最新运行约束，iOS 真机必须使用 release 版本，debug / integration debug runner 不再作为 iOS 有效运行证明。本轮新增专用脚本：

```bash
./scripts/smoke_ios_release_install_launch.sh <device-id>
```

脚本行为：

- 执行 `flutter --no-version-check build ios --release`。
- 使用 `xcrun devicectl device install app` 覆盖安装 `build/ios/iphoneos/Runner.app`。
- 使用 `xcrun devicectl device process launch --terminate-existing --timeout 30 top.simitalk.aichat` 启动 release app。
- 校验 `device info apps` 包含 `top.simitalk.aichat`。
- 校验 `device info processes` 可见 `Runner.app/Runner`。
- 支持传入 CoreDevice UUID 或 UDID；`devicectl` 可直接识别。

复验命令：

```bash
./scripts/smoke_ios_release_install_launch.sh CAFC7AFA-4565-5C8D-B724-090061D144D0
```

结果：

```text
Building top.simitalk.aichat for device (ios-release)...
Xcode build done. 10.5s
✓ Built build/ios/iphoneos/Runner.app (33.1MB)
Installed release app:
- bundleID: top.simitalk.aichat
- installationURL: file:///private/var/containers/Bundle/Application/E02133DA-6E36-4BC6-B845-258CCEC28AB1/Runner.app/
- databaseSequenceNumber: 4264
Launched release app:
- pid: 79321
Verified installed app listing contains top.simitalk.aichat
Verified release Runner process is visible
```

结论：iPhone13 release 构建、覆盖安装、启动和进程可见性已通过；iOS 运行证明以后以该 release 脚本为准。

## Android release 稳定运行复验（2026-07-06 14:09）

用户确认 `people` 是主力机后，本轮不再触碰 people；所有新增复验先放在 Android Pixel 8（`37101FDJH0077P`）上完成。目标是在更新主力机前先证明当前工作树的测试门禁、Dreaming 基准、关键真机 smoke 和 Android release 覆盖安装 / 启动都稳定。

### 本轮命令与结果

```bash
./scripts/smoke_full_stability_gate.sh -r expanded
flutter --no-version-check analyze --no-pub
./scripts/benchmark_dreaming.sh -r expanded
./scripts/smoke_device_integration_send.sh 37101FDJH0077P
./scripts/smoke_device_integration_settings.sh 37101FDJH0077P
./scripts/smoke_device_integration_native_audio_player.sh 37101FDJH0077P
./scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

结果：

- 全量稳定性门禁通过：`344` 个 Flutter 测试全部通过。
- `flutter --no-version-check analyze --no-pub` 通过，无 analyzer 问题。
- Dreaming 基准通过：`1000` 条消息，`insert_ms=292`，`run_ms=44`，`digest_elapsed_ms=41`，`session_count=1`，`memory_candidates=40`，`has_content=true`。
- `scripts/benchmark_dreaming.sh` 曾因 `sqlite3` native asset 尝试从 GitHub 下载 `libsqlite3.arm64.macos.dylib` 超时而失败；已改为复用 `scripts/lib/release_pubspec_hook.sh` 临时启用 `sqlite3.source=system`，跑完自动恢复正式 `pubspec.yaml` / `pubspec.lock`，避免门禁依赖外网下载。
- Pixel 8 真机发送 smoke 通过：设备内 OpenAI 兼容 mock、UI 输入、SSE 回复、assistant 落库和 UI 展示闭环通过。
- Pixel 8 设置页 smoke 通过：主题切换、字体 120% 缩放持久化和返回首页闭环通过。
- Pixel 8 静音原生播放 smoke 通过：应用私有目录 WAV 播放后 `stop()`，收到 stopped 且无 error；测试 WAV 已为 zero-filled PCM，避免再次发出“嗯嗯”测试音。
- Android release 构建成功：`build/app/outputs/flutter-apk/app-release.apk`，大小约 `31.4MB`。
- `adb install -r` 覆盖安装成功，未执行卸载或清数据。
- 包信息：`versionCode=1`，`versionName=1.0.0`，`lastUpdateTime=2026-07-06 14:09:30`，`dataDir=/data/user/0/top.simitalk.aichat`。
- release 启动成功，`pidof top.simitalk.aichat` 返回 `30894`。
- 清空 logcat 后重启 release 并按 SimiAIChat app pid 观察 25 秒：`release_app_pid_logcat_fatal_markers=none`。
- `dumpsys window` 显示当前焦点为 `top.simitalk.aichat/top.simitalk.aichat.MainActivity`。
- `git diff --check`、相关 shell 脚本 `bash -n` 和正式 `pubspec.yaml` 临时 hook 残留检查均通过。

### 结论

Pixel 8 当前已处于 Android release 正式包运行状态；本轮未触碰 people。以当前证据看，更新主力机前的 Android 侧稳定性门禁通过。iOS 主力机后续如需更新，应继续只走 release 覆盖安装路径，不做 debug / integration runner 实验。

## Dreaming 长会话截断可见性补强（2026-07-06）

继续围绕 Dreaming 稳定性做代码级补强：此前 `DreamingService.runDailyDigest(maxMessages: 5000)` 会按上限读取当天原始消息，但 digest / Markdown 不会说明当天消息是否超过上限。长会话或重度使用场景下，用户和后续 Reflection 只能看到“已整理 N 条”，无法判断是否还有未整理内容。

### 变更

- `DreamingDigest` 新增：
  - `isTruncated`：当天原始消息是否超过本机整理上限。
  - `messageLimit`：本次整理实际使用的消息上限。
- `DreamingService.runDailyDigest` 改为读取 `effectiveMaxMessages + 1` 条原始消息探测是否截断；后续版本在截断时会再取最近 `effectiveMaxMessages` 条整理，避免突破既有性能边界。
- `DreamingDigest.toJson/fromJson` 支持新字段，旧 JSON 默认 `isTruncated=false` / `messageLimit=0`，兼容已有本地数据。
- `DreamingDigest.toMarkdown()` 在截断时增加提示：当天原始消息超过本机整理上限，本日报只整理最近 N 条原始消息。
- `scripts/benchmark_dreaming.sh` 复用临时 `sqlite3.source=system` hook，避免基准测试因为 GitHub sqlite3 native asset 下载超时而误失败；脚本退出后自动恢复正式 `pubspec.yaml` / `pubspec.lock`。

### 验证

```bash
./scripts/smoke_full_stability_gate.sh test/dreaming_service_test.dart -r expanded
./scripts/benchmark_dreaming.sh -r expanded
flutter --no-version-check analyze --no-pub
./scripts/smoke_full_stability_gate.sh -r expanded
```

结果：

- `test/dreaming_service_test.dart` 3 个测试通过，新增覆盖超过 `maxMessages` 时 `isTruncated=true`、`messageLimit=2`、只处理限定消息数、Markdown 出现截断提示、JSON 往返保留字段。
- Dreaming 1000 条消息基准通过：`run_ms=41`，`digest_elapsed_ms=39`，`memory_candidates=40`，`has_content=true`。
- `flutter --no-version-check analyze --no-pub` 通过，无问题。
- 全量门禁通过：`345` 个测试全部通过。
- `git diff --check` 通过，正式 `pubspec.yaml` 未残留临时 `hooks:` / `sqlite3.source=system`。

### 结论

Dreaming 在超长日对话场景下现在不会“静默只整理部分内容”；digest、持久化 JSON 和 Markdown 都能显式暴露截断事实，方便后续 UI、Reflection 或二次整理策略继续演进。

## Reflection 承接 Dreaming 截断事实（2026-07-06）

上一步 Dreaming 已能在超长日对话超过 `maxMessages` 时标记 `isTruncated` / `messageLimit`。本轮继续把这个事实传递到 Reflection，避免本地反思和下一轮短期提示把“只整理了最近 N 条”的日报误当成完整画像来源。

### 变更

- `ReflectionReport` 新增：
  - `sourceDigestIsTruncated`
  - `sourceDigestMessageLimit`
- `ReflectionService.buildDailyReflection()` 会从 `DreamingDigest.isTruncated` / `messageLimit` 复制来源完整性字段。
- 当来源 Dreaming 被截断时，Reflection 会优先添加高优先级结论 `整理完整性`，提醒后续画像和反思可能缺少当天后半段线索。
- 短期行动项会提示：不要把本次 Dreaming 当作当天完整画像，需要分段整理或补跑更高上限后再确认长期记忆。
- `ReflectionReport.toMarkdown()` 在截断时增加提示，说明本反思不代表当天全部对话。
- JSON 编解码兼容旧数据，旧报告默认 `sourceDigestIsTruncated=false` / `sourceDigestMessageLimit=0`。

### 验证

```bash
./scripts/smoke_full_stability_gate.sh test/reflection_service_test.dart -r expanded
flutter --no-version-check analyze --no-pub
./scripts/smoke_full_stability_gate.sh -r expanded
```

结果：

- `test/reflection_service_test.dart` 5 个测试通过，新增覆盖截断来源会进入 Reflection 字段、Markdown、JSON 往返和 `buildAssistantReflectionSystemPrompt()` 短期提示。
- `flutter --no-version-check analyze --no-pub` 通过，无问题。
- 全量门禁通过：`346` 个测试全部通过。

### 结论

长会话超限时，链路现在是：Dreaming 发现截断 → Digest 持久化截断事实 → Reflection 报告和短期提示继承该事实。这样助手不会静默基于部分日报做完整长期画像判断。


## Dreaming 截断时保留最新上下文（2026-07-06）

上一步 Dreaming 已能显式标记超长日对话被 `maxMessages` 截断，但实际整理样本仍来自当天最早 N 条消息。对智能助理来说，最新用户任务、最新约束和最新上下文通常更重要；如果只保留最早内容，可能漏掉当天后续推进结论。

### 变更

- `MessageDao` 新增 `getLatestOriginalMessagesInTimeRange()`，可在给定日期范围内按 `createdAt desc` 读取最近 N 条原始消息。
- `DreamingService.runDailyDigest()` 保持普通日对话只查一次升序消息；只有探测到超过上限时，才二次读取最近 `maxMessages` 条，并反转回升序后再整理。
- Dreaming Markdown 截断提示明确为“只整理最近 N 条”。
- 回归测试改为确认超限时保留第 1 / 第 2 条最新消息，丢弃第 0 条最早消息。

### 验证

```bash
./scripts/smoke_full_stability_gate.sh test/dreaming_service_test.dart -r expanded
./scripts/benchmark_dreaming.sh -r expanded
flutter --no-version-check analyze --no-pub
./scripts/smoke_full_stability_gate.sh -r expanded
```

结果：

- `test/dreaming_service_test.dart` 3 个测试通过，截断用例确认只保留最近消息。
- Dreaming 1000 条消息基准通过：`run_ms=48`，`digest_elapsed_ms=45`，`memory_candidates=40`。
- `flutter --no-version-check analyze --no-pub` 通过。
- 全量门禁通过：`346` 个测试全部通过。

### 结论

超长日对话现在不会优先保留过早上下文，而是保留最近可执行上下文，同时继续通过 `isTruncated` / `messageLimit` 向 Reflection 暴露“这不是完整日报”。

## Android release 稳定运行复验（2026-07-06 14:37）

按用户要求，本轮不触碰 `people` 主力机，只在 Android Pixel 8 `37101FDJH0077P` 做 release 覆盖安装和稳定性验证。

### 命令

```bash
./scripts/smoke_full_stability_gate.sh -r expanded
flutter --no-version-check analyze --no-pub
git diff --check
./scripts/benchmark_dreaming.sh -r expanded
./scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
# 清 log 后，不清数据 force-stop，再启动 release 包并按 pid 观察 25 秒
adb -s 37101FDJH0077P logcat -c
adb -s 37101FDJH0077P shell am force-stop top.simitalk.aichat
adb -s 37101FDJH0077P shell monkey -p top.simitalk.aichat -c android.intent.category.LAUNCHER 1
```

### 结果

- 全量门禁：`346` 个测试全部通过。
- `flutter --no-version-check analyze --no-pub`：无问题。
- `git diff --check`：无输出。
- Dreaming 1000 条消息基准：`run_ms=57`，`digest_elapsed_ms=53`，`memory_candidates=40`，`has_content=true`。
- release APK：`build/app/outputs/flutter-apk/app-release.apk`，约 `31.5MB`。
- 覆盖安装：`adb install -r` 成功；未执行卸载、未清应用数据。
- 包信息：`versionName=1.0.0`，`versionCode=1`，`firstInstallTime=2026-07-06 14:09:30`，`lastUpdateTime=2026-07-06 14:37:36`，`dataDir=/data/user/0/top.simitalk.aichat`。
- 启动稳定性：release pid `32365`，按 pid 观察 25 秒，采集日志 32 行，未发现 `FATAL EXCEPTION` / `AndroidRuntime` / `ANR` / `Fatal signal` / `SIGABRT` / `crash`。
- 前台状态：`topResumedActivity=ActivityRecord{... top.simitalk.aichat/.MainActivity ...}`。
- 临时 hook 清理：正式 `pubspec.yaml` / `pubspec.lock` 不包含 `hooks:` 或 `sqlite3.source=system`。

### 结论

当前工作树在本地全量门禁、Dreaming 长会话基准和 Android release 真机稳定运行三层均通过；Pixel 8 已处于 release 正式包运行状态。本轮没有触碰 `people` 主力 iPhone。

## Dreaming 已整理 / 总量缺口可见性（2026-07-06）

在“超长日对话只整理最近 N 条”的基础上，本轮继续补齐量化缺口，避免只看到“整理了 N 条”而不知道当天实际有多少条。

### 变更

- `MessageDao` 新增 `countOriginalMessagesInTimeRange()`，Dreaming 运行前先统计当天原始消息总量。
- `DreamingDigest` 新增 `totalOriginalMessageCount`；Markdown / JSON 同时记录“已整理原始消息数”和“当天原始消息总数”。
- 截断提示明确为：当天共有多少条原始消息，本日报只整理最近多少条。
- `ReflectionReport` 新增 `sourceDigestTotalOriginalMessageCount`；Reflection Markdown 和短期提示显示类似 `2 / 5` 的整理覆盖比例。
- 旧 JSON 兼容：缺少总数字段时，用已有 `originalMessageCount` 回填。

### 验证

- 全量门禁：`./scripts/smoke_full_stability_gate.sh -r expanded`，`346` 个测试通过。
- 静态分析：`flutter --no-version-check analyze --no-pub` 通过。
- Dreaming 基准：1000 条消息 `run_ms=57` / `digest_elapsed_ms=53` / `memory_candidates=40`。

### 结论

长会话被截断时，现在链路会保留三个事实：当天总量、已整理数量、只整理最近消息。Reflection 和下一轮短期提示可以基于 `已整理 / 总量` 判断缺口，不会把部分日报当作完整画像来源。

## people 主力机 release 覆盖更新（2026-07-06）

本轮先在 Android Pixel 8 完成 release 稳定门禁，并确认本地全量测试、静态分析、`git diff --check` 和临时 hook 清理均通过。随后 `people` 设备从 `unavailable` 变为 `available (paired)`，按用户约束只执行 iOS release 覆盖安装 / 启动，不跑 debug / integration runner，不卸载、不清数据。

### 命令

```bash
./scripts/smoke_ios_release_install_launch.sh BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D
```

### 结果

```text
Xcode build done. 75.1s
✓ Built build/ios/iphoneos/Runner.app (33.2MB)
Installed release app:
- bundleID: top.simitalk.aichat
- installationURL: file:///private/var/containers/Bundle/Application/2A23A22A-ED85-41BD-BF42-646607CD66AE/Runner.app/
- databaseSequenceNumber: 6216
Launched release app:
- pid: 64943
Verified installed app listing contains top.simitalk.aichat
Verified release Runner process is visible
```

补充复查：

- `device info processes` 可见：`64943 ... /Runner.app/Runner`。
- `device info apps` 可见：`SimiAIChat top.simitalk.aichat 1.0.0 1`。
- 正式 `pubspec.yaml` / `pubspec.lock` 不包含 `hooks:` 或 `sqlite3.source=system`。
- `git diff --check` 无输出。
- 脚本完成后的最终复查中，`xcrun devicectl list devices` 又显示 `people unavailable`，继续查询 apps / processes 返回 CoreDevice 1011，因此没有追加交互测试。

### 结论

`people` 主力机已完成 release 覆盖更新并在脚本内启动成功；本轮没有使用 iOS debug / integration runner，也没有卸载或清理应用数据。后续手工 UI / 长时间交互需要等 `people` 再次可用后继续复验。

## 主力机不触碰的最终稳定复核（2026-07-06 15:09）

本轮按“先确保真机稳定运行，必要测试优先 Android，`people` 是主力机”的约束执行：当前 `people` 在 CoreDevice 中为 `unavailable`，因此没有对主力 iPhone 执行安装、启动或交互 smoke；只在 Pixel 8 测试机和本地构建环境复核。

### 命令与结果

```bash
git diff --check
flutter --no-version-check analyze
scripts/smoke_full_stability_gate.sh -r expanded
scripts/benchmark_dreaming.sh -r expanded
scripts/smoke_device_integration_send.sh 37101FDJH0077P
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
flutter --no-version-check build ios --release
```

- `git diff --check`：无输出。
- `flutter --no-version-check analyze`：无问题。
- 全量稳定门禁：`scripts/smoke_full_stability_gate.sh -r expanded`，`348` 项测试通过。
- Dreaming 1000 条消息基准：`run_ms=48`，`digest_elapsed_ms=46`，`memory_candidates=40`，`has_content=true`。
- Pixel 8 真机集成发送：`scripts/smoke_device_integration_send.sh 37101FDJH0077P` 通过，设备内 OpenAI mock 覆盖 UI 输入 → SSE → assistant 落库 / 展示闭环。
- Android release 恢复：真机集成测试后立即恢复普通 release，`app-release.apk` 约 `31.5MB`，`adb install -r` 成功，启动 pid `4047`，20 秒后仍为 `4047`，logcat 未发现 crash。
- Android 最终包信息：`versionName=1.0.0`，`versionCode=1`，`dataDir=/data/user/0/top.simitalk.aichat`，`firstInstallTime=2026-07-06 15:07:44`，`lastUpdateTime=2026-07-06 15:07:44`。
- iOS 普通 release 候选构建通过：`build/ios/iphoneos/Runner.app`，约 `33.2MB`。
- 构建后复查：`people` 仍为 `unavailable`，未触碰主力机。
- 正式 `pubspec.yaml` / `pubspec.lock` 不包含临时 `hooks:` 或 `sqlite3.source=system`。

### 注意

Android `integration_test` 会安装 debug 包，测试机可能被 Flutter 工具重建应用数据；因此它只用于 Pixel 8 测试机，不作为 `people` 主力 iPhone 的更新路径。`people` 仍只允许走普通 iOS release 覆盖安装脚本，并且必须在设备可用 / 解锁后执行。


## Android release 覆盖安装复验（2026-07-06 15:33）

本轮继续遵守“people 是主力机，先用 Android 验证”的约束；未对 people 执行安装或实验性测试。完成离线发送 / 联网恢复提示加固并通过全量门禁后，在 Pixel 8 复验普通 release 覆盖安装与启动。

命令：

```bash
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

结果：

- `flutter --no-version-check build apk --release --no-pub --target-platform android-arm64` 成功，产物 `build/app/outputs/flutter-apk/app-release.apk`，大小约 `31.5MB`。
- `adb install -r` 返回 `Success`，未执行卸载或清数据。
- `monkey` 启动 `top.simitalk.aichat` 成功。
- 包信息：`versionCode=1`、`versionName=1.0.0`、`firstInstallTime=2026-07-06 15:07:44`、`lastUpdateTime=2026-07-06 15:33:20`、`dataDir=/data/user/0/top.simitalk.aichat`。
- `pidof top.simitalk.aichat` 返回 `5312`，release 进程可见。

结论：Pixel 8 当前已更新到普通 release 包并能启动；覆盖安装保留数据证据成立。people 主力机本轮未触碰，后续如需更新仍只走 iOS release 覆盖安装路径。
