> **仓库内执行版本**：本文件根据用户于 2026-08-19 提供的 PRD 原文归档，用于后续分阶段实施和验收。现有仓库代码与测试是实现事实来源；与此前短版多模态需求不一致时，以本文件为准。
> **实施判定补充**：交互状态、参数边界、长内容三路径、Artifact 安全边界、完成定义和验收矩阵同时遵守 [需求补充规格](android-multimodal-long-content-artifact-requirements-refinement.md)。

# SimiAIChat Android 多模态工具、超长内容与 Artifact 执行型 PRD

## 0. 文档用途

本文档用于指导开发 AI 基于现有 SimiAIChat Flutter/Android 代码继续开发。

开发 AI 应将**现有仓库代码作为最终事实来源**。本文描述目标行为、架构边界和验收标准，但不允许在未检查代码的情况下假设现有类名、状态管理方案、数据库或目录结构。

实施前必须阅读：

* 仓库根目录的 `AGENTS.md`；
* `docs/requirements.md`；
* `docs/chatgpt-interaction-reference.md`；
* 当前聊天、附件、多媒体、模型配置和持久化相关代码；
* 现有测试文件。

本轮不得为了完成新功能，重写与需求无关的模块。

---

# 一、项目目标

在保留现有普通聊天能力的前提下，完成以下改造：

1. 将图片、语音和视频能力统一放入聊天页的 `+` 工具入口；
2. 每一种工具使用独立的“本次任务面板”；
3. 设置页只保存渠道、Base URL、API Key、默认模型和默认参数；
4. 每次任务的参数不再依赖设置页的全局模式；
5. 增加超长文本粘贴处理：

   * 粘贴内容过大时自动转为文本文件附件；
   * 模型支持文件时按附件发送；
   * 模型不支持文件时自动退化为文本传输；
   * 文本仍超出上下文时自动分批处理；
6. 建立模型能力描述和厂商请求映射层；
7. 增加 Artifact，用于承载网页、Markdown、SVG、Mermaid、代码文件等独立成果；
8. 所有任务结果统一写回当前会话；
9. 所有任务具备保存草稿、停止、失败重试和后台恢复能力；
10. 参考 ChatGPT 的信息架构和状态切换，但不得复制其品牌、图标、文案或视觉资源。

---

# 二、非目标

本轮不包含以下内容：

* 不新增与现有需求无关的“生成音乐”等功能；
* 不将 Android 客户端改造成完整 IDE；
* 不在 Android 客户端内嵌 Node.js、npm 或完整 React 构建工具链；
* 不默认假设所有 OpenAI-compatible 渠道具有相同参数；
* 不依赖标准 `/v1/models` 自动返回完整能力信息；
* 不直接把所有厂商字段塞入通用 `extra`；
* 不展示模型的隐藏推理或内部思维过程；
* 不执行真实、可能计费的图片、音频或视频测试，除非开发环境明确提供测试账号并获得授权；
* 不重构无关页面、网络层或数据库。

---

# 三、当前实现事实与必须修复的问题

开发 AI 应先验证以下现状，路径发生变化时以仓库实际代码为准。

## 3.1 当前相关代码

已知相关代码包括：

```text
lib/shared/widgets/chat_input_bar.dart
lib/shared/providers/chat_provider.dart
lib/shared/providers/image_generation_provider.dart
lib/core/ai/image_generation_service.dart
lib/core/ai/universal_media_service.dart
lib/core/media/openai_text_to_speech_engine.dart
lib/core/media/openai_speech_to_text_engine.dart
```

## 3.2 图片生成现状

当前至少存在以下限制：

* 图片数量固定为 `n: 1`；
* 参考图片只取第一张；
* 缺少独立的比例、分辨率、质量字段；
* 图片模型主要使用自由文本配置；
* 不存在完整的模型能力约束。

必须取消：

```text
n 固定为 1
referenceImages.firstOrNull
```

## 3.3 语音现状

当前普通语音合成、声音设计和声音克隆依赖全局 TTS 模式，导致三个入口互斥。

必须改为三个并列工具：

```text
语音合成
声音设计
声音克隆
```

设置页仅负责默认值，不能继续决定当前聊天只能使用哪一种语音模式。

## 3.4 语音识别现状

当前已有：

* 音频附件；
* `auto / zh / en`；
* 上传后自动转写链路。

但缺少独立的语音识别任务面板和结果卡片。

## 3.5 视频现状

当前至少存在以下问题：

* 只有单张参考图；
* 首帧图和普通参考图没有区分；
* 缺参考音频；
* 缺比例；
* 时长为任意整数；
* xAI/Grok 可能发送 `seconds`，而实际 profile 需要 `duration`。

必须建立 provider/model-specific 映射层。

## 3.6 聊天页现状

目标交互已经确定为：

```text
顶部：[菜单] [聊天 | 工作] [更多]
底部：单一 Composer
扩展能力：统一由 + 进入
```

本轮不得继续在顶部堆放模型、设置、新建、重试、停止等多个常驻操作。

---

# 四、总体技术原则

## 4.1 三层职责必须分开

系统必须区分：

### A. 产品级任务对象

表示用户想做什么，例如：

```text
ImageGenerationOptions
VideoGenerationOptions
SpeechSynthesisOptions
```

### B. 模型能力描述

表示当前模型支持什么，例如：

```text
supportsFileInput
supportedAspectRatios
maxReferenceImages
```

### C. 厂商请求适配器

表示某个渠道实际使用什么字段，例如：

```text
duration
seconds
aspect_ratio
response_format
```

禁止让 UI 直接拼接厂商请求 JSON。

禁止让厂商字段反向污染通用任务对象。

---

## 4.2 能力状态使用三态

