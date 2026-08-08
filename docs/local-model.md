# 本地 Ollama 模型接入与稳定性

## 目标与边界

SimiChat 将 Ollama 作为一等模型协议，而不是把它伪装成 OpenAI 云端渠道。用户在会话中选择 Ollama 模型后，聊天和依赖当前模型的后台功能都会通过 OllamaProtocol 请求配置的本地地址。

应用负责：

- 保存 Ollama 渠道和模型名称；
- 读取 /api/tags；如配置了反向代理密钥，模型列表和聊天请求都会带 Bearer 鉴权；
- 发送 /api/chat 流式 NDJSON；
- 解析 message.content 和 message.thinking；
- 处理连接超时、流式空闲超时、取消和非 200 响应；
- 在本地渠道没有 API Key 时继续工作。

应用不负责：

- 自动安装 Ollama 或下载模型权重；
- 自动启动或停止 Ollama；
- 本地服务不可用时静默改用远程模型；
- 为用户开放局域网端口或修改系统防火墙。

## 配置

推荐模型：

- gemma4：默认自动获取模型时优先勾选的模型。
- qwen3:4b：结构化输出和 thinking/content 兼容性验证的备选模型。
- llama3.2:3b：资源较紧张时的轻量备选。

这些只是推荐名称，最终以 ollama list 和 /api/tags 返回的实际模型为准。

### Base URL

| 运行环境 | Base URL |
| --- | --- |
| macOS / Linux / Windows 桌面端 | http://127.0.0.1:11434 |
| iOS Simulator | http://127.0.0.1:11434 |
| Android Emulator | http://10.0.2.2:11434 |
| Android / iOS 真机 | Ollama 主机的局域网 IP，例如 http://192.168.x.x:11434 |

真机走局域网时，Ollama 需要监听可被设备访问的地址，主机防火墙也要允许端口；这属于环境配置，不由 App 自动修改。

## 最短验证路径

~~~bash
ollama list
curl -fsS http://127.0.0.1:11434/api/tags
OLLAMA_MODEL=gemma4 scripts/smoke_local_ollama.sh
~~~

smoke_local_ollama.sh 依次验证：

1. /api/tags 可访问；
2. 请求模型已安装（兼容 :latest 省略写法）；
3. /api/chat 能返回完成的 NDJSON 流；
4. 至少有正文或 thinking 输出。

它不会启动 Ollama，也不会输出请求密钥或完整模型回复。没有运行中的服务时，脚本应明确失败，而不是伪造成功。

## 代码路径

| 功能 | 代码 |
| --- | --- |
| 预设、推荐模型和 API Key 规则 | lib/core/ai/model_provider_preset.dart |
| 统一协议选择 | lib/core/ai/ai_service.dart |
| Ollama 请求与 NDJSON | lib/core/ai/ollama_protocol.dart |
| 模型列表获取和可选 Bearer 鉴权 | lib/core/ai/model_fetcher.dart |
| 模型连接测试和有限重试 | lib/core/ai/model_tester.dart |
| 设置页添加 / 获取 / 测试模型 | lib/features/settings/settings_page.dart |
| 聊天发送、取消、上下文压缩 | lib/shared/providers/chat_provider.dart |
| 本地渠道 API Key 空值兼容 | lib/core/crypto/key_encryptor.dart |

## 稳定性策略

- 连接建立最多等待 15 秒。
- 流式响应连续 5 分钟没有新行时超时，避免模型加载卡死后永久占用会话。
- 取消请求会关闭 HTTP client；取消不会写入一条错误的 assistant 消息。
- 非 200 响应只保留有限长度的错误正文，避免异常响应无限膨胀。
- NDJSON 解析保留 thinking 字段，避免支持思考输出的模型出现“只有思考、没有可见正文”时被误判为空回复。
- 本地协议密钥为空时使用 decryptOrEmpty；非空密钥仍严格解密，坏密钥不会被吞掉。
- 上游不可用只显示错误，不触发隐藏的远程回退。

## 自动化覆盖

- test/ollama_protocol_test.dart：JSON 模式请求字段、thinking + content 解析、CancelToken 停止流、/api/tags 模型列表和可选 Bearer 鉴权。
- `ModelFetcher.defaultSelectedModelIds`：Ollama 获取模型弹窗默认勾选 gemma4 及其 tag 变体；云端渠道仍默认勾选全部新模型。
- test/model_provider_preset_test.dart：Ollama 无 Key 规则、推荐模型、云端协议仍要求 Key。
- test/settings_page_ollama_test.dart：设置页本地模型入口、API Key 显示为可选、本地地址预填。
- test/key_encryptor_test.dart：空密钥、加密密钥和旧格式兼容。

仓库中的 mock HTTP 测试验证协议行为，不等于真实权重推理质量验证。真实模型的首次加载耗时、内存占用、长会话质量和移动端局域网稳定性，必须另行执行本页的 runtime smoke。

## 故障排查

| 现象 | 先检查 |
| --- | --- |
| /api/tags 连接被拒绝 | Ollama 是否正在运行、端口是否为 11434、桌面端是否使用正确地址 |
| Android Emulator 连接失败 | 不要使用 localhost，改用 10.0.2.2 |
| 真机连接失败 | Ollama 监听地址、电脑与手机是否同网、系统防火墙 |
| 模型不存在 | ollama list、模型名称和 :latest 后缀 |
| 首 token 很慢 | 首次加载模型属于正常冷启动；超过 5 分钟无流才按超时排查 |
| 发送后没有可见正文 | 检查 Ollama 返回的 message.content，当前适配器已同时保留 message.thinking |
| 设置页提示 API Key 缺失 | 确认协议是 ollama，不是 OpenAI-compatible 自定义渠道 |
