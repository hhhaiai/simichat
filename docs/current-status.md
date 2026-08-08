# 当前项目状态

> **更新时间：2026-08-09**
>
> 本文档是当前状态的快速事实摘要。项目目标、长期待办和历史账本以根目录 `AGENTS.md` 为准；安装和使用入口以根目录 `README.md` 为准；具体实现方案以本目录专题文档为准；本次验证命令与结果以 `verification-baseline-2026-08-08.md` 为准；移动端 MCP / Skills / 记忆专项以 `mobile-mcp-skills-memory-quality-2026-08-08.md` 为准；Node-Mobile 最新构建与真机边界以 `mobile-node-mcp-runtime-2026-08-09.md` 为准。

## 一、当前结论

| 范围 | 当前结论 | 证据边界 |
| --- | --- | --- |
| Dart / Flutter 代码 | 已完成本轮本地模型修复及相关整理 | 静态分析通过 |
| 本地 Ollama 配置 | 已支持无 API Key，自动获取模型时默认勾选 `gemma4` | 设置页、模型预设、模型列表选择逻辑有回归覆盖 |
| Ollama 协议 | 已处理 NDJSON、thinking/content、取消、超时、非 200 响应和可选 Bearer 鉴权 | mock HTTP 协议测试通过 |
| 移动端 MCP | App Native、移动端 stdio 拒绝、SSE 生命周期和设置页入口已收口 | Pixel 8 / iPhone13 逻辑专项各 162 项、UI smoke 各 1 项通过 |
| App Native MCP 真机运行 | 在 App 进程内完成 MCP 初始化、工具发现和 `simichat.runtime_info` / `simichat.now` 调用，不依赖外部环境 | Pixel 8 / iPhone13 各 1 项真实设备 smoke 通过 |
| Android 内置 Node MCP | APK 内置 `nodejs-mobile v18.20.4`、`arm64-v8a/libnode.so` 和 JNI bridge；MCP server 由 APK 内 Node 执行 | Pixel 8 真机 initialize、tools/list、runtime_info、echo 通过；当前只覆盖 arm64-v8a |
| PC 内置 Node MCP | App 只启动随包 Node binary，不回退宿主机 `node` / `npx` / Docker / Podman | bundled Node 真实进程 smoke 与 macOS Flutter App integration 通过；macOS/Xcode、Linux/CMake、Windows/CMake 将 binary 放入 App 安装目录；运行时输出 `SIMICHAT_DESKTOP_BUNDLED_NODE_MCP_READY` |
| Android / PC Node 文档 | 已补齐实现、生命周期、构建、平台矩阵和真实证据边界 | `docs/MCP_BUNDLED_NODE_RUNTIME.md`、`docs/runtime-manifest.example.json` |
| 移动端 Skills | 本地缓存恢复、下载大小 / 编码 / SHA-256 边界、搜索竞态已收口 | Pixel 8 / iPhone13 Skills Hub UI 和逻辑专项通过 |
| 移动端记忆 | Key Point、SQLite FTS、semantic、索引预热 / 修复和搜索竞态已收口 | Pixel 8 / iPhone13 全局搜索 UI 与 162 项专项通过 |
| 移动端扩展包协议 | MCP / Skill / Agent 共用 manifest、SHA-256、权限 allowlist、原子安装、registry、quarantine；Skill / Agent / App Native MCP 已接入 shared provider | `test/mobile_extension_installer_test.dart` 通过；Android Pixel 8 / iPhone13 真机扩展包 smoke 均输出 `SIMICHAT_MOBILE_EXTENSIONS_APP_NATIVE_READY` |
| iOS 纯 JS MCP | NodeMobile bridge、device / simulator XCFramework、App link/embed 和 iPhone13 真机链路已接入 | iPhone13 已出现 `SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY`、`SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY`、`SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY`；状态为 `runtime_verified` |
| Android 构建 | Debug / release APK 构建通过 | `build/app/outputs/flutter-apk/app-debug.apk`、`build/app/outputs/flutter-apk/app-release.apk` |
| 全量测试 | 693 项通过 | `flutter test --no-pub -r compact` |
| 本机真实 Ollama | 当前未验证 | 本机没有 `ollama` 命令，`127.0.0.1:11434` 当前不可连接 |
| 真机 / 长会话 | 当前未在本轮重新验证 | 不能由静态分析、mock 或 APK 构建替代 |
| Android 16 KB page-size / 非 arm64 ABI | source ELF 与 release APK 已完成；真机 / 非 arm64 仍未完成 | 重建后的 `arm64-v8a/libnode.so` 四个 `LOAD` segment 均为 `0x4000`，release APK 全部 native library 与 ZIP 16 KB audit PASS；16 KB 真机和非 arm64 仍未支持 |
| Android Node watchdog | 已实现代码边界 | native state / exit code、single-flight、最多一次启动重试已补齐；长时间锁屏后台仍需 Foreground Service 真机证据 |

## 二、本轮修复逐项记录

### 1. Ollama API Key 可选

- `modelProtocolRequiresApiKey('ollama')` 返回 `false`。
- 设置页显示 `API Key（可选）`。
- 空密钥通过 `KeyEncryptor.decryptOrEmpty()` 读取。
- 非空密钥仍然严格解密，损坏密钥不会被静默吞掉。
- 批量导入和设置页使用同一个协议判断，避免入口之间出现不同规则。