模型能力不能只使用布尔值，必须允许未知状态：

```text
supported
unsupported
unknown
```

例如：

```text
fileInputSupport = supported
fileInputSupport = unsupported
fileInputSupport = unknown
```

处理规则：

* `supported`：允许使用相应能力；
* `unsupported`：直接走降级流程；
* `unknown`：采用保守兼容策略，不默认发送高风险字段；
* 用户或管理员可以在渠道配置中覆盖未知能力。

---

## 4.3 能力信息来源优先级

模型能力按以下顺序合并：

1. 后端或渠道明确返回的模型能力；
2. App 内置的已验证模型 profile；
3. 用户在渠道设置中的自定义覆盖；
4. 保守默认值。

不得仅根据模型名称字符串猜测所有能力。

可以根据模型名称匹配内置 profile，但匹配结果必须可覆盖。

---

# 五、模型能力数据结构

建议建立统一的数据结构。实际类名应遵循仓库现有命名习惯。

```text
ModelCapabilities
- modelId
- providerId
- contextWindowTokens
- maxOutputTokens
- maxRequestBytes

- textInputSupport

- fileInputSupport
- supportedInputMimeTypes[]
- supportedFileTransports[]
- maxInputFiles
- maxInputFileBytes

- visionSupport
- maxReferenceImages

- imageGenerationSupport
- supportedImageCounts[]
- supportedAspectRatios[]
- supportedImageResolutions[]
- supportedImageQualities[]

- speechSynthesisSupport
- supportedVoices[]
- supportedSpeechSpeeds[]
- supportedAudioOutputFormats[]

- voiceDesignSupport
- voiceCloneSupport
- supportedReferenceAudioMimeTypes[]
- maxReferenceAudioBytes
- maxReferenceAudioDurationSeconds

- speechRecognitionSupport
- supportedRecognitionLanguages[]

- videoGenerationSupport
- supportsFirstFrame
- supportsReferenceAudio
- supportedVideoDurations[]
- supportedVideoAspectRatios[]
- supportedVideoResolutions[]
```

文件传输方式至少支持以下枚举：

```text
FileTransport
- multipart
- base64DataUrl
- messageContentFile
- remoteFileId
- unsupported
```

`supportsFileInput` 和 `FileTransport` 不得混为一谈。

一个模型可能具备文件理解能力，但当前渠道没有实现相应文件传输协议，此时仍不能直接发送附件。

---

# 六、聊天页整体交互

## 6.1 顶部结构

聊天页顶部统一为：

```text
[菜单]              [聊天 | 工作]              [更多]
```

### 聊天模式

用于：

* 普通对话；
* 文件附件；
* 图片理解；
* 多模态生成；
* Artifact 创建和继续修改。

### 工作模式

用于：

* 长任务状态；
* 分批处理状态；
* 上传进度；
* 排队状态；
* 多媒体生成状态；
* Artifact 构建或重新渲染；
* 停止；
* 失败；
* 重试。

### 模式切换规则

切换 `聊天 / 工作` 时不得：

* 新建会话；
* 清空输入草稿；
* 删除附件；
* 清除工具参数；
* 改变当前模型；
* 中断正在运行的任务；
* 重复发起网络请求。

---

## 6.2 单一 Composer

### 空状态

```text
[+]  询问 SimiAIChat                    [录音] [实时语音]
```

### 有文本或附件

```text
[+]  输入内容或附件                              [发送]
```

### 任务执行中

```text
[+]  正在处理 2/6                                [停止]
```

### 规则

* 最右侧只能显示一个主操作；
* 主操作在“实时语音、发送、停止”之间切换；
* 有附件但无文本时，发送按钮仍应可用；
* 输入框自然增长至约四行；
* 超过四行后输入框内部滚动；
* 附件区固定显示在输入框上方；
* 附件支持预览、删除、替换；
* 键盘弹出时 Composer 贴合安全区；
* 停止任务不得清除草稿、附件和本次任务参数；
* 正在执行任务时，用户仍可准备下一条草稿，但不得误触重复提交当前任务。

---

## 6.3 `+` 工具菜单

本轮菜单至少包含：

```text
添加内容
├─ 相机
├─ 相册
└─ 选择文件

语音
├─ 实时语音
├─ 识别语音
├─ 语音合成
├─ 声音设计
└─ 声音克隆

生成
├─ 生成图片
└─ 生成视频

成果
└─ 创建 Artifact
```

已有但不在本轮实施范围的功能可以保留，但不能作为本轮验收条件。

不可用入口必须展示原因，例如：

```text
尚未配置 TTS 服务
当前模型不支持视频生成
当前渠道不支持文件上传
```

禁止无响应、点击后无反馈。

---

# 七、超长内容粘贴

这是本轮新增的明确需求。

## 7.1 产品目标

当用户向 Composer 粘贴特别大的文本时：

1. 不将全部文本直接塞入输入框；
2. 自动把本次粘贴内容保存为本地文本文件附件；
3. 在 Composer 上方显示附件卡片；
4. 用户可以继续输入问题并直接发送；
5. 当前模型支持文件时，按文件附件发送；
6. 当前模型不支持文件时，自动转成文本输入；
7. 文本仍超出模型上下文或请求体限制时，自动分批处理；
8. 用户在会话时间线中只看到原始附件消息和最终回答，不看到内部批处理消息。

---

## 7.2 大粘贴判定

阈值必须可配置，不能散落在 Widget 中硬编码。

首版默认值：

```text
pasteAsFileCharacterThreshold = 16000
pasteAsFileUtf8ByteThreshold = 64 KiB
pasteAsFileEstimatedTokenThreshold = 8000
```

满足任一条件即视为大粘贴。

