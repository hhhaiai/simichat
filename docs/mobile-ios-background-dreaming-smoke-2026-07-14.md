# iOS 系统后台 Dreaming / Reflection 真机验证（2026-07-14）

## 目标

确认 iOS release App 能注册 `BGProcessingTask`，系统真实保留 pending request，并在后台执行正式 Dreaming → Reflection → 持久化链路。前台启动 / 恢复 / 定时兜底不作为系统后台执行成功的替代证据。

## 安全边界

- 正式 Bundle ID：`top.simitalk.aichat`
- 隔离 Bundle ID：`top.simitalk.aichat.iosbackgroundsmoke`
- 隔离 task identifier：`top.simitalk.aichat.iosbackgroundsmoke.dreaming.processing`
- smoke 只使用 release 构建；安装前必须通过解锁 launch preflight。
- cleanup 必须卸载隔离 bundle、恢复 Xcode / Info.plist / AppDelegate / sqlite 配置，并重新启动正式 App。

## 当前实现

- `AppDelegate` 在 Flutter 启动完成前注册 BGTask identifier。
- Info.plist 声明 `BGTaskSchedulerPermittedIdentifiers` 和 `processing` background mode。
- Dart 使用一次性 `BGProcessingTask`，成功后排下一日，失败时排 15 分钟重试。
- 后台 runner 复用正式 Dreaming、待确认画像变更、Reflection、pending retry 和通知编排。
- `simichat/background_refresh_status` 原生通道支持：
  - `getBackgroundRefreshStatus`
  - `openAppSettings`
- 设置页在 denied / restricted 时显示“打开系统设置”和“重新检查”。
- 隔离 READY JSON 同时写入 `backgroundRefreshStatus` 和 `Workmanager().printScheduledTasks()`，防止插件吞掉 submit 错误后误报成功。

## 2026-07-14 15:19 真机结果

设备：

```text
iPhone13
00008110-0016349A3A20A01E
CoreDevice CAFC7AFA-4565-5C8D-B724-090061D144D0
```

执行：

```bash
scripts/smoke_ios_release_background_dreaming.sh \
  00008110-0016349A3A20A01E
```

已通过：

```text
launch preflight
release 构建
27.5MB Runner.app
隔离安装
隔离启动
READY JSON
原生 backgroundRefreshStatus 读取
失败 cleanup
正式 App 恢复
```

设备直接输出：

```json
{
  "marker": "SIMICHAT_IOS_BACKGROUND_DREAMING_READY",
  "status": "ready",
  "taskIdentifier": "top.simitalk.aichat.iosbackgroundsmoke.dreaming.processing",
  "backgroundRefreshStatus": "denied",
  "scheduledTasks": "[BGTaskScheduler] There are no scheduled tasks"
}
```

结论：当前不是 Dart 调度调用缺失，也不是 release 构建或 task identifier 错误；设备原生状态明确为 `denied`，系统因此没有保留 pending task。不能继续执行 LLDB 严格触发，也不能把前台兜底或代码测试标记为 iOS BGTask 真机成功。

## 用户恢复路径

Dreaming 设置页在状态为 denied / restricted 时提供：

```text
打开系统设置
重新检查
```

“打开系统设置”通过 `UIApplication.openSettingsURLString` 打开当前 App 设置；用户开启后台 App 刷新并返回后，可点“重新检查”刷新原生状态。状态变为 available 后，重新执行隔离 release smoke。

## 验证与清理

- iOS 状态 / release manifest / 设置页聚焦 27 项通过。
- 全量稳定门禁 531 项通过。
- `flutter --no-version-check analyze --no-pub` 无问题。
- 隔离 bundle 已卸载。
- 正式 `top.simitalk.aichat` 存在并运行 pid `86792`。
- 仓库无 sqlite hook，`git diff --check` 通过。
- Android 跨日 job id `0` 仍为 waiting，未受 iOS smoke 影响。

证据：

```text
/tmp/simichat-ios-background-dreaming-20260714151832.log
/tmp/simichat-full-stability-ios-settings-20260714.log
```

## 尚未证明

- `backgroundRefreshStatus=available` 后系统真实保留 pending request；
- LLDB `_simulateLaunchForTaskWithIdentifier:` 严格触发；
- iOS 后台 Dreaming 与 Reflection result JSON；
- 冷启动后持久化结果恢复；
- 系统自然调度时延与长时间可靠性。

## 2026-07-14 23:50 只读状态复查

为避免每次检查系统开关都重复执行 release 构建、隔离安装和清理，新增：

```bash
./scripts/check_ios_background_refresh_status.sh \
  CAFC7AFA-4565-5C8D-B724-090061D144D0
```

该入口只执行：

1. 确认正式 `top.simitalk.aichat` 已安装并保存 identity；
2. 启动已安装正式 App，通过 launch preflight 确认设备已解锁；
3. LLDB 只读调用 `UIApplication.backgroundRefreshStatus`；
4. `process detach`；
5. 再次比较正式 App identity。

明确不执行：

- Flutter / Xcode 构建；
- App 安装或卸载；
- bundle / task identifier 替换；
- sqlite hook；
- App 数据清理。

LLDB 使用系统自带的 arm64 `/usr/bin/true` 创建临时 target，再附加设备上的 Runner 进程；不依赖 `build/ios` 或本地 Runner 产物，因此清理 build 目录后仍可执行。

iPhone13 实时结果：

```text
IOS_BACKGROUND_REFRESH_STATUS_OK
raw=1
status=denied
```

因此当前仍不重复运行必然无法进入 pending 的 BGTask release smoke。状态变为 `raw=2 status=available` 后，才重新执行完整隔离 smoke。

取证：

```text
/tmp/simichat-ios-background-refresh-status-20260714235035.log
```

## 2026-07-15 01:47 LLDB 瞬时中断恢复

真机复查时出现一次辅助门禁波动：LLDB 已成功附加并停止正式 Runner，但执行 `UIApplication.backgroundRefreshStatus` 表达式时被临时 `SIGSTOP` 中断，导致脚本没有取得状态值并退出。正式 App、BGTask 实现和系统设置均未发生变化，随后手工复跑立即得到 `raw=1 status=denied`。

为避免把单次 LLDB 波动误判成 App 或系统状态失败，`scripts/check_ios_background_refresh_status.sh` 增加有界恢复：

- 首次读取失败后重新启动正式 App并获取新 pid；
- 最多执行 2 次 LLDB 读取，即只自动重试 1 次；
- 任意一次得到 `0 / 1 / 2` 即停止；
- 两次都失败时仍保留完整日志并返回失败；
- cleanup 继续比较正式 App identity；
- 不增加构建、安装、卸载、数据清理或工程替换操作。

验证：

- manifest 测试先红后绿，1 项通过；
- `bash -n` 与 `git diff --check` 通过；
- 使用 `/tmp` 临时 xcrun wrapper 注入第一次 LLDB 失败，脚本输出重试提示并在第二次真机读取成功；
- 最终状态仍为 `raw=1 status=denied`，因此仍不运行完整 BGTask release smoke。

取证：

```text
/tmp/simichat-ios-background-refresh-status-20260715014347.log
/tmp/simichat-ios-background-refresh-retry-20260715014745.log
```
