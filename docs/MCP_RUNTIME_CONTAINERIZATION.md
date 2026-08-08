# simichat MCP Runtime 容器化设计

## 背景

当前 `simichat` 已经具备：

- 多模型协议适配（OpenAI / Claude / Gemini / Ollama）
- Skills 注入
- MCP Server 配置、连接、工具发现、工具调用
- AI → Tool Call → Tool Result → AI Final Reply 的对话闭环

但当前 MCP 运行方式仍然偏“客户端直连外部进程”：

- UI / Provider 直接管理 MCP Server 生命周期
- `stdio` 类型 MCP 依赖宿主机上的 `node` / `npx` / `npm` / `python`
- 权限、安装、运行、日志、故障恢复都分散在桌面端逻辑里

这更像“单机高级客户端”，还不是“团队级内部 AI 调度工具”。

如果目标是做成团队内部使用的 AI 调度台，MCP 应该进入一层独立的 Runtime 容器化设计，而不是继续把安装与运行细节耦合在聊天 UI 中。

---

## 目标

把 MCP 从“客户端直接拉起外部命令”升级为：

> **App 调用 MCP Runtime，Runtime 负责安装、启动、隔离、权限、日志、状态与工具桥接**

目标能力：

1. **统一运行时**
   - App 不再直接依赖宿主机 `npx`
   - 支持 Node / Python / Binary / Remote SSE 等多种 MCP 来源

2. **团队级治理**
   - MCP Server 安装来源可控
   - 运行权限可控
   - 工具调用可记录
   - 故障状态可见

3. **跨平台一致性**
   - Windows / macOS / Linux 行为一致
   - GUI 启动时不再依赖用户 shell 环境差异

4. **可演进**
   - 短期兼容现有 MCP 生态
   - 中期内建高频工具
   - 长期支持团队共享与调度编排

---

## 非目标

当前阶段不追求：

- 直接用 Docker/Podman 作为首发桌面容器层
- 一步到位做成云端多租户平台
- 把所有 MCP 都重写成内建模块
- 一次性解决所有团队权限/审计/SSO 问题

---

## 2026-07-08 已落地切片：App 内建 MCP Runtime v1

本轮先把移动端必须可直接运行的 MCP 基线落到代码里：

- 新增 `app_native` 传输：`lib/core/mcp/mcp_client.dart` 内的 `AppNativeMcpTransport` 直接在 App 进程内响应 MCP JSON-RPC，不启动 `Process.start(...)`，不依赖宿主机 `node` / `npx` / `python`。
- 内建工具：`simichat.now`、`simichat.runtime_info`；内建资源：`simichat://runtime/info`。
- `McpManager` 已支持 `app_native`，并提供 `ready` Future 便于测试和后续启动门禁。
- MCP 市场首位新增 `SimiChat 内建工具`，安装后会自动连接；设置页新增并默认选择 `App 内建（移动端/PC 直接运行）`。
- 传统 `stdio` / `SSE` 仍保留为 PC 高级连接，但不再是移动端可运行 MCP 的默认路径；Node MCP 生态后续应走桌面 Runtime/容器侧车，而不是让移动端或 GUI 直接依赖宿主机环境。

验证：

```bash
flutter --no-version-check test --no-pub --no-test-assets test/mcp_app_native_transport_test.dart -r expanded
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub --no-test-assets -r expanded
```

覆盖内容：内建传输初始化、工具调用、时区参数、市场首项为移动端可运行内建 MCP、`McpManager` 无 stdio command 连接内建 MCP；随后 analyzer 无问题，全量 Flutter 测试 461 项通过。

## 2026-08-08 移动端真机决策：App Native 优先，Android 另提供内置 Node Runtime

本轮新增独立真机 smoke：

```text
integration_test/mobile_mcp_app_native_real_smoke_test.dart
```

该 smoke 在 Pixel 8 和 iPhone13 上通过真实 `McpManager` 完成：

- 从本地内存数据库加载启用的 `app_native` MCP 配置；
- 在 App 进程内完成 MCP `initialize`、`tools/list`；
- 调用 `simichat.runtime_info`；
- 调用 `simichat.now` 并校验 UTC+08:00 转换；
- 校验 `externalProcess=false`、`requiresNode=false`、`requiresNpx=false`、`requiresPython=false`、`mobileReady=true`。

