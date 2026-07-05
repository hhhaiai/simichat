# base64 语音真机发送 smoke 验证记录（2026-07-06）

## 目标

补齐 P0 真机主链路中的语音输入证据：在真实移动设备上验证用户把 `data:audio/...;base64,...` 粘贴到聊天输入框后，应用会先在本机解析成 audio 附件，走 STT 转写，再把转写文本发送给 OpenAI 兼容聊天模型。

该验证不依赖真实麦克风、真实 STT 服务或外部 API Key，不访问真实模型，不读取或清理用户真实数据。

## 新增验证入口

新增文件：`integration_test/mobile_base64_audio_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_base64_audio.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，结束后恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

## 测试设计

测试使用真机 `integration_test` 跑完整输入 → 附件 → STT → 模型请求 → assistant 回复闭环：

1. 使用内存 SQLite 和 mock SharedPreferences，避免读写真机用户数据。
2. 启动设备进程内本地 OpenAI 兼容 SSE mock server，只接收 `/v1/chat/completions`。
3. 种入 `Base64 Audio Mock OpenAI / base64-audio-mock-model` 渠道、模型和会话。
4. 通过 Riverpod override 注入 fake `SpeechToTextEngine`，固定返回 `Pixel8 voice transcript 20260706`。
5. 在 UI 输入框粘贴小型 `data:audio/wav;base64,...` 并点击发送。
6. 验证数据库 user message 只保留净化后的 `已接收 base64 语音` 占位，不包含原始 base64 或 `data:audio`。
7. 验证附件表新增 1 条 `fileType=audio` 的 `inline-base64-audio.wav`，fake STT 收到归档后的本地音频路径。
8. 验证 `audio_transcripts/` sidecar 状态为 `ready`，正文为 fake STT 转写结果。
9. 验证 mock 聊天请求最后一条 user content 包含 `以下是语音转文字结果` 和转写文本，不包含原始 base64 或 `data:audio`。
10. 验证 SSE assistant 回复落库并显示到 UI，且 `tester.takeException()` 为空。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_base64_audio.sh 37101FDJH0077P
```

脚本内部执行：

```bash
flutter --no-version-check test integration_test/mobile_base64_audio_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.6s
00:00 +0: mobile device sends pasted base64 audio through fake STT
00:03 +1: (tearDownAll)
00:03 +1: All tests passed!
```

结论：Pixel 8 真机上，base64 语音粘贴输入可以被本地解析成 audio 附件，原始 base64 不进入数据库用户消息或模型请求；STT 转写 sidecar 为 `ready`；聊天模型收到的是转写文本并正常返回流式 assistant 回复。

## 调试记录

首次运行暴露测试期望文案错误：实际内联音频文件名为 `inline-base64-audio.wav`，测试误写为 `inline-audio.wav`。已只修正测试断言，未改业务代码。

## 验证与边界

本轮已验证：

- 新增 base64 语音真机 integration smoke。
- 新增可重复执行脚本并自动恢复临时 sqlite3 hook。
- Pixel 8 真机通过 UI 粘贴 base64 音频、fake STT、sidecar ready、净化后聊天请求和 SSE 回复闭环。
- 正式 `pubspec.yaml` 不保留临时 `hooks:`。

本轮未覆盖：

- 真实麦克风录音按钮、Android / iOS 原生录音权限弹窗。
- 真实 OpenAI / Groq / 自定义 STT 网络接口。
- 长音频、来电 / 音频焦点中断、后台恢复。
- iPhone13 语音 smoke；当前设备仍需物理解锁后复跑。
