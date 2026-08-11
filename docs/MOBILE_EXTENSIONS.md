# Android / iOS / PC 本地 MCP、Skills、Agent 安装协议

## 1. 目标与当前边界

SimiChat 的移动端扩展不是一个任意 npm / npx 安装器，而是 App 自己管理的、可回滚的扩展包系统：

```text
下载 bytes
  -> .part
  -> UTF-8 / JSON
  -> manifest 校验
  -> entry size + SHA-256 校验
  -> 权限 allowlist 校验
  -> 路径穿越校验
  -> App sandbox 原子安装
  -> registry.json 持久化
  -> enable / platform adapter
```

目标承诺是：**Android / iOS / PC 可以直接安装经过 manifest、SHA-256 和权限校验的 MCP、Skills、Agents。**

| 类型 | Android | iOS | 当前执行方式 |
| --- | --- | --- | --- |
| App Native MCP | 支持并可直接连接 | 支持并可直接连接 | Flutter / Dart 内建 handler |
| `runtime=node-mobile` 纯 JS MCP | APK 内置 Node，支持纯 JS 包安装、注册和 JSONL stdio session | App 内置 NodeMobile framework，支持纯 JS 包安装、注册和 JSONL stdio session | macOS / Linux / Windows 使用随包 Node 和同一 JSONL stdio bridge |
| Markdown Skill | 支持 | 支持 | Dart 读取并注入 system prompt |
| Declarative Agent | 支持 | 支持 | Dart 编排；默认模型 `gemma4` |
| `stdio` / `npx` MCP | `stdio-v1` 走 App-owned JSONL stdin/stdout session；旧 `stdio-compat-v1` / 已审核 npx 保留 adapter 兼容；未知包拒绝 | `stdio-v1` 走 App-owned JSONL stdin/stdout session；旧 `stdio-compat-v1` / 已审核 npx 保留 adapter 兼容；未知包拒绝 | 不启动宿主机 stdio / npx 进程；使用随 App 提供的 Runtime |
| native addon / 下载二进制 | 不支持动态安装 | 不支持动态安装 | 构建时集成，不能由包引入 |

这份文档区分“包已安装”和“运行时已连接”。安装成功不等于任意 MCP 已经具备可用执行端点。

## 2. 包格式 v1

移动端下载的是 JSON envelope，不是 npm tarball，也不是 zip：

```json
{
  "packageFormat": 1,
  "manifest": {
    "id": "mobile-research-agent",
    "version": "1.0.0",
    "type": "agent",
    "entry": "agent.json",
    "sha256": "<entry file SHA-256 hex>",
    "sizeBytes": 256,
    "runtime": "declarative",
    "name": "移动研究员",
    "description": "只使用本地声明式能力的 Agent",
    "nativeAddon": false,
    "permissions": ["memory.read", "mcp.call"],
    "autoEnable": false
  },
  "files": {
    "agent.json": "<base64>",
    "prompts/system.md": "<base64>"
  }
}
```

### 2.1 manifest 字段

| 字段 | 必填 | 约束 |
| --- | --- | --- |
| `id` | 是 | 2–128 位小写字母、数字、`.`, `_`, `-` |
| `version` | 是 | 非空；同时作为 sandbox 目录名，不能包含路径穿越 |
| `type` | 是 | `mcp` / `skill` / `agent` |
| `entry` | 是 | 相对路径；不能是绝对路径、`.`、`..`、盘符 |
| `sha256` | 是 | entry 原始 bytes 的 64 位小写 SHA-256 |
| `sizeBytes` | 是 | entry 原始 bytes 大小，最大 10 MB |
| `runtime` | 是 | Skill=`dart`，Agent=`declarative`，纯 JS MCP=`node-mobile` |
| `nativeAddon` | 是 | 必须为 `false` |
| `permissions` | 是 | 只能使用已知 capability |
| `mcpTransport` | MCP 可选 | `app_native` 或 `sse` |
| `mcpServerId` | app-native MCP 必填 | 只能绑定 App 已内置的 handler |
| `autoEnable` | 否 | 默认 `false`；必须由用户或审核包显式打开 |