判定必须基于本次粘贴片段，而不是整个 Composer 的总文本。

例如：

```text
Composer 原有文字：请检查下面代码的问题
本次粘贴：一段 30000 字符代码
```

结果应为：

```text
输入框保留：请检查下面代码的问题
附件新增：pasted-content-20260819-145800.txt
```

不得把用户原本已输入的提问一起转成文件。

---

## 7.3 自动转文件行为

大粘贴发生时：

* 不弹出阻塞式确认框；
* 自动创建 App 私有目录文件；
* 显示轻提示：

```text
粘贴内容较长，已转换为附件
```

附件卡片显示：

* 文件名；
* 文件类型；
* 字符数；
* 文件大小；
* 预估 Token；
* 预览；
* 删除；
* 重命名；
* 还原为文本。

文件名示例：

```text
pasted-content-20260819-145800.md
pasted-content-20260819-145800.txt
```

扩展名规则：

* 明显包含 Markdown 标题、列表、代码围栏时使用 `.md`；
* 其他情况使用 `.txt`；
* 无论使用哪种扩展名，都必须原样保留文本内容；
* 不得擅自格式化、修剪或改写用户粘贴内容。

---

## 7.4 文本保真要求

必须保留：

* Unicode；
* 中文；
* Emoji；
* 换行；
* 空行；
* Tab；
* Markdown；
* 代码围栏；
* CRLF/LF 内容语义；
* 文件末尾换行状态。

允许统一内部编码为 UTF-8。

不得：

* 自动删除连续空行；
* 自动替换引号；
* 自动格式化代码；
* 自动压缩空格；
* 因预览截断而修改原文件。

---

## 7.5 草稿和生命周期

大粘贴附件必须绑定当前会话草稿。

需要保存：

```text
PastedTextAttachment
- id
- conversationId
- draftId
- localPath
- displayName
- mimeType
- source = largePaste
- characterCount
- utf8ByteCount
- estimatedTokens
- sha256
- createdAt
```

生命周期规则：

* 关闭任务面板后附件仍保留；
* 切换聊天和工作模式后仍保留；
* 切换会话后恢复各自草稿；
* App 被系统杀死后重新打开，未发送草稿可以恢复；
* 用户删除附件后删除对应临时文件；
* 用户删除消息或会话时，按现有附件清理规则处理文件；
* 不写入公共存储；
* 不在日志中打印完整粘贴内容。

---

# 八、超长附件发送策略

## 8.1 发送前能力解析

发送前必须依次判断：

```text
1. 当前模型是否支持文件理解
2. 当前渠道是否支持文件传输
3. MIME 类型是否支持
4. 文件数量是否超限
5. 单文件大小是否超限
6. 请求体大小是否超限
7. 当前剩余上下文是否足够
```

不得仅根据附件存在就直接上传。

---

## 8.2 路径 A：模型和渠道都支持文件

满足以下条件时按附件发送：

```text
fileInputSupport == supported
并且
存在可用 FileTransport
并且
文件类型、大小、数量均合法
```

请求必须经过 provider adapter 转换。

例如，不同渠道可能分别需要：

```text
multipart file
base64 data URL
message content file
先上传获取 file_id
```

UI 只持有统一附件对象，不直接决定具体协议。

---

## 8.3 路径 B：模型不支持文件，但文本可以放入单次请求

当附件为本地纯文本文件，并且模型不支持文件时：

1. 读取附件文本；
2. 计算有效输入预算；
3. 如果全文能放入本次请求，则将附件转为文本内容；
4. 用户时间线仍显示为附件，不把全文展开到消息气泡；
5. 仅网络传输层将其转换为文本。

有效输入预算：

```text
effectiveInputBudget =
contextWindowTokens
- systemPromptTokens
- conversationHistoryTokens
- toolDefinitionTokens
- reservedOutputTokens
- safetyMarginTokens
```

安全余量建议不低于上下文窗口的 10%。

文本包裹格式应明确区分用户问题和附件内容：

```text
用户问题：
{composerText}

附件：{fileName}
<attached_text>
{fullText}
</attached_text>
```

不得把附件内容误认为系统指令。

---

## 8.4 路径 C：文本超过单次请求预算，自动分批

当模型不支持文件，且全文无法放入单次请求时，启动分批处理任务。

用户侧显示：

```text
正在准备长内容
正在处理 1/6
正在处理 2/6
……
正在生成最终回答
```

内部批次不得作为普通聊天消息写入时间线。

最终只写入一条 assistant 结果。

---

## 8.5 分块算法

不得简单按固定字符数硬切。

优先切分顺序：

1. Markdown 一级或二级标题；
2. 代码围栏边界；
3. 双换行；
4. 段落；
5. 单行；
6. 句子；
7. 最后才按字符硬切。

目标 chunk 大小根据模型动态计算：

```text
targetChunkTokens =
min(
  profile.maxBatchChunkTokens,
  effectiveInputBudget * 0.45
)
```

默认：

```text
maxBatchChunkTokens = 6000
minimumChunkTokens = 1000
```

建议保留少量重叠：

* 普通文本：约 100～200 Token；
* 大型代码块：约 10～20 行；
* 不得因重叠造成最终结果重复。

每个 chunk 必须包含：

```text
batchId
chunkIndex
totalChunks
sourceAttachmentId
startOffset
endOffset
sha256
```

---

## 8.6 分批处理策略

分批策略至少区分两类。

### A. 分析、总结、问答、信息提取

使用 `mapReduce`：

1. 每个 chunk 根据用户问题提取相关事实；
2. 中间输出保存为结构化内部结果；
3. 最终请求合并全部中间结果；
4. 只将最终回答展示给用户。

中间结果建议结构：