这条验证链不启动 HTTP mock、远程 SSE、`node`、`npx`、Python、Docker 或 Podman。证明 App Native 移动端 MCP 不依赖外部运行时。

随后为满足“Android App / PC App 直接内置 Node 框架”的要求，新增独立的
`simichat-node-bundled` 路径：Android APK 使用 `nodejs-mobile v18.20.4` 的
`arm64-v8a/libnode.so` 和 JNI bridge；PC 使用构建前由
`scripts/prepare_node_runtime.sh` 准备的官方 Node executable。两条路径都由
`BundledNodeRuntime` / `McpManager` 管理，不回退到宿主机 `node`、`npx`、Docker
或 Podman。Android Pixel 8 真机已完成 initialize、tools/list、runtime_info 和
echo 的真实 Node 链路验证。

当前边界保持明确：移动端 `stdio` 继续拒绝；`simichat-node-container` 仍作为
PC 可选隔离侧车保留，但不再是 PC 内置 Node 的唯一路径。Android 当前只交付
arm64-v8a，16 KB page-size 设备、非 arm64 ABI 和 Android 长时间后台仍需单独
验收。PC host-side bundled process smoke 与 macOS Flutter PC App 集成已通过；
Linux / Windows 发布包仍需逐平台生成并启动验证。实现、命令和证据矩阵详见
`docs/MCP_BUNDLED_NODE_RUNTIME.md`。

---




## 2026-07-09 已落地切片：容器内建工具与权限边界 v1

本轮继续把 PC Node 容器 Runtime 从“状态 / echo 验证”推进到可用工具：

- 新增容器内建工具：`simichat.fs_list`、`simichat.fs_read_text`、`simichat.fetch_text`。
- 文件工具只允许访问 `MCP_RUNTIME_WORKSPACE_ROOT` 内的相对路径，拒绝绝对路径和越界路径；文本读取受 `MCP_RUNTIME_MAX_TEXT_BYTES` 限制。
- Fetch 工具只允许 HTTP(S) GET，返回文本摘要并受同一最大字节限制。
- 这些能力在容器内由 Node 直接提供，替代默认路径里对宿主机 `npx` filesystem/fetch 类 MCP 的依赖；旧 stdio / npx 条目仍作为高级手动配置保留，但默认不自动启用。
- `scripts/mcp_runtime_container.sh smoke` 已扩展验证 `tools/list`、`simichat.echo`、`simichat.fs_list` 和 `simichat.fetch_text`。

真实容器验证：

```bash
SIMICHAT_MCP_RUNTIME_BASE_IMAGE=ghcr.io/basketikun/infinite-canvas:latest \
SIMICHAT_MCP_RUNTIME_IMAGE=simichat-mcp-runtime:smoke \
scripts/mcp_runtime_container.sh smoke
# SMOKE_HEALTH_OK
# SMOKE_TOOL_LIST_OK
# SMOKE_TOOL_CALL_OK
# SMOKE_FS_TOOL_OK
# SMOKE_FETCH_TOOL_OK
```

复查 `scripts/mcp_runtime_container.sh status` 显示未留下运行容器，临时 smoke 镜像已清理。

## 2026-07-09 已落地切片：App 侧 MCP Runtime 管理入口 v1

本轮把 PC 容器 Runtime 从“只有脚本和市场 SSE 条目”继续推进到 App 可见 / 可操作的管理入口：

- 新增 `lib/shared/providers/mcp_runtime_provider.dart`：`McpRuntimeController` 管理 PC Node 容器 Runtime 的 `status/start/stop/smoke`，并在移动端明确返回 unsupported 状态，提示移动端使用 App 内建 MCP Runtime；桌面打包时会从 Flutter assets 把 Runtime 脚本 / Dockerfile / Node server 写入应用支持目录后再执行，避免依赖源码仓库路径。
- 设置页 MCP 区新增“MCP Runtime（内建 / PC 容器）”入口：移动端展示 App 内建边界；PC 端可刷新状态、启动容器、停止容器和运行 smoke。
- 该入口优先调用开发仓库中的 `scripts/mcp_runtime_container.sh`；打包后使用随 App 资产释放到本机应用支持目录的同一套脚本与容器文件。脚本仍不调用宿主机 `node/npm/npx`；Node MCP 继续走容器侧车 SSE。
- 新增 `test/mcp_runtime_provider_test.dart` 与 `test/settings_page_mcp_runtime_test.dart` 覆盖移动端边界、PC lifecycle 输出解析、失败诊断和设置页可见入口。

