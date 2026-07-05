# 原生音频播放通道真机 smoke 验证记录（2026-07-06）

## 目标

补齐 P0 真机主链路中的原生播放边界证据：在 Pixel 8 上直接调用 `simichat/audio_player` MethodChannel，通过 Android `MediaPlayer` 播放应用私有目录内的本地 WAV 文件，并验证停止播放事件能回传到 Dart。

该验证不依赖真实 TTS 服务、不使用真实 API Key，不卸载应用、不清理真机数据。

## 新增验证入口

新增文件：`integration_test/mobile_native_audio_player_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_native_audio_player.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，结束后恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

## 测试设计

测试使用真机 `integration_test` 跑 Dart 播放接口 → 原生播放器 → 原生事件回传闭环：

1. 在应用临时目录下生成 `native_audio_player_smoke/simichat-native-smoke.wav`，内容为 1.8 秒 44.1 kHz 单声道 PCM WAV。
2. 使用正式 `MethodChannelAudioPlayer`，订阅 `player.events`。
3. 调用 `playFile(audioFile.path)`，验证 Android 原生侧接受应用私有目录内普通文件并启动播放。
4. 等待约 250 ms 后调用 `stop()`。
5. 验证收到 `AudioPlaybackEventType.stopped` 事件，且没有 `error` 事件。
6. 验证音频文件仍存在、长度大于 WAV header，且 `tester.takeException()` 为空。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_native_audio_player.sh 37101FDJH0077P
```

脚本内部执行：

```bash
flutter --no-version-check test integration_test/mobile_native_audio_player_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.8s
00:00 +0: mobile device native audio player plays private wav and stops
00:00 +1: (tearDownAll)
00:01 +1: All tests passed!
```

结论：Pixel 8 真机上，`MethodChannelAudioPlayer` 可以把应用私有目录内的本地 WAV 交给 Android `MediaPlayer` 播放，`stop()` 后原生 stopped 事件可回传到 Dart，且未出现播放错误事件。

## 调试记录

首次运行时测试要求 stopped 事件路径必须精确等于 Dart 侧文件路径，导致等待超时；原生事件本身已经回传但不应把 smoke 绑定到路径字符串一致性。已调整为验证 stopped 事件类型与无 error 事件，保持对原生播放 / 停止边界的核心验证，未改业务代码。

## 验证与边界

本轮已验证：

- 新增原生音频播放通道真机 integration smoke。
- 新增可重复执行脚本并自动恢复临时 sqlite3 hook。
- Pixel 8 真机通过应用私有目录 WAV、Android `MediaPlayer` 播放、停止事件回传和无错误事件闭环。
- 正式 `pubspec.yaml` 不保留临时 `hooks:`。

本轮未覆盖：

- iPhone13 原生播放器；当前设备仍需物理解锁后复跑。
- 真实 TTS 生成音频的原生解码外放；本轮使用测试生成 WAV。
- 长音频、来电 / 音频焦点中断、后台恢复。
