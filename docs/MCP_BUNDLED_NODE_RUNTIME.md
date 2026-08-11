# SimiChat 内置 Node Runtime

## 1. 目标与边界

`simichat-node-bundled` 是 Android / iOS / PC App 内置的 Node MCP 路径。它把
Node Runtime 和 MCP server 脚本随应用一起交付，应用启动 MCP 时由自身负责
准备、启动、健康检查和连接，不依赖用户机器预装的：

- `node`
- `npm`
- `npx`
- Docker
- Podman

这里的“内置”分为两种实现：

| 平台 | 实现 | 进程边界 | 当前支持范围 |
| --- | --- | --- | --- |
| Android | `nodejs-mobile v18.20.4` 的 `libnode.so` + JNI bridge | Node event loop 在 App 进程内 | `arm64-v8a`；Pixel 8 真机已验证 |
| iOS | `NodeMobile.xcframework`（`nodejs-mobile v18.20.4`）+ Swift / Objective-C++ bridge | Node event loop 在 App 进程内 | `ios-arm64`、`ios-arm64_x86_64-simulator`；iPhone13 真机已验证 |
| macOS / Linux / Windows | 官方 Node executable 随 App 资源分发，由 Dart controller 启动 | App 管理的本地子进程 | 构建脚本已支持六个平台；macOS Flutter App integration 已验证，Linux / Windows 仍需各自发布包验收 |

PC 的 `externalProcess=true` 只表示 Node 是 App 管理的本地子进程，不表示
它来自宿主机 PATH。Android 使用嵌入式 `libnode.so`，因此为
`externalProcess=false`。

Docker / Podman 仍保留为 `simichat-node-container` 的可选隔离侧车，但它不再
是 Android 或 PC 内置 Node 的唯一路径，也不应被 `simichat-node-bundled` 的
启动流程隐式调用。

## 2. 运行链路

```text
McpManager
  └─ marketplaceId == simichat-node-bundled
       └─ BundledNodeRuntime.start()
            ├─ Android: MethodChannel
            │    └─ SimiChatNodeRuntime.kt
            │         └─ JNI -> libnode.so -> runtime-server.mjs
            ├─ iOS: NodeMobile.xcframework -> runtime-server.mjs
            └─ PC: Process.start(<bundled node>, <runtime-server.mjs>)
                 └─ localhost SSE /health + /mcp/sse/simichat-node
```

Node server 统一使用：

```text
tools/mcp_runtime/container/runtime-server.mjs
```

server 只使用 Node 内置模块，不依赖 `package.json` 外部依赖。它提供：

- `/health`
- `/mcp/sse/:serverId`
- `/mcp/messages/:connectionId`
- `simichat.node_runtime_info`
- `simichat.echo`
- `simichat.fs_list`
- `simichat.fs_read_text`
- `simichat.fetch_text`

文件工具限制在 `MCP_RUNTIME_WORKSPACE_ROOT`，HTTP 工具只允许 HTTP(S) GET，
读取大小由 `MCP_RUNTIME_MAX_TEXT_BYTES` 限制。

## 3. Android 实现

### 3.1 APK 内置内容

Android 当前交付的 native 文件：

```text
android/app/src/main/jniLibs/arm64-v8a/libnode.so
android/app/src/main/cpp/simichat_node_bridge.cpp
android/app/src/main/cpp/CMakeLists.txt
android/app/src/main/java/top/simitalk/aichat/SimiChatNodeRuntime.kt
```

版本和校验信息在：

```text
tools/node_runtime/manifest.json
```

当前 arm64 library：

```text
runtime: nodejs-mobile
version: 18.20.4
abi: arm64-v8a
sha256: 6f45b99339a9e4264e3a82aabe6c6fd7acb0bbdc7d428ee03aada653f4cd91ec
```

Gradle 通过 CMake 将 `libnode.so`、JNI bridge 和 `libc++_shared.so` 一起放入
APK。Flutter asset 中还包含：

