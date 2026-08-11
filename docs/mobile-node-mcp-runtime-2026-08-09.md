# 移动端纯 JS Node-Mobile MCP 运行验收记录（2026-08-09）

## 1. 目标与运行边界

本次实现的目标是让 Android、iOS 和 PC App 在不依赖宿主机 Node 环境的情况下，运行
纯 JavaScript MCP 扩展，并为历史 `stdio` / `npx` 配置提供移动端兼容路径。

移动端不会执行宿主命令；但标准 `transport: "stdio"` 配置会进入 App-owned Runtime 的
JSONL stdin / stdout session：

```text
node / npm / npx / shell / Docker / Podman / child_process / Process.start
```

纯 JS 扩展通过 App 自有的 Node runtime 运行；未知的第三方包、native addon、依赖 shell
的 CLI 和未审核的 `npx` 包继续在 stdio session start 阶段拒绝。

## 2. 交付内容

### 2.1 Android

- APK 内置 `nodejs-mobile v18.20.4` 的 `arm64-v8a/libnode.so`。
- Kotlin/JNI bridge 在 App 进程内启动 Node runtime；不启动外部命令。
- `runtime-server.mjs` 提供 health、扩展注册、MCP SSE / message endpoint，以及独立的
  stdio session `start / stdin / stdout / close` endpoint。
- 扩展注册时校验 manifest、entry SHA-256、路径边界、文件数量 / 大小、禁止能力和
  `nativeAddon=false`，然后在 Node runtime 内动态 import 纯 JS entry。
- 标准 `stdio-v1` 不再映射为 App Native handler 或 SSE：移动端由
  `MobileStdioTransport` 建立独立 JSONL stdin / stdout session。

### 2.2 iOS

- 通过 `NodeMobile.xcframework`、Objective-C++ bridge 和 Swift runtime wrapper 接入
  App 进程内 Node runtime。
- framework 由 `scripts/prepare_ios_node_mobile.sh` 从固定的 nodejs-mobile 18.20.4
  源码在隔离目录构建，不修改原始源码目录。
- 发布门禁必须同时检查 device arm64、arm64 simulator 和 x86_64 simulator slice，
  并在最终 App 中检查 framework 已 link / embed。
- iPhone13 真机 marker 已出现；iOS 纯 JS Node MCP、stdio-compat-v1 和 legacy npx
  adapter 均通过同一 App 内置 NodeMobile runtime 验收；标准 `stdio-v1` JSONL session
  也已通过新的移动端 stdio smoke。

### 2.3 PC

- PC 继续使用随 App 提供的 bundled Node binary / local runtime process。
- Dart 只连接 App 管理的 loopback SSE endpoint（bundled runtime 的通用 Node MCP）；移动
  纯 JS 扩展则通过 App-owned JSONL stdio session，不读取宿主机 PATH 中的 `node` / `npx`。
- PC 的 bundled Node integration 与移动端 Node-Mobile 是两条实现，但共用
  `runtime-server.mjs` 的扩展协议和 manifest 校验规则。

### 2.4 stdio / npx 兼容层

移动端不启动宿主 stdin/stdout 子进程。`MobileNpxResolver` 只允许下列已审核包，随后把
原始 `command + args` 交给 App-owned Runtime 的 JSONL stdio session：

```text
@modelcontextprotocol/server-time
@modelcontextprotocol/server-memory
@modelcontextprotocol/server-fetch
@modelcontextprotocol/server-filesystem
```

支持 `npx -y`、`npx --yes` 和版本后缀，但版本号只用于匹配，不会下载 npm 包。Runtime
的 stdout 会逐行返回 MCP JSON-RPC response，`notifications/initialized` 等通知不返回
response；未知包、需要 native addon 或子进程的包继续返回受控拒绝。

## 3. Android Pixel 8 真机证据

设备：`Pixel 8`，Android 16 / API 36，`37101FDJH0077P`。

命令：

```bash
DEVICE_ID=37101FDJH0077P \\
./scripts/smoke_device_mobile_extensions.sh
```

已观察到的决定性 marker：

```text
SIMICHAT_MOBILE_EXTENSIONS_APP_NATIVE_READY
SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY
SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY
SIMICHAT_MOBILE_STDIO_PROTOCOL_DEVICE_READY
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
All tests passed
```

这条证据覆盖 APK 内 `libnode.so`、JNI bridge、loopback HTTP/SSE、Node runtime
`register -> initialize -> tools/list -> tools/call`、纯 JS extension 动态 import、
`stdio-compat-v1`、标准 `stdio-v1` JSONL session 和 legacy npx in-process adapter。
Android 这条链路标记为：

```text
runtime_verified
```

当前交付 ABI 仍是 `arm64-v8a`；其他 ABI 和 16 KB 真机属于独立门禁。

## 4. iPhone13 真机证据

设备：`iPhone13`，iOS 26.5 / `23F77`，
`00008110-0016349A3A20A01E`。

目标命令：

```bash
DEVICE_ID=00008110-0016349A3A20A01E \\
./scripts/smoke_device_mobile_extensions.sh
```

最终验收必须同时出现：

```text
SIMICHAT_MOBILE_EXTENSIONS_APP_NATIVE_READY
SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY
SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
```

NodeMobile 的 device arm64、arm64 simulator 和 x86_64 simulator slice 已构建并组装为
`ios/Runner/NodeRuntime/NodeMobile.xcframework`。最终 App 构建证实
`Runner.app/Frameworks/NodeMobile.framework/NodeMobile` 已被 link / embed，随后在
iPhone13 上完成以下 marker 验证：

```text
SIMICHAT_MOBILE_EXTENSIONS_APP_NATIVE_READY
SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY
SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY
SIMICHAT_MOBILE_STDIO_PROTOCOL_DEVICE_READY
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
All tests passed
```

