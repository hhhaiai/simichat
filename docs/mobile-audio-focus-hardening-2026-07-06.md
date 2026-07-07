# 移动端原生音频播放焦点 / 中断加固记录（2026-07-06）

## 目标

补齐语音播报在 Android 侧的基础音频焦点处理，并补上 iOS `AVAudioSession` interruption 开始事件处理，避免 TTS / 原生播放在来电、导航、其他媒体应用抢占焦点或系统中断时继续强播。

本轮完成产品路径代码加固、本地回归、Android / iOS 编译，以及 Pixel 8 现有三条原生播放 smoke 复验。真实来电、蓝牙耳机、系统闹钟、导航播报、其他播放器抢占焦点等外部焦点 / 中断场景仍需后续真机手动 / 自动化复验。

## 变更

- `android/app/src/main/kotlin/top/simitalk/aichat/MainActivity.kt`
  - 产品路径播放应用私有目录音频前先请求 `AudioManager` 音频焦点。
  - Android O 及以上使用 `AudioFocusRequest` + `AudioAttributes.USAGE_MEDIA` / `CONTENT_TYPE_SPEECH`。
  - Android O 以下保留旧版 `requestAudioFocus` 兼容路径。
  - 使用 `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`，更符合短语音播报：允许系统 / 其他音频 duck，而不是长期独占。
  - `AUDIOFOCUS_LOSS` / `AUDIOFOCUS_LOSS_TRANSIENT` 触发 `stopAudioPlayback()`，并通过既有事件通道回传 stopped。
  - `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK` 降低当前播放器音量，`AUDIOFOCUS_GAIN` 恢复音量。
  - 播放完成、播放错误、主动停止和播放失败都会释放音频焦点。
  - `skipAudioFocusRequest` 只作为 direct integration smoke 的显式测试参数；正式 `MethodChannelAudioPlayer.playFile()` 不传该参数。
- `lib/core/media/audio_player.dart`
  - 保持正式 `playFile()` 不传测试参数。
  - 新增 `playFileForTesting(..., skipAudioFocusRequest: true)`，仅用于当前无 UI / 非普通用户点击流的原生音频 integration smoke。
- `ios/Runner/AppDelegate.swift`
  - 注册 `AVAudioSession.interruptionNotification` 监听，避免重复注册。
  - 收到 `AVAudioSession.InterruptionType.began` 且当前正在播放时，调用既有 `stopAudioPlayback()`，复用 stopped 事件回传。
  - 播放完成、播放错误、主动停止、启动失败和 interruption 停止都会 `setActive(false, options: [.notifyOthersOnDeactivation])`，把音频会话归还给系统 / 其他应用。
- `integration_test/mobile_native_audio_player_smoke_test.dart`
- `integration_test/mobile_long_audio_playback_smoke_test.dart`
- `integration_test/mobile_audio_playback_replace_smoke_test.dart`
- `integration_test/mobile_audio_focus_loss_smoke_test.dart`
- `integration_test/mobile_external_audio_focus_smoke_test.dart`
- `scripts/smoke_device_external_audio_focus.sh`
- `scripts/smoke_android_audio_focus_suite.sh`
  - 三条 direct-channel 原生音频 smoke 显式跳过音频焦点请求，避免 Android instrumentation 环境拒绝焦点导致误判。
  - 事件等待从 `tester.pump(Duration)` 改为真实时间 `Future.delayed` 轮询，避免无 UI direct-channel 测试依赖 Flutter 帧泵。
  - 测试 WAV 改为静音 PCM（数据区保持 zero-filled），保留有效 WAV 时长与播放事件验证，同时避免真机测试时发出“嗯嗯”声。
  - 新增 Android debug-only 设备 smoke：先走正式焦点请求播放静音长 WAV，再通过 `requestCompetingAudioFocusForTesting` 请求一个独立的竞争性 `AUDIOFOCUS_GAIN_TRANSIENT`，验证系统焦点仲裁会让原播放回传 stopped、无 completed、无 error。测试结束会调用 `abandonCompetingAudioFocusForTesting` 清理竞争焦点；测试入口由 `ApplicationInfo.FLAG_DEBUGGABLE` 限制，release 不暴露。
  - 保留 `simulateAudioFocusLossForTesting` 作为最小 listener 分支兜底，但当前设备 smoke 已不再依赖直接调用原播放 listener。
  - 新增 Android 外部包抢占焦点 smoke：脚本临时生成并安装独立 helper APK `top.simitalk.aichat.audiofocusstealer`，integration test 先让 SimiChat 走正式焦点请求播放 9 秒静音 WAV，输出 `SIMICHAT_EXTERNAL_AUDIO_FOCUS_READY` 后脚本启动 helper；helper 从另一个包请求 `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE` 并保持 6 秒，验证 SimiChat 收到 stopped、无 completed、无 error；脚本退出会卸载 helper 包并恢复 `pubspec.yaml` / `pubspec.lock`。
  - 新增 Android 音频焦点 suite：`scripts/smoke_android_audio_focus_suite.sh` 会顺序运行 debug-only competing AudioFocus smoke、外部 helper APK 抢占 smoke，并在成功或失败后按需恢复普通 Android release，避免单条 integration smoke 后设备停留在 debug 包。