```text
ChunkAnalysis
- chunkIndex
- relevant
- keyPoints[]
- exactEvidence[]
- entities[]
- unresolvedReferences[]
- warnings[]
```

### B. 翻译、改写、格式转换等顺序型任务

使用 `orderedTransform`：

1. 按原文顺序处理每个 chunk；
2. 每个 chunk 的结果按顺序保存；
3. 最终拼接；
4. 必要时进行一次轻量一致性校正；
5. 不得因最终校正丢失段落或改变原意。

初版可以通过明确关键词和任务入口判断策略。

无法明确判断时默认使用 `mapReduce`，同时在任务内部保存原始附件，避免数据丢失。

---

## 8.7 分批任务数据结构

```text
ChunkedContentTask
- id
- conversationId
- sourceMessageId
- sourceAttachmentId
- originalPrompt
- modelId
- providerId
- strategy
- totalChunks
- completedChunks
- status
- chunkResults[]
- finalResponseMessageId
- createdAt
- updatedAt
```

批次任务状态：

```text
draft
validating
preparing
running
succeeded
failed
cancelled
```

---

## 8.8 取消、失败和重试

### 取消

用户点击停止后：

* 停止未发送批次；
* 尝试取消当前网络请求；
* 不写入残缺 assistant 消息；
* 保留原始附件；
* 保留用户问题；
* 保留已完成批次的内部缓存；
* 允许从头重试或继续处理。

### 单批失败

* 单批最多自动重试 2 次；
* 使用现有网络重试机制；
* 不得无限重试；
* 失败后展示明确错误摘要；
* 用户可选择重新处理、切换模型或直接发送较小内容。

### 文件上传被服务端拒绝

当 profile 标记支持文件，但服务端返回明确的文件不支持错误，例如：

```text
unsupported file
unsupported content type
invalid attachment
415
特定 400 错误码
```

允许自动降级一次到文本或分批模式。

必须满足：

* 同一个任务只自动降级一次；
* 不循环重试；
* 不生成重复消息；
* 记录降级原因；
* 用户侧显示“当前渠道未接受附件，已改为文本处理”。

不得对所有 400 错误无条件降级。

---

## 8.9 当前实现状态（2026-08-19）

本节记录已交付的路径 C，避免把该 PRD 的后续目标误读为尚未实现或已经全部完成。

- **触发范围**：仅当输入由纯 `document` 文本附件构成且超出单次安全预算时自动创建任务。混合图片、音频、视频或其它文件的超预算输入必须在提交前明确拒绝，不能只处理其中的文本。
- **持久化**：使用 schema 14 的 `chunked_content_tasks` 保存无凭据 `request_snapshot`、源附件引用、策略、分块偏移/哈希/重试次数/内部结果、进度、lease 与确定性最终消息 ID。原始正文继续保留在应用私有附件，不复制进任务表；API Key 不进入任务快照。
- **策略**：`mapReduce` 每段输出内部分析，全部完成后只发送一次 reduce；`orderedTransform` 强制零 overlap、按 `chunkIndex` 拼接，当前不做会删除或重排文本的最终润色请求。
- **恢复**：冷启动不会重发可能计费的 chunk 请求。`preparing`、`running`、`reducing` 会收敛为 failed，并保留已完成段；用户可显式“继续未完成部分”或“从头重试”。重试先验证源附件、提交时模型和快照；无效时保留终态而不显示伪进行中。
- **交付和取消**：中间结果不写 messages、Markdown 对话档案或默认聊天时间线；最终 assistant 使用固定 ID 且以 SQLite 事务 `insertOrIgnore` 交付。Stop 同时取消网络 token 和任务状态；即使 reduce 响应随后到达，状态裁决也会阻止最终消息写入。
- **路径 A 子集（已实现）**：对 `openai_response`，经模型级文件契约验证的普通 `document` 走 Responses `input_file`。应用以 `file_data=data:<mime>;base64,...` 传送原始附件 bytes，并发送清洗后的用户文件名；该路线跳过文本正文抽取，确保同一文档不会同时出现在 `input_text` 与 `input_file`，也不会泄露应用私有归档路径。协议层与 ChatProvider Dio 回环均已验证请求字段和单条 assistant 交付。
- **尚未实现**：其它 provider 的真实 File API / `FileTransport`、由服务端明确附件拒绝触发的一次性 File→文本降级、跨设备备份/导入中间结果、真实云端长文 E2E、完整聊天/工作分段视图和 Artifact 均不属于本次完成项。

---

# 九、统一任务面板

点击生成类工具后，在当前聊天页打开任务面板。

## 9.1 展示方式

* 手机竖屏：底部抽屉；
* 字段较多时可展开为全屏；
* 平板或横屏：优先右侧面板；
* 顶部：工具名称和关闭按钮；
* 中间：输入、附件和参数；
* 底部：固定主按钮。

## 9.2 通用规则

* 关闭面板后保留未提交草稿；
* 参数只作用于本次任务；
* 可以提供“设为默认值”，但不得自动覆盖默认配置；
* 模型切换后重新解析能力；
* 不支持字段隐藏或禁用；
* 禁用时必须说明原因；
* 已选择的参数在模型切换后失效时，应明确提示并重置；
* 提交后生成统一任务记录；
* 失败后保留参数和附件；
* 成功后只清除本次已消费的数据。

---

# 十、生成图片

## 10.1 面板字段

按以下顺序：

1. 图片模型；
2. 提示词；
3. 生成数量；
4. 参考图；
5. 图片比例；
6. 清晰度；
7. 像素分辨率；
8. 图片质量；
9. 生成按钮。

## 10.2 参数要求

### 模型

