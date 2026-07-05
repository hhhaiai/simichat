# 长音频原生播放真机 smoke 验证记录（2026-07-06）

## 目标

补齐 P0 真机语音链路中的长音频播放证据：在 Pixel 8 上直接调用正式 `MethodChannelAudioPlayer`，让 Android `MediaPlayer` 播放应用私有目录内较长 WAV 文件直到自然结束，并验证 completed 事件能回传到 Dart。

该验证不依赖真实 TTS 服务、不使用真实 API Key，不卸载应用、不清理真机数据。

## 新增验证入口

新增文件：`integration_test/mobile_long_audio_playback_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_long_audio_playback.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，结束后恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

## 测试设计

测试使用真机 `integration_test` 跑 Dart 播放接口 → 原生播放器 → 自然完成事件回传闭环：

1. 在应用临时目录下生成 `long_audio_playback_smoke/simichat-long-native-smoke.wav`，内容为 6.5 秒 24 kHz 单声道 PCM WAV。
2. 使用正式 `MethodChannelAudioPlayer`，订阅 `player.events`。
3. 调用 `playFile(audioFile.path)`，验证 Android 原生侧接受应用私有目录内普通文件并启动播放。
4. 等待收到 `AudioPlaybackEventType.completed`，且真实等待时间大于 4 秒，避免只证明“瞬时触发”。
5. 验证没有 `AudioPlaybackEventType.error` 事件。
6. 验证音频文件仍存在、长度大于 WAV header，且 `tester.takeException()` 为空。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_long_audio_playback.sh 37101FDJH0077P
```

脚本内部执行：

```bash
flutter --no-version-check test integration_test/mobile_long_audio_playback_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.8s
00:00 +0: mobile device native audio player completes longer private wav
00:07 +1: (tearDownAll)
00:07 +1: All tests passed!
```

结论：Pixel 8 真机上，`MethodChannelAudioPlayer` 可以把应用私有目录内 6.5 秒 WAV 交给 Android `MediaPlayer` 播放到自然完成，`playbackCompleted` 事件可回传到 Dart，且未出现播放错误事件。

## 验证与边界

本轮已验证：

- 新增长音频原生播放真机 integration smoke。
- 新增可重复执行脚本并自动恢复临时 sqlite3 hook。
- Pixel 8 真机通过应用私有目录 6.5 秒 WAV、Android `MediaPlayer` 自然播放完成、completed 事件回传和无错误事件闭环。
- 正式 `pubspec.yaml` 不保留临时 `hooks:`。

本轮未覆盖：

- iPhone13 原生播放器；当前设备仍需物理解锁后复跑。
- 真实云端 TTS 返回长音频后的端到端播放；本轮使用测试生成 WAV。
- 来电 / 音频焦点中断、后台恢复。
