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
   - 已有 stdio / SSE 协议桥接雏形
   - 可下沉到 Runtime 端使用

3. `lib/shared/providers/chat_provider.dart`
   - 已有 tool call 解析与调用闭环
   - 可继续作为 Orchestrator 层

4. `lib/core/database/tables.dart`
   - 已有 `mcp_servers`
   - 后续建议增加 runtime 状态/日志/任务表

### 当前必须重构的部分

1. **UI 直接管理 MCP 生命周期**
   - 应改为调用 Runtime API

2. **桌面端直接 `Process.start(...)`**
   - 应改为 Runtime 统一管理

3. **连接状态与安装状态耦合**
   - 需要拆成：installed / running / healthy / failed

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

不是再继续补零碎兼容，而是开始一个明确实现切片：

### 推荐第一实现切片

> **MCP Runtime Manifest + Runtime 状态表 + Runtime API 抽象**

最小交付包括：

1. `docs/runtime-manifest.example.json`
2. `mcp_runtime_instances` 表
3. Runtime 状态 Provider
4. 当前 `mcp_provider.dart` 改成“调用 runtime client”

这会是 `simichat` 从“高级客户端”迈向“团队级内部 AI 调度工具”的第一道真正分水岭。

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

