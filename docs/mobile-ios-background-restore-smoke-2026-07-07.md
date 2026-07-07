# iOS release 后台恢复 smoke 入口与验证记录（2026-07-07）

## 目标

补齐移动端 P0 中 iOS 侧“后台恢复”的 release-only 可重复验证入口：应用以 release 包运行，进入后台 / 暂停后恢复前台，验证应用可恢复并记录结果。

## 入口

- `lib/core/smoke/release_background_smoke_harness.dart`
- `scripts/smoke_ios_release_background_restore.sh`

## 设计

- 仅通过 release dart-define 启用：
  - `SIMICHAT_RELEASE_BACKGROUND_SMOKE=true`
  - `SIMICHAT_RELEASE_BACKGROUND_SMOKE_RUN_ID=<run id>`
- 安装 smoke 包前先做 launch 预检：
  - `assert_device_unlocked_for_launch "$DEVICE_ID"`
  - 先尝试启动当前已安装的普通 `top.simitalk.aichat`。
  - 如果 CoreDevice JSON 明确包含 `Locked`，脚本直接退出 2，并提示 `Refusing to install iOS background smoke build while device is locked`。
  - 如果预检超时或其他失败导致不能证明设备已解锁，也直接退出 2，并提示 `Refusing to install iOS background smoke build because launch preflight did not prove the device is unlocked`。
  - 这样锁屏或 CoreDevice 状态不明确时都不会先覆盖安装 smoke dart-define 包，降低主力机被临时测试包污染的风险。
- harness 启动后在应用 Documents 写入：
  - `Documents/ai_chat/release_background_smoke/ios-release-background-smoke.json`
- ready 标记：
  - `status=ready`
  - `marker=SIMICHAT_RELEASE_BACKGROUND_READY`
- 脚本等待 ready 后执行：
  - `xcrun devicectl device process suspend --pid <pid>`
  - `xcrun devicectl device process resume --pid <pid>`
- harness 通过生命周期恢复或 timer tick gap 识别 suspend/resume，并写入 `status=passed`。
- 脚本默认 `RESTORE_NORMAL_RELEASE=1`，失败或成功后都会恢复普通 release 构建；失败时也会 best-effort 恢复，避免设备停留在 smoke dart-define 包。

## 已通过复跑记录（2026-07-07）

启动命令：

```bash
./scripts/smoke_ios_release_background_restore.sh 00008110-0016349A3A20A01E
```

设备解析：

- Flutter / USB 设备 ID：`00008110-0016349A3A20A01E`
- CoreDevice ID：`CAFC7AFA-4565-5C8D-B724-090061D144D0`
- 设备：iPhone13

结果：通过。脚本先构建带 `SIMICHAT_RELEASE_BACKGROUND_SMOKE=true` 的 release 包，覆盖安装并启动 `top.simitalk.aichat`，等待 ready marker 后执行 CoreDevice suspend / resume，harness 写入 passed：

```text
runId=ios-release-background-20260707100131
launch pid=80004
reason=process_suspend_resume_gap
gapMs=3214
elapsedMs=4483
marker=SIMICHAT_RELEASE_BACKGROUND_READY
```

脚本随后自动恢复普通 release 包并启动：

```text
Restoring normal iOS release build without background smoke dart-defines...
Installed release app:
- bundleID: top.simitalk.aichat
- databaseSequenceNumber: 4312
Launched release app:
- pid: 80007
```

结论：本轮已补齐 iPhone13 上的 iOS release 后台暂停 / 恢复自动化取证；该证明覆盖进程级 suspend / resume，不等同于真实用户手动 Home / 锁屏 / 解锁全链路。

## 历史阻塞记录（people 锁屏）

启动命令：

```bash
scripts/smoke_ios_release_background_restore.sh BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D
```

结果：未进入后台恢复验证阶段。release smoke 包构建和安装后，`devicectl process launch` 被设备锁屏拒绝：

```text
FBSOpenApplicationServiceErrorDomain RequestDenied
reason: Locked
Unable to launch top.simitalk.aichat because the device was not, or could not be, unlocked.
```

脚本随后触发失败清理并执行普通 release 恢复路径：

```text
flutter --no-version-check build ios --release
devicectl device install app --device BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D build/ios/iphoneos/Runner.app
```

恢复后取证：

- `build/ios/iphoneos/Runner.app` 约 32MB。
- `xcrun devicectl device info apps` 中仍可见：
  - `bundleIdentifier=top.simitalk.aichat`
  - `name=SimiAIChat`
  - `version=1.0.0`
  - `bundleVersion=1`
- `xcrun devicectl device info processes` 当前未见 `Runner.app/Runner` 进程；普通 release 覆盖安装已完成，但因为设备锁屏，本轮没有强制启动证明。

## 本地静态门禁

当前脚本 / harness 已被 `test/core/release_send_smoke_manifest_test.dart` 覆盖：

- release-only dart-define。
- 安装 smoke 包前的 Locked launch 预检。
- ready marker。
- `devicectl process suspend` / `resume`。
- 默认恢复普通 release。
- `simichat_release_pubspec_setup 0` / `simichat_release_pubspec_restore`。
- shell 语法检查。
- macOS `mktemp` 模板尾部 `XXXXXX` 约束。

补充验证：

```bash
flutter --no-version-check test --no-pub -r expanded \
  test/core/release_send_smoke_manifest_test.dart \
  --name "iOS release background restore smoke is release-only and restorable"
bash -n scripts/smoke_ios_release_background_restore.sh
flutter --no-version-check test --no-pub -r expanded \
  test/core/release_send_smoke_manifest_test.dart
```

结果：

- 红灯阶段目标用例失败于缺少 `assert_device_unlocked_for_launch`。
- 加固后目标用例通过。
- 全量 `test/core/release_send_smoke_manifest_test.dart` 7 项通过。

## 边界

- iPhone13 上的 release 进程级 suspend / resume 后台恢复已通过；people 主力机此前仍有一次锁屏阻塞历史，需设备解锁后按需复跑。
- Locked / timeout / 其他预检失败都会阻止安装 smoke 包；这牺牲首次安装便利性，换取不污染真机的安全边界。
- 未覆盖真实用户手动 Home / 锁屏 / 解锁后的恢复。
- 未覆盖后台未完成网络请求的恢复 / 重试队列。
