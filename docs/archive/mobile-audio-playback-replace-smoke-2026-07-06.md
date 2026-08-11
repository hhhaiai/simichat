# 原生音频播放替换 / 中断真机 smoke 验证记录（2026-07-06）

## 目标

补齐 P0 真机语音链路中的“播放中断 / 替换”证据：在 Pixel 8 上用正式 `MethodChannelAudioPlayer` 先播放一段较长 WAV，再在播放过程中启动第二段 WAV，验证第一段会收到 stopped 事件，第二段能自然完成并收到 completed 事件。

该验证不依赖真实 TTS 服务、不使用真实 API Key，不卸载应用、不清理真机数据。

## 新增验证入口

新增文件：`integration_test/mobile_audio_playback_replace_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_audio_playback_replace.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，结束后恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

## 测试设计

测试使用真机 `integration_test` 跑 Dart 播放接口 → Android `MediaPlayer` → 原生事件回传闭环：

1. 在应用临时目录生成两段 WAV：
   - `simichat-replace-first.wav`：6.5 秒，330 Hz。
   - `simichat-replace-second.wav`：0.9 秒，660 Hz。
2. 使用正式 `MethodChannelAudioPlayer`，订阅 `player.events`。
3. 调用 `playFile(firstAudio.path)` 启动第一段长音频。
4. 等待约 350 ms 后调用 `playFile(secondAudio.path)` 启动第二段音频。
5. 验证第一段音频收到 `AudioPlaybackEventType.stopped`。
6. 验证第二段音频收到 `AudioPlaybackEventType.completed`。
7. 验证第一段不会收到 completed，且全程没有 `AudioPlaybackEventType.error`。
8. 验证两个音频文件仍存在、长度大于 WAV header，且 `tester.takeException()` 为空。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_audio_playback_replace.sh 37101FDJH0077P
```

脚本内部执行：

```bash
flutter --no-version-check test integration_test/mobile_audio_playback_replace_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.6s
00:00 +0: mobile device replaces active native audio playback
00:01 +1: (tearDownAll)
00:02 +1: All tests passed!
```

脚本结束后复核：

```text
hooks_present= False
```

结论：Pixel 8 真机上，新的播放请求可以替换正在播放的原生音频；第一段长音频收到 stopped，第二段音频可自然完成并回传 completed，且未出现 error 事件。

## 边界

- 本轮验证的是应用主动发起第二段播放时的“替换 / 中断”行为。
- 未覆盖系统来电、蓝牙耳机、其他 App 抢占音频焦点等真实系统音频焦点中断场景。
- iPhone13 原生播放器仍需设备物理解锁后复跑。
