# 移动端远程模型 Reflection 长会话质量验证（2026-07-14）

## 1. 目标与安全边界

本轮验证移动端 Dreaming 生成的长会话摘要能否通过用户授权的远程 OpenAI-compatible 模型稳定增强 Reflection，同时保持本地规则、安全过滤和未完成状态的真实性。

硬约束：

- 不启动、调用或探测 Ollama / 本地模型；
- 不使用本机模型端口或 `adb reverse`；
- 真实 Base URL、API key 和模型名只从仓库外 `MODEL_CONFIG_FILE` 读取；
- 配置文件权限必须是 `600` 或 `400`；
- 地址、key 和模型默认值不进入代码、脚本、测试、文档、编译参数或 APK；
- Android 跨日隔离任务保持 `waiting`，本轮不得重新 schedule、force 或 cleanup。

## 2. 审计发现

旧 `tool/model_reflection_live_quality_test.dart` 仍默认连接本机 loopback 模型并直接使用本地模型协议，与当前用户约束冲突。本轮将它改成远程配置文件驱动，并新增以下门禁：

- 只接受 `protocol=openai_chat`；
- 拒绝 localhost、`127.*`、`::1` 和 `0.0.0.0`；
- 配置必须为普通文件且权限为 `600/400`；
- 配置大小上限 8 KiB；
- 读取后不删除，便于重复质量验证；
- live gate 源码和脚本不得包含本地端口、本地模型默认值或真实远程配置。

初次真实流式采样暴露远程服务会随机返回 HTTP 200 但没有任何 content / thinking chunk：两组三轮采样分别出现 1 次和 2 次空响应。这证明 SSE 适合普通聊天展示，但当前远程服务的流式模式不足以作为后台结构化 Reflection 的稳定通道。

## 3. 修复

### 3.1 Reflection 使用非流式 OpenAI-compatible 请求

`ChannelModelRelayBridge.forwardOnce()` 只对 `openai_chat` 使用 `/v1/chat/completions` 非流式单次响应；Reflection provider 优先使用该路径。普通聊天仍使用原 SSE，Claude / Gemini 等其他协议也继续使用既有流式路径，避免扩大行为变化。

请求仍传播 `CancelToken` 并受 60 秒总墙钟超时约束；远程失败、空内容、格式错误或不安全输出仍由正式 provider 安全回退本地 Reflection，不残留 pending。

### 3.2 重复 JSON 解析

真实非流式响应会出现：

- `<think>...</think>`；
- JSON 代码围栏；
- 首个 JSON 后再次输出重复 JSON。

旧解析器按第一个 `{` 到最后一个 `}` 截取，会把两个对象拼成非法 JSON。修复后用字符串和转义感知的花括号平衡扫描提取完整对象，按顺序尝试第一个可解析对象；既有尾逗号、缺根闭合、全角右括号和 action object 保守兼容继续保留，敏感信息、URL、本机路径、占位 schema 和虚假完成过滤不变。

### 3.3 Live quality 可用性与质量分离

远程上游偶发返回临时 `401`。live quality 工具对 `401 / 408 / 429 / 5xx / 超时 / 空响应` 最多重试 3 次，并在结果中记录 attempts；这只用于区分接口瞬时可用性和模型输出质量。正式 App 不执行该质量工具重试，仍按生产策略快速回退本地安全报告。

## 4. 真实远程三日长会话结果

命令：

```bash
MODEL_CONFIG_FILE=/仓库外/remote-model.json \
SIMICHAT_LIVE_MODEL_RUNS=3 \
  ./scripts/smoke_model_reflection_live_quality.sh
```

三个 synthetic dayKey 均使用 72 条长会话、36 条用户消息和 36 条助手消息；本地规则先生成 5 条结论和 4 个行动项，远程模型只能补充最多 4 条且不能覆盖本地安全基线。

| dayKey | elapsed | attempts | 本地结论 / 行动 | 最终结论 / 行动 | 响应字符 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2026-07-14 | 27.744s | 2 | 5 / 4 | 8 / 8 | 2137 |
| 2026-07-15 | 29.701s | 1 | 5 / 4 | 8 / 8 | 3092 |
| 2026-07-16 | 14.554s | 1 | 5 / 4 | 8 / 8 | 1191 |

