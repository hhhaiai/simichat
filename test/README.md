# 测试目录说明

`test/` 是仓库内所有 Flutter 单元测试、Widget 测试、静态 manifest 测试、本地 smoke 测试和 benchmark 的统一目录。

当前约定是：**测试文件直接放在 `test/` 根目录，不再按 `core/`、`shared/`、`benchmark/`、`smoke/` 建子目录**。这样可以从一个目录完成盘点、搜索和批量执行，也避免同一类测试被多个路径入口重复描述。

## 目录边界

| 位置 / 命名 | 类型 | 说明 |
| --- | --- | --- |
| `test/*_test.dart` | 单元 / Widget / manifest / 本地 smoke | 默认由 `flutter test` 递归发现；通过文件名区分模块和用途 |
| `test/*_benchmark.dart` | benchmark | 性能或规模基准，不作为每次提交的默认质量门禁 |
| `test/README.md` | 本说明 | 不参与测试运行 |
| `integration_test/*_test.dart` | 真机 / 模拟器集成测试 | 保留 Flutter integration runner 所需的独立入口，不与本地测试混放 |

`*_smoke_test.dart` 表示 Flutter 测试进程内的 smoke 或 manifest 检查；它不自动等同于真实设备 UI 验证。真实设备测试统一放在 `integration_test/`，并通过对应的 `scripts/smoke_device_*.sh` 入口执行。

## 常用命令

### 全量 Flutter 测试

```bash
flutter --no-version-check test --no-pub
```

### 本地模型专项

```bash
flutter --no-version-check test --no-pub \
  test/key_encryptor_test.dart \
  test/model_provider_preset_test.dart \
  test/model_channel_importer_test.dart \
  test/ollama_protocol_test.dart \
  test/settings_page_ollama_test.dart
```

### 指定单个测试

```bash
flutter --no-version-check test --no-pub test/<name>_test.dart
```

### benchmark

benchmark 通过根目录 `scripts/benchmark_*.sh` 运行。脚本内部统一调用 `test/<name>_benchmark.dart`，不要重新恢复分类子目录。

## 整理规则

1. 新增 Flutter 测试直接放到 `test/` 根目录。
2. 文件名必须包含明确的能力或页面名，并以 `_test.dart` 或 `_benchmark.dart` 结尾。
3. 协议、Provider、设置页、数据库和 manifest 测试不再依赖目录名表达分类。
4. 真实设备 / 模拟器交互测试继续放在 `integration_test/`，避免破坏 Flutter integration runner 和现有设备 smoke 脚本。
5. 移动或重命名测试后，必须同步脚本、README、`AGENTS.md`、专题文档和验证记录中的路径。
6. 运行全量测试、静态分析和 `git diff --check` 后，才更新当前验证基线。

## 当前规模

截至本次整理：

- `test/` 共 151 个文件；
- 其中 134 个 `_test.dart`；
- 其中 17 个 `_benchmark.dart`；
- `test/` 下没有分类子目录；
- `integration_test/` 继续作为独立的移动端设备测试目录。