- `test/core/microphone_permission_manifest_test.dart`
  - 增加静态回归，锁定三条 direct-channel 原生音频 smoke 使用 `_buildSilentWav` / zero-filled PCM，不再引入 `dart:math` / `math.sin` 正弦波。
  - 增加静态回归，锁定 Android 原生播放器必须包含 `AudioFocusRequest`、`AudioManager`、`OnAudioFocusChangeListener`、`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`、`requestAudioFocus`、`abandonAudioFocus`、`skipAudioFocusRequest`、`simulateAudioFocusLossForTesting` 和 `ApplicationInfo.FLAG_DEBUGGABLE` 等关键路径。
  - 增加静态回归，锁定 iOS 原生播放器必须监听 `AVAudioSession.interruptionNotification`、识别 interruption began、停止播放并释放音频会话。
- `test/core/text_to_speech_service_test.dart`
  - 增加 Dart MethodChannel 回归：正式 `playFile()` 不带 `skipAudioFocusRequest`，只有 `playFileForTesting(..., skipAudioFocusRequest: true)` 会传测试参数。
  - 增加音频焦点拒绝错误映射回归，确保原生侧返回 `AUDIO_FOCUS_DENIED` 且 message 缺失时，Dart 侧仍给出“无法获取音频播放焦点”的明确提示。

## 验证

- `flutter --no-version-check test --no-pub --no-test-assets test/core/microphone_permission_manifest_test.dart test/core/text_to_speech_service_test.dart -r expanded`
  - 结果：17 个测试全部通过。
- `flutter --no-version-check test --no-pub --no-test-assets test/core/microphone_permission_manifest_test.dart -r expanded`
  - 结果：8 个测试全部通过；静态约束已锁定 `requestCompetingAudioFocusForTesting` / `abandonCompetingAudioFocusForTesting` debug-only 竞争焦点入口。
- `flutter --no-version-check test --no-pub --no-test-assets -r expanded`
  - 结果：335 个测试全部通过。
- `flutter --no-version-check analyze`
  - 结果：无问题。
- `flutter --no-version-check build apk --debug --no-pub`
  - 结果：临时追加 `sqlite3.source=system` hook 后 Android debug APK 构建通过；构建结束后恢复正式 `pubspec.yaml` / `pubspec.lock`。
  - 说明：不加 hook 直接构建时，本机当前会因 GitHub sqlite3 预编译 Android native asset 下载超时失败；该失败不指向本轮 Kotlin / Dart 代码编译错误。
- `flutter --no-version-check build ios --debug --no-codesign --no-pub`
  - 结果：临时追加 `sqlite3.source=system` hook 后 iOS Debug `Runner.app` 构建通过；构建结束后恢复正式 `pubspec.yaml` / `pubspec.lock`。
- `./scripts/smoke_device_integration_native_audio_player.sh 37101FDJH0077P`
  - 结果：当前工作树 Pixel 8 通过；静音应用私有目录 WAV 可播放并 stop，收到 stopped，无 error。
