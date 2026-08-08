# 当前项目状态

> **更新时间：2026-08-08**
>
> 本文档是当前状态的快速事实摘要。项目目标、长期待办和历史账本以根目录 `AGENTS.md` 为准；安装和使用入口以根目录 `README.md` 为准；具体实现方案以本目录专题文档为准；本次验证命令与结果以 `verification-baseline-2026-08-08.md` 为准；移动端 MCP / Skills / 记忆专项以 `mobile-mcp-skills-memory-quality-2026-08-08.md` 为准。

## 一、当前结论

| 范围 | 当前结论 | 证据边界 |
| --- | --- | --- |
| Dart / Flutter 代码 | 已完成本轮本地模型修复及相关整理 | 静态分析通过 |
| 本地 Ollama 配置 | 已支持无 API Key，自动获取模型时默认勾选 `gemma4` | 设置页、模型预设、模型列表选择逻辑有回归覆盖 |
| Ollama 协议 | 已处理 NDJSON、thinking/content、取消、超时、非 200 响应和可选 Bearer 鉴权 | mock HTTP 协议测试通过 |
| 移动端 MCP | App Native、移动端 stdio 拒绝、SSE 生命周期和设置页入口已收口 | Pixel 8 / iPhone13 逻辑专项各 162 项、UI smoke 各 1 项通过 |
| App Native MCP 真机运行 | 在 App 进程内完成 MCP 初始化、工具发现和 `simichat.runtime_info` / `simichat.now` 调用，不依赖外部环境 | Pixel 8 / iPhone13 各 1 项真实设备 smoke 通过 |
| 移动端 Skills | 本地缓存恢复、下载大小 / 编码 / SHA-256 边界、搜索竞态已收口 | Pixel 8 / iPhone13 Skills Hub UI 和逻辑专项通过 |
| 移动端记忆 | Key Point、SQLite FTS、semantic、索引预热 / 修复和搜索竞态已收口 | Pixel 8 / iPhone13 全局搜索 UI 与 162 项专项通过 |
| Android 构建 | Debug APK 构建通过 | `build/app/outputs/flutter-apk/app-debug.apk` |
| 全量测试 | 672 项通过 | `flutter --no-version-check test --no-pub --no-test-assets -r expanded` |
| 本机真实 Ollama | 当前未验证 | 本机没有 `ollama` 命令，`127.0.0.1:11434` 当前不可连接 |
| 真机 / 长会话 | 当前未在本轮重新验证 | 不能由静态分析、mock 或 APK 构建替代 |

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

## 四、尚未完成的真实证据

以下项目不能仅凭当前测试标记为已完成：

- 本机真实 `gemma4` 权重是否已安装并能完成推理；
- 首次加载模型的耗时和首 token 延迟；
- 长上下文、Dreaming、Reflection 的本地模型质量；
- Android Emulator、Android 真机、iOS Simulator、iOS 真机的真实网络访问；
- 移动端后台、锁屏、系统资源限制和长时间运行；
- 模型内存 / 显存占用和并发容量。

这些项目必须在真实环境中补证，并在新的带日期验证记录中记录，不修改历史验证文档的原始结论。

## 五、当前工作树边界

本轮没有执行 reset、clean、删除、覆盖、commit 或 push。当前仓库仍保留原有未提交代码、测试、平台生成文件和未跟踪功能实现；工作树状态不能直接等同于“可发布提交”。

整理文档时只新增或更新入口、状态和专题说明，不删除未跟踪实现文件，不把静态测试结果写成真机成功。
