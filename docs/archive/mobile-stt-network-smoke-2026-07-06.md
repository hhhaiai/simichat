# OpenAI 兼容 STT 网络真机 smoke 验证记录（2026-07-06）

## 目标

补齐 P0 真机主链路中的语音网络证据：在真实移动设备上验证 audio 附件发送前会先调用 OpenAI 兼容 `/v1/audio/transcriptions`，拿到转写文本后再调用 `/v1/chat/completions`，并且聊天请求不携带原始 audio base64。

该验证使用设备进程内本地 mock 服务，不依赖真实 OpenAI / Groq / 自定义 STT 服务，不使用真实 API Key，不读取或清理用户真实数据。

## 新增验证入口

新增文件：`integration_test/mobile_stt_network_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_stt_network.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，结束后恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

## 测试设计

测试使用真机 `integration_test` 跑完整音频 → STT 网络 → 聊天模型闭环：

1. 使用内存 SQLite 和 mock SharedPreferences，避免读写真机用户数据。
2. 启动设备进程内 OpenAI 兼容 mock server，同时处理 `/v1/audio/transcriptions` 和 `/v1/chat/completions`。
3. 种入 `STT Network Mock OpenAI / stt-network-mock-model` 渠道、模型和会话；不配置独立 STT Provider，强制覆盖“复用当前 OpenAI 兼容聊天渠道做 STT fallback”的路径。
4. 在 UI 输入框粘贴小型 `data:audio/wav;base64,...` 并点击发送。
5. 验证数据库 user message 只保留净化后的 `已接收 base64 语音` 占位，不包含原始 base64、`data:audio` 或 STT 转写文本。
6. 验证附件表新增 1 条 `fileType=audio` 的 `inline-base64-audio.wav`。
7. 验证 STT mock 收到 1 次 `POST /v1/audio/transcriptions`，`Authorization` 为渠道 API Key，`Content-Type` 为 multipart，multipart body 包含默认 `whisper-1` 模型和音频文件名。
8. 验证 `audio_transcripts/` sidecar 状态为 `ready`，正文为 mock STT 转写结果。
9. 验证 chat mock 收到 1 次 `POST /v1/chat/completions`，最后一条 user content 包含 `以下是语音转文字结果` 和 STT 文本，不包含原始 base64 或 `data:audio`。
10. 验证 SSE assistant 回复落库并显示到 UI，且 `tester.takeException()` 为空。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_stt_network.sh 37101FDJH0077P
```

脚本内部执行：

```bash
flutter --no-version-check test integration_test/mobile_stt_network_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.7s
00:00 +0: mobile device uses OpenAI-compatible STT endpoint before chat
00:03 +1: (tearDownAll)
00:03 +1: All tests passed!
```

结论：Pixel 8 真机上，未配置独立 STT Provider 时，`openai_chat` 渠道可以被复用为 OpenAI 兼容 STT fallback；应用会先发 multipart `/v1/audio/transcriptions`，把返回文本写入 sidecar，并仅把转写文本发给聊天模型。

## 验证与边界

本轮已验证：

- 新增 OpenAI 兼容 STT 网络真机 integration smoke。
- 新增可重复执行脚本并自动恢复临时 sqlite3 hook。
- Pixel 8 真机通过 base64 音频解析、渠道 STT fallback、multipart STT 请求、ready sidecar、净化后聊天请求和 SSE 回复闭环。
- 正式 `pubspec.yaml` 不保留临时 `hooks:`。

本轮未覆盖：

- 真实云端 STT 服务。
- 真实麦克风录音按钮、Android / iOS 原生录音权限弹窗。
- 长音频、来电 / 音频焦点中断、后台恢复。
- iPhone13 STT 网络 smoke；当前设备仍需物理解锁后复跑。