* 使用可选择列表；
* 可以保留“自定义模型 ID”高级入口；
* 自定义模型使用保守能力 profile；
* 不得继续只依赖自由文本。

### 数量

由模型能力决定，例如：

```text
1
2
4
6
8
10
```

### 参考图

* 支持一张或多张；
* 支持预览；
* 支持排序；
* 支持替换；
* 支持删除；
* 最大数量由模型决定。

### 比例

示例：

```text
1:1
4:3
3:4
16:9
9:16
```

### 清晰度

示例：

```text
1K
2K
4K
```

### 像素分辨率

示例：

```text
1024x1024
1536x1024
1024x1536
```

### 质量

示例：

```text
自动
低
中
高
```

## 10.3 通用请求对象

```text
ImageGenerationOptions
- model
- prompt
- count
- referenceImages[]
- aspectRatio
- resolution
- size
- quality
```

## 10.4 必须修复

* `n` 不得固定为 `1`；
* 不得使用 `.firstOrNull` 丢弃参考图；
* 不支持字段不得发送；
* 参数必须经模型 profile 和 provider adapter 转换；
* 图片编辑和图片生成协议不同的情况下，不得强行复用同一请求。

---

# 十一、语音合成

## 11.1 面板字段

1. 模型；
2. 输入内容；
3. 音色；
4. 语速；
5. 输出格式；
6. 试听或生成按钮。

## 11.2 参数要求

* 输入内容使用独立多行文本框；
* 音色显示名称、语言和风格说明；
* 支持音色试听时，试听请求必须独立标记；
* 语速默认 `1.0x`；
* 语速范围由模型决定；
* 输出格式由模型决定；
* 本次参数不得自动覆盖全局默认值。

## 11.3 请求对象

```text
SpeechSynthesisOptions
- model
- input
- voice
- speed
- responseFormat
```

---

# 十二、声音设计

## 12.1 面板字段

1. 模型；
2. 输入内容；
3. 声音风格；
4. 语速；
5. 输出格式；
6. 生成按钮。

声音风格为自然语言，例如：

```text
温柔自然的年轻女声，普通话标准，语气亲切，适合知识讲解。
```

## 12.2 请求对象

```text
VoiceDesignOptions
- model
- input
- style
- speed
- responseFormat
```

## 12.3 规则

* 风格必须为本次任务参数；
* 设置页仅保存默认风格；
* 用户可以主动选择“保存为声音预设”；
* 未选择保存时不得修改全局配置。

---

# 十三、声音克隆

## 13.1 面板字段

1. 模型；
2. 输入内容；
3. 参考音频；
4. 语速；
5. 输出格式；
6. 生成按钮。

## 13.2 参考音频

支持：

* 上传；
* 录制；
* 试听；
* 替换；
* 删除。

显示：

* 文件名；
* 格式；
* 大小；
* 时长。

限制必须由模型能力决定，不得永久固定为：

```text
WAV
10 MB
```

## 13.3 授权要求

提交前显示确认：

```text
我确认拥有该声音的使用权，或已获得声音主体的明确授权。
```

未确认时不得提交。

参考音频默认保存在 App 私有目录。

不得在用户不知情的情况下长期复用。

## 13.4 请求对象

```text
VoiceCloneOptions
- model
- input
- referenceAudio
- speed
- responseFormat
- authorizationConfirmed
```

---

# 十四、识别语音

## 14.1 面板字段

1. 识别模型；
2. 音频文件；
3. 识别语言；
4. 开始识别按钮。

语言选项：

```text
自动检测
中文
English
```

映射：

```text
自动检测：不发送 language
中文：zh
English：en
```

## 14.2 结果卡片

识别结果写入当前会话，支持：

* 展开完整文本；
* 复制；
* 编辑；
* 保存为 `.txt`；
* 保存为 `.md`；
* 重新识别；
* 将识别结果填入 Composer；
* 基于识别结果继续提问。

## 14.3 请求对象

```text
SpeechRecognitionOptions
- model
- audioFile
- language
```

不得继续只依赖“附件发送后隐式自动转写”。

原有自动转写能力可以保留，但必须与独立工具入口共存。

---

# 十五、生成视频

“手诊图”统一修正为“首帧图”。

## 15.1 面板字段

1. 视频模型；
2. 提示词；
3. 首帧图；
4. 参考图；
5. 参考音频或参考音色；
6. 时长；
7. 比例；
8. 分辨率；
9. 生成按钮。

## 15.2 参数规则

### 首帧图

* 与普通参考图分开；
* 单独上传区域；
* 使用独立字段。

### 参考图

* 支持多张；
* 最大数量由模型决定；
* 支持排序、预览、替换和删除。

### 参考音频

* 模型支持时显示；
* 支持上传、录制、试听、替换和删除；
* 模型不支持时不发送任何占位字段。

### 时长

必须使用模型支持的离散选项，例如：

```text
5 秒
8 秒
10 秒
15 秒
```

不得继续使用无限制正整数。

### 比例

示例：

```text
1:1
16:9
9:16
```

### 分辨率

示例：

```text
480p
720p
1080p
```

## 15.3 请求对象

```text
VideoGenerationOptions
- model
- prompt
- firstFrameImage
- referenceImages[]
- referenceAudio
- duration
- aspectRatio
- resolution
```

## 15.4 xAI/Grok 映射

目标请求示例：

```json
{
  "model": "grok-imagine-video-1.5",
  "prompt": "A paper airplane flying over a city",
  "duration": 8,
  "aspect_ratio": "16:9",
  "resolution": "720p"
}
```

xAI/Grok profile 必须将通用字段映射为：

```text
duration -> duration
aspectRatio -> aspect_ratio
resolution -> resolution
```

不得继续发送：

```json
{
  "seconds": 8
}
```