验证：

```bash
flutter --no-version-check test --no-pub --no-test-assets test/mcp_runtime_provider_test.dart test/settings_page_mcp_runtime_test.dart -r expanded
flutter --no-version-check test --no-pub test/mcp_runtime_container_manifest_test.dart -r expanded
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub --no-test-assets -r expanded
```

## 2026-07-08 已落地切片：PC Node MCP 容器侧车 v1

本轮继续补 PC 端 Node MCP 的自依赖路径：

- 新增 `tools/mcp_runtime/container/Dockerfile`，默认基于 `node:22-alpine`，并支持 `SIMICHAT_MCP_RUNTIME_BASE_IMAGE` 切换到企业镜像源 / 预拉取 Node 镜像；Node 随容器分发，不读取宿主机 `node` / `npm` / `npx`。
- 新增 `tools/mcp_runtime/container/runtime-server.mjs`，提供 MCP SSE 兼容端点：`/mcp/sse/:serverId` 与 `/mcp/messages/:connectionId`。
- 新增内建容器工具：`simichat.node_runtime_info`、`simichat.echo`；健康检查：`/health`。
- 新增 `scripts/mcp_runtime_container.sh`，支持 `build/start/stop/restart/status/logs/smoke`，自动选择 Docker / Podman，但脚本本身不调用宿主机 Node/npm/npx；`smoke` 会启动容器并验证 `/health`、MCP SSE `tools/list` 和 `simichat.echo` 调用链路。
- 新增 `docs/runtime-manifest.example.json`，同时记录 App Native、Android / PC bundled Node 和 PC `node-container` 三条自依赖路径。
- MCP 市场新增 `SimiChat Node 容器 Runtime`，默认连接 `http://127.0.0.1:37651/mcp/sse/simichat-node`。
- MCP 市场旧 `stdio` / `npx` 条目安装后默认禁用，不再自动连接或弹出直接连接动作，避免移动端 / 普通 PC 路径继续依赖宿主机命令；需要旧 stdio 的用户只能作为高级手动配置处理，默认推荐容器 Runtime。

验证：

```bash
flutter --no-version-check test --no-pub --no-test-assets test/mcp_runtime_container_manifest_test.dart -r expanded
flutter --no-version-check test --no-pub --no-test-assets test/mcp_sse_transport_test.dart -r expanded
flutter --no-version-check test --no-pub --no-test-assets test/mcp_app_native_transport_test.dart test/mcp_runtime_container_manifest_test.dart test/mcp_sse_transport_test.dart -r expanded
flutter --no-version-check analyze --no-pub
scripts/mcp_runtime_container.sh smoke
```

覆盖内容：Dockerfile 自带 Node、runtime server 暴露 MCP SSE / message / tools 调用入口、容器脚本 `bash -n` 通过且不调用宿主机 Node/npm/npx、市场项和 manifest 均指向 PC 容器侧车；同时补 `SseTransport` 相对 `/mcp/messages/...` endpoint 回归，确保容器 SSE 返回相对地址时客户端会按 SSE 源地址解析为 `http://127.0.0.1:37651/mcp/messages/...` 后再 POST。

本轮已启动 OrbStack / Docker daemon，并新增 `scripts/mcp_runtime_container.sh smoke` 作为真实容器闭环自检入口。默认 Docker Hub 拉取 `node:22-alpine` 在当前网络下仍遇到 `Bad Gateway`，因此脚本新增 `SIMICHAT_MCP_RUNTIME_BASE_IMAGE` 镜像源 / 预拉取基镜像覆盖；使用本机已存在且自带 Node 22 的镜像验证通过：

