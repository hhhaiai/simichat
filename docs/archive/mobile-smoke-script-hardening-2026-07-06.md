# 真机 smoke 脚本临时 hook 恢复加固记录（2026-07-06）

## 背景

本项目的真机 `integration_test` smoke 脚本会在运行前临时向 `pubspec.yaml` 追加：

```yaml
hooks:
  user_defines:
    sqlite3:
      source: system
```

用于规避本机 Flutter 测试 / 构建时 sqlite3 native asset 下载失败问题。脚本退出时必须恢复 `pubspec.yaml` / `pubspec.lock`，确保正式工作区不保留临时 hook。

本轮继续尝试新增后台恢复 smoke 时，中断脚本后发现旧 `mktemp` 模板会在 `/tmp` 留下字面量文件名：

```text
/tmp/simichat-pubspec.XXXXXX.yaml
/tmp/simichat-pubspec-lock.XXXXXX.lock
```

随后再次运行脚本会触发 `mktemp: mkstemp failed ... File exists`，并可能让临时 sqlite hook 残留在 `pubspec.yaml`。这是验证基础设施问题，不是业务代码问题。

## 修复范围

已统一修复以下真机 smoke 脚本的 `mktemp` 模板，去掉 `XXXXXX` 后缀之后的扩展名，避免 BSD `mktemp` 把模板当作固定路径：

- `scripts/smoke_device_integration_send.sh`
- `scripts/smoke_device_integration_settings.sh`
- `scripts/smoke_device_integration_markdown_scroll.sh`
- `scripts/smoke_device_integration_base64_audio.sh`
- `scripts/smoke_device_integration_stt_network.sh`
- `scripts/smoke_device_integration_voice_recording.sh`
- `scripts/smoke_device_integration_tts_network.sh`
- `scripts/smoke_device_integration_native_audio_player.sh`
- `scripts/smoke_device_integration_long_audio_playback.sh`

模板从：

```bash
mktemp /tmp/simichat-pubspec.XXXXXX.yaml
mktemp /tmp/simichat-pubspec-lock.XXXXXX.lock
```

改为：

```bash
mktemp /tmp/simichat-pubspec.XXXXXX
mktemp /tmp/simichat-pubspec-lock.XXXXXX
```

## 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_native_audio_player.sh 37101FDJH0077P
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.7s
00:00 +0: mobile device native audio player plays private wav and stops
00:00 +1: (tearDownAll)
00:01 +1: All tests passed!
```

脚本结束后复核：

```text
hooks_present= False
```

结论：修复后的真机 smoke 脚本仍可正常运行并恢复 `pubspec.yaml` / `pubspec.lock`，当前正式工作区不保留临时 sqlite hook。

## 边界

- 本轮只修复真机 smoke 脚本的临时文件模板和恢复可靠性，不改变业务代码。
- 后台恢复 smoke 草稿在当前 Flutter integration lifecycle 注入方式下会挂起测试泵，已放弃本轮提交；后台恢复仍需后续用更接近真实系统后台 / 前台切换的方式重新设计验证。