OpenAI/Sora、xAI/Grok 和自定义兼容渠道必须使用不同 adapter。

---

# 十六、Provider 请求适配层

建议建立类似以下接口：

```text
ProviderRequestAdapter<TOptions>
- validate(options, capabilities)
- buildRequest(options, capabilities, channelConfig)
- parseResponse(response)
- classifyError(error)
```

至少提供：

```text
ImageGenerationRequestAdapter
SpeechSynthesisRequestAdapter
VoiceDesignRequestAdapter
VoiceCloneRequestAdapter
SpeechRecognitionRequestAdapter
VideoGenerationRequestAdapter
ChatFileInputAdapter
```

请求发送前必须完成：

1. 参数合法性验证；
2. 能力验证；
3. 参数默认值补全；
4. 厂商字段转换；
5. 不支持字段移除；
6. 文件编码或上传；
7. 请求体大小校验。

禁止在 Widget 中构造最终 HTTP JSON。

---

# 十七、Artifact

## 17.1 定义

Artifact 用于承载可以独立查看、编辑、运行或下载的 AI 成果。

首版支持：

* HTML；
* SVG；
* Mermaid；
* Markdown；
* 纯文本；
* 单个代码文件；
* 多文件源码项目；
* 已经包含可运行静态构建产物的网页项目。

普通代码回答仍显示为代码块。

不得仅因为回答很长就自动创建 Artifact。

---

## 17.2 创建入口

用户可以从 `+` 菜单选择：

```text
创建 Artifact
```

也可以在明确支持结构化输出的模型中，由模型返回 Artifact envelope。

首版优先采用显式创建，不使用模糊文本启发式自动识别。

---

## 17.3 Artifact 输出协议

优先级：

1. 模型工具调用；
2. 结构化 JSON；
3. 明确标记的 fenced envelope；
4. 普通代码块不自动转换。

统一结构：

```text
ArtifactEnvelope
- title
- type
- entryFile
- files[]
```

示例：

```json
{
  "title": "产品落地页",
  "type": "html",
  "entryFile": "index.html",
  "files": [
    {
      "path": "index.html",
      "language": "html",
      "mimeType": "text/html",
      "content": "<!doctype html>..."
    }
  ]
}
```

解析失败时：

* 不得丢弃模型原始回答；
* 按普通消息展示；
* 显示“Artifact 数据格式无效”；
* 提供重新生成。

---

## 17.4 会话内卡片

Artifact 创建完成后显示：

```text
产品落地页
HTML · 已生成
[打开]
```

卡片包含：

* 标题；
* 类型；
* 更新时间；
* 文件数量；
* 缩略图或类型图标；
* 打开；
* 下载；
* 复制；
* 重命名；
* 删除。

---

## 17.5 手机端查看

手机竖屏使用全屏：

```text
[返回]  Artifact 名称                 [更多]

[预览] [源码]

内容区域

[继续修改]                         [下载]
```

禁止在手机竖屏强制使用狭窄双栏。

---

## 17.6 平板和横屏

大屏设备可以使用：

```text
左侧：会话
右侧：Artifact
```

右侧支持：

* 预览；
* 源码；
* 文件树；
* 错误信息。

---

## 17.7 首版预览范围

### 直接支持预览

* Markdown；
* SVG；
* Mermaid；
* 单文件 HTML；
* 带静态入口文件的网页项目。

### React 和多文件项目

首版规则：

* 可以查看源码；
* 可以下载 ZIP；
* 当 Artifact 已包含构建后的 `index.html` 和静态资源时，可以预览；
* 只有服务端或模型返回可运行 bundle 时才预览；
* 不在 Android 客户端内嵌 Node/npm 现场编译 React。

后续版本可以增加独立构建服务。

---

## 17.8 WebView 隔离要求

Artifact 预览必须使用隔离配置。

至少包括：

* 禁止访问 App 私有文件；
* 禁止任意 `file://` 访问；
* 禁止 Content Provider 访问；
* 不注入高权限 JavaScript Bridge；
* 默认阻止摄像头；
* 默认阻止麦克风；
* 默认阻止定位；
* 默认阻止剪贴板读取；
* 默认阻止文件选择；
* 默认阻止任意外部网络请求；
* 外部链接点击前确认；
* 拦截自定义 scheme；
* 禁止预览页面覆盖宿主导航；
* 显示运行错误；
* 支持刷新和停止加载。

允许 JavaScript 的 Artifact 必须在受限 WebView 中运行。

---

## 17.9 源码模式

支持：

* 文件树；
* 语法高亮；
* 搜索；
* 复制当前文件；
* 复制全部文件；
* 编辑；
* 保存；
* 重新预览；
* 未保存状态提示；
* 错误文件定位。

首版编辑器以稳定为优先，不要求完整 IDE 能力。

---

## 17.10 下载

规则：

```text
HTML -> .html
SVG -> .svg
Markdown -> .md
文本 -> .txt
单文件代码 -> 对应扩展名
多文件项目 -> .zip
```

要求：

* 下载内容必须为当前已保存版本；
* 文件名过滤非法字符；
* 禁止绝对路径；
* 禁止 `../`；
* ZIP 内路径必须规范化；
* 使用 Android 系统文件保存界面；
* 不默认写入无权限的公共路径。

---

## 17.11 继续修改

Artifact 页面提供自然语言修改入口，例如：

```text
把背景改成深蓝色
增加移动端导航
修复当前运行错误
```

规则：

* 修改当前 Artifact；
* 每次成功修改形成新版本；
* 失败时保留上一可用版本；
* 修改后自动刷新预览；
* 用户可以恢复旧版本；
* 用户可以另存为新 Artifact；
* 修改请求必须携带当前 Artifact 的必要文件，而不是无条件携带整个会话所有内容。