```bash
SIMICHAT_MCP_RUNTIME_BASE_IMAGE=ghcr.io/basketikun/infinite-canvas:latest \
SIMICHAT_MCP_RUNTIME_IMAGE=simichat-mcp-runtime:smoke \
scripts/mcp_runtime_container.sh smoke
# SimiChat MCP runtime started: http://127.0.0.1:37651/mcp/sse/simichat-node
# SMOKE_HEALTH_OK
# SMOKE_TOOL_LIST_OK
# SMOKE_TOOL_CALL_OK
```

验证后复查 `scripts/mcp_runtime_container.sh status`，未留下运行容器；临时 `simichat-mcp-runtime:smoke` 镜像已清理。

---

## 总体架构

```text
simichat UI
  └─ Chat / Session / Settings / Skills / Marketplace
       ↓
Orchestrator Layer
  └─ prompt / context / skill / tool-call loop / task dispatch
       ↓
MCP Runtime Client
  └─ 统一请求 install / start / stop / status / logs / call
       ↓
MCP Runtime Daemon
  ├─ Runtime Registry
  ├─ Process Supervisor
  ├─ Permission Gate
  ├─ Tool Bridge
  ├─ Artifact / Log Store
  └─ Runtime Adapters
       ├─ Node Adapter
       ├─ Python Adapter
       ├─ Binary Adapter
       └─ Remote SSE Adapter
```

核心原则：

- **UI 不直接启动进程**
- **MCP Runtime 统一托管进程**
- **客户端只面向 Runtime API**

---

## 为什么不直接继续依赖宿主机 npx

当前方式的问题：

1. **宿主机环境不一致**
   - GUI 进程 PATH 与 shell PATH 不一致
   - Windows `npx.cmd` / Linux `npx` / macOS Homebrew / nvm 路径差异大

2. **权限不可控**
   - 哪个 MCP 能访问文件系统、网络、浏览器，当前缺少运行时级治理

3. **安装状态不透明**
   - 用户不知道 MCP 是否真正安装、真正运行、启动失败原因是什么

4. **团队部署困难**
   - 不能要求团队每台机器手工配 node/npm/python 环境

因此：

> `npx` 只是 MCP 生态接入方式，不应该成为产品运行时边界。

---

## Runtime 形态建议

### 方案选择

首发建议采用：

> **本地 Sidecar Runtime Daemon**

而不是直接上 Docker。

理由：

- 桌面端用户机器不一定有 Docker
- Windows/macOS/Linux 的 Docker 依赖体验重
- GUI 集成 Docker 生命周期复杂
- 当前目标是先做团队级桌面工具，不是云端容器平台

### Runtime 部署位置

每个平台本地一个后台 runtime：

- macOS: `~/Library/Application Support/simichat/runtime/`
- Linux: `~/.local/share/simichat/runtime/`
- Windows: `%APPDATA%\\simichat\\runtime\\`

目录建议：

```text
runtime/
  registry/
    servers/
      filesystem/
        manifest.json
        state.json
      memory/
      puppeteer/
  runtimes/
    node/
    python/
    binary/
  packages/
    node/
      @modelcontextprotocol/
    python/
  logs/
    filesystem/
      stdout.log
      stderr.log
      runtime.log
  cache/
  tmp/
  artifacts/
```

---

## MCP Server Manifest 设计

每个 MCP Server 不应只保存“command + args”，而应保存标准 Manifest。

示例：

```json
{
  "id": "filesystem",
  "name": "Filesystem",
  "version": "1.0.0",
  "runtime": "node",
  "install": {
    "type": "npm",
    "package": "@modelcontextprotocol/server-filesystem",
    "version": "latest"
  },
  "launch": {
    "transport": "stdio",
    "command": "node",
    "entry": "dist/index.js",
    "args": []
  },
  "permissions": {
    "fsRead": true,
    "fsWrite": true,
    "network": false,
    "browser": false,
    "spawn": false
  },
  "healthcheck": {
    "method": "initialize"
  },
  "source": {
    "type": "registry",
    "marketplaceId": "filesystem"
  }
}
```

这样可以把：

- 安装方式
- 启动方式
- 权限模型
- 健康检查
- 来源信息

统一纳入 Runtime 管理。

---

## Runtime API 设计

App 与 Runtime 之间建议统一走本地 API（HTTP / Unix Socket / Named Pipe）。

### 基础接口

#### 1. 安装

```http
POST /runtime/mcp/install
```

请求：

