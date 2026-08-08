# 移动端纯 JS Node-Mobile MCP 运行验收记录（2026-08-09）

## 1. 目标与运行边界

本次实现的目标是让 Android、iOS 和 PC App 在不依赖宿主机 Node 环境的情况下，运行
纯 JavaScript MCP 扩展，并为历史 `stdio` / `npx` 配置提供移动端兼容路径。

移动端运行时明确不调用：

```text
node / npm / npx / shell / Docker / Podman / child_process / Process.start
```

纯 JS 扩展通过 App 自有的 Node runtime 或 App Native in-process adapter 运行；未知的
第三方包、native addon、依赖 shell 的 CLI 和未审核的 `npx` 包继续拒绝。

## 2. 交付内容

### 2.1 Android

- APK 内置 `nodejs-mobile v18.20.4` 的 `arm64-v8a/libnode.so`。
- Kotlin/JNI bridge 在 App 进程内启动 Node runtime；不启动外部命令。
- `runtime-server.mjs` 提供 health、扩展注册、扩展状态和 MCP SSE / message endpoint。
- 扩展注册时校验 manifest、entry SHA-256、路径边界、文件数量 / 大小、禁止能力和
  `nativeAddon=false`，然后在 Node runtime 内动态 import 纯 JS entry。

### 2.2 iOS

- 通过 `NodeMobile.xcframework`、Objective-C++ bridge 和 Swift runtime wrapper 接入
  App 进程内 Node runtime。
- framework 由 `scripts/prepare_ios_node_mobile.sh` 从固定的 nodejs-mobile 18.20.4
  源码在隔离目录构建，不修改原始源码目录。
- 发布门禁必须同时检查 device arm64、arm64 simulator 和 x86_64 simulator slice，
  并在最终 App 中检查 framework 已 link / embed。
- iPhone13 真机 marker 已出现；iOS 纯 JS Node MCP、stdio-compat-v1 和 legacy npx
  adapter 均通过同一 App 内置 NodeMobile runtime 验收。

### 2.3 PC

- PC 继续使用随 App 提供的 bundled Node binary / local runtime process。
- Dart 只连接 App 管理的 loopback SSE endpoint，不读取宿主机 PATH 中的 `node` / `npx`。
- PC 的 bundled Node integration 与移动端 Node-Mobile 是两条实现，但共用
  `runtime-server.mjs` 的扩展协议和 manifest 校验规则。

### 2.4 stdio / npx 兼容层

移动端不伪装启动真实 stdin/stdout 子进程。`MobileNpxResolver` 只把下列已审核包转成
App Native in-process profile：

```text
@modelcontextprotocol/server-time
@modelcontextprotocol/server-memory
@modelcontextprotocol/server-fetch
@modelcontextprotocol/server-filesystem
```

支持 `npx -y`、`npx --yes` 和版本后缀，但版本号只用于匹配，不会下载 npm 包。未知包、
需要 native addon 或子进程的包继续返回受控拒绝。

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
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
All tests passed
```

这条证据覆盖 APK 内 `libnode.so`、JNI bridge、loopback HTTP/SSE、Node runtime
`register -> initialize -> tools/list -> tools/call`、纯 JS extension 动态 import、
`stdio-compat-v1` 和 legacy npx in-process adapter。Android 这条链路标记为：

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
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
All tests passed
```

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
| `stdio-compat-v1` | `runtime_verified` | `runtime_verified`，通过 App 内 in-process compatibility adapter | 不走移动端 adapter |
| legacy npx adapter | `runtime_verified` | `runtime_verified`，allowlist profile 的 initialize / tools/list / tools/call 通过 | 使用 PC bundled runtime / 原生配置 |
| 外部 node / npm / npx / shell | 明确拒绝 | 明确拒绝 | 不依赖宿主 PATH |
