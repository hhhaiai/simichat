# Android 物理断网流式取消真机 smoke（2026-07-07）

## 目标

补齐移动端 P0 网络稳定性的一条设备侧证明：当前台已有真实流式模型请求进行中时，Android 真机发生物理网络断开，应用必须主动停止生成、保留可重试错误提示，不能继续显示“生成中”，也不能把半截 assistant 回复落库。

## 入口

- `integration_test/mobile_network_stream_cancel_smoke_test.dart`
- `scripts/smoke_android_network_stream_cancel.sh`

## 安全闸门

脚本默认拒绝真实断网：

```bash
scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P
```

必须显式授权：

```bash
REAL_NETWORK_TOGGLE=1 scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P
REAL_NETWORK_TOGGLE=1 NETWORK_TOGGLE_MODE=airplane scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P
```

脚本行为：

1. 启动前先关闭飞行模式、启用 Wi-Fi / data，尽量从在线状态开始。
2. 临时启用 `sqlite3.source=system` hook，退出时恢复 `pubspec.yaml` / `pubspec.lock`。
3. 运行 `integration_test/mobile_network_stream_cancel_smoke_test.dart`。
4. 测试在设备进程内启动 OpenAI Chat 兼容慢 SSE mock，UI 输入并发送 `network stream cancel smoke 20260707`。
5. 测试等待 mock 收到真实 `/v1/chat/completions` 且 `streamStateProvider(sessionId).isStreaming == true`，打印 `SIMICHAT_NETWORK_STREAM_CANCEL_READY`。
6. 脚本收到 READY 后按 `NETWORK_TOGGLE_MODE` 真实断开 Wi-Fi / data 或启用 airplane mode。
7. 测试确认应用进入 `networkStreamingInterruptedMessage` 错误态，打印 `SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED`。
8. 脚本收到 INTERRUPTED 后恢复飞行模式 / Wi-Fi / data。
9. 测试确认恢复后出现 `网络已恢复，可点“重试”继续`，且 SQLite 中只有 user 消息，没有 assistant 半截回复。
10. 退出时兜底恢复网络和 pubspec；若 INTERRUPTED 标记迟迟不出现，fallback timer 也会恢复网络。

## 红灯记录

首轮 Pixel 8 真实断网运行时，应用已经进入断网取消错误态，但测试额外等待设备内 loopback mock 在 8 秒内观察到 socket 断开，导致红灯：

```text
TimeoutException after 0:00:08.000000: Future not completed
```

结论：物理网络切换 smoke 不应把 loopback socket 底层关闭时机作为成败条件；取消传播已有独立 SSE / 后台慢流 smoke 覆盖。本 smoke 聚焦物理网络事件能否触发用户可见的流式取消、恢复提示和不落库半截回复。因此移除该过强断言，保留状态、UI、请求和数据库断言。

## 验证记录

本地门禁：

说明：直接 `flutter test` 在当前 macOS 环境曾受 sqlite3 native asset 下载失败影响；按本项目现有门禁改用 `scripts/smoke_full_stability_gate.sh` 临时 `sqlite3.source=system` hook 执行测试，退出后恢复正式 `pubspec.yaml` / `pubspec.lock`。


```bash
bash -n scripts/smoke_android_network_stream_cancel.sh
flutter --no-version-check test --no-pub -r expanded \
  test/release_send_smoke_manifest_test.dart \
  --name "Android network stream cancel"
flutter --no-version-check analyze
```

结果：脚本语法通过；manifest 安全闸门测试通过；静态检查无问题；全量理论门禁 `./scripts/smoke_full_stability_gate.sh -r expanded` 380 项通过。

Pixel 8 真机：

```bash
REAL_NETWORK_TOGGLE=1 scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P
```

结果：通过。

关键输出：

```text
00:00 +0: mobile network loss cancels in-flight stream on device
SIMICHAT_NETWORK_STREAM_CANCEL_READY
Disabling Wi-Fi and mobile data on Android test device 37101FDJH0077P
SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED
Restoring Android network after stream-interrupted marker.
00:07 +1: (tearDownAll)
00:07 +1: All tests passed!
```

随后恢复普通 Android release：

```bash
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

结果：通过。

关键输出：

```text
✓ Built build/app/outputs/flutter-apk/app-release.apk (31.5MB)
Performing Streamed Install
Success
Installed Android release app:
    versionCode=1 minSdk=24 targetSdk=36
    versionName=1.0.0
    lastUpdateTime=2026-07-07 11:11:44
      dataDir=/data/user/0/top.simitalk.aichat
      firstInstallTime=2026-07-07 11:11:44
Launched Android release app:
- pid: 7197
```

恢复后复核 Pixel 8 网络状态：

```text
cmd connectivity airplane-mode -> disabled
Wi-Fi is enabled
Active default network: WIFI CONNECTED / IS_VALIDATED
SSID="shufang_5G" IP=192.168.50.159
```

### 2026-07-07 airplane mode 复跑

命令：

```bash
REAL_NETWORK_TOGGLE=1 NETWORK_TOGGLE_MODE=airplane scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P
```

结果：通过。

关键输出：

```text
00:00 +0: mobile network loss cancels in-flight stream on device
SIMICHAT_NETWORK_STREAM_CANCEL_READY
Enabling airplane mode on Android test device 37101FDJH0077P
SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED
Restoring Android network after stream-interrupted marker.
00:07 +1: (tearDownAll)
00:07 +1: All tests passed!
```

随后恢复普通 Android release：

```bash
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

结果：通过；31.5MB APK 覆盖安装并启动 pid `8774`，`lastUpdateTime=2026-07-07 11:19:07`。

恢复后复核 Pixel 8 网络状态：

```text
cmd connectivity airplane-mode -> disabled
Wi-Fi is enabled
Active default network: WIFI CONNECTED / IS_VALIDATED
SSID="shufang_5G" IP=192.168.50.159
```

## 边界

- 本轮覆盖 Android 真机物理 Wi-Fi / data 断开触发的前台流式取消。
- 已覆盖 Wi-Fi / data 断开与 airplane mode 两种 Android 物理断网模式。
- 未覆盖 iOS 物理网络切换；iOS release-only 网络切换仍待补。
- 不做自动重发；恢复后只提供显式 `重试` 操作。
