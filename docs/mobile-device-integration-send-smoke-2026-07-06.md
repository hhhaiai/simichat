# 真机集成发送 smoke 验证记录（2026-07-06）

## 目标

> **iOS 运行边界更新**：用户已明确 iOS 必须使用 release 版本，否则不能作为有效运行证明。因此本文件中的 iPhone13 debug / integration_test 记录只保留为排障历史；iOS 有效运行证明以 `scripts/smoke_ios_release_install_launch.sh` 和 `docs/mobile-device-install-smoke-2026-07-06.md` 的 release 结果为准。`scripts/smoke_device_integration_send.sh` 现在会拒绝 iOS 设备并提示改用 release smoke。


补一个可重复执行的真机级发送验证入口，用设备内本地 OpenAI 兼容 mock 服务验证对话页真实链路：Flutter UI 输入 → `sendMessage` → OpenAI Chat SSE → assistant 落库 → UI 展示。

该验证不依赖外部 API Key，不访问真实模型，不提交用户数据。

## 新增验证入口

新增文件：`integration_test/mobile_real_send_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_send.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；若传入 iOS CoreDevice UUID，脚本会通过 `devicectl device info details` 自动解析为 Flutter 可识别的硬件 UDID；iOS 运行前还会通过 `devicectl device info processes` 清理残留 `Runner.app/Runner` 测试进程，避免旧 VM service / Runner 干扰；脚本会精确备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，测试结束后无论成功失败都会恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

新增 dev 依赖：

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

iOS `Podfile.lock` 同步增加 `integration_test` 插件条目，便于后续在 iPhone 真机继续复跑。

## 测试设计

测试在设备进程内启动一个 `dart:io` HTTP server：

- 绑定 `127.0.0.1:<random_port>`。
- 只处理 `POST /v1/chat/completions`。
- 校验请求中的 `model`、`stream` 和最后一条 user 消息。
- 返回 OpenAI Chat SSE chunk：`DEVICE integration reply 20260706`。

测试使用 `ProviderScope` 覆盖正常数据库 provider，注入内存 SQLite：

- channel：`Integration Mock OpenAI`。
- base URL：`http://127.0.0.1:<server.port>`。
- protocol：`openai_chat`。
- model：`integration-mock-model`。
- session：`真机集成发送 smoke`。

随后通过真实 Widget 交互执行：

1. 断言顶部模型显示 `Integration Mock OpenAI / integration-mock-model`。
2. 输入 `device integration send`。
3. 点击发送按钮。
4. 等待 DB 出现 assistant 消息。
5. 断言：
   - user 消息落库为 `device integration send`。
   - assistant 回复落库为 `DEVICE integration reply 20260706`。
   - assistant `channelModelId=integration-model`。
   - UI 显示 `DEVICE integration reply 20260706`。
   - mock 收到 1 个 `/v1/chat/completions` 请求。
   - mock 请求中 `model=integration-mock-model`、`stream=true`、`lastUser=device integration send`。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

由于本机环境无法稳定下载 sqlite3 native asset，本轮按既有项目约束由 `scripts/smoke_device_integration_send.sh` 在命令内临时追加：

```yaml
hooks:
  user_defines:
    sqlite3:
      source: system
```

测试后已还原正式 `pubspec.yaml`，确认正式文件不保留该 hook。

命令：

```bash
./scripts/smoke_device_integration_send.sh 37101FDJH0077P
```

脚本内部执行：

```bash
flutter --no-version-check test integration_test/mobile_real_send_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.8s
00:00 +0: mobile device real send smoke uses local OpenAI mock
00:02 +1: (tearDownAll)
00:03 +1: All tests passed!
```

脚本复跑时曾暴露一次测试等待条件不完整：测试只等待 DB assistant 落库，随后立即断言 UI 文本，在真机负载下 UI provider 刷新可能晚于 DB。已按条件等待修正为继续等待 `DEVICE integration reply 20260706` 出现在 Widget 树中，再执行最终 UI 断言；修正后脚本复跑通过。

结论：Pixel 8 真机上，新增集成 smoke 可稳定验证 UI 输入、真实发送、SSE 解析、assistant 落库和 UI 展示闭环。

## iPhone13 历史尝试与排障

设备：iPhone13，UDID `00008110-0016349A3A20A01E`，iOS 26.5。

命令：

```bash
flutter --no-version-check test integration_test/mobile_real_send_smoke_test.dart \
  -d 00008110-0016349A3A20A01E --no-pub -r expanded
```