```text
assets/flutter_assets/tools/mcp_runtime/container/runtime-server.mjs
```

### 3.2 生命周期

`SimiChatNodeRuntime.kt` 在首次 `start` 时把 Node server 脚本复制到 App 私有
目录，然后调用 JNI。JNI 在独立 native thread 中调用 `node::Start`，设置：

```text
MCP_RUNTIME_HOST=127.0.0.1
SIMICHAT_NODE_RUNTIME_KIND=android-embedded
SIMICHAT_NODE_APP_MANAGED=true
```

Android 的 stop 当前返回 `stopSupported=false`。这是有意的边界：Node loop
与 App 进程绑定，代码不伪造一个没有实现的停止状态；Android Activity / App
进程结束时二者一起结束。

启动状态会通过 MethodChannel 暴露：

```text
stopped -> starting -> running
                    -> crashed
```

native bridge 记录 `nativeState`、`nativeExitCode` 和 `restartCount`。Dart 控制器
采用 single-flight，健康检查失败最多再尝试一次；不会创建无限重启循环，也不会
把没有实现的 Android stop 报告成成功。Android 的一次重试只有在 native Node 已经
退出并释放启动闸门后才会真正创建新线程；如果仍处于 `starting`，第二次请求只是
等待同一个 `/health` 结果。

### 3.3 Android 构建

```bash
flutter --no-version-check build apk --debug --no-pub
```

确认 APK 内容：

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk \
  | grep -E 'libnode|libsimichat_node_bridge|libc\+\+_shared|runtime-server'
```

项目 Android app 的 JNI bridge 固定使用 NDK `28.2.13676358`。`libnode.so` 则从
`sourceRevision` 对应的 nodejs-mobile 源码重建，使用 NDK `27.1.12297006` 并显式
加入以下 linker flags：

```text
-Wl,-z,max-page-size=16384
-Wl,-z,common-page-size=16384
```

之所以没有把 `libnode.so` 也切换到 NDK r28，是因为该版本的 libc++ 不再提供
`std::char_traits<unsigned short>`，nodejs-mobile v18.20.4 的 inspector 类型会在
构建阶段失败；r27 构建结果已通过 ELF 对齐检查。这个差异必须保留在 manifest，不能
只看 Gradle 的 NDK 版本推断 libnode 的构建工具链。

发布门禁使用 release APK，并要求 Android build-tools 35+ 提供 `zipalign -P 16`：

```bash
flutter --no-version-check build apk --release --no-pub
LLVM_READELF=/path/to/ndk/toolchains/llvm/prebuilt/<host>/bin/llvm-readelf \
ZIPALIGN=/path/to/android-sdk/build-tools/35.0.1/zipalign \
  ./scripts/verify_android_native_16k.sh \
  build/app/outputs/flutter-apk/app-release.apk
