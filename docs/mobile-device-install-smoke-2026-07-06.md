# 移动端真机覆盖安装与启动记录（2026-07-06）

## 目标

在不卸载、不清数据的前提下，把当前提交 `d67a6f4 feat: add local assistant reflection loop` 覆盖安装到在线真机，确认移动端基础安装 / 启动链路仍可用，为后续真机长会话、Dreaming 和 Reflection 质量评估做前置基线。

## 设备状态

`flutter --no-version-check devices` 检测到：

- Pixel 8：`37101FDJH0077P`，Android 16 API 36，可用。
- iPhone13：`00008110-0016349A3A20A01E`，iOS 26.5，可用。
- `people`、`biao的iPhone`、`iPhone-cqs` 当前为无线不可用或 `unavailable`，本轮不作为验证设备。

## Android Pixel 8

命令：

```bash
flutter --no-version-check build apk --debug
adb -s 37101FDJH0077P install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s 37101FDJH0077P shell dumpsys package top.simitalk.aichat | grep -E 'firstInstallTime|lastUpdateTime|versionName|versionCode|dataDir'
adb -s 37101FDJH0077P shell monkey -p top.simitalk.aichat -c android.intent.category.LAUNCHER 1
adb -s 37101FDJH0077P shell pidof top.simitalk.aichat
adb -s 37101FDJH0077P shell dumpsys window | grep -E 'mCurrentFocus|top.simitalk.aichat'
```

结果：

- `flutter build apk --debug` 成功，产物：`build/app/outputs/flutter-apk/app-debug.apk`。
- `adb install -r` 返回 `Success`，未执行卸载或清数据。
- 包信息：
  - `versionCode=1`
  - `versionName=1.0.0`
  - `firstInstallTime=2026-07-02 23:29:09`
  - `lastUpdateTime=2026-07-06 02:17:48`
  - `dataDir=/data/user/0/top.simitalk.aichat`
- `monkey` 启动成功。
- `pidof top.simitalk.aichat` 返回 `15642`。
- `dumpsys window` 显示当前焦点包含 `top.simitalk.aichat/top.simitalk.aichat.MainActivity`。

结论：Pixel 8 当前提交覆盖安装并启动成功，应用数据目录保持同一包名目录，未清数据。

## iPhone13

命令：

```bash
flutter --no-version-check build ios --release
xcrun devicectl device install app --device 00008110-0016349A3A20A01E build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device 00008110-0016349A3A20A01E top.simitalk.aichat
xcrun devicectl device info apps --device 00008110-0016349A3A20A01E
xcrun devicectl device info processes --device 00008110-0016349A3A20A01E
```

结果：

- `flutter build ios --release` 成功，产物：`build/ios/iphoneos/Runner.app`，大小约 `33.0MB`。
- `devicectl device install app` 成功：
  - `bundleID: top.simitalk.aichat`
  - `installationURL: file:///private/var/containers/Bundle/Application/14463BF7-4A98-4004-8227-F7A0271DF996/Runner.app/`
  - `databaseUUID: D546E20B-9FCA-4BBB-A2B6-CBC0B3A56823`
  - `databaseSequenceNumber: 4168`
- `devicectl device process launch` 已发起但长时间未返回，本轮手动中断。
- 后续 `device info apps` 可见：`SimiAIChat top.simitalk.aichat 1.0.0 1`。
- 后续 `device info processes` 可见 Runner 进程：`78854 /private/var/containers/Bundle/Application/.../Runner.app/Runner`。

结论：iPhone13 当前提交 release 覆盖安装成功，安装后存在 Runner 进程；但 `devicectl process launch` 命令未正常返回，本轮只记录为“安装成功 + 进程可见”，不声称完整交互冒烟已通过。

## 当前边界

本轮只验证安装与启动 / 进程可见性，不覆盖：

- 长会话真实滚动、发送、停止、重试。
- 真机 Dreaming 手动运行和本地反思弹窗交互。
- 语音长时间播报、来电 / 音频焦点中断。
- 网络切换、后台恢复、Relay 长时间运行。

## 下一步

1. 在 Pixel 8 上做真实长会话输入 / 滚动 / 历史搜索 / 设置页反思弹窗检查。
2. 在 iPhone13 上复核 `devicectl process launch` 卡住原因，必要时用设备侧手动启动或 Xcode Instruments 辅助确认前台状态。
3. 形成 Dreaming + Reflection 真机质量评估记录：长会话消息数、是否生成 digest、是否生成反思、短期提示是否可预览。