实际进展：

```text
Automatically signing iOS for device deployment using specified development team in Xcode project: 6X97AH5URL
Running pod install... 1,609ms
Running Xcode build...
Xcode build done. 46.7s
Installing and launching...
The Dart VM Service was not discovered after 60 seconds. This is taking much longer than expected...
```

随后检查设备：

- `xcrun devicectl device info lockState` 显示设备 `unlockedSinceBoot: true`。
- `xcrun devicectl device info processes` 只看到既有 Runner 进程，未发现新的可调试测试 Runner 进入稳定状态。
- 为避免长时间悬挂，已中止该次测试，输出 `No tests ran.`。

历史结论：当时 iPhone13 构建 / 安装阶段可达，但 Flutter 测试运行器未成功发现 Dart VM Service；后续已通过清理旧 Runner、使用 Flutter 识别的 UDID 并复跑 smoke 解决。

### 进一步定位：Xcode debug session 层（2026-07-06 03:47–03:55）

为排除旧进程干扰，先用 `devicectl` 查询并终止 iPhone13 上两个 Runner 进程：

- `com.aichat.aiChatApp` 旧包 Runner，pid `78854`。
- `top.simitalk.aichat` 新包 Runner，pid `79005`。

终止后再次运行：

```bash
./scripts/smoke_device_integration_send.sh 00008110-0016349A3A20A01E
```

本次不再只停在 Dart VM Service 提示，而是给出更明确错误：

```text
Xcode is taking longer than expected to start debugging the app.
Error starting debug session in Xcode: Timed out waiting for CONFIGURATION_BUILD_DIR to update.
Could not run build/ios/iphoneos/Runner.app on 00008110-0016349A3A20A01E.
Try launching Xcode and selecting "Product > Run" to fix the problem:
  open ios/Runner.xcworkspace
```

随后用普通 debug 启动作对照，并同样临时追加 `sqlite3.source=system` hook、避免 native asset 下载干扰：

```bash
flutter --no-version-check run \
  -d 00008110-0016349A3A20A01E \
  --debug --no-resident --no-publish-port --device-connection attached
```

普通 app debug 也在同一层失败：

```text
Xcode is taking longer than expected to start debugging the app.
Error starting debug session in Xcode: Timed out waiting for CONFIGURATION_BUILD_DIR to update.
Error launching application on iPhone13.
```

环境版本：

```text
Flutter 3.41.9 / Dart 3.11.5
Xcode 26.6 (17F113)
devicectl 518.33
iPhone13 iOS 26.5 23F77
```

历史结论更新：iPhone13 当时问题不是 `integration_test` 测试体、不是设备内 mock 服务；现象更接近本机 Flutter→Xcode debug session 启动链路问题。后续已用 Flutter UDID 和清理旧 Runner 的方式复跑通过。

### 进一步定位：直接 `xcodebuild` 与设备锁屏边界（2026-07-06 04:01–04:04）

为判断 `CONFIGURATION_BUILD_DIR` 超时是否来自项目构建配置，继续在同一 iPhone13 上绕过 Flutter CLI，直接执行 Xcode 构建。命令内仍临时追加 `sqlite3.source=system` hook，结束后恢复 `pubspec.yaml` / `pubspec.lock`，正式文件不保留 hook。

关键命令：

```bash
xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination 'id=00008110-0016349A3A20A01E' \
  -showBuildSettings

xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination 'id=00008110-0016349A3A20A01E' \
  build
```

`showBuildSettings` 可正常产出构建目录：

```text
BUILT_PRODUCTS_DIR = /Users/sanbo/Library/Developer/Xcode/DerivedData/Runner-edfmvbaktobcznbgqfxmjxwlhuce/Build/Products/Debug-iphoneos
CONFIGURATION_BUILD_DIR = /Users/sanbo/Library/Developer/Xcode/DerivedData/Runner-edfmvbaktobcznbgqfxmjxwlhuce/Build/Products/Debug-iphoneos
TARGET_BUILD_DIR = /Users/sanbo/Library/Developer/Xcode/DerivedData/Runner-edfmvbaktobcznbgqfxmjxwlhuce/Build/Products/Debug-iphoneos
```

直接构建结果：

```text
Project /Users/sanbo/code/simichat built and packaged successfully.
** BUILD SUCCEEDED **
```

