# 测试稳定性收口记录（2026-07-06）

## 背景

理论稳定性门禁复跑时，基础 widget smoke 使用默认 `ProviderScope(child: AiChatApp())`，会让测试直接打开默认 `AppDatabase()`。当同一测试进程里还有其他数据库实例时，Drift debug 输出可能出现多数据库生命周期警告。该问题不等同于用户数据损坏，但会降低全量 gate 输出的可信度，也可能掩盖真正的数据库生命周期问题。

## 处理

- 新增 `test/core/widget_test_database_lifecycle_test.dart`，静态约束基础 widget smoke 必须使用一次性测试数据库。
- `test/widget_test.dart` 改为通过 `AppDatabase.forTesting(NativeDatabase.memory())` 创建内存库。
- 通过 `databaseProvider.overrideWithValue(db)` 注入测试库，不再打开默认应用数据库。
- 使用 `addTearDown(db.close)` 保证每个 widget 用例结束后关闭测试库。

## 验证

- 红灯：新增生命周期约束测试先确认旧写法会失败。
- 局部绿灯：`scripts/smoke_full_stability_gate.sh -r expanded test/core/widget_test_database_lifecycle_test.dart test/widget_test.dart`，3 项通过，局部输出无 Drift warning。
- 静态检查：`flutter --no-version-check analyze` 无问题。
- 全量理论门禁：`scripts/smoke_full_stability_gate.sh -r expanded`，352 项通过。
- 全量日志复查：`/tmp/simichat_full_gate_1752.log` 中未匹配到 `WARNING (drift)` 或 `multiple databases`。
- 卫生检查：`git diff --check` 无输出，正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 `sqlite3.source=system` hook。

## 结论

基础 widget smoke 已改为可释放的内存数据库生命周期，不再污染默认应用数据库；当前理论测试门禁可作为更干净的稳定性基线。该结论仅覆盖本地静态 / 单元 / widget / smoke 理论门禁，不替代 iOS release 真机长时间运行、真实网络切换、真实音频中断等后续真机验证。

---

## Dreaming 销毁中途通知闸门

### 背景

前台自动 Dreaming 在 digest 生成后会继续执行画像提案、反思和完成通知。理论复查发现旧逻辑只在 digest 返回后检查一次 `mounted`：如果页面在画像提案或反思等待期间被销毁，后续仍可能继续触发 Dreaming 完成通知。

### 处理

- 在 `lib/main.dart` 中为 Dreaming 完成通知增加测试可替换 hook：`dreamingDigestCompleteNotifier`。
- 在 `_runDueDreamingIfNeeded()` 的画像提案完成后、反思完成后分别增加 `if (!mounted) return`。
- 新增 `mobile disposed shell skips dreaming notification after proposal wait` 回归测试，用 `_GateUserProfileChangeProposalsNotifier` 精确卡住画像提案写入阶段，模拟页面销毁后再放行。

### 验证

- 红灯：目标用例先失败，`Expected: <0>` / `Actual: <1>`，证明旧逻辑会在销毁后触发完成通知。
- 绿灯：`scripts/smoke_full_stability_gate.sh -r expanded test/smoke/mobile_main_flow_smoke_test.dart --name "mobile disposed shell skips dreaming notification after proposal wait"`，1 项通过。
- 相关 smoke：`scripts/smoke_full_stability_gate.sh -r expanded test/smoke/mobile_main_flow_smoke_test.dart`，9 项通过。
- 静态检查：`flutter --no-version-check analyze` 无问题。
- 全量理论门禁：`scripts/smoke_full_stability_gate.sh -r expanded`，353 项通过；日志 `/tmp/simichat_full_gate_current_182005.log` 未匹配 `WARNING (drift)` 或 `multiple databases`。
- 卫生检查：`git diff --check` 无输出，正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 `sqlite3.source=system` hook。

### 结论

前台自动 Dreaming 在页面销毁后的后续链路更稳：digest 已落盘时仍保留整理结果，但画像提案 / 反思等待期间发生销毁后，不再继续触发完成通知，避免主界面生命周期外的误提示。