当模型不支持文件时，可以复用超长内容的文本降级和分批处理机制。

---

## 17.12 数据结构

```text
Artifact
- id
- conversationId
- sourceMessageId
- title
- type
- entryFile
- currentVersionId
- previewStatus
- createdAt
- updatedAt
```

```text
ArtifactFile
- id
- artifactId
- versionId
- path
- language
- mimeType
- content
- contentHash
```

```text
ArtifactVersion
- id
- artifactId
- versionNumber
- changeSummary
- createdAt
```

Artifact 必须绑定来源会话和来源消息。

重新打开会话后，应恢复：

* Artifact 卡片；
* 当前版本；
* 文件；
* 预览状态；
* 版本记录。

持久化应复用现有数据库或 repository 层，不得无理由增加第二套数据库。

---

# 十八、统一任务状态

所有聊天长任务、多模态任务、分批处理和 Artifact 使用统一状态语义：

```text
draft
validating
preparing
uploading
queued
running
succeeded
failed
cancelled
```

任务记录建议包含：

```text
TaskRecord
- id
- conversationId
- sourceMessageId
- type
- status
- progressCurrent
- progressTotal
- requestSnapshot
- resultReference
- errorCode
- errorMessage
- createdAt
- updatedAt
```

规则：

### 成功

* 结果写回当前会话；
* 只清除已消费的文本、附件和参数；
* 不影响用户正在编辑的下一条草稿。

### 失败

* 保留输入；
* 保留附件；
* 保留任务参数；
* 展示可理解的错误摘要；
* 支持重试；
* 支持修改参数后重试。

### 取消

* 终止当前请求；
* 不写入半条 assistant 消息；
* 不丢失原始输入；
* 已生成的有效旧结果不删除。

### 后台恢复

重新打开 App 或会话后：

* 恢复真实状态；
* 不将未知状态错误显示为“已完成”；
* 无法继续的任务标记为“可重试”；
* 不只依赖一次性 Toast。

---

# 十九、错误分类

错误至少分为：

```text
configurationError
authenticationError
capabilityUnsupported
validationError
fileTooLarge
requestTooLarge
contextTooLarge
rateLimited
providerUnavailable
networkError
cancelled
responseParseError
artifactRuntimeError
unknown
```

UI 应根据错误类型提供对应动作。

示例：

```text
当前模型不支持文件附件，已切换为文本处理
文件超过当前模型允许的 10 MB
当前内容超过上下文限制，将分 6 批处理
API Key 无效，请检查渠道配置
视频生成服务暂时不可用，可稍后重试
```

不得直接把完整服务端堆栈展示给普通用户。

调试日志可以保存错误码和截断后的响应，但不得记录 API Key、完整音频 Base64、完整文件内容或完整大粘贴文本。

---

# 二十、实施阶段

每个阶段结束时必须保证：

```text
flutter analyze
flutter test
git diff --check
```

均通过，或明确说明已有基线问题。

## Phase 0：仓库检查和基线

* 阅读 `AGENTS.md` 和需求文档；
* 确认状态管理方式；
* 确认聊天草稿持久化；
* 确认附件模型；
* 确认数据库；
* 确认 provider/channel 配置；
* 运行现有测试；
* 记录基线失败；
* 不修改业务逻辑。

## Phase 1：能力模型和请求适配层

* 新增 `ModelCapabilities`；
* 新增能力 registry；
* 新增 provider request adapters；
* 建立三态能力；
* 建立文件传输类型；
* 建立六类 Options；
* 修复 Grok `duration`；
* 取消图片 `n: 1`；
* 取消参考图 `.firstOrNull`；
* 补充序列化单元测试。

## Phase 2：超长粘贴

* 监听 paste 事件；
* 实现阈值计算；
* 自动创建本地文本附件；
* 实现附件卡片；
* 实现草稿恢复；
* 实现支持文件的发送路径；
* 实现单次文本降级；
* 实现分块器；
* 实现 `mapReduce`；
* 实现 `orderedTransform`；
* 实现进度、停止、失败和重试；
* 补充完整测试矩阵。

## Phase 3：聊天壳层与 Composer

* 会话抽屉；
* `聊天 / 工作`；
* 顶栏操作收敛；
* 单一 Composer 状态机；
* 附件区域；
* 键盘避让；
* 发送、实时语音、停止互斥；
* 后台恢复。

## Phase 4：六个任务面板

按顺序实施：

1. 生成图片；
2. 识别语音；
3. 语音合成；
4. 声音设计；
5. 声音克隆；
6. 生成视频。

每完成一个面板，都必须：

* 接入能力 profile；
* 接入 provider adapter；
* 增加 Widget 测试；
* 增加 mock HTTP 测试；
* 验证失败后草稿保留。

## Phase 5：Artifact MVP

* Artifact 数据模型；
* 会话卡片；
* Markdown、SVG、Mermaid、HTML 预览；
* 源码查看；
* 单文件下载；
* 多文件 ZIP；
* 隔离 WebView；
* 基础编辑；
* 版本保存；
* 继续修改；
* 手机全屏；
* 平板分栏。

## Phase 6：真机验证

在 Pixel 8 上验证：

* 键盘避让；
* 大粘贴；
* 附件预览；
* 切换会话；
* App 重启草稿恢复；
* 分批任务停止；
* 任务失败重试；
* 图片多参考图；
* 三类语音工具并列；
* 语音识别结果卡片；
* Grok 视频请求字段；
* Artifact 预览；
* 下载；
* 外部链接拦截；
* 120% 系统字体。

---

# 二十一、测试要求

## 21.1 超长粘贴单元测试

必须覆盖：