```

该脚本同时检查 source/APK 中每个 `lib/<abi>/*.so` 的 `LOAD` segment 是否至少
`0x4000` 对齐，以及 `zipalign -c -P 16 -v 4`。旧版只支持 `-p` 的 zipalign 不能
证明 16 KB ZIP 对齐，脚本会明确返回工具链缺口而不是给出假 PASS。
因此 `elfLoadAlignment` 与 `apkZipAlignment` 在 manifest 中是两个独立字段；当前
两者均已由 source / release APK 证据验证，仍不能把静态 APK 证据外推成 16 KB 真机
长时运行证据。

## 4. iOS 实现

### 4.1 发布 framework

iOS 不查找宿主机 `node`，而是将固定源码构建为发布构件：

```bash
SIMICHAT_NODE_MOBILE_SOURCE=/path/to/nodejs-mobile-18.20.4 \
  ./scripts/prepare_ios_node_mobile.sh
```

脚本在隔离复制目录中构建 device / simulator slices，应用 nodejs-mobile
v18.20.4 在新 Xcode SDK 下的 V8 `mach_vm.h` 兼容 patch，然后生成：

```text
ios/Runner/NodeRuntime/NodeMobile.xcframework
```

`Info.plist` 必须包含 `ios-arm64` 与 `ios-arm64_x86_64-simulator`，Xcode project
同时负责 link、embed、CodeSignOnCopy。构建结果不能由 source checkout 或
单独的静态库文件代替。

### 4.2 iOS 运行时边界

`SimiChatNodeRuntime.swift` 在 App 私有队列调用 Objective-C++ wrapper 的
`node_start`，向内置 Node 设置 `MCP_RUNTIME_*` 环境变量，并把 Flutter asset
中的 `runtime-server.mjs` 复制到 Application Support。Flutter 只连接 loopback
health / SSE；不会创建 iOS 外部进程，也不会使用 npx / shell / Docker。

当前 iPhone13 真机 smoke 需要同时看到：

```text
SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY
SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
```

## 5. PC 实现

### 5.1 构建前准备

PC binary 不从 PATH 查找，也不会在运行时自动下载。构建前必须按目标平台
执行：

```bash
SIMICHAT_NODE_RUNTIME_PLATFORM=macos-arm64 \
  ./scripts/prepare_node_runtime.sh
```

当前仓库已随 Git LFS 提供 macOS arm64 的 Node executable；其他目标平台仍需
在构建机上执行准备脚本。发布机必须先确认 Git LFS 对象已下载。不指定平台时，
脚本依据当前构建机的 `uname` 选择平台。官方归档版本、下载
地址和 SHA-256 都由以下 manifest 固定：

```text
tools/node_runtime/manifest.json
```

支持的 platform id：

```text
macos-arm64
macos-x64
linux-arm64
linux-x64
windows-arm64
windows-x64
```

脚本的下载策略：

1. 从 manifest 读取 Node 版本和官方归档名；
2. 下载到 `.part` 文件；
3. 下载命令成功后原子改名；
4. 优先使用 `sha256sum`，在 macOS 等环境回退到 `shasum -a 256` 校验；
5. 解压到 `tools/node_runtime/bundled/<platform-id>/node[.exe]`；
6. 校验失败时终止，不把不完整 binary 交给 Flutter。

桌面 Node binary **不纳入 Flutter assets**。这是刻意的跨平台边界：如果把
整个 `tools/node_runtime/bundled/` 声明成 Flutter asset，Android APK 会携带
macOS/Linux/Windows 的无关 executable，增大包体并污染移动发布包。

桌面原生构建阶段负责把目标平台 binary 复制到 App 自己的安装目录：

| 平台 | 构建入口 | App 内路径 |
| --- | --- | --- |
| macOS | `macos/Runner.xcodeproj` 的 `Bundle Node Runtime` phase | `Contents/Resources/node_runtime/<platform-id>/node` |
| Linux | `linux/CMakeLists.txt` install rule | `node_runtime/<platform-id>/node` |
| Windows | `windows/CMakeLists.txt` install rule | `node_runtime/<platform-id>/node.exe` |

当前仓库中的 macOS arm64 binary 可直接进入 macOS App bundle；Linux / Windows
发布构建必须在 `flutter build` 前准备与目标平台匹配的 binary。macOS 构建在
binary 缺失时由 Xcode phase 直接失败；Linux / Windows CMake 配置在 binary
缺失时直接失败。App 运行时同样只接受明确的 bundled path，若缺失会报错
“找不到随应用分发的 Node runtime”，不会静默回退宿主机 `node`。

### 5.2 PC 运行时查找顺序

`lib/core/mcp/bundled_node_runtime.dart` 只查找明确的 bundled path：

1. `SIMICHAT_BUNDLED_NODE_PATH`（诊断 / 测试覆盖）；
2. 仓库或构建工作目录下的 `tools/node_runtime/bundled/<id>/node`；
3. App 私有 runtime 目录；
4. macOS `Resources/node_runtime/<id>/node`；
5. Windows / Linux executable 邻近的 `node_runtime` 路径。

其中没有 `command -v node`、`npm`、`npx`、Docker 或 Podman fallback。

### 5.3 PC host-side smoke

在已有 bundled binary 的开发机上可以运行：

```bash
SIMICHAT_MCP_RUNTIME_PORT=37651 \
  ./scripts/smoke_bundled_node_runtime.sh
```

该 smoke 会验证：

- 使用指定 bundled Node executable 启动 server；
- `/health` 返回 `simichat-node-embedded`；
- SSE endpoint 可以建立；
- `tools/list` 包含 `simichat.node_runtime_info`；
- `tools/call` 返回 `requiresHostNode=false`、`requiresHostNpx=false`、
  `requiresDocker=false`；
- cleanup 后不留下 server 或 SSE 进程。

当前这条 host-side process smoke 已通过。它证明的是 bundled executable → Node
server → SSE → MCP tool 的真实进程链路。随后 macOS Flutter App integration 也已
通过，测试实际启动 App 管理的 bundled Node 并完成 MCP initialize、tools/list 和
`simichat.node_runtime_info`；测试输出了
`SIMICHAT_DESKTOP_BUNDLED_NODE_MCP_READY`。本次运行同时出现
`Failed to foreground app; open returned 1` 的工具层提示，但测试进程和 runtime
链路均完成，未观察到 MCP failure。

## 6. Marketplace 与配置

市场条目：

```text
id: simichat-node-bundled
transport: sse
url: http://127.0.0.1:37651/mcp/sse/simichat-node
```

`McpManager.connectServer` 发现该 `marketplaceId` 后，先启动
`BundledNodeRuntime`，再创建 SSE client。普通第三方 `stdio` 条目不会自动
变成 bundled runtime，也不会在移动端被错误启动；legacy `stdio` / `npx` 只有命中
已审核的 in-process adapter 才会连接。

对应配置示例：

```text
docs/runtime-manifest.example.json
```

> 本节中关于 `stdio-compat-v1` / legacy npx in-process adapter 的描述是旧版兼容层
> 验收记录。当前标准 `transport: "stdio"` 已由移动端 `stdio-v1` JSONL session
> 承载，完整实现、设备 marker 和边界以 `docs/MOBILE_MCP_RUNTIME.md` 为准。

三条路径的边界：

| 路径 | Android | iOS | PC | 宿主机 Node | Docker / Podman |
| --- | ---: | ---: | ---: | ---: | ---: |
| `simichat-local` App Native | 是 | 是 | 是 | 否 | 否 |
| `simichat-node-bundled` | arm64 已验证 | iPhone13 已验证 | macOS App integration 已验证；Linux / Windows 待补 | 否 | 否 |
| `simichat-node-container` | 否 | 否 | 可选侧车 | 否 | 是 |

## 7. 当前真实证明矩阵

| 证据 | 结果 | 说明 |
| --- | --- | --- |
| Flutter analyze | PASS | Dart / Flutter 静态检查 |
| MCP manifest / provider 单测 | PASS | 只证明 source/config/test boundary |
| Android debug APK | PASS | APK 含 `libnode.so`、JNI bridge、`libc++_shared.so`、server asset |
| Pixel 8 真机 | PASS | initialize、tools/list、runtime_info、echo 均由 APK 内 Node 完成 |
| iOS NodeMobile.xcframework | PASS | device arm64、arm64 simulator、x86_64 simulator 已组装；最终 App 包含已 link/embed 的 framework |
| iPhone13 真机 | PASS | pure JS、stdio-compat-v1、legacy npx adapter 的 initialize / tools/list / tools/call marker 全部通过 |
| PC bundled Node host process | PASS | exact bundled path 的真实 Node / SSE / tool smoke |
| PC Flutter App integration | PASS | macOS App test 完成 bundled Node、MCP initialize、tools/list、runtime_info；输出 `SIMICHAT_DESKTOP_BUNDLED_NODE_MCP_READY` |
| PC 六平台发布包 | UNVERIFIED | 当前机器未逐个平台生成和启动发布产物 |
| Android 非 arm64 ABI | NOT SUPPORTED | 当前没有对应 `libnode.so` |
| Android 16 KB page size | ELF PASS / APK ZIP PASS / 真机 UNVERIFIED | source 与 release APK 的 native / ZIP 审计均通过；仍需 16 KB 真机启动与 MCP smoke |
| Android watchdog / 有限重启 | IMPLEMENTED | native 状态、退出码、single-flight 和最多一次重试已接入；长时间锁屏后台仍需 Foreground Service 证据 |

Pixel 8 真机命令：

```bash
flutter --no-version-check test \
  integration_test/mobile_node_mcp_real_smoke_test.dart \
  -d 37101FDJH0077P --no-pub -r expanded
flutter --no-version-check test \
  integration_test/mobile_node_mcp_real_smoke_test.dart \
  -d 00008110-0016349A3A20A01E --no-pub -r expanded
```

预期 marker：

```text
SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY
SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
```

## 8. 发布前门禁

### Android

```bash
flutter --no-version-check analyze --no-pub
flutter --no-version-check build apk --debug --no-pub
flutter --no-version-check build apk --release --no-pub
flutter --no-version-check test \
  integration_test/mobile_node_mcp_real_smoke_test.dart \
  -d <android-device-id> --no-pub -r expanded
unzip -l build/app/outputs/flutter-apk/app-debug.apk \
  | grep -E 'libnode|libsimichat_node_bridge|libc\+\+_shared|runtime-server'
LLVM_READELF=/path/to/ndk/toolchains/llvm/prebuilt/<host>/bin/llvm-readelf \
ZIPALIGN=/path/to/android-sdk/build-tools/35.0.1/zipalign \
  ./scripts/verify_android_native_16k.sh \
  build/app/outputs/flutter-apk/app-release.apk
```

### iOS

```bash
SIMICHAT_NODE_MOBILE_SOURCE=/path/to/nodejs-mobile-18.20.4 \
  ./scripts/prepare_ios_node_mobile.sh
xcodebuild -project ios/Runner.xcodeproj -list
flutter build ios --debug --no-pub
DEVICE_ID=<ios-device-id> ./scripts/smoke_device_mobile_extensions.sh
```

发布前必须同时确认 `NodeMobile.xcframework/Info.plist`、device / simulator
slices、最终 App 中的 embedded framework，以及 iPhone 真机三个 marker；
只生成 framework 或只通过 Xcode link 不能替代 Node health、SSE 和 MCP tool call。

### PC

```bash
SIMICHAT_NODE_RUNTIME_PLATFORM=<target-platform> \
  ./scripts/prepare_node_runtime.sh
flutter build <desktop-target>
./scripts/smoke_bundled_node_runtime.sh
flutter test \
  integration_test/desktop_bundled_node_mcp_real_smoke_test.dart \
  -d <desktop-device> --no-pub -r expanded
```

发布包还必须检查目标 binary 确实进入 App，而不是只检查 Flutter build 成功：

```bash
# macOS
APP="build/macos/Build/Products/Release/ai_chat_app.app"
test -x "$APP/Contents/Resources/node_runtime/macos-arm64/node"

# Linux
test -x "build/linux/x64/release/bundle/node_runtime/linux-x64/node"

# Windows PowerShell
Test-Path "build\\windows\\x64\\runner\\Release\\node_runtime\\windows-x64\\node.exe"
```

随后执行 host smoke 和桌面 integration smoke；两者都必须从目标 App bundle
路径启动 Node，不能只使用 `SIMICHAT_BUNDLED_NODE_PATH` 覆盖路径来冒充发布包
证据。

只有 macOS 已获得 App launch、bundled Node process、MCP initialize、tools/list 和
`simichat.node_runtime_info` 的证据；Linux / Windows 仍需分别获得相同 evidence
后再更新对应平台的 `runtime_verified` 状态。
