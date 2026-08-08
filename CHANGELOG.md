# 更新日志

## v2026.08.08-local-model — 2026-08-08

### 本地模型

- 设置页的“添加渠道 → 厂商预设”新增 Ollama 本地模型入口；Ollama 渠道 API Key 可留空，并提供 gemma4 / qwen3:4b / llama3.2:3b 推荐模型名。
- Ollama 自动获取模型时默认勾选 gemma4 及其 tag 变体，云端渠道的默认勾选行为保持不变。
- Ollama NDJSON 适配器保留 message.thinking 与 message.content，增加连接 / 流式空闲超时、有限错误响应和可选 Bearer 鉴权。
- 空密钥渠道兼容旧数据库和手工导入，非空密钥仍严格解密。
- 新增 scripts/smoke_local_ollama.sh，用于验证真实 Ollama 的 /api/tags 与流式 /api/chat，脚本不会代启或修改服务。

### 文档与验证

- 重写根目录 README，补充项目结构、本地模型网络地址和验证边界。
- 新增 docs/README.md、docs/local-model.md 和当前验证基线。
- 本轮仓库测试和静态分析通过；本机 Ollama 未运行，真实模型 runtime 仍需按文档补证。

## v2026.07.05-voice — 2026-07-05

### 重点

- 录音可以使用了：移动端录音会保存为应用私有目录内的音频附件，并进入现有 STT 转写链路。
- 语音发送链路增强：优先使用设置页显式 STT 配置；未配置时复用当前 OpenAI 兼容聊天渠道的 `/v1/audio/transcriptions`；iOS 可继续使用系统 Speech 作为兜底识别。
- 支持粘贴 base64 语音文本：发送前会本地解码为临时音频附件并转写，原始 base64 不进入聊天上下文或 Markdown 档案。
- 继续保留 TTS 播报、停止播报、播放完成状态回传和 STT/TTS 厂商预设能力。

### 稳定性

- 增强长上下文预算控制：按协议与模型推断上下文窗口，发送前裁剪并在上下文超限时严格裁剪重试一次。
- 扩展 Markdown / Draw.io / Mermaid 等渲染兼容测试，保持用户输入与 AI 输出一致渲染。

### 验证

- `flutter analyze` 通过。
- `flutter test` 全量 318 个测试通过。
- `git diff --check` 无格式问题。
