# 移动端 MCP / Skills / 记忆质量门禁（2026-08-08）

## 1. 验收范围

本轮只收口移动端稳定性，不把桌面端布局、mock 服务或 source inspection 当成真机成功。覆盖三条主线：

1. **MCP**：App 内建 MCP、移动端 `stdio` 硬边界、SSE 连接 / endpoint / timeout / disconnect / HTTP 错误、`web_search` 工具和设置页入口。
2. **Skills**：SkillHub 本地缓存、Generic HTTP 技能源、大小限制、JSON / UTF-8 / SHA-256 校验、分页、搜索竞态、移动端 Skills Hub 页面。
3. **记忆**：Key Point、SQLite FTS、消息语义索引、语义搜索开关、搜索结果上限、搜索竞态、Dreaming / Reflection / background runner / user profile 的本地持久化和失败回退边界。

证据按以下层级记录：

| 标签 | 本轮含义 |
| --- | --- |
| `source_fixed` | 实现路径已修复，见代码路径和行为说明 |
| `tested` | 指定 Dart / Flutter 测试通过 |
| `device_targeted` | `flutter test -d <device>` 在目标真机上运行了专项测试 |
| `ui_verified` | 目标真机真实启动 App、操作页面并完成断言 |
| `blocked_with_evidence` | 有明确现场证据，不能继续写成已完成 |

## 2. 本轮修复

### 2.1 MCP 移动端边界与生命周期

涉及：

- `lib/shared/providers/mcp_provider.dart`
- `lib/core/mcp/mcp_client.dart`
- `lib/features/settings/settings_page.dart`

修复结果：

- 移动端连接旧数据库中的 `stdio` MCP 时，在管理器层直接返回受控错误，不进入 `Process.start()`；移动端设置页也不再提供 `Stdio（PC 高级 / Runtime）` 新建选项。
- 损坏的 `args` / `headers` JSON 不再阻断 provider 初始化；旧的 enabled `stdio` 配置只记录连接失败，不阻塞 `ready`。
- `McpClient.dispose()` 幂等；初始化失败会断开 transport；请求发送失败会清除 pending；销毁 manager 时异步释放所有 client。
- SSE 连接会清理旧连接、重置 message endpoint、限制连接和 endpoint 等待时间、拒绝非 2xx、支持相对 endpoint，并在 disconnect / timeout / POST 错误时释放资源。
- 未连接的 SSE `send()` 现在返回受控异常，不再静默丢失请求；响应正文不完整回显到日志。

### 2.2 Skills 存储、下载和搜索竞态

涉及：

- `lib/core/skills/skill_hub_repository.dart`
- `lib/core/skills/skill_marketplace_source.dart`
- `lib/shared/providers/skill_provider.dart`
- `lib/features/skills/skills_hub_page.dart`

修复结果：

- SkillHub 本地 `online_skills.json` 损坏、截断或类型错误时安全降级为空列表，并改名为 `.corrupt` / `.corrupt.N` 保存证据。
- 线上技能列表使用临时文件、flush、rename 完整写入，失败时清理临时文件；HTTP client 有明确 dispose 路径。
- SkillHub 和 Generic HTTP 技能索引 / 安装文件统一限制为 `512 * 1024` bytes；超过上限在解码前拒绝。
- UTF-8、JSON、SHA-256 元数据错误统一转换为 `SkillImportException`；校验针对原始 response bytes，避免文本重编码造成校验偏差。
- URL、页码、结果数量和最多 1000 项索引结果均有边界；旧搜索请求不能覆盖新搜索结果，notifier 销毁后不再写状态。

### 2.3 记忆和本地搜索

涉及：

- `lib/core/database/dao/message_dao.dart`
- `lib/core/database/dao/session_dao.dart`
- `lib/core/search/local_full_text_search.dart`
- `lib/features/search/search_sheet.dart`

修复结果：

- `limit <= 0` 的本地搜索直接返回空结果；消息、session、FTS、semantic 查询均归一化结果上限，避免移动端无界读取大量消息。
- 全局搜索输入增加 generation；清空搜索立即结束 loading；旧查询不会覆盖新查询；页面销毁后异步结果不再 `setState`。
- 保留 Key Point、SQLite FTS、消息语义搜索、语义搜索开关和索引检查 / 预热 / 修复路径。
- 设置页移动端 MCP 添加服务器弹窗在窄屏下通过 `DropdownButtonFormField.isExpanded` 收口传输方式选择器，修复 iPhone13 真机发现的右侧 12 px `RenderFlex` 溢出。

## 3. 真机结果

### 3.1 Pixel 8

设备：`Pixel 8`，Android 16 / API 36，`37101FDJH0077P`。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| MCP / Skills / 记忆逻辑专项 | `device_targeted` 通过，162 项 | `/tmp/simichat-mcp-skills-memory-logic-pixel8-final.log` |
| MCP / Skills / 记忆真实 UI smoke | `ui_verified` 通过，1 项 | `/tmp/simichat-mcp-skills-memory-ui-pixel8-final.log` |

