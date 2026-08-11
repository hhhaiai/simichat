# MCP / Skills / 记忆纯本地真机验收（2026-08-09）

## 1. 验收目标

在 Android 和 iOS 真机上验证 MCP、Skills、记忆三条链路可以直接使用 App 自有能力，
不依赖第三方在线服务、远程 MCP、宿主机 Node / npm / npx、Python、shell、Docker 或
Podman。

这里的“不依赖第三方”指**运行时不需要 App 外部环境或在线服务**。Flutter、Drift、
SQLite、SharedPreferences 和 NodeMobile 等依赖均已随 App 构建交付，不在真机运行时
临时下载或调用宿主环境。

## 2. 本轮补强

新增真机测试：

```text
integration_test/mobile_mcp_skills_memory_local_real_smoke_test.dart
```

新增统一入口：

```text
scripts/smoke_device_mobile_mcp_skills_memory_local.sh
```

统一入口依次验证：

1. App Native MCP 真正完成 `initialize`、`tools/list`、`tools/call`。
2. Skill 从内存 package bytes 安装到 App 私有目录，校验 SHA-256、启用并在重建
   installer 后从 registry 恢复。
3. 记忆写入真机 App sandbox 内的真实 SQLite 文件，关闭数据库、重新打开后继续完成
   FTS、semantic 和本地搜索。
4. Key Point 使用生产 `KeyPointMemoryNotifier` 写入隔离的真实 SharedPreferences key，
   重建 notifier 后重新加载和召回。
5. MCP / Skills / 记忆移动端页面、搜索索引和全局搜索结果在真实 UI 中可见。
6. App 内置 NodeMobile、纯 JS MCP、旧 `stdio-compat-v1` 和 legacy npx in-process
   adapter 继续通过；标准 `stdio-v1` JSONL session 的独立真机证据见
   `docs/mobile-node-mcp-runtime-2026-08-09.md`。

`KeyPointMemoryNotifier` 新增可选 `storageKey`，生产默认值保持
`key_point_memory_v1` 不变；真机测试使用隔离 key，结束后删除，不覆盖用户记忆。

## 3. 无外部依赖路径

### MCP

```text
AppNativeMcpTransport
  -> in-app initialize
  -> simichat.runtime_info
  -> simichat.now
```

决定性返回：

```text
dependencyMode=in_app
externalProcess=false
requiresNode=false
requiresNpx=false
requiresPython=false
mobileReady=true
```

纯 JS MCP 使用随 App 发布的 Android `libnode.so` 或 iOS `NodeMobile.framework`；不读取
宿主机 PATH，不调用外部 npx。

### Skills

```text
MobileExtensionPackage bytes
  -> package SHA-256
  -> manifest / entry SHA-256
  -> App sandbox staging
  -> atomic rename
  -> registry enable
  -> installer recreate
  -> registry reload
```

该路径调用 `installBytes`，不调用 `installFromUrl`，没有 Marketplace 或 HTTP 请求。

### 记忆

```text
message
  -> device-local SQLite file
  -> FTS5 + local semantic index
  -> database close
  -> database reopen
  -> local retrieval

Key Point
  -> SharedPreferences isolated key
  -> notifier recreate
  -> local relevance search
  -> cleanup isolated key
```

所有测试目录均位于测试 App 可访问的设备本地临时 sandbox，并在 `finally` 中清理。

## 4. Pixel 8 真机结果

设备：

```text
Pixel 8
Android 16 / API 36
37101FDJH0077P
```

命令：

```bash
DEVICE_ID=37101FDJH0077P \
./scripts/smoke_device_mobile_mcp_skills_memory_local.sh
```

结果：

```text
SIMICHAT_MOBILE_MCP_APP_NATIVE_READY
SIMICHAT_MOBILE_EXTENSIONS_APP_NATIVE_READY
SIMICHAT_MCP_SKILLS_MEMORY_LOCAL_DEVICE_READY
SIMICHAT_MCP_SKILLS_MEMORY_UI_READY
SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY
SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
SIMICHAT_MCP_SKILLS_MEMORY_LOCAL_SUITE_READY
All tests passed
```

逻辑专项：23 个测试文件、175 项通过。

## 5. iPhone13 真机结果

设备：

```text
iPhone13
iOS 26.5 / 23F77
00008110-0016349A3A20A01E
```

命令：

```bash
DEVICE_ID=00008110-0016349A3A20A01E \
./scripts/smoke_device_mobile_mcp_skills_memory_local.sh
```

结果：

```text
SIMICHAT_MOBILE_MCP_APP_NATIVE_READY
SIMICHAT_MOBILE_EXTENSIONS_APP_NATIVE_READY
SIMICHAT_MCP_SKILLS_MEMORY_LOCAL_DEVICE_READY
SIMICHAT_MCP_SKILLS_MEMORY_UI_READY
SIMICHAT_NODE_MOBILE_MCP_DEVICE_READY
SIMICHAT_STDIO_COMPAT_MCP_DEVICE_READY
SIMICHAT_NPX_COMPAT_MCP_DEVICE_READY
SIMICHAT_MCP_SKILLS_MEMORY_LOCAL_SUITE_READY
All tests passed
```

逻辑专项：23 个测试文件、175 项通过。

仓库门禁：

```text
flutter analyze --no-pub: No issues found
flutter test --no-pub -r compact: 694 tests passed
```

## 6. 证据矩阵

| 能力 | Pixel 8 | iPhone13 | 外部运行时 / 在线服务 |
| --- | --- | --- | --- |
| App Native MCP | `runtime_verified` | `runtime_verified` | 不需要 |
| 纯 JS Node-Mobile MCP | `runtime_verified` | `runtime_verified` | 不需要 |
| Skill 本地安装 / SHA-256 | `runtime_verified` | `runtime_verified` | 不需要 |
| Skill registry 重载 | `runtime_verified` | `runtime_verified` | 不需要 |
| SQLite 关闭 / 重开持久化 | `runtime_verified` | `runtime_verified` | 不需要 |
| FTS5 / semantic 本地搜索 | `runtime_verified` | `runtime_verified` | 不需要 |
| Key Point 保存 / 重载 / 召回 | `runtime_verified` | `runtime_verified` | 不需要 |
| MCP / Skills / 记忆真实 UI | `ui_verified` | `ui_verified` | 不需要；Skills 数据由进程内 MockClient 提供 |
| 任意未知 npx 包 | 拒绝 | 拒绝 | 不自动下载 |

## 7. 当前边界

- 本轮证明 App 自有路径，不把远程 Skill Marketplace 或远程 MCP 可用性算入纯本地
  成功条件。
- 移动端 legacy npx 仅支持审核 allowlist 的 in-process adapter；未知包仍拒绝。
- 本轮真实 SQLite / SharedPreferences 测试执行完已清理隔离数据，不改写生产记忆 key。
- 长时间锁屏、系统回收、跨版本升级恢复仍是独立稳定性门禁。