已知 capability：

```text
network
filesystem.app_container
clipboard
photo_picker
calendar
contacts
memory.read
mcp.call
```

未知权限直接拒绝。权限是 App capability，不等同于给扩展一个 shell、任意文件系统或任意进程权限。

### 2.2 类型约束

- Skill：`runtime=dart`，`entry` 必须为 Markdown；正文进入现有 `Skill` 模型，SHA-256 标记为已验证。
- Agent：`runtime=declarative`，`entry` 必须为 JSON；可引用包内 `prompt` Markdown，不允许入口代码。
- 纯 JS MCP：`runtime=node-mobile`，`entry` 必须为 `.js` / `.mjs`；只能由 App 自己随包提供的 Node runtime 处理。
- App Native MCP：`runtime=dart`，`mcpTransport=app_native`，必须绑定已存在的 `mcpServerId`；安装包不能新增 Dart/native handler。

## 3. 安装与回滚

实现文件：

```text
lib/core/extensions/mobile_extension_manifest.dart
lib/core/extensions/mobile_extension_store.dart
lib/core/extensions/mobile_extension_registry.dart
lib/core/extensions/mobile_extension_installer.dart
lib/core/extensions/mobile_extension_adapters.dart
lib/core/extensions/mobile_extension_agent.dart
lib/core/extensions/mobile_extension_service.dart
lib/shared/providers/mobile_extension_provider.dart
```

### 3.1 文件布局

```text
<App support>/simichat_extensions/
  registry.json
  downloads/*.part
  quarantine/*.package
  installed/<type>/<id>/<version>/
    manifest.json
    <entry and supporting files>
```

### 3.2 安装阶段

1. HTTP(S) 响应先写入 `downloads/*.part`，超过 20 MB 在 JSON 解码前拒绝。
2. 按原始 bytes 做 UTF-8、JSON、manifest、entry size、entry SHA-256 校验。
3. 所有文件都检查相对路径；不能写到安装目录外。
4. 文件先写入同一父目录下的 `.installing-*` 临时目录。
5. 已有同版本目录先改名为 `.backup-*`，新目录完成后再替换；失败时恢复 backup。
6. `registry.json` 使用同目录临时文件和 rename 更新，记录状态、版本、路径、启用状态和错误。
7. 解析失败、哈希失败或下载失败的 bytes 进入 `quarantine/`，不会作为可运行扩展留下。

### 3.3 状态

```text
available -> downloading -> downloaded -> verifying -> installing
                                                   -> installed
                                                   -> enabled
                                                   -> disabled
                                                   -> failed / quarantined
```

`installed` 与 `enabled` 是两个不同状态。用户关闭权限、MCP 连接失败或 App 重启后，包仍可以保留在 registry 中而不阻塞主聊天。

## 4. 三类运行链路

### 4.1 Skills

`installMobileExtension` 会把经过校验的 Markdown 写入现有 Skills 表：

```text
package -> skillFromMobileExtension -> SkillDao.upsertSkill
       -> enabledSkillsProvider
       -> buildSkillsSystemPrompt
       -> ContextBuilder
```

重复安装同一 `id` 是幂等 upsert，不会因为 SQLite 主键重复把页面打崩。Skill 自身没有 shell 执行接口；需要系统能力时必须通过已声明 capability 和 App 预定义桥接。

### 4.2 Agents

Agent 是声明式配置，不是下载执行文件。`agent.json` 可以声明：

```json
{
  "name": "移动研究员",
  "model": "gemma4",
  "prompt": "prompts/system.md",
  "skills": ["skill-summary"],
  "mcpServers": ["simichat-local"],
  "permissions": ["memory.read", "mcp.call"]
}
```

`MobileAgentRuntime.buildPlan` 在真正请求前检查：

