# 移动端纯 JS MCP 与 stdio / npx 兼容层

## 1. 结论

移动端不执行宿主命令：

```text
node / npm / npx / shell / Docker / Podman / child_process
```

可运行的第三方 MCP 必须满足以下之一：

1. `runtime=node-mobile`，入口是纯 JavaScript `index.js` / `index.mjs`，依赖文件随扩展包一起提供，并实现 `mobile-mcp-v1` 或 `stdio-compat-v1`。
2. 旧版 Marketplace 配置命中 `MobileNpxResolver` 的已审核包，转成 App Native in-process adapter。它保留 MCP 工具语义，但不是在手机上运行 `npx`。
3. 使用远程 SSE / Streamable HTTP MCP，由用户显式配置网络端点。

未知的 `stdio`、任意 `npx` 包、native addon、需要子进程的 CLI 会被拒绝，而不是静默下载或回退到设备环境。

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

`stdio-compat-v1` 表示把原有 stdio MCP 的业务逻辑改造成上述 in-process 对象；它不代表仍然存在 stdin/stdout 子进程。

## 3. App-owned Node Runtime 适配

```text
MobileExtensionInstaller
  -> App sandbox installed/<type>/<id>/<version>
  -> BundledNodeRuntime.start()
  -> POST /runtime/extensions/register
  -> import(entry.mjs)
  -> initialize(context)
  -> /mcp/sse/<extension-id>
  -> McpClient(SseTransport)
```

Node Runtime 服务端（Android / iOS / PC 共用）：

```text
GET  /health
GET  /runtime/extensions/status
POST /runtime/extensions/register
POST /runtime/extensions/unregister
GET  /mcp/sse/<server-id>
POST /mcp/messages/<connection-id>
```

注册前会重新校验：

- `id`、root、entry 的路径边界；
- `manifest.json` 与注册元数据一致；
- entry SHA-256；
- `nativeAddon=false`；
- 总文件数和总字节数；
- JavaScript / JSON 源码没有 `child_process`、`worker_threads`、`cluster`、`process.binding`、`spawn`、`exec`、`fork`、`npm`、`npx`、动态代码执行或 `.node` native addon。

入口只能访问通过 `context` 暴露的 capability：

```text
context.hasPermission(permission)
context.readText(relativePath, maxBytes)
context.fetchText(url, maxBytes)
```

路径和网络能力必须与 manifest permissions 同时满足。Node Runtime 的 workspace 和扩展根目录分离，扩展不能把安装目录解析到 workspace 外。

## 4. Android / iOS / PC 实现矩阵

| 平台 | Node 引擎 | Native boundary | 连接方式 | 当前限制 |
| --- | --- | --- | --- | --- |
| Android | APK 内 `nodejs-mobile v18.20.4` / `libnode.so` | Kotlin + JNI native thread | loopback SSE | 当前发布 ABI 为 arm64-v8a |
| iOS | App 内 `NodeMobile.xcframework` | Swift + Objective-C++ bridge | loopback SSE | Node loop 与 App 进程同生命周期，stop 不单独杀线程 |
| macOS / Linux / Windows | App 随包 Node binary | Dart 管理本地 bundled process | loopback SSE | 不使用宿主 PATH 的 node/npx |

NodeMobile framework 由 `scripts/prepare_ios_node_mobile.sh` 从固定 nodejs-mobile 源码构建，产物放入：

```text
ios/Runner/NodeRuntime/NodeMobile.xcframework
```

发布构建必须检查 `xcodebuild -create-xcframework` 产出的 device 与 simulator slice、`Info.plist`、签名和最终 App 包中的 `NodeMobile.framework`。

## 5. Legacy stdio / npx 适配

`MobileNpxResolver` 目前只接受以下已审核包（支持 npx 的 `--yes`、`-y` 和版本后缀）：

```text
@modelcontextprotocol/server-time       -> profile=time
@modelcontextprotocol/server-memory     -> profile=memory
@modelcontextprotocol/server-fetch      -> profile=fetch
@modelcontextprotocol/server-filesystem -> profile=filesystem
```

这些 profile 使用 App Native transport：

- `time`：设备时间；
- `memory`：读取本地 Key Point memory；
- `fetch`：受限 HTTP(S) GET；
- `filesystem`：只读 Application Support app container，拒绝路径穿越。

旧版 `stdio` 配置只在命中上述 allowlist 时转为对应的 App Native profile；
`npx` 版本号只用于匹配，不会下载或执行 npm 包。未知包不会尝试 npm registry，
也不会调用 `Process.start`。需要浏览器、Git、数据库 native addon、shell、
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

必须至少证明同一条链路：

```text
register -> health -> SSE endpoint -> initialize -> tools/list -> tools/call -> unregister
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
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
```

安装、注册、MCP initialize 和工具调用分别记录；不能用 `registry.json` 或 `flutter test` 单独替代真机 runtime 证据。