- `./scripts/smoke_device_integration_long_audio_playback.sh 37101FDJH0077P`
  - 结果：当前工作树 Pixel 8 通过；6.5 秒静音 WAV 自然 completed，无 error。
- `./scripts/smoke_device_integration_audio_playback_replace.sh 37101FDJH0077P`
  - 结果：当前工作树 Pixel 8 通过；静音第一段 stopped，第二段 completed，无 error。
- `./scripts/smoke_device_integration_audio_focus_loss.sh 37101FDJH0077P`
  - 结果：先红灯失败于 `MissingPluginException(No implementation found for method simulateAudioFocusLossForTesting on channel simichat/audio_player)`；补 Android debug-only 原生入口后 Pixel 8 通过，播放中模拟 `AUDIOFOCUS_LOSS_TRANSIENT` 后收到 stopped，无 completed、无 error。
  - 复验：2026-07-07 改为 `requestCompetingAudioFocusForTesting` 竞争焦点路径后，Pixel 8 再次通过，确认不是直接调用原播放 listener，也能收到 stopped、无 completed、无 error。
- `./scripts/smoke_device_external_audio_focus.sh 37101FDJH0077P`
  - 结果：2026-07-07 Pixel 8 通过；Flutter integration test 输出 `SIMICHAT_EXTERNAL_AUDIO_FOCUS_READY` 后，脚本启动独立 helper APK 抢占 `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE`，SimiChat 原生播放收到 stopped、无 completed、无 error；脚本 cleanup 后 `pm list packages top.simitalk.aichat.audiofocusstealer` 为空。
- `./scripts/smoke_android_release_install_launch.sh 37101FDJH0077P`
  - 结果：2026-07-07 competing focus integration smoke 后恢复 Pixel 8 普通 release，`app-release.apk` 31.5MB，覆盖安装成功，`versionName=1.0.0`，`lastUpdateTime=2026-07-07 11:34:25`，启动 pid `10374`。
  - 复验：外部 helper APK 抢占焦点 smoke 后再次恢复 Pixel 8 普通 release，`lastUpdateTime=2026-07-07 11:44:05`，启动 pid `11520`。
- `./scripts/smoke_android_audio_focus_suite.sh 37101FDJH0077P`
  - 结果：2026-07-07 Pixel 8 通过；先跑 debug-only competing focus smoke，再跑外部 helper APK focus takeover smoke，最后恢复普通 release，`lastUpdateTime=2026-07-07 11:55:53`，启动 pid `12728`，输出 `Android audio focus suite passed for 37101FDJH0077P`。
- `git diff --check`
  - 结果：无输出。
- `pubspec.yaml` / `pubspec.lock` 检查
  - 结果：正式文件不包含临时 `hooks:` / `source: system`。

## 重要边界

- Pixel 8 三条原生播放 smoke 验证的是现有 direct-channel 播放、停止、完成和替换事件没有被音频焦点改造破坏；这些 smoke 通过测试参数跳过焦点请求。新增 `audio_focus_loss` smoke 不跳过焦点请求，并已从直接调用 listener 推进为 debug-only 竞争焦点请求；新增 `external_audio_focus` smoke 进一步用独立 helper APK 从另一个包请求系统音频焦点，覆盖“外部应用抢占焦点”自动化路径。它仍不是来电 / 闹钟 / 真实媒体播放器全场景，但已比本进程 listener 模拟更接近真实外部抢占。
- 产品正式路径仍是 `MethodChannelAudioPlayer.playFile()` → Android 原生请求音频焦点 → 成功后播放；拿不到焦点会返回“无法获取音频播放焦点”。
- 真实外部焦点 / 中断场景仍未关闭：来电 / 系统闹钟 / 其他播放器 / 导航播报 / 蓝牙耳机需后续在真实用户前台场景复验。
- iOS 侧本轮只做 interruption began → stopped 的代码级兜底；是否自动恢复播放、后台音频恢复策略、来电 / 耳机场景仍待真机复验。