这条证据同时覆盖标准 `transport: "stdio"` 配置：`command: "npx"` 与
`args: ["--yes", "@modelcontextprotocol/server-time@latest"]` 进入真实 JSONL
session，并完成 `initialize`、`tools/list`、`tools/call`。

因此 iOS 这条链路标记为：

```text
runtime_verified
```

## 5. NodeMobile framework 发布门禁

本轮最终组装和 App link/embed 已完成，复核命令如下：

```bash
find ios/Runner/NodeRuntime/NodeMobile.xcframework \\
  -type f -name NodeMobile -exec file {} \\

lipo -info \\
  ios/Runner/NodeRuntime/NodeMobile.xcframework/ios-arm64/NodeMobile.framework/NodeMobile

lipo -info \\
  ios/Runner/NodeRuntime/NodeMobile.xcframework/ios-arm64_x86_64-simulator/NodeMobile.framework/NodeMobile

plutil -p ios/Runner/NodeRuntime/NodeMobile.xcframework/Info.plist

xcodebuild -project ios/Runner.xcodeproj -list
flutter build ios --debug --no-pub
```

证据要求：

1. device slice 必须是 arm64 iPhone Mach-O。
2. simulator slice 必须同时包含 arm64 和 x86_64。
3. `Info.plist` 的 library identifier、supported architectures 和 platform 必须与
   `xcodebuild -create-xcframework` 输出一致。
4. 最终 App 包必须存在 `NodeMobile.framework/NodeMobile`，不能只证明仓库里存在
   framework 文件。
5. 最终 App 启动后必须出现 iPhone13 四个 marker；只编译成功仍是
   `blocked_with_evidence`。

本轮实际结果：

```text
ios-arm64: arm64 Mach-O
ios-arm64_x86_64-simulator: arm64 + x86_64 universal Mach-O
Runner.app: 208M
Runner.app/Frameworks/NodeMobile.framework/NodeMobile: arm64 Mach-O
```

## 6. 测试门禁

代码层 targeted tests：

```bash
flutter test --no-pub \\
  test/mobile_npx_resolver_test.dart \\
  test/mobile_extension_protocol_test.dart \\
  test/mcp_runtime_container_manifest_test.dart
```

协议与脚本门禁：

```bash
node --check tools/mcp_runtime/container/runtime-server.mjs
python3 -m json.tool docs/runtime-manifest.example.json >/dev/null
python3 -m json.tool tools/node_runtime/manifest.json >/dev/null
bash -n scripts/prepare_ios_node_mobile.sh
git diff --check
```

测试通过只证明 source / protocol boundary；移动端最终结论必须同时引用目标真机的
runtime marker。

## 7. 结论矩阵

| 能力 | Android Pixel 8 | iPhone13 | PC App |
| --- | --- | --- | --- |
| App Native MCP | `runtime_verified` | 既有 App Native 路径已验证 | 已有 bundled integration 证据 |
| 纯 JS Node-Mobile MCP | `runtime_verified` | `runtime_verified`，NodeMobile XCFramework 已 link/embed 且 iPhone13 marker 通过 | `runtime_verified`，使用 bundled Node |
| `stdio-compat-v1` legacy | `runtime_verified` | `runtime_verified`，历史对象入口已通过 | 不走移动端 adapter |
| `stdio-v1` / JSONL mobile stdio | `runtime_verified`，`SIMICHAT_MOBILE_STDIO_PROTOCOL_DEVICE_READY` 已通过 | `runtime_verified`，`SIMICHAT_MOBILE_STDIO_PROTOCOL_DEVICE_READY` 已通过 | 使用 PC 原生进程 stdio |
| 审核 npx 配置 | `runtime_verified`，`command + args` 真实进入移动 JSONL session | `runtime_verified`，`command + args` 真实进入移动 JSONL session | 使用 PC bundled runtime / 原生配置 |
| 外部 node / npm / npx / shell | 明确拒绝 | 明确拒绝 | 不依赖宿主 PATH |

## 8. 移动端 `transport: stdio` 真实 JSONL 路径（2026-08-09）

移动端现在可以保存和连接如下标准配置。`command` 和 `args` 会实际参与 session
启动与 allowlist 解析；它们不会被静默丢弃，也不会被改成 SSE：

```json
{
  "transport": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-time@latest"]
}
```

```text
已审核 npx 配置
  -> MobileNpxResolver
  -> POST /runtime/stdio/start(command,args)
  -> POST /runtime/stdio/<session-id>/stdin
  -> GET /runtime/stdio/<session-id>/stdout
  -> MobileStdioTransport

已安装 node-mobile / stdio-v1 扩展
  -> manifest / entry / SHA-256 / permission 校验
  -> BundledNodeRuntime.registerExtension()
  -> POST /runtime/stdio/start(serverId)
  -> JSONL stdin / stdout
  -> McpClient initialize / tools/list / tools/call
```

协议级测试已覆盖：

```text
runtime-server.mjs health
stdio/start(command,args)
stdin JSON line
stdout JSON line
initialize
tools/list
tools/call
close
```

对应测试：

```bash
flutter test --no-pub --no-test-assets test/mobile_stdio_transport_test.dart
node --check tools/mcp_runtime/container/runtime-server.mjs
```

本轮实现不会调用宿主机 `Process.start()`、`npx` 或 shell；未知命令在
`/runtime/stdio/start` 阶段失败。Android Pixel 8（`37101FDJH0077P`）与 iPhone13
（`00008110-0016349A3A20A01E`）均已出现
`SIMICHAT_MOBILE_STDIO_PROTOCOL_DEVICE_READY`，因此 `stdio-v1 / JSONL mobile stdio`
在两台目标设备上均为 `runtime_verified`。