```json
{
  "serverId": "filesystem",
  "source": {
    "type": "registry",
    "package": "@modelcontextprotocol/server-filesystem"
  }
}
```

#### 2. 启动

```http
POST /runtime/mcp/start
```

#### 3. 停止

```http
POST /runtime/mcp/stop
```

#### 4. 状态

```http
GET /runtime/mcp/status/:id
```

状态示例：

```json
{
  "id": "filesystem",
  "installed": true,
  "running": true,
  "health": "ok",
  "pid": 12345,
  "lastError": null,
  "tools": [
    "read_file",
    "write_file"
  ]
}
```

#### 5. 日志

```http
GET /runtime/mcp/logs/:id
```

#### 6. 工具调用

```http
POST /runtime/mcp/call-tool
```

#### 7. 列表

```http
GET /runtime/mcp/list
```

---

## Runtime Adapter 设计

不同类型 MCP 统一抽象成 Adapter：

```text
RuntimeAdapter
  ├─ install()
  ├─ start()
  ├─ stop()
  ├─ healthcheck()
  ├─ discoverTools()
  └─ callTool()
```

### NodeRuntimeAdapter

负责：

- npm package 安装
- node 入口启动
- stdio 协议桥接

### PythonRuntimeAdapter

负责：

- venv/uv/pip 依赖安装
- python 入口启动

### BinaryRuntimeAdapter

负责：

- 下载/校验二进制
- 启动二进制型 MCP

### RemoteSseAdapter

负责：

- 远程 SSE MCP Server 接入
- 不需要本地拉进程

---

## 权限模型

团队级工具必须把 MCP 权限做成显式模型。

建议最小权限项：

- `fsRead`
- `fsWrite`
- `network`
- `browser`
- `spawn`
- `clipboard`
- `downloads`

### 权限使用方式

1. 安装前展示权限
2. 首次启用前确认权限
3. 管理页随时可撤销
4. 工具调用日志中记录权限使用痕迹

---

## 运行状态机

建议每个 MCP Server 都有标准状态机：

```text
uninstalled
  -> installing
  -> installed
  -> starting
  -> running
  -> unhealthy
  -> restarting
  -> stopped
  -> failed
```

UI 不应再只显示一个开关，而应显示：

- 是否已安装
- 是否运行中
- 最近错误
- 工具列表是否已发现
- 日志入口

---

## 日志与可观测性

Runtime 需要独立日志：

- 安装日志
- 启动日志
- stdout/stderr
- healthcheck 结果
- tool invocation 日志

客户端 UI 至少要能看：

- 最近错误
- 最后启动时间
- 最后一次 tool call 结果

---

## 与当前 simichat 的映射

### 当前已有可复用部分

1. `lib/shared/providers/mcp_provider.dart`
   - 已有 MCP Server 配置模型
   - 可保留为“客户端视角状态层”

2. `lib/core/mcp/mcp_client.dart`
   - 已有 `app_native` / stdio / SSE 协议桥接
   - `app_native` 是移动端与 PC 端共同可用的自依赖基线
   - stdio 后续可下沉到 Runtime/容器侧车端使用

3. `lib/shared/providers/chat_provider.dart`
   - 已有 tool call 解析与调用闭环
   - 可继续作为 Orchestrator 层

4. `lib/core/database/tables.dart`
   - 已有 `mcp_servers`
   - 后续建议增加 runtime 状态/日志/任务表

### 当前必须继续重构的部分

1. **外部型 MCP 的生命周期仍在客户端侧**
   - `app_native` 已经是 App 内建自依赖路径；外部 stdio/SSE 仍应继续改为调用 Runtime API

2. **桌面端 stdio 仍可直接 `Process.start(...)`**
   - 短期保留为 PC 高级连接兼容；Node/Python 生态后续应改为 Runtime/容器侧车统一管理

3. **连接状态与安装状态耦合**
   - 需要拆成：installed / running / healthy / failed

### 2026-08-08 实现边界更新：Bundled Node 已落地

在保留容器侧车的前提下，当前实现已经增加一条不依赖 Docker / Podman 的
Bundled Node 路径：

- Android 使用 APK 内的 `nodejs-mobile v18.20.4`、`arm64-v8a/libnode.so`、
  JNI bridge 和 `runtime-server.mjs`；