随后使用该 Debug 产物做不卸载、不清数据的覆盖安装：

```bash
xcrun devicectl device install app \
  --device 00008110-0016349A3A20A01E \
  /Users/sanbo/Library/Developer/Xcode/DerivedData/Runner-edfmvbaktobcznbgqfxmjxwlhuce/Build/Products/Debug-iphoneos/Runner.app
```

安装成功：

```text
App installed:
• bundleID: top.simitalk.aichat
• installationURL: file:///private/var/containers/Bundle/Application/489769C9-148D-4122-9A50-23A508DE4D38/Runner.app/
• databaseSequenceNumber: 4208
```

但直接 launch 被设备当前锁屏状态拒绝：

```text
ERROR: The application failed to launch. (com.apple.dt.CoreDeviceError error 10002)
BSErrorCodeDescription = RequestDenied
NSLocalizedFailureReason = The request was denied by service delegate (SBMainWorkspace) for reason: Locked ("Unable to launch top.simitalk.aichat because the device was not, or could not be, unlocked").
FBSOpenApplicationErrorDomain error 7
BSErrorCodeDescription = Locked
```

同一时间 `xcrun devicectl device info lockState` 只显示 `passcodeRequired: true` 与 `unlockedSinceBoot: true`，不足以证明设备“当前已解锁”；`process launch` 的 JSON / stderr 明确给出当前 launch 阶段的 `Locked` 拒绝原因。

结论更新：

- 项目 iOS Debug 构建配置可正常解析 `CONFIGURATION_BUILD_DIR`。
- 直接 `xcodebuild build` 成功，说明当前不是项目无法 Debug 构建或签名失败。
- 同一 Debug 产物可通过 `devicectl install app` 覆盖安装到 `top.simitalk.aichat`，未执行卸载或清数据。
- 当时无法继续 iPhone13 集成发送 smoke 的直接阻塞变为：设备锁屏 / 无法被自动化解锁，SpringBoard 拒绝 launch。
- 后续设备可用后，已用 Flutter 识别的 UDID `00008110-0016349A3A20A01E` 复跑 `./scripts/smoke_device_integration_send.sh` 并通过。


## iPhone13 复跑通过（2026-07-06 11:42）

设备：iPhone13，Flutter / xcdevice 识别 UDID `00008110-0016349A3A20A01E`，CoreDevice UUID `CAFC7AFA-4565-5C8D-B724-090061D144D0`。

关键边界：`devicectl list devices` 展示的是 CoreDevice UUID，但 `flutter test -d` 需要使用 xcdevice / Flutter 设备列表中的 UDID。脚本已补自动解析；修复前误用 CoreDevice UUID 会得到：

```text
No supported devices found with name or id matching 'CAFC7AFA-4565-5C8D-B724-090061D144D0'.
```

本轮先用 `flutter --no-version-check devices -v` 确认 Flutter 可见设备：

```text
iPhone13 (mobile) • 00008110-0016349A3A20A01E • ios • iOS 26.5 23F77
```

随后第一次用 UDID 运行时，测试在 `Installing and launching...` 后长时间无 Dart 测试输出。诊断显示设备隧道、`iproxy` 和 Dart VM service 进程已启动，设备上有多个 `Runner.app/Runner` 进程；中断后输出 `No tests ran.`。为排除旧进程干扰，使用 `devicectl device info processes` 找到并终止测试 Runner 进程后复跑。

通过命令：

```bash
./scripts/smoke_device_integration_send.sh 00008110-0016349A3A20A01E
```

结果：

```text
00:00 +0: loading /Users/sanbo/code/simichat/integration_test/mobile_real_send_smoke_test.dart
Automatically signing iOS for device deployment using specified development team in Xcode project: 6X97AH5URL
Running Xcode build...
Xcode build done. 21.7s
Installing and launching... 20.2s
00:00 +0: mobile device real send smoke uses local OpenAI mock
00:12 +1: (tearDownAll)
00:13 +1: All tests passed!
```

历史结论：iPhone13 debug integration_test 曾跑通设备内本地 OpenAI SSE mock、UI 输入、`sendMessage`、assistant 落库和 UI 展示闭环；但按最新约束，iOS 必须 release 运行，因此该结果只作为排障历史，不作为 iOS 有效运行证明。脚本现已改为拒绝 iOS debug integration 路径。


## 脚本边界复验（2026-07-06）

