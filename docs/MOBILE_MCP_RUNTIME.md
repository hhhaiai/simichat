# 移动端纯 JS MCP 与 stdio / npx 兼容层

## 1. 结论

移动端支持标准 MCP `transport: "stdio"` 配置，并在 App-owned Node Runtime 中建立真实的
JSON Lines stdin / stdout session；不执行宿主命令：

```text
node / npm / npx / shell / Docker / Podman / child_process
```

可运行的第三方 MCP 必须满足以下之一：

1. `runtime=node-mobile`，入口是纯 JavaScript `index.js` / `index.mjs`，依赖文件随扩展包一起提供，并实现 `mobile-mcp-v1`、`stdio-v1` 或 legacy `stdio-compat-v1`。
2. 旧版 Marketplace 配置命中 `MobileNpxResolver` 的已审核包，由 App-owned Node Runtime 按 `command + args` 建立 stdio session；它不下载或执行手机上的 `npx`。
3. 使用远程 SSE / Streamable HTTP MCP，由用户显式配置网络端点。

移动端的 `stdio` 配置会按以下顺序处理：已审核的 `npx` 包进入 App-owned Node Runtime 的
JSONL stdio session，已安装的 `node-mobile` 扩展先注册再进入同一 session；未知的 `stdio`、
任意 `npx` 包、native addon、需要子进程的 CLI 会在 session start 阶段得到可操作错误，而不是
静默下载或回退到设备环境。

## 2. 纯 JS MCP 包协议

示例 manifest：

```json
{
  "packageFormat": 1,
  "manifest": {
    "id": "weather-mobile",
    "version": "1.0.0",
    "type": "mcp",
    "runtime": "node-mobile",
    "protocol": "mobile-mcp-v1",
    "entry": "index.mjs",
    "sha256": "<entry sha256>",
    "sizeBytes": 1234,
    "nativeAddon": false,
    "permissions": ["network"]
  },
  "files": {
    "index.mjs": "<base64>",
    "package.json": "<base64>",
    "node_modules/example/index.mjs": "<base64>"
  }
}
```

入口可以导出默认对象，也可以导出 `createMcpServer(context)`：

```js
export default {
  async initialize(context) {
    return {
      protocolVersion: context.protocolVersion,
      capabilities: { tools: {} },
      serverInfo: { name: 'weather-mobile', version: '1.0.0' }
    };
  },
  async listTools() {
    return { tools: [] };
  },
  async callTool(name, args, context) {
    return {
      content: [{ type: 'text', text: 'ok' }],
      isError: false
    };
  }
};
```

必需函数：

```text
initialize(context [, params])
listTools(context)
callTool(name, arguments, context)
```

可选函数：

```text
listResources(context)
readResource(uri, context)
```

`stdio-v1` 扩展在 App-owned Runtime 中通过 JSONL stdin/stdout session 提供 MCP 行协议；
`stdio-compat-v1` 仍可安装和迁移，但只作为旧版对象入口，不再是新扩展协议。无论是已审核
`npx` 配置还是 `stdio-v1` 扩展，Dart 侧都写入 stdin 行、从 stdout 行读取，不再改接
`SseTransport`。

## 3. App-owned Node Runtime 适配

```text
McpServerConfig(transport: "stdio", command, args)
  -> MobileNpxResolver / installed extension metadata
  -> BundledNodeRuntime.start()
  -> POST /runtime/stdio/start
  -> POST /runtime/stdio/<session-id>/stdin  (one JSON line)
  -> GET  /runtime/stdio/<session-id>/stdout (JSON lines)
  -> McpClient(MobileStdioTransport)

installed extension path:
  -> POST /runtime/extensions/register
  -> import(entry.mjs)
  -> stdio-v1 server target
```

Node Runtime 服务端（Android / iOS / PC 共用）：

```text
GET  /health
GET  /runtime/extensions/status
POST /runtime/extensions/register
POST /runtime/extensions/unregister
POST /runtime/stdio/start
POST /runtime/stdio/<session-id>/stdin
GET  /runtime/stdio/<session-id>/stdout
POST /runtime/stdio/<session-id>/close
GET  /mcp/sse/<server-id>
POST /mcp/messages/<connection-id>
```

注册前会重新校验：

- `id`、root、entry 的路径边界；
- `manifest.json` 与注册元数据一致；
- entry SHA-256；
- `nativeAddon=false`；
- 总文件数和总字节数；
- JavaScript 源码没有 `child_process`、`worker_threads`、`cluster`、`process.binding`、`spawn`、`exec`、`fork`、`npm`、`npx`、动态代码执行或 `.node` native addon。

入口在协议层只应使用通过 `context` 暴露的 capability：

```text
context.hasPermission(permission)
context.readText(relativePath, maxBytes)
context.fetchText(url, maxBytes)
```

路径和网络能力必须与 manifest permissions 同时满足。Node Runtime 的 workspace 和扩展根目录分离，扩展不能把安装目录解析到 workspace 外。

