# OpenAI 兼容 TTS 网络真机 smoke 验证记录（2026-07-06）

## 目标

补齐 P0 真机主链路中的语音播报网络证据：在 Pixel 8 上从 assistant 消息点击“语音播报”，验证应用会调用 OpenAI 兼容 `/v1/audio/speech`，把返回音频写入应用临时目录，并进入可停止的播报状态。

该验证使用设备进程内本地 mock TTS 服务和可记录的 fake audio player，不依赖真实云端 TTS，不使用真实 API Key，不卸载应用、不清理真机数据。

## 新增验证入口

新增文件：`integration_test/mobile_tts_network_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_tts_network.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，结束后恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

## 测试设计

测试使用真机 `integration_test` 跑 assistant 消息 → TTS 网络 → 播放状态闭环：

1. 使用内存 SQLite 和 mock SharedPreferences，避免读写真机用户数据。
2. SharedPreferences 预置启用的 OpenAI 兼容 TTS 配置：本地 mock Base URL、`tts-network-mock-model`、`alloy`、加密测试 Key。
3. 启动设备进程内 TTS mock server，只处理 `/v1/audio/speech`。
4. 种入一个会话和一条 assistant 消息 `DEVICE TTS assistant message 20260706`。
5. 通过 Provider override 注入 `_RecordingAudioPlayer`，避免依赖真实音频解码，同时验证 `TextToSpeechService` 已把返回 bytes 写入 `tts_audio/` 临时文件并调用播放接口。
6. 点击 assistant 消息下方“语音播报”按钮。
7. 验证 TTS mock 收到 1 次 `POST /v1/audio/speech`，`Authorization` 为测试 Key，JSON body 包含模型、音色、输入文本和 `response_format=mp3`。
8. 验证生成的音频文件位于 `tts_audio/`，文件存在且大小大于 0。
9. 验证 UI 进入“停止播报”状态，点击停止后 fake player `stop` 被调用，UI 回到“语音播报”按钮。
10. 验证 `tester.takeException()` 为空。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_tts_network.sh 37101FDJH0077P
```

脚本内部执行：

```bash
flutter --no-version-check test integration_test/mobile_tts_network_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.7s
00:00 +0: mobile device generates assistant speech through TTS endpoint
00:02 +1: (tearDownAll)
00:03 +1: All tests passed!
```

结论：Pixel 8 真机上，assistant 消息的语音播报入口可以读取本地加密 TTS 配置，调用 OpenAI 兼容 `/v1/audio/speech`，保存临时音频文件，并进入可停止的播报状态。

## 调试记录

首次运行时，测试在 TTS 配置异步加载完成前点击播报，导致没有实际 TTS 请求；已改为使用 `ProviderContainer` 并在启动 UI 前等待 `textToSpeechConfigProvider.notifier.ready`，只修正测试时序，未改业务代码。

## 验证与边界

本轮已验证：

- 新增 OpenAI 兼容 TTS 网络真机 integration smoke。
- 新增可重复执行脚本并自动恢复临时 sqlite3 hook。
- Pixel 8 真机通过 assistant 播报按钮、TTS JSON 请求、临时音频写入、播放接口调用、停止播报和 UI 状态回退闭环。
- 正式 `pubspec.yaml` 不保留临时 `hooks:`。

本轮未覆盖：

- Android / iOS 原生播放器真实解码与外放；本 smoke 用 fake audio player 只验证服务层到播放接口边界。
- 真实云端 TTS 服务。
- 长文本播报、来电 / 音频焦点中断、后台恢复。
- iPhone13 TTS smoke；当前设备仍需物理解锁后复跑。