用户确认 iOS 必须 release 版本后，`scripts/smoke_device_integration_send.sh` 已增加 iOS 防护：传入 iOS CoreDevice UUID 时会先解析为 Flutter UDID，然后拒绝 debug integration runner，并提示改用 release smoke：

```text
Resolved iOS device id CAFC7AFA-4565-5C8D-B724-090061D144D0 to Flutter UDID 00008110-0016349A3A20A01E
iOS devices must be validated with a release build for this project.
Use scripts/smoke_ios_release_install_launch.sh instead of the debug integration runner.
ios_debug_guard=OK
```

同一脚本继续支持 Android；复验命令：

```bash
./scripts/smoke_device_integration_send.sh 37101FDJH0077P
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.8s
00:00 +0: mobile device real send smoke uses local OpenAI mock
00:03 +1: (tearDownAll)
00:03 +1: All tests passed!
```

## 验证与边界

本轮已验证：

- 新增跨平台 `integration_test` 真机发送 smoke 文件。
- 新增 `scripts/smoke_device_integration_send.sh`，封装临时 sqlite3 hook、真机测试、iOS CoreDevice UUID 到 Flutter UDID 的自动解析、旧 Runner 清理和恢复流程。
- Pixel 8 真机通过设备内本地 mock 完成 UI→发送→SSE→DB→UI 闭环。
- 正式 `pubspec.yaml` 不保留临时 sqlite3 hook。
- `flutter --no-version-check analyze` 通过。
- iPhone13 直接 `xcodebuild -showBuildSettings` 可正常产出 `CONFIGURATION_BUILD_DIR`，直接 `xcodebuild build` 成功。
- iPhone13 同一 Debug `Runner.app` 可通过 `devicectl install app` 覆盖安装到 `top.simitalk.aichat`，未卸载、未清数据。
- iPhone13 历史上曾出现 `devicectl process launch` 被 SpringBoard 以 `RequestDenied` / `Locked` 拒绝；本轮设备可用后已用 Flutter UDID 复跑集成发送 smoke 并通过。
- iPhone13 debug integration 历史上曾完成 UI→发送→SSE→DB→UI 闭环，但不作为 iOS release 有效证明。

本轮未完成：

- iOS release 发送链路已通过 `scripts/smoke_ios_release_send.sh` 覆盖；停止、重试、模型切换仍只有 Pixel 8 手工真机 smoke 记录，iOS release 侧待补。
- 未覆盖真实外部模型 API。


## iOS release 发送链路补证（2026-07-06）

用户确认 iOS 必须 release 版本后，已新增 `scripts/smoke_ios_release_send.sh` 和 release-only harness。`people` 设备（`BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D`）已通过 release 发送闭环：

```text
iOS release send smoke passed:
- runId: ios-release-send-20260706121606
- reply: IOS release smoke reply 20260706
- request.path: /v1/chat/completions
- request.model: ios-release-smoke-model
- request.lastUser: ios release send smoke
Restoring normal iOS release build without smoke dart-defines...
Launched release app:
- pid: 64165
```

补充取证确认普通 release 进程可见，且 smoke 临时 Markdown 档案不残留：

```text
SMOKE_ARCHIVE_ABSENT
result.status=passed
result.runId=ios-release-send-20260706121606
```

详见 `docs/mobile-ios-release-send-smoke-2026-07-06.md`。

## Android 真机复跑与 release 恢复（2026-07-06 15:07）

本轮再次按主力机保护原则只在 Pixel 8 上复跑 Android 集成发送：

```bash
scripts/smoke_device_integration_send.sh 37101FDJH0077P
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 4.1s
00:00 +0: mobile device real send smoke uses local OpenAI mock
00:03 +1: (tearDownAll)
00:03 +1: All tests passed!
```

由于 Android `integration_test` 会安装 debug 包，本轮复跑后立即恢复普通 release：

```bash
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

恢复结果：

- `app-release.apk` 约 `31.5MB`。
- `adb install -r` 成功。
- 启动 pid `4047`，20 秒后仍为 `4047`。
- 最终包信息：`versionName=1.0.0`，`versionCode=1`，`dataDir=/data/user/0/top.simitalk.aichat`，`firstInstallTime=2026-07-06 15:07:44`，`lastUpdateTime=2026-07-06 15:07:44`。
- logcat crash 扫描无命中。

结论：Pixel 8 测试机发送闭环通过，且最终已恢复为普通 release 包；该 debug integration 路径不用于 `people` 主力 iPhone。
