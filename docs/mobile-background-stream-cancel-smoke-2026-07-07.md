# Android 后台流式取消真机 smoke（2026-07-07）

## 目标

补齐“后台未完成请求恢复”的设备侧验证：在 Android 真机上启动一个真实的 OpenAI Chat 兼容慢流请求，应用进入非前台生命周期后必须取消当前流式生成，回到前台后保留可重试错误提示，不把未完成回复落库为 assistant 消息。

## 实现

- `integration_test/mobile_background_stream_cancel_smoke_test.dart`
  - 在 Pixel 8 / Android integration runner 内启动本机 `HttpServer`，模拟 `/v1/chat/completions` 慢 SSE。
  - 使用内存 SQLite seed 一个 OpenAI Chat 渠道、模型和会话。
  - UI 输入 `background stream cancel smoke 20260707` 并点击发送。
  - 等待 mock 服务收到真实 `/v1/chat/completions` 请求，且 `streamStateProvider(sessionId)` 进入 `isStreaming=true` / `isWaitingForFirstToken=true`。
  - 在设备 integration 流程内触发 `AppLifecycleState.inactive` / `resumed`，验证生命周期恢复后的用户可见状态。
  - 断言：
    - `streamState.isStreaming == false`。
    - `streamState.error == backgroundStreamingInterruptedMessage`。
    - 页面显示 `应用进入后台，已停止本次生成，回到前台后可重试。`。
    - 页面显示 `已停止后台生成，可点“重试”继续`。
    - SharedPreferences 中 `simichat.background_interrupted_session_id` 已被同进程恢复提示消费。
    - SQLite 中只有 user 消息，没有 assistant 半截回复。
    - mock 收到 1 次 `/v1/chat/completions`，模型为 `background-stream-cancel-model`，`stream=true`。
- `scripts/smoke_android_background_stream_cancel.sh`
  - Android adb 设备专用入口；iOS 仍要求 release-only 证明。
  - 临时启用 `sqlite3.source=system` hook，退出后恢复 `pubspec.yaml` / `pubspec.lock`。
  - 运行 `flutter --no-version-check test integration_test/mobile_background_stream_cancel_smoke_test.dart -d <device> --no-pub -r expanded`。
- `lib/shared/providers/chat_provider.dart`
  - 新增 `_backgroundStreamCancellationErrors`，只记录带错误提示的后台取消。
  - `cancelStreaming(..., error: backgroundStreamingInterruptedMessage)` 会先记录后台取消错误，再取消上游 `CancelToken`。
  - `_runAssistantResponse()` 在等待 completer 返回后，如果发现该 session 是后台取消，立即恢复 `StreamState(error: ...)` 并 return，不再把未完成内容作为 assistant 回复落库。
  - 手动停止不传 `error`，保留原有手动停止路径。

## 红灯记录

- 新增 manifest 约束后，目标测试先失败于缺少 `scripts/smoke_android_background_stream_cancel.sh` / `integration_test/mobile_background_stream_cancel_smoke_test.dart`。
- 首轮真实设备慢流测试使用 adb Home / monkey 拉回时，debug integration runner 在长连接场景下会丢失可启动 Activity，无法稳定作为证明；因此本 smoke 改为“设备内真实 HTTP 慢流 + integration 生命周期注入”，物理 Home 恢复仍由既有 `scripts/smoke_android_background_restore.sh` 覆盖。
- 调整为设备内 lifecycle 后，旧实现红灯失败于真实取消抛出 `DioException [request cancelled]`，并伴随后台恢复后异步流程继续触碰已 dispose provider 的风险。
- 修复后，目标真机 smoke 通过。

## 验证记录

### 2026-07-07 取消传播修复后复验

在补 `cancelStreaming()` 显式取消订阅、`openSseStream()` SSE 取消传播后，Pixel 8 复跑本 smoke 先红灯暴露回归：

```text
DioException [request cancelled]: The request was manually cancelled by the user.
Error: 用户取消
Bad state: Tried to read a provider from a ProviderContainer that was already disposed
```

修复：

- `cancelStreaming()` 对 `subscription.cancel()` 的 Future 增加 `catchError((_) {})`，避免预期取消错误成为未处理异步异常。
- `openSseStream()` 的 cancellation-aware wrapper 在 `CancelToken` 已取消时吞掉 `DioExceptionType.cancel`，把它视为正常取消结束。
- `_showBackgroundInterruptedRetryPromptIfNeeded()` 开头补 `mounted` guard，避免测试 teardown 或真实页面销毁后 lifecycle 回调继续读取已 dispose 的 provider。

复验命令：

```bash
./scripts/smoke_android_background_stream_cancel.sh 37101FDJH0077P
./scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

结果：

```text
00:00 +0: mobile background stream cancel smoke keeps retry affordance
00:03 +1: (tearDownAll)
00:04 +1: All tests passed!
```

随后恢复普通 Android release：

```text
✓ Built build/app/outputs/flutter-apk/app-release.apk (31.5MB)
Installed Android release app:
    versionCode=1 minSdk=24 targetSdk=36
    versionName=1.0.0
    lastUpdateTime=2026-07-07 10:41:24
Launched Android release app:
- pid: 4150
```

本轮同时确认正式 `pubspec.yaml` / `pubspec.lock` 未残留 `sqlite3.source=system`，且 `integration_test` dev dependency 已恢复。

### 初始通过记录

```bash
scripts/smoke_android_background_stream_cancel.sh 37101FDJH0077P
```

结果：

```text
00:00 +0: mobile background stream cancel smoke keeps retry affordance
00:03 +1: (tearDownAll)
00:04 +1: All tests passed!
```

配套回归：

```bash
flutter --no-version-check test --no-pub -r expanded \
  test/mobile_main_flow_smoke_test.dart \
  test/release_send_smoke_manifest_test.dart
flutter --no-version-check analyze
git diff --check
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

结果：

- `mobile_main_flow_smoke_test.dart` + `release_send_smoke_manifest_test.dart` 共 20 项通过。
- `flutter analyze` 无问题。
- `git diff --check` 无输出。
- Pixel 8 已恢复普通 release 覆盖安装并启动：`app-release.apk` 31.5MB，`versionName=1.0.0`，`lastUpdateTime=2026-07-07 08:10:58`，release pid `22529`。
- 正式 `pubspec.yaml` / `pubspec.lock` 不保留 `sqlite3.source=system` hook，`integration_test` 依赖仍存在。

## 边界

- 本 smoke 验证真实 Android 设备内 HTTP 慢流请求和 lifecycle 取消逻辑，但不使用 adb Home 作为触发器；物理 Home 后草稿恢复已有独立 Pixel 8 smoke 覆盖。
- 当前仍是单 active session 的后台取消保护；多会话并行生成需要后续扩展队列。
- 仍不自动重发，用户需点击错误条或 SnackBar 的“重试”，避免重复 API 调用和费用。