对应文档：

- `README.md`
- `local-model.md`
- `ai-protocols.md`

对应测试：

- `test/key_encryptor_test.dart`
- `test/model_provider_preset_test.dart`
- `test/model_channel_importer_test.dart`
- `test/settings_page_ollama_test.dart`

### 2. Ollama 默认勾选 gemma4

- Ollama 自动获取模型时传入 `preferredModel: 'gemma4'`。
- 默认选择逻辑由 `ModelFetcher.defaultSelectedModelIds()` 统一实现。
- 支持 `gemma4`、`gemma4:latest` 和其他 `gemma4:*` tag 变体。
- 云端渠道没有传入首选模型，继续默认勾选全部新模型。
- Ollama 推荐模型顺序为：`gemma4`、`qwen3:4b`、`llama3.2:3b`。

对应代码：

- `lib/core/ai/model_fetcher.dart`
- `lib/features/settings/settings_page.dart`
- `lib/core/ai/model_provider_preset.dart`

对应测试：

- `test/ollama_protocol_test.dart`
- `test/model_provider_preset_test.dart`

### 3. Ollama 协议稳定性

- 连接超时：15 秒。
- 流式空闲超时：5 分钟。
- CancelToken 取消时关闭 HTTP client。
- `/api/tags` 和 `/api/chat` 均支持可选 Bearer 鉴权。
- 保留 `message.thinking` 和 `message.content`。
- malformed NDJSON 不输出完整模型响应。
- 错误正文限制长度，避免异常响应无限增长。

对应代码：

- `lib/core/ai/ollama_protocol.dart`
- `lib/core/ai/model_fetcher.dart`

### 4. 本地模型验证入口

真实服务验证入口：

```bash
ollama pull gemma4
ollama serve
OLLAMA_MODEL=gemma4 scripts/smoke_local_ollama.sh
```

脚本只验证已经运行的服务，不会自动启动、停止或修改 Ollama。

不同运行环境的 Base URL：

| 环境 | Base URL |
| --- | --- |
| macOS / Linux / Windows 桌面端 | `http://127.0.0.1:11434` |
| iOS Simulator | `http://127.0.0.1:11434` |
| Android Emulator | `http://10.0.2.2:11434` |
| Android / iOS 真机 | Ollama 主机的局域网 IP |

## 三、当前验证门禁

```bash
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
flutter --no-version-check build apk --debug
git diff --check
bash -n scripts/smoke_local_ollama.sh
```

本次结果详见：

```text
docs/verification-baseline-2026-08-08.md
```

移动端 MCP / Skills / 记忆专项结果：

```text
docs/mobile-mcp-skills-memory-quality-2026-08-08.md
```

内置 Node Runtime 专项：

```text
docs/MCP_BUNDLED_NODE_RUNTIME.md
```

当前已复现的专项命令：

```bash
SIMICHAT_MCP_RUNTIME_PORT=37651 ./scripts/smoke_bundled_node_runtime.sh
```

移动端扩展包协议与安装器：

```text
docs/MOBILE_EXTENSIONS.md
lib/core/extensions/
lib/shared/providers/mobile_extension_provider.dart
test/mobile_extension_installer_test.dart
```

预期输出：

```text
SIMICHAT_DESKTOP_BUNDLED_NODE_PROCESS_READY
```

## 四、尚未完成的真实证据

以下项目不能仅凭当前测试标记为已完成：

- 本机真实 `gemma4` 权重是否已安装并能完成推理；
- 首次加载模型的耗时和首 token 延迟；
- 长上下文、Dreaming、Reflection 的本地模型质量；
- Android Emulator、Android 真机、iOS Simulator、iOS 真机的真实网络访问；
- 移动端后台、锁屏、系统资源限制和长时间运行；
- 模型内存 / 显存占用和并发容量。
- Android / iOS 扩展管理页面的真实文件选择器 UI、应用重启后的扩展 registry 恢复和发布包升级回滚仍需单独补证。
- Android Pixel 8 与 iPhone13 已完成扩展包运行时 smoke：Skill SHA-256、启用、Agent `gemma4` plan、App Native MCP initialize / tools/list / tools/call、Agent 卸载均通过；尚未覆盖文件选择器 UI 和真实发布包升级恢复。
- iOS `runtime=node-mobile` 纯 JS MCP 的长时间运行、后台资源限制、升级恢复和更多非 arm64 发布设备仍需单独补证；本轮 iPhone13 的 framework / health / tools/list / tools/call 已通过。

这些项目必须在真实环境中补证，并在新的带日期验证记录中记录，不修改历史验证文档的原始结论。

## 五、当前工作树边界

本轮内置 Node Runtime 变更包含 Android native bridge、PC bundled runtime controller、
manifest、准备 / smoke 脚本、集成测试和文档；Android native library 使用 Git LFS。
平台构建生成的 macOS SwiftPM / CocoaPods 文件不属于本功能源变更，提交前应清理并
在 `git diff --check` 后确认工作树边界。工作树状态不能直接等同于“可发布提交”。

整理文档时只新增或更新入口、状态和专题说明，不删除未跟踪实现文件，不把静态测试结果写成真机成功。