- PC 使用 `tools/node_runtime/manifest.json` 固定的官方 Node 版本和归档
  SHA-256，由 `scripts/prepare_node_runtime.sh` 在构建前准备 binary；
- `BundledNodeRuntime` 只查找明确的随应用路径，不执行 `command -v node`，也
  不回退到 `npm`、`npx`、Docker 或 Podman；
- `McpManager` 通过 `marketplaceId == simichat-node-bundled` 先拉起 bundled
  runtime，再建立本地 SSE 连接。

这条路径的完整命令、文件清单、验证矩阵和未覆盖边界以
`docs/MCP_BUNDLED_NODE_RUNTIME.md` 为准。本文件继续保留容器方案的设计、
权限和治理说明，不再把容器描述成 PC Node 的唯一交付方式。

---

## 数据模型建议补充

建议新增表：

### `mcp_runtime_instances`

- `id`
- `server_id`
- `runtime_type`
- `install_state`
- `run_state`
- `health_state`
- `pid`
- `last_error`
- `last_started_at`
- `last_stopped_at`

### `mcp_runtime_logs`

- `id`
- `server_id`
- `level`
- `source`
- `message`
- `created_at`

### `tool_executions`

- `id`
- `session_id`
- `server_id`
- `tool_name`
- `arguments_json`
- `result_json`
- `status`
- `duration_ms`
- `created_at`

### `tasks` / `task_steps`

为未来“团队级内部 AI 调度”做准备。

---

## 产品演进路线

### Phase 1：Runtime 抽象

目标：

- Runtime Manifest
- Runtime Client / Daemon 边界
- 安装 / 启动 / 停止 / 日志 / 状态 API

### Phase 2：团队工具治理

目标：

- 权限面板
- MCP 注册表
- 工具启用策略
- 错误和日志面板

### Phase 3：任务调度

目标：

- 会话升级为任务
- 多步 tool workflow
- 结果产物化

### Phase 4：工作区与知识沉淀

目标：

- Markdown / Mermaid / 报告 / 方案输出
- 团队知识沉淀
- 可导出和可共享的任务结果

### Phase 5：团队共享

目标：

- 共享 Prompt / Skill / MCP 配置
- 团队级模型渠道
- 审计与权限

---

## 与 `PC_SimiTlakTools` 的关系

`PC_SimiTlakTools` 更适合提供：

- Markdown 工作区能力
- Mermaid / 公式 / 图表 / 结构化文档输出

`simichat` 更适合作为：

- Team AI Console
- Multi-provider AI runtime
- MCP Runtime host
- Skills / Prompt / Tool orchestration 中枢

最终组合方向应是：

> `simichat = AI 调度中枢`  
> `PC_SimiTlakTools 风格能力 = 任务结果与知识工作区`

---

## 当前建议的下一刀

Bundled Node 的主链路已经完成代码接入；下一步不应把“继续增加容器依赖”误当
作完成，而应补真实发布证据和运行时治理：

1. 解决 macOS `sqlite3` native asset 下载前置条件，完成 PC Flutter App
   integration；
2. 在 Windows / Linux 目标机器上生成并启动对应 bundled Node 发布包；
3. 对 Android 16 KB page-size、非 arm64 ABI、冷启动、锁屏和长时间运行做真机
   验收；
4. 把 `installed / running / healthy / failed` 和 PID / 日志落到
   `mcp_runtime_instances`、`mcp_runtime_logs` 等状态表；
5. 对第三方 MCP 包建立签名 / SHA-256 / 权限白名单，必要时再选择容器作为
   隔离后端。

只有完成真实设备 / 发布包证据后，才能把对应平台从 `implemented` 提升为
`runtime_verified`。

---

## 总结

如果你的目标是“团队级内部 AI 调度工具”，那么：

- `npm/node/npx` 只是 MCP 生态接入手段
- 不应该成为最终产品运行边界
- 应该尽快抽象出 **MCP Runtime 容器层**

最合理的方向不是直接 Docker 化，而是先做：

> **本地 Sidecar Runtime Daemon**

由它来统一：

- 安装
- 启动
- 权限
- 日志
- 工具桥接
- 运行状态

App 自己只做：

- Orchestrator
- UI
- 会话/任务
- 输出工作区
