# iOS 实时语音 PCM 真机链路

## 固定协议

`ios/Runner/RealtimePcmAudio.swift` 是 iOS 原生实时语音 PCM bridge：

- 麦克风输入：`16_000 Hz`、`mono`、`PCM16`。
- Flutter EventChannel 只接收原始 PCM16 字节，不创建录音文件。
- 输入 tap 使用 `AVAudioConverter` 的 input block 做实时重采样，并在转换器侧 downmix 到 mono；实时转换使用 `.none` prime method，避免等待不存在的尾部帧。
- 扬声器输出：`24_000 Hz`、`mono`、`PCM16`，通过 `AVAudioPlayerNode` 调度到 `AVAudioEngine`，由系统图形继续转换到实际硬件 route。
- `getDiagnostics` 只返回格式、route、引擎 / session 状态和 `writesAudioFiles=false`，不返回音频内容或凭据。

## 生命周期与系统事件

- `NSMicrophoneUsageDescription` 已存在于 `ios/Runner/Info.plist`；首次 `startCapture` 由 `AVAudioSession.requestRecordPermission` 触发系统权限请求。
- session 使用 `.playAndRecord`、`.defaultToSpeaker` 和 `.allowBluetoothHFP`，并尽力请求 mono 输入；不能满足硬件偏好时仍由 converter 归一化协议格式。
- interruption began、物理 route change、media services reset、应用进入后台和应用退出都会发出错误事件并停止 capture / playback；自身激活 `.playAndRecord` 产生的 `categoryChange` 不会被误判为物理路由变化。
- 停止时移除 input tap、停止并 reset player、停止 engine，并以 `notifyOthersOnDeactivation` 释放 `AVAudioSession`；EventChannel 被 Flutter 取消时也会清理 capture。
- Debug 构建额外包含 `debugSimulateInterruption` 和 `debugSimulateRouteUnavailable`，只用于集成 smoke 触发同一套 notification observer；Release 不编译这两个入口。

## Smoke 入口

```bash
# Debug：包含 synthetic interruption / route-change observer 验证
BUILD_MODE=debug scripts/smoke_ios_realtime_pcm.sh <ios-device>

# Release：验证真实发布构建的 PCM capture / playback / cleanup
BUILD_MODE=release scripts/smoke_ios_realtime_pcm.sh <ios-device>

# 默认 all：先 Debug，再 Release
scripts/smoke_ios_realtime_pcm.sh <ios-device>
```

脚本通过 `FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER` 将构建安装到
`top.simitalk.aichat.realtimepcm` 隔离 bundle。脚本只允许清理这个隔离 bundle，
不对 `top.simitalk.aichat` 执行 uninstall、数据清理或进程终止。`SMOKE_BUNDLE_ID`
如果被改到正式 bundle 或离开 realtimepcm namespace 会直接拒绝运行。
脚本从 `devicectl` 的 `hardwareProperties.udid` 优先解析设备标识；该值同时可被
Flutter device discovery 和 `devicectl` 使用，避免把 CoreDevice identifier 误传给
`flutter drive`。构建命令使用 shell 环境赋值传入 `FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER`，
不依赖 `env` wrapper。

Smoke 集成测试与 driver：

- `integration_test/ios_realtime_pcm_smoke_test.dart`
- `integration_test/ios_realtime_pcm_smoke_driver.dart`
- `scripts/smoke_ios_realtime_pcm.sh`
- `test/ios_realtime_pcm_smoke_manifest_test.dart`

测试只生成内存中的 24 kHz PCM16 tone 作为 playback 输入；capture 输出只统计
字节数和对齐性，不写入 WAV、CAF、PCM 或其他音频文件。`getDiagnostics` 在运行中
验证 native target format，停止后验证 engine / session / capture / playback 均为
inactive。

## 代码级验证与真机缺口

代码级检查至少包括：Xcode Sources 引用、AppDelegate method / event channel 注册、
麦克风权限声明、Swift native typecheck、脚本 `bash -n`、manifest 测试，以及
`AVAudioConverter` / `AVAudioEngine` / interruption / route-change / tap cleanup 和
无文件写入约束。

Release 集成测试会记录 interruption / route-change 为人工真机观察项；Debug 集成
测试会用只存在于 Debug 的 notification hook 验证停止分支。真实来电、闹钟、第三方
播放器抢占和真实耳机 / Bluetooth 拔插仍需在已解锁且已授权麦克风的 iPhone 上手工
复跑。若 `devicectl` 报告设备 unavailable、锁定或无法取得 lock state，脚本只输出
`SMOKE_SKIPPED` 并退出，不安装 smoke 包。

## 本机验证记录

2026-08-18 已完成以下代码级与脚本级验证：

- `xcrun swiftc -typecheck` 对 `RealtimePcmAudio.swift` 的 iOS arm64 target 通过；
- `flutter build ios --debug --no-codesign --no-pub` 通过；Release no-code-sign
  build 的 Xcode clean 阶段被当前 `build/ios/Release-iphoneos` 生成目录归属检查阻塞，
  没有出现 `RealtimePcmAudio.swift` 编译错误；
- iOS Runner wiring / 权限 / 无音频文件落盘 manifest 测试 3 项通过；
- Debug fake-device harness 通过 `SMOKE_PASS`，并证明 `pubspec.yaml`、`pubspec.lock`
  内容不变；formal bundle id 与非隔离 bundle 参数均被拒绝；
- `iPhone13` 当前 `devicectl` 状态为 `unavailable`，脚本输出 `SMOKE_SKIPPED`；
- `people` 可用且解锁，Debug 构建已到达 Xcode build 与安装启动阶段，但当前无线
  CoreDevice 没有在 75 秒内发现 Dart VM Service；脚本随后只清理隔离 smoke 包，未对
  `top.simitalk.aichat` 执行 uninstall、clear 或 terminate。该次不计入 PCM capture / playback
  真机通过证据。

因此，真实麦克风权限弹窗、16 kHz PCM capture 数据、24 kHz 播放排程、来电 / 闹钟
interruption、耳机 / Bluetooth route change 以及 Debug / Release 集成测试的完整真机
证据仍需在 Flutter 能发现 Dart VM Service 的已解锁 iOS 设备上复跑。