汇总：

```text
runs=3
elapsedMs=71999
attempts=[2,1,1]
result=3/3 passed
```

每轮均验证：

- `generationMode=model`；
- 全部本地结论和行动项仍存在；
- 模型至少增加一条非重复、具体、可执行行动项；
- 最终不超过 8 条结论和 8 个行动项；
- 合成密钥、URL 和本机路径没有进入结果；
- 没有把 Android 跨日验证、iOS 后台 App 刷新或质量门禁写成已经完成；
- 内容与移动端、后台、跨日、iOS、反思、稳定或长会话任务相关。

取证：

```text
/tmp/simichat-remote-reflection-quality-20260714223755.log
/tmp/simichat-remote-reflection-nonstream-20260714222646.log
/tmp/simichat-remote-reflection-thinking-20260714222436.log
```

## 5. 自动化与静态验证

新增 / 修改后的聚焦组合 38 项通过；最终全量稳定门禁：

```text
557 tests passed
```

并通过：

```text
flutter --no-version-check analyze --no-pub
git diff --check
bash -n scripts/smoke_model_reflection_live_quality.sh
sqlite hook residue scan
remote address/key repository scan
```

## 6. 当前结论与剩余边界

本轮证明一个外部配置驱动的 OpenAI-compatible 远程模型可以在三个 dayKey 的 72 条长会话上通过严格 Reflection 质量门禁，且正式 Reflection 非流式路径比当前远程 SSE 稳定。

但仍不能扩大为“所有远程模型均稳定”：

- 第一天需要 2 次请求，说明上游仍有临时鉴权 / 可用性波动；
- 当前只覆盖一个已授权远程模型配置；
- 仍需更多远程模型族、多日真实用户会话和更长周期质量观察；
- Android 2026-07-15 跨日任务仍待独立 verify；
- iOS 系统后台执行仍等待后台 App 刷新开启；
- 长时间 Doze / OEM 严格后台仍未完成。

## 7. Pixel 8 正式后台路径复验

主机端三轮质量通过后，继续使用独立 `top.simitalk.aichat.backgroundmodelsmoke` 复验修改后的正式移动端路径：

```text
Dreaming
→ Android JobScheduler 自然调度
→ UI 进程被回收
→ SystemJobService 冷启动新进程
→ OpenAI-compatible 非流式 Reflection
→ 当前报告 / 历史持久化
```

首次运行在构建前被远程预检安全拒绝：

```text
REMOTE_MODEL_API_FAILED status=401
```

因此未构建、安装或改动设备。随后为预检增加最多 3 次有界重试，只重试 `401 / 408 / 429 / 5xx / curl 失败 / HTTP 200 空内容`；其他 4xx 立即失败，attempt 会记录且不输出配置内容。第二次运行的预检结果：

```text
REMOTE_MODEL_API_RETRY attempt=1 status=401
REMOTE_MODEL_API_READY attempts=2
```

Pixel 8 真机结果：

```text
ready pid=8925
background pid=10117
process restart=true
triggerMode=natural
delaySeconds=30
elapsedSeconds=324
status=completed
digest=2026-07-14
reflection=2026-07-14
generationMode=model
```

设备 prefs 独立复查：

```text
dreaming current=present
dreaming history=present
reflection current=present
reflection history=present
reflection pending=absent
model_fallback=absent
remote address/key leak=absent
```

cleanup 后：

```text
remote smoke package=absent
sqlite hook=absent
formal package pid=10528
formal firstInstallTime=2026-07-14 00:29:02
formal dataDir=/data/user/0/top.simitalk.aichat
cross-day job_0_state=waiting
```

取证：

```text
/tmp/simichat-android-background-dreaming-20260714224926.log
/tmp/simichat-android-background-dreaming-prefs-20260714224926.xml
```

脚本重试 manifest 回归和最终全量稳定门禁通过：

```text
557 tests passed
```

该结果证明上一节的非流式修复不仅在主机质量工具中可用，也已通过 Pixel 8 的正式后台 ProviderContainer、数据库渠道配置、加密 key、JobScheduler 自然进程重启和持久化链路。远程上游临时 `401` 仍作为可用性风险保留；正式 App 遇到远程失败仍安全回退本地 Reflection。
