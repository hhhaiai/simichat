# 深度链接 `ai-chat://` v1

## 目标

为移动端提供最小可用的应用内跳转入口，方便后续通知、外部渠道、技能市场或电脑端中转页把用户带回 SimiAIChat 的指定位置。

## 已支持路由

- `ai-chat://home`：回到聊天首页。
- `ai-chat://new` / `ai-chat://new-chat`：回到首页并新建会话。
- `ai-chat://settings`：打开设置页。
- `ai-chat://marketplace` / `ai-chat://skills`：打开技能 / MCP 市场页。
- `ai-chat://chat?sessionId=<id>`：打开指定本地会话。
- `ai-chat://session/<id>`：打开指定本地会话。

会话 ID 只接受 1–128 位的字母、数字、下划线和短横线；无法解析或不属于 `ai-chat` scheme 的链接会被丢弃，不会触发跳转。

## 平台接入

- Android：`AndroidManifest.xml` 声明 `VIEW` / `BROWSABLE` / `ai-chat` scheme，`MainActivity` 通过 `simichat/deep_link` MethodChannel 暴露 `getInitialLink` 并在 `onNewIntent` 推送 `linkOpened`。
- iOS：`Info.plist` 声明 `CFBundleURLTypes` / `ai-chat` scheme；`AppDelegate` 与 `SceneDelegate` 处理冷启动和运行中打开 URL，并通过同一 MethodChannel 回传 Dart。
- Flutter：`MethodChannelSimiDeepLinkService` 负责解析初始链接和运行中链接；`ResponsiveShell` 在不阻塞启动主链路的前提下处理跳转。运行中打开设置页 / 市场页时显式使用 root Navigator，并在平台回调后让出一个 microtask 再入栈，避免 Android `onNewIntent` 已送达但路由未显示。

## 验证

2026-07-07 本地验证：

- `flutter --no-version-check test --no-pub --no-test-assets test/deep_link_service_test.dart test/deep_link_manifest_test.dart`
- `flutter --no-version-check test --no-pub --no-test-assets test/mobile_main_flow_smoke_test.dart -r expanded`
- `flutter --no-version-check test --no-pub --no-test-assets`
- `flutter --no-version-check analyze`
- `git diff --check`
- `scripts/smoke_android_deep_link.sh 37101FDJH0077P`
- `scripts/smoke_ios_release_deep_link.sh 00008110-0016349A3A20A01E`
- 临时 `sqlite3.source=system` hook 下：
  - `flutter --no-version-check build apk --debug --no-pub`
  - `flutter --no-version-check build ios --debug --no-codesign --no-pub`

Android 真机 URL 打开已补自动化 smoke：`scripts/smoke_android_deep_link.sh 37101FDJH0077P` 在 Pixel 8 上通过。脚本通过 `adb shell am start -W -f 0x24000000 -a android.intent.action.VIEW -d ... -n top.simitalk.aichat/.MainActivity` 走 Android `ACTION_VIEW` 外部链接路径，依次验证 `ai-chat://settings` 打开设置页、`ai-chat://session/deep-link-target-session` 返回并切到指定会话。

iOS release URL 打开已补自动化 smoke：`scripts/smoke_ios_release_deep_link.sh 00008110-0016349A3A20A01E` 在 iPhone13 上通过。脚本先做 launch preflight，确认设备未锁定后才安装带 smoke dart-define 的 release 包；随后用 `devicectl device process launch --payload-url ai-chat://settings` 验证冷启动设置页 deep link，再用 `--payload-url ai-chat://session/ios-release-deep-link-target-session` 验证运行中 URL 切到目标会话；最后自动恢复普通 release。
