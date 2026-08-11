# 真机录音按钮 smoke 验证记录（2026-07-06）

## 目标

补齐 P0 真机主链路中的真实录音入口证据：在 Pixel 8 上走聊天页麦克风按钮，调用 Android 原生 `MediaRecorder` 录制 `.m4a`，停止后作为 audio 附件发送，随后复用 OpenAI 兼容 STT fallback 和聊天补全链路。

该验证使用设备进程内本地 mock 服务，不依赖真实云端 STT / 聊天模型，不使用真实 API Key，不卸载应用、不清理真机数据。

## 新增验证入口

新增文件：`integration_test/mobile_voice_recording_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_voice_recording.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，结束后恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

脚本会先 `flutter build apk --debug --no-pub` 并 `adb install -r` 覆盖安装，再通过 `adb shell pm grant top.simitalk.aichat android.permission.RECORD_AUDIO` 预授予麦克风权限，避免系统权限弹窗阻断自动化；该流程不执行卸载或清数据。

## 测试设计

测试使用真机 `integration_test` 跑完整 UI 录音 → STT → 聊天模型闭环：

1. 使用内存 SQLite 和 mock SharedPreferences，避免读写真机用户数据。
2. 启动设备进程内 OpenAI 兼容 mock server，同时处理 `/v1/audio/transcriptions` 和 `/v1/chat/completions`。
3. 种入 `Voice Recorder Mock OpenAI / voice-recorder-mock-model` 渠道、模型和会话；不配置独立 STT Provider，覆盖“复用当前 OpenAI 兼容聊天渠道做 STT fallback”的路径。
4. 点击聊天输入栏 `voice-record-button` 开始录音，确认 UI 切换为停止图标。
5. 等待约 1.6 秒后再次点击同一按钮停止录音，确认出现 audio 附件图标。
6. 点击发送，验证 user message 正文为空，附件表新增 1 条 `fileType=audio`、文件名为 `simichat-recording-*.m4a`、文件大小大于 0 且归档文件存在。
7. 验证 STT mock 收到 1 次 `POST /v1/audio/transcriptions`，`Authorization` 为渠道 API Key，`Content-Type` 为 multipart，multipart body 包含默认 `whisper-1` 模型和录音文件名。
8. 验证 `audio_transcripts/` sidecar 状态为 `ready`，正文为 mock STT 转写结果。
9. 验证 chat mock 收到 1 次 `POST /v1/chat/completions`，最后一条 user content 包含 `以下是语音转文字结果` 和 STT 文本，不包含 `base64` 或本机归档路径。
10. 验证 SSE assistant 回复落库并显示到 UI，且 `tester.takeException()` 为空。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_voice_recording.sh 37101FDJH0077P
```

脚本内部关键步骤：

```bash
flutter --no-version-check build apk --debug --no-pub
adb -s 37101FDJH0077P install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s 37101FDJH0077P shell pm grant top.simitalk.aichat android.permission.RECORD_AUDIO
flutter --no-version-check test integration_test/mobile_voice_recording_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 6.1s
00:00 +0: mobile device records voice and sends it through STT
00:05 +1: (tearDownAll)
00:06 +1: All tests passed!
```

结论：Pixel 8 真机上，聊天页麦克风按钮可以触发 Android 原生录音，停止后生成 `.m4a` audio 附件；发送时会先走 OpenAI 兼容 STT fallback，写入 ready sidecar，再把转写文本发给聊天模型并正常接收流式 assistant 回复。

## 验证与边界

本轮已验证：

- 新增真机录音按钮 integration smoke。
- 新增可重复执行脚本并自动恢复临时 sqlite3 hook。
- Pixel 8 真机通过麦克风按钮、Android 原生录音、audio 附件归档、multipart STT、ready sidecar、净化后聊天请求和 SSE 回复闭环。
- 正式 `pubspec.yaml` 不保留临时 `hooks:`。

本轮未覆盖：

- iPhone13 录音按钮；当前设备仍需物理解锁后复跑。
- 用户首次授权弹窗的人机交互；自动化脚本使用 `pm grant` 预授予权限。
- 真实云端 STT 服务。
- 长音频、来电 / 音频焦点中断、后台恢复。
