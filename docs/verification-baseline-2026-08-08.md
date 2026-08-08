# 当前验证基线（2026-08-08）

## 结果摘要

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| Dart 静态分析 | 通过 | flutter --no-version-check analyze --no-pub，No issues found |
| 本地模型专项回归 | 通过 | Ollama 协议、预设、密钥、渠道导入和设置页入口测试共 39 项通过 |
| 设置页回归 | 通过 | DW Chainless、渠道导入和模型剔除测试共 17 项通过 |
| 移动端 MCP / Skills / 记忆逻辑专项 | 通过 | Pixel 8 和 iPhone13 各 162 项；逻辑 runner 使用临时 `--dart-define=sqlite3.source=system` 绕过 GitHub native asset 下载故障 |
| 移动端 MCP / Skills / 记忆真实 UI smoke | 通过 | Pixel 8 和 iPhone13 各 1 项；真实 Drawer、Skills Hub、MCP 设置、索引预热和全局搜索 |
| Android bundled Node MCP 真机 smoke | 通过 | Pixel 8 / Android 16 / arm64-v8a；APK 内 `libnode.so` 完成 initialize、tools/list、runtime_info、echo |
| PC bundled Node host process smoke | 通过 | macOS arm64 exact bundled Node path；真实 `/health`、SSE、tools/list、runtime_info |
| PC macOS Flutter bundled Node integration | 通过 | App test 输出 `SIMICHAT_DESKTOP_BUNDLED_NODE_MCP_READY` |
| 全量 Flutter 单元 / Widget 测试 | 通过 | flutter --no-version-check test --no-pub --no-test-assets -r compact，681 项通过 |
| 格式检查 | 通过 | git diff --check 无输出 |
| 本地模型 smoke 脚本 mock | 通过 | mock HTTP 服务返回 /api/tags、thinking + content NDJSON 和 done=true，脚本输出 LOCAL_OLLAMA_SMOKE_OK |
| Android debug 构建 | 通过 | flutter --no-version-check build apk --debug，生成 build/app/outputs/flutter-apk/app-debug.apk |
| Android release 16 KB audit | 通过 | release APK 的全部 native library 与 ZIP alignment 通过 `ANDROID_16K_NATIVE_AUDIT_PASS`；使用 build-tools 35.0.1 |
| 本机真实 Ollama | 未验证 | ollama 命令不存在，127.0.0.1:11434 当前连接被拒绝 |

## 本轮代码验证

移动端专项的逐项修复、设备、日志和未证明边界见：

```text
docs/mobile-mcp-skills-memory-quality-2026-08-08.md
```

本轮还修复了 iPhone13 窄屏 MCP 添加弹窗的 `DropdownButtonFormField` 右侧 12 px `RenderFlex` 溢出；修复后 Pixel 8 / iPhone13 UI smoke 均重新通过。

内置 Node Runtime 的实现、版本、APK 内容、PC 准备脚本和未完成 ABI / 16 KB
page-size 边界见：

```text
docs/MCP_BUNDLED_NODE_RUNTIME.md
```

## 升级后追加证据（2026-08-08）

- 从 nodejs-mobile `18.20.4` 的固定 source revision 重建了 Android
  `arm64-v8a/libnode.so`。
- 使用 NDK `27.1.12297006` 和 `-Wl,-z,max-page-size=16384`、
  `-Wl,-z,common-page-size=16384`；四个 `LOAD` segment 均为 `0x4000`。
- `LLVM_READELF=... ./scripts/verify_android_native_16k.sh` 对 source JNI library
  输出 `ANDROID_16K_NATIVE_AUDIT_PASS`。
- release APK 的全部 native library 和 ZIP 16 KB alignment audit 也已输出
  `ANDROID_16K_NATIVE_AUDIT_PASS`；16 KB 真机仍需独立证据，manifest 对应字段保持
  分开记录。

本轮将本地模型接入收口为以下事实：

- 设置页可以直接添加 Ollama 渠道，API Key 明确为可选；
- 旧数据库或手工导入的空 apiKeyEncrypted 不会在聊天、标题、替身回复、设置页模型测试或本地 Bot 路径触发解密异常；
- Ollama 流式协议保留 thinking 和 content；
- 模型自动获取链路在 Ollama 反向代理配置 API Key 时也发送 Bearer 鉴权；
- HTTP 请求有连接 / 空闲超时，取消会关闭 client；
- 本地模型预设提供 gemma4、qwen3:4b、llama3.2:3b 推荐名称，自动获取模型时 Ollama 默认勾选 gemma4 及其 tag 变体；
- 新增 scripts/smoke_local_ollama.sh 作为真实服务验证入口。

## 未完成的 runtime 证据

当前机器没有可连接的 Ollama 运行时，因此不能声称以下项目已经在真实本地模型上通过：

- 指定模型权重的首 token / 总响应耗时；
- 长会话上下文压缩和 Dreaming / Reflection 质量；
- Android Emulator、Android 真机、iOS Simulator、iOS 真机的网络地址和后台行为；
- 模型显存 / 内存占用以及并发请求容量。

运行真实验证：

~~~bash
ollama pull gemma4
ollama serve
OLLAMA_MODEL=gemma4 scripts/smoke_local_ollama.sh
~~~

## 当前工作树边界

开始本轮前工作树已有一批未提交修改和未跟踪实现文件。本轮继续补齐 Android / PC
bundled Node、测试和文档；平台构建生成的 macOS SwiftPM / CocoaPods 文件已从
功能 diff 中清理。最终提交前仍需完成 Git LFS、diff、secret 和远端推送检查。