1. 小文本粘贴保持在输入框；
2. 字符数超过阈值转附件；
3. UTF-8 字节超过阈值转附件；
4. Token 估算超过阈值转附件；
5. 原有输入文本不被转附件；
6. Markdown 保存为 `.md`；
7. 普通文本保存为 `.txt`；
8. 中文、Emoji 和代码围栏不丢失；
9. 删除附件后临时文件被清理；
10. 草稿恢复后附件仍存在；
11. 多次大粘贴生成多个附件；
12. 文件名不冲突。

## 21.2 文件能力测试

覆盖：

```text
模型支持文件 + 渠道支持 multipart
模型支持文件 + 渠道支持 base64
模型支持文件 + 渠道不支持传输
模型不支持文件
模型文件能力未知
MIME 不支持
文件过大
文件数量过多
服务端拒绝附件并自动降级
```

## 21.3 分批处理测试

覆盖：

* 正确计算 chunk 数；
* 保留 chunk 顺序；
* 标题边界切分；
* 代码围栏尽量不被破坏；
* 处理进度正确；
* 中间结果不进入时间线；
* 最终只生成一条 assistant 消息；
* 单批失败重试；
* 取消后停止后续请求；
* 重试不会重复创建用户消息；
* `mapReduce` 正常；
* `orderedTransform` 正常；
* App 重启后任务状态可恢复或明确可重试。

## 21.4 多模态请求测试

使用 mock HTTP 精确断言：

* 图片 `n`；
* 多参考图；
* 图片比例；
* 图片分辨率；
* 图片质量；
* TTS `voice`；
* TTS `speed`；
* TTS `response_format`；
* 声音设计 `style`；
* 声音克隆参考音频；
* STT `auto` 不发送 `language`；
* STT 中文发送 `zh`；
* STT 英文发送 `en`；
* Grok 视频发送 `duration`；
* Grok 视频发送 `aspect_ratio`；
* 不支持字段不会进入请求。

## 21.5 Artifact 测试

覆盖：

* Artifact envelope 解析；
* 非法 envelope 回退为普通消息；
* HTML 预览；
* SVG 预览；
* Mermaid 预览；
* Markdown 预览；
* 文件树；
* 编辑和保存；
* 版本增加；
* 恢复旧版本；
* 单文件下载；
* ZIP 路径安全；
* `../` 路径被拒绝；
* 外部链接被拦截；
* 摄像头、麦克风和定位权限被拒绝；
* 会话重新打开后 Artifact 恢复。

---

# 二十二、验收标准

以下项目全部满足，才视为本轮完成。

1. 六项多模态能力均可从 `+` 菜单独立进入；
2. 用户无需进入设置页即可完成一次任务；
3. 普通语音合成、声音设计和声音克隆可以并列使用；
4. 图片支持模型、数量、多参考图、比例、分辨率和质量；
5. 图片请求不再固定 `n: 1`；
6. 多参考图不再被 `.firstOrNull` 截断；
7. 语音识别有独立入口；
8. 语音识别支持自动、中文和英文；
9. 视频支持首帧图、多参考图、参考音频、时长、比例和分辨率；
10. Grok 视频正确发送 `duration`；
11. Grok 视频正确发送 `aspect_ratio`；
12. 不向不支持字段的模型发送无效参数；
13. 大粘贴自动转换为文件附件；
14. 原有 Composer 文本不会被错误转入附件；
15. 文件支持模型可以按正确协议接收附件；
16. 文件不支持模型可以自动退化为文本；
17. 文本超过上下文时可以自动分批处理；
18. 分批处理中间消息不进入用户时间线；
19. 分批处理最终只产生一条可见回答；
20. 停止分批处理后不丢失原始附件和问题；
21. 服务端拒绝附件时最多自动降级一次；
22. 失败或取消后不丢失草稿、附件和参数；
23. 网页或文档成果可以创建 Artifact；
24. Artifact 可以预览、查看源码和下载；
25. 多文件 Artifact 可以 ZIP 下载；
26. Artifact 修改形成新版本；
27. Artifact 修改失败时保留上一可用版本；
28. Artifact 预览运行在受限环境；
29. 手机端使用全屏 Artifact 页面；
30. 平板和横屏支持会话与 Artifact 分栏；
31. Pixel 8 真机完成键盘、停止、恢复、错误和下载验证；
32. `flutter analyze` 通过；
33. 所有新增测试通过；
34. `git diff --check` 通过；
35. 未产生与需求无关的代码修改。

---

# 二十三、开发 AI 输出格式

每完成一个阶段，开发 AI 必须按以下格式报告，不得只说“已完成”。

```text
[TARGET]
本次实现的阶段和目标。

[CODE INSPECTION]
实施前确认的现有代码结构、状态管理、持久化和关键限制。

[CHANGES]
完成的功能和行为变化。

[FILES]
新增或修改的文件及作用。

[REQUEST MAPPING]
涉及的通用字段、模型能力和厂商字段映射。

[TESTS]
执行的命令、测试数量和结果。

[DEVICE EVIDENCE]
真机验证步骤和实际观察；未进行真机验证时必须明确说明。

[KNOWN GAPS]
尚未覆盖的能力、未验证的真实接口或风险。

[NEXT]
下一阶段应执行的具体工作。
```

开发 AI 不得：

* 在没有代码证据时声称功能已经存在；
* 在没有运行测试时声称测试通过；
* 在没有真机操作时声称真机验证完成；
* 以 UI 已显示为依据，声称服务端请求一定正确；
* 使用真实计费请求代替 mock 测试；
* 为了快速通过编译而删除现有测试；
* 用通用 `extra` 继续绕过 provider adapter；
* 隐藏未完成部分或已知风险。