真实 UI smoke 覆盖 Android Drawer、Skills Hub HTTP 搜索、设置页 MCP 区、App Native MCP、移动端隐藏 stdio、搜索索引预热 / 修复、全局搜索 bottom sheet、SQLite FTS / semantic / message 结果渲染和页面返回。

### 3.2 iPhone13

设备：`iPhone13`，iOS 26.5 / `23F77`，`00008110-0016349A3A20A01E`。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| MCP / Skills / 记忆逻辑专项 | `device_targeted` 通过，162 项 | `/tmp/simichat-mcp-skills-memory-logic-iphone13-final.log` |
| MCP / Skills / 记忆真实 UI smoke | `ui_verified` 通过，1 项 | `/tmp/simichat-mcp-skills-memory-ui-iphone13-final.log` |

首次 iPhone13 UI 复跑发现：添加 MCP 服务器弹窗中的 `DropdownButtonFormField<String>` 在真实窄屏下溢出 12 px；修复为 `isExpanded: true` 后，iPhone13 UI smoke 重新运行通过。修复后的最终日志不包含 Flutter layout exception。

## 4. 可复现命令

### 4.1 真实移动 UI smoke

默认使用应用正常 native asset 配置，不使用测试替代实现：

```bash
flutter --no-version-check test \
  integration_test/mobile_mcp_skills_memory_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded

flutter --no-version-check test \
  integration_test/mobile_mcp_skills_memory_smoke_test.dart \
  -d 00008110-0016349A3A20A01E --no-pub -r expanded
```

### 4.2 逻辑专项

同一组 21 个测试文件在两台设备上复跑：

```bash
MCP_MEMORY_TESTS=(
  test/mcp_app_native_transport_test.dart
  test/mcp_runtime_provider_test.dart
  test/mcp_sse_transport_test.dart
  test/mcp_web_search_tool_test.dart
  test/skill_marketplace_source_test.dart
  test/key_point_memory_test.dart
  test/key_point_memory_provider_test.dart
  test/local_full_text_search_test.dart
  test/settings_page_search_index_test.dart
  test/dreaming_service_test.dart
  test/dreaming_provider_test.dart
  test/reflection_service_test.dart
  test/reflection_provider_test.dart
  test/dreaming_background_runner_test.dart
  test/model_reflection_service_test.dart
  test/model_reflection_protocol_integration_test.dart
  test/user_profile_test.dart
  test/user_profile_provider_test.dart
  test/settings_page_dreaming_test.dart
  test/settings_page_user_profile_test.dart
)

flutter --no-version-check test -d 37101FDJH0077P --no-pub \
  --dart-define=sqlite3.source=system "${MCP_MEMORY_TESTS[@]}" -r expanded

flutter --no-version-check test -d 00008110-0016349A3A20A01E --no-pub \
  --dart-define=sqlite3.source=system "${MCP_MEMORY_TESTS[@]}" -r expanded
```

当前验证命令额外使用：

```bash
--dart-define=sqlite3.source=system
```

该参数只用于 Flutter 测试 runner 的 macOS native asset 构建：本轮默认 native asset 下载因 GitHub 连接超时失败，使用系统 SQLite 后 162 项专项测试在 Pixel 8 和 iPhone13 均通过。它没有写入 `pubspec.yaml` / `pubspec.lock`，也没有用于上述真实 UI smoke；正式应用配置仍以仓库 `pubspec.yaml` 为准。

### 4.3 仓库门禁

```bash
flutter --no-version-check test --no-pub --no-test-assets -r expanded
flutter --no-version-check analyze --no-pub
git diff --check
```

本轮结果：全量 Flutter 测试 **672 项通过**；Dart analyze `No issues found!`；`git diff --check` 无输出。

## 5. 尚未被本轮证明的边界

以下边界不能由本轮 UI smoke 或 162 项逻辑专项替代：

- 长时间、弱网、真实远程 MCP SSE 的断线重连和服务端恢复；本轮验证的是 transport 边界和本地 UI 路径。
- iOS 系统 `BGTaskScheduler` 真正由系统后台执行；现有 iPhone13 证据仍受设备 Background App Refresh 状态限制。
- Android OEM 严格后台限制、跨日 / 长期 Doze 和长时间进程回收；本轮只复用了既有后台专项代码 / provider 回归。
- 真实 Ollama `gemma4` 权重、移动端局域网地址、长上下文本地模型质量；详见 `docs/local-model.md` 和 `docs/verification-baseline-2026-08-08.md`。

因此本轮结论是：**MCP、Skills、记忆的核心移动 UI 路径已在 Pixel 8 和 iPhone13 通过，相关逻辑专项也在两台真机目标上重复通过；系统后台、长时外部网络和真实本地模型仍保持单独的未证明边界。**