- 所有 Skill 已安装且已启用；
- 所有 MCP 已连接；
- 只把声明的 Skill / MCP 放入计划；
- `model` 为空时使用本地默认 `gemma4`；
- prompt 与 Skills 合并到现有上下文构建链，不静默改变用户选中的远程渠道。

当前 Agent 运行的真实模型请求仍由现有 `AiService` / `ContextBuilder` 负责；Agent planner 本身不启动外部进程。

### 4.3 MCP

#### App Native MCP

这是 Android / iOS 当前最稳定的直接安装路径。安装包只能声明一个已经编译进 App 的 `mcpServerId`。安装激活后，shared provider 创建 `McpServerConfig`，调用现有 `McpManager` 完成 `initialize`，随后可用于 `tools/list` 和 `tools/call`。

#### Bundled Node MCP

Android 已有 APK 内置 `libnode.so`、JNI bridge、health、SSE 和重试生命周期；
PC 使用随包 Node binary；iOS 使用随 App 发布的 `NodeMobile.xcframework` 和
Swift / Objective-C++ bridge。这个运行时不调用宿主机 `node` / `npx` / Docker /
Podman。纯 JS MCP 包会由 installer 校验并写入 App sandbox，随后将安装目录、entry、
协议、SHA-256 和 permissions 交给 bundled Node endpoint。

#### iOS

iOS 的 Skills、声明式 Agents 和 App Native MCP 不依赖 Node，可以直接安装和运行。
纯 JS MCP 通过 App 内置 `NodeMobile.xcframework` 运行，Node server 与 Flutter
通过 `127.0.0.1` SSE 连接；不要求 iOS 外部 node、npx、shell、Docker 或网络服务。

## 5. 失败与恢复验收

最小测试：

```bash
flutter test --no-pub test/mobile_extension_installer_test.dart
flutter analyze
```

Android / iOS 真机 smoke：

```bash
DEVICE_ID=<android-device-id> ./scripts/smoke_device_mobile_extensions.sh
DEVICE_ID=<ios-device-id> ./scripts/smoke_device_mobile_extensions.sh
```

当前真机入口为 `integration_test/mobile_extensions_real_smoke_test.dart` 与
`integration_test/mobile_node_mcp_real_smoke_test.dart`，覆盖 Skill SHA-256、
启用、Agent `gemma4` plan、App Native MCP `initialize` / `tools/list` /
`tools/call`、Agent 卸载，以及纯 JS `mobile-mcp-v1`、`stdio-compat-v1` 和
legacy npx in-process adapter。

纯 JS / 兼容层真机 marker：

```text
SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY
SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
```

必须覆盖：

- Skill 安装、upsert、enable、uninstall；
- Agent 安装、prompt 引用、`gemma4` 默认值、Skill/MCP allowlist；
- App Native MCP 安装描述；
- UTF-8 / JSON / size / SHA-256 / permission 失败；
- `../` 路径穿越；
- `.part`、quarantine、registry 损坏恢复；
- 安装中断后旧版本可恢复；
- App 重启后从 registry 恢复，不依赖 PC、宿主 Node、Docker 或 Podman。

真实设备验收要另外记录：

```text
Android Pixel 8: install Skill / Agent / App Native MCP / initialize / tools/list / tools/call
iPhone:         install Skill / Agent / App Native MCP / initialize / tools/list / tools/call
```

没有对应设备日志时，只能标记 `host_verified` 或 `runtime_verified`，不能标记 `ui_verified`。

## 6. 不支持的设计

以下路径明确拒绝或转移，不作为移动端直接安装能力；只有已审核 adapter 才会保留
对应 MCP 的工具语义：

```text
npm install 任意依赖
npx -y 任意 MCP
下载并执行 Mach-O / ELF / .so / .dylib / .dll
动态安装 native addon
child_process / shell / exec / spawn
把 iOS / Android 做成任意代码应用商店
```

需要上述能力的 MCP 应构建进 App、放到 PC bundled Node、或部署为远程 MCP 服务；移动端只保存经过校验的声明和连接配置。
