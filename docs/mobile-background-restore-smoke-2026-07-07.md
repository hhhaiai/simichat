# Android 后台恢复真机 smoke（2026-07-07）

## 目标

补齐移动端 P0 里“后台恢复”的一条可重复 Android 真机验证：应用进入后台再恢复前台后，聊天输入草稿不能丢，不能误写入消息表，也不能产生 Flutter 异常。

## 入口

- `integration_test/mobile_background_restore_smoke_test.dart`
- `scripts/smoke_android_background_restore.sh`

## 安全闸门

脚本默认不会真实操作设备后台：

```bash
scripts/smoke_android_background_restore.sh 37101FDJH0077P
```

必须显式授权：

```bash
REAL_BACKGROUND_TOGGLE=1 scripts/smoke_android_background_restore.sh 37101FDJH0077P
```

脚本行为：

1. 临时启用 `sqlite3.source=system` hook 以避免集成测试构建下载 native asset 卡住。
2. 启动 `integration_test/mobile_background_restore_smoke_test.dart`。
3. 测试输入 `mobile background restore draft 20260706` 后打印 `SIMICHAT_BACKGROUND_RESTORE_READY`。
4. 脚本收到 READY 标记后执行 `adb shell input keyevent KEYCODE_HOME`。
5. 等待 `BACKGROUND_SECONDS`（默认 3 秒）后用 `monkey -p top.simitalk.aichat -c android.intent.category.LAUNCHER 1` 拉起应用。
6. 测试确认 lifecycle 曾进入非 resumed，随后恢复 `AppLifecycleState.resumed`。
7. 测试确认草稿仍显示、消息表仍为空、无 Flutter 异常。
8. 退出时恢复 `pubspec.yaml` / `pubspec.lock`。

## 验证记录

```bash
bash -n scripts/smoke_android_background_restore.sh
flutter --no-version-check test --no-pub -r expanded \
  test/release_send_smoke_manifest_test.dart \
  --name "Android background restore smoke has explicit safety gates"
REAL_BACKGROUND_TOGGLE=1 scripts/smoke_android_background_restore.sh 37101FDJH0077P
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
flutter --no-version-check test --no-pub -r expanded \
  test/release_send_smoke_manifest_test.dart \
  test/connectivity_provider_test.dart \
  test/chat_page_offline_test.dart \
  test/chat_page_tts_playback_event_test.dart \
  test/mobile_main_flow_smoke_test.dart
flutter --no-version-check analyze
git diff --check
```

结果：

- 默认未设置 `REAL_BACKGROUND_TOGGLE=1` 时，脚本退出码 2，并提示 `Refusing to background the device`。
- `REAL_BACKGROUND_TOGGLE=1 scripts/smoke_android_background_restore.sh 37101FDJH0077P` 通过：
  - 测试输出 `SIMICHAT_BACKGROUND_RESTORE_READY`；
  - 脚本发送 `KEYCODE_HOME`；
  - 脚本重新启动 `top.simitalk.aichat`；
  - `mobile background restore smoke keeps composer draft` 通过。
- 影响面本地门禁通过：`test/release_send_smoke_manifest_test.dart`、`test/connectivity_provider_test.dart`、`test/chat_page_offline_test.dart`、`test/chat_page_tts_playback_event_test.dart`、`test/mobile_main_flow_smoke_test.dart` 共 22 项通过；`flutter --no-version-check analyze` 无问题；`git diff --check` 无输出。
- 因 debug integration runner 会安装调试包，随后运行 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release：
  - `app-release.apk` 31.5MB；
  - `adb install -r` 成功；
  - `versionName=1.0.0`；
  - `dataDir=/data/user/0/top.simitalk.aichat`；
  - `lastUpdateTime=2026-07-07 00:02:13`；
  - release 启动 pid `827`。

## 边界

- 本轮只覆盖 Android 前台输入草稿 → Home 后台 → 重新拉起前台。
- 不等同于 iOS 后台恢复。
- 不覆盖后台未完成网络请求的恢复 / 重试队列。
- 不覆盖系统杀进程后的状态恢复。
