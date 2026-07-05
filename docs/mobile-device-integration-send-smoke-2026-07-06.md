# 真机集成发送 smoke 验证记录（2026-07-06）

## 目标

补一个可重复执行的真机级发送验证入口，用设备内本地 OpenAI 兼容 mock 服务验证对话页真实链路：Flutter UI 输入 → `sendMessage` → OpenAI Chat SSE → assistant 落库 → UI 展示。

该验证不依赖外部 API Key，不访问真实模型，不提交用户数据。

## 新增验证入口

新增文件：`integration_test/mobile_real_send_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_send.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会精确备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，测试结束后无论成功失败都会恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

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

## iPhone13 尝试结果

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

结论：当前 iPhone13 构建 / 安装阶段可达，但 Flutter 测试运行器未成功发现 Dart VM Service；iOS 真机发送链路仍未完成，需要后续继续排查 Xcode 自动化权限、设备解锁前台状态、debug/test runner 启动方式或改用 `xcodebuild test` / XCUITest 路径。

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

结论更新：iPhone13 当前问题不是 `integration_test` 测试体、不是设备内 mock 服务、也不是旧 Runner 进程本身；更接近本机 Flutter→Xcode debug session 启动链路问题。后续优先验证 Xcode 自动化权限 / Xcode GUI `Product > Run` / DerivedData 清理 / `xcodebuild test` 或 XCUITest 替代路径。

## 验证与边界

本轮已验证：

- 新增跨平台 `integration_test` 真机发送 smoke 文件。
- 新增 `scripts/smoke_device_integration_send.sh`，封装临时 sqlite3 hook、真机测试和恢复流程。
- Pixel 8 真机通过设备内本地 mock 完成 UI→发送→SSE→DB→UI 闭环。
- 正式 `pubspec.yaml` 不保留临时 sqlite3 hook。
- `flutter --no-version-check analyze` 通过。

本轮未完成：

- iPhone13 真机发送链路仍因 Xcode debug session `CONFIGURATION_BUILD_DIR` 超时而未跑到测试体；普通 `flutter run --debug` 也复现同层错误。
- 未覆盖停止、重试、模型切换；这些已有 Pixel 8 手工真机 smoke 记录。
- 未覆盖真实外部模型 API。