**当前安全边界必须如实理解**：`node-mobile` 入口是在 App-owned Node VM 中动态
`import` 的 JavaScript，不是独立沙箱；`permissions` 只约束上面的 `context` helper，
不能阻止入口通过 Node 内置模块或动态构造代码访问进程能力。因此只能安装来自可信来源、
经过审计并固定 package SHA-256 的扩展；当前不能把任意第三方 JavaScript MCP 宣称为安全
隔离执行。

## 4. Android / iOS / PC 实现矩阵

| 平台 | Node 引擎 | Native boundary | 连接方式 | 当前限制 |
| --- | --- | --- | --- | --- |
| Android | APK 内 `nodejs-mobile v18.20.4` / `libnode.so` | Kotlin + JNI native thread | JSONL stdio session / SSE | 当前发布 ABI 为 arm64-v8a |
| iOS | App 内 `NodeMobile.xcframework` | Swift + Objective-C++ bridge | JSONL stdio session / SSE | Node loop 与 App 进程同生命周期，stop 不单独杀线程 |
| macOS / Linux / Windows | App 随包 Node binary | Dart 管理本地 bundled process | 原生进程 stdio / SSE | 不使用宿主 PATH 的 node/npx |

NodeMobile framework 由 `scripts/prepare_ios_node_mobile.sh` 从固定 nodejs-mobile 源码构建，产物放入：

```text
ios/Runner/NodeRuntime/NodeMobile.xcframework
```

发布构建必须检查 `xcodebuild -create-xcframework` 产出的 device 与 simulator slice、`Info.plist`、签名和最终 App 包中的 `NodeMobile.framework`。

## 5. 审核的移动 stdio command / args

`MobileNpxResolver` 目前只接受以下已审核包（支持 npx 的 `--yes`、`-y` 和版本后缀）：

```text
@modelcontextprotocol/server-time       -> profile=time
@modelcontextprotocol/server-memory     -> profile=memory
@modelcontextprotocol/server-fetch      -> profile=fetch
@modelcontextprotocol/server-filesystem -> profile=filesystem
```

这些审核 profile 在 PC 端也会由随应用分发的 Bundled Node Runtime 通过 JSONL
stdio session 执行；MCP 市场中的 `time`、`memory`、`fetch`、`filesystem` 条目不再要求
宿主机 `npx`。PC 上其他未命中的 stdio 配置仍只有在用户手动启用并明确提供宿主命令时才会
走桌面 `StdioTransport`，不会被误标成“内建”。

这些 profile 由 Node Runtime 的 stdio session 暴露：

- `time`：设备时间；
- `memory`：legacy 兼容 profile（当前为空结果占位）；
- `fetch`：受限 HTTP(S) GET；
- `filesystem`：只读 Node Runtime workspace（随 App 创建的私有运行目录），拒绝路径穿越；
  它不等价于 Flutter AppNative profile 的完整 Application Support 文件树。

其中 legacy `server-memory` 在当前 Node Runtime 仍是兼容占位 profile，返回空结果，
并不等价于已经接入 Flutter 的 Key Point memory；需要真实本地记忆时请使用 AppNative
路径，或等待该 profile 的本地存储桥接完成。

旧版 `stdio` 配置命中上述 allowlist 时，`command` 和完整 `args` 会原样传到
`/runtime/stdio/start`，Runtime 再按 allowlist 选择随包 profile。`npx` 版本号只用于匹配，
不会下载或执行 npm 包。纯 JS 移动扩展安装后，其 MCP 配置也可以保留为 `stdio`，注册元数据
由 App-owned Node Runtime 校验后进入同一 JSONL session。
未知包不会尝试 npm registry，也不会调用 `Process.start`。需要浏览器、Git、数据库 native addon、shell、
Puppeteer 或其他子进程的 MCP 必须改造成纯 JS mobile adapter 或放到远程 / PC runtime。

## 6. 稳定性门禁

### 静态 / 单元

```bash
flutter analyze --no-pub
flutter test test/mobile_npx_resolver_test.dart
flutter test test/mobile_extension_installer_test.dart
node --check tools/mcp_runtime/container/runtime-server.mjs
```

### Node Runtime 动态协议

必须至少证明同一条 stdio 链路：

```text
health -> stdio/start(command,args) -> stdin JSON line -> stdout JSON line
  -> initialize -> tools/list -> tools/call -> close
```

对应脚本 / 真机测试：

```bash
node --check tools/mcp_runtime/container/runtime-server.mjs
DEVICE_ID=<android> ./scripts/smoke_device_mobile_extensions.sh
DEVICE_ID=<ios> ./scripts/smoke_device_mobile_extensions.sh
```

真机 marker：

```text
SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY
SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY
SIMICHAT_MOBILE_STDIO_PROTOCOL_DEVICE_READY
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
```

安装、注册、MCP initialize 和工具调用分别记录；不能用 `registry.json` 或 `flutter test` 单独替代真机 runtime 证据。
