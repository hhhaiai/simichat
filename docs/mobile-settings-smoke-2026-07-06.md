# 移动端设置页真机 smoke 验证记录（2026-07-06）

## 目标

补齐 P0 真机主链路中的设置页证据：在真实移动设备上验证从对话首页进入设置页、打开外观配置、切换主题、调整字体缩放并持久化，确保设置页不是只在 widget smoke 中可用。

该验证不依赖外部 API Key，不访问真实模型，不读取或清理用户真实数据。

## 新增验证入口

新增文件：`integration_test/mobile_settings_smoke_test.dart`。

新增脚本：`scripts/smoke_device_integration_settings.sh`。脚本默认使用 Pixel 8 设备 ID `37101FDJH0077P`，也可传入设备 ID 或通过 `DEVICE_ID` 环境变量指定；脚本会备份 `pubspec.yaml` / `pubspec.lock`，临时追加 `sqlite3.source=system` hook，结束后恢复正式文件并执行 `pub get`，避免把临时 hook 留在仓库。

## 测试设计

测试使用真机 `integration_test` 跑完整 Widget 交互：

1. 使用内存 SQLite 和 mock SharedPreferences，避免读写真机用户数据。
2. 将视口固定为 390×844，覆盖移动端布局。
3. 从首页确认 `SimiAIChat` 与 `未选择模型` 状态。
4. 点击设置按钮进入设置页。
5. 验证设置页可见：`设置`、`外观`、`主题模式`、`字体大小`、`数据与档案`。
6. 打开主题模式弹窗，选择 `深色模式`，等待 SharedPreferences 写入 `theme_mode=dark`，并验证 UI 变为深色模式。
7. 打开字体大小弹窗，把 Slider 设置为 120%，保存后等待 SharedPreferences 写入 `font_scale≈1.2`，并验证 UI 显示 `当前: 120%`。
8. 通过平台 back route 返回首页，确认没有 Flutter 异常。

## Pixel 8 验证结果

设备：Pixel 8，序列号 `37101FDJH0077P`，Android 16 API 36。

命令：

```bash
./scripts/smoke_device_integration_settings.sh 37101FDJH0077P
```

脚本内部执行：

```bash
flutter --no-version-check test integration_test/mobile_settings_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
```

结果：

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk... 5.7s
00:00 +0: mobile device settings smoke persists theme and font scale
00:03 +1: (tearDownAll)
00:04 +1: All tests passed!
```

结论：Pixel 8 真机上，设置页入口、外观设置弹窗、主题持久化、字体缩放持久化和返回首页闭环通过。

## 调试记录

首次运行暴露两个测试定位问题，均未改业务代码：

- 字体弹窗中按文本查找 `保存` 在真机测试里失败；改为从当前 `AlertDialog.actions` 精确取唯一 `FilledButton` 执行保存，避免布局 / 文本定位差异造成 flake。
- `tester.pageBack()` 查找 Cupertino 返回按钮失败；本项目是 Material 路由，改用 `tester.binding.handlePopRoute()` 模拟平台返回。

## 验证与边界

本轮已验证：

- 新增设置页真机 integration smoke。
- 新增可重复执行脚本并自动恢复临时 sqlite3 hook。
- Pixel 8 真机通过设置页入口、主题模式、字体缩放和返回首页闭环。
- 正式 `pubspec.yaml` 不保留临时 `hooks:`。

本轮未覆盖：

- iPhone13 设置页 smoke；当前设备仍因 Locked 状态拒绝 launch，需要物理解锁后复跑。
- 设置页内所有深层功能弹窗；本轮只覆盖 P0 主链路中最关键的外观设置和页面可达性。
- 真实用户 SharedPreferences；测试使用 mock preferences，避免污染真机用户数据。
