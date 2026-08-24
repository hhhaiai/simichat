# Android 多模态工具与 Artifact 功能需求

> **状态**：此短版需求已被 2026-08-19 的执行型 PRD 扩展；阶段、超长内容、三态能力和 Artifact 边界以 `docs/android-multimodal-long-content-artifact-prd.md` 为准。本文件保留此前交互与六项工具字段的补充说明。
> **最后更新**：2026-08-19。
> **适用范围**：Android 优先，Flutter 共享代码；平板与桌面布局仅在移动端主链路稳定后扩展。
> **关联文档**：[执行型 PRD](android-multimodal-long-content-artifact-prd.md)、[需求补充规格](android-multimodal-long-content-artifact-requirements-refinement.md)、[ChatGPT 风格交互基准](chatgpt-interaction-reference.md)、[多模态 Composer 现状](chat-composer-multimodal.md)、[产品需求总纲](requirements.md)。

## 1. 目标与边界

在**不改变普通聊天发送、流式回复、附件归档和现有会话数据语义**的前提下，把图片、语音、视频和可运行成果收敛到 SimiAIChat 的单一 Composer 交互中：

- 所有工具均从输入框左侧的 `+` 进入；
- 每一种能力使用独立的“本次任务面板”，本次参数不会悄悄覆盖设置页默认值；
- 设置页只保存厂商、Base URL、加密 API Key、默认模型、默认参数和明确授权后的本地偏好；
- 所有成功结果写回发起时的当前会话；失败、取消和后台恢复保留可解释的任务状态；
- 网页、完整代码项目和独立文件使用 Artifact 承载，支持预览、源码、下载、编辑和版本恢复；
- 交互参考 ChatGPT 的信息架构、状态转换和操作层级，不复用其品牌、图标、文案、视觉资源、会话标题或数据。

本需求不承诺某一远端模型一定支持某个参数。模型可用性以保存的渠道、模型能力描述和请求前实时校验为准；未声明能力的自定义模型必须保守隐藏高级字段或显示具体禁用原因，不能把推测的字段发送到上游。

## 2. 聊天页交互框架

### 2.1 顶栏

聊天页统一为：

```text
[菜单]                    [聊天 | 工作]                    [更多]
```

| 区域 | 规则 |
| --- | --- |
| 菜单 | 打开左侧会话抽屉；抽屉负责一级导航、搜索、置顶、最近、设置和新建聊天。 |
| 聊天 | 展示普通消息、附件、生成结果和 Artifact 卡片。 |
| 工作 | 展示当前会话绑定任务的上传、排队、运行、失败、停止和重试状态；不展示模型内部隐式推理。 |
| 更多 | 按当前模式提供轻量操作；不得把新建、设置、模型、重试等所有操作挤入顶栏。 |

切换“聊天 / 工作”只切换视图：不得创建会话、清空草稿、删除附件、改变当前模型、停止音频播放或中断正在运行的任务。

### 2.2 单一 Composer

```text
静止：    [+]  询问 SimiAIChat                          [录音] [实时语音]
输入后：  [+]  输入内容                                          [发送]
任务中：  [+]  当前任务状态                                      [停止]
```

- 最右侧始终只保留一个主操作，在实时语音、发送和停止之间转换；
- 输入框自然增长至约四行，超过后内部滚动；
- 附件位于输入框上方，提供预览、删除、替换和数量提示；
- 键盘弹出时 Composer 贴合键盘安全区上沿，不能遮住最后一条消息或附件；
- 停止任务只取消传输 / 轮询和未完成结果，**不得**清空输入、附件或任务参数；
- 成功只清除该任务明确消费的文本与附件；未消费附件仍留在 Composer 草稿中。

### 2.3 `+` 工具菜单

```text
添加内容
├─ 相机
├─ 相册
└─ 选择文件

语音与编辑
├─ 实时语音
├─ 编辑图片
└─ 识别语音

生成与工具
├─ 生成图片
├─ 生成视频
├─ 语音合成
├─ 声音设计
├─ 声音克隆
├─ 生成音乐
└─ 创建 Artifact
```

每个入口都必须可见。未配置或当前模型不支持时，入口为禁用状态并说明原因（例如“尚未配置 TTS 服务”“当前视频模型不支持参考音频”），不能点击无响应，也不能仅靠隐藏入口掩盖不可用状态。

## 3. 统一任务面板与生命周期

### 3.1 面板布局与草稿

- 手机竖屏：底部抽屉；字段较多时可展开为全屏。
- 平板或横屏：优先右侧面板，避免遮挡长消息和预览内容。
- 顶部：工具名称与关闭按钮；中间：模型、输入、附件和模型允许的参数；底部：固定提交按钮。
- 关闭面板时保留未提交草稿；失败、取消或切换“聊天 / 工作”不丢失草稿。
- 切换模型后立即按能力重新计算字段、默认值与禁用说明；不再适用的参数不能静默发送。

### 3.2 统一状态

所有多模态任务和 Artifact 采用以下公共状态：

```text
draft → validating → uploading → queued → running → succeeded
                                      ↘ failed
                                      ↘ cancelled
```

| 状态 | 用户可见语义 | 规则 |
| --- | --- | --- |
| `draft` | 尚未提交 | 保留可编辑文本、附件和参数。 |
| `validating` | 正在检查参数 | 本地校验模型能力、文件存在性、格式、大小和必要授权。 |
| `uploading` | 正在上传素材 | 只显示阶段，不泄露本地绝对路径或凭据。 |
| `queued` | 正在排队 | 保存 provider job ID、轮询地址和提交时路由信息。 |
| `running` | 正在生成 / 处理 | Composer 主操作为停止。 |
| `succeeded` | 已完成 | 事务写入结果、附件和会话卡片后才可标记完成。 |
| `failed` | 失败，可重试 | 保留草稿和附件，显示脱敏错误摘要。 |
| `cancelled` | 已取消 | 取消请求 / 轮询，不插入残缺 assistant 结果。 |

应用重启后，持久化任务必须恢复真实状态；重试默认沿用原 Options，并允许用户先调整后再次提交。

## 4. 领域模型、能力与协议边界（P0）

### 4.1 六类一次性请求对象

每次提交从独立不可变请求对象生成，不使用设置页的全局模式，也不能将所有厂商参数直接塞到无约束的 `extra`：

```text
ImageGenerationOptions
- model
- prompt
- count
- referenceImages[]
- aspectRatio
- resolution
- quality

SpeechSynthesisOptions
- model
- input
- voice
- speed
- responseFormat

VoiceDesignOptions
- model
- input
- style
- speed
- responseFormat

VoiceCloneOptions
- model
- input
- referenceAudio
- speed
- responseFormat

SpeechRecognitionOptions
- model
- audioFile
- language

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

`referenceImages[]`、首帧和参考音频为不同语义字段。实现不得使用 `.firstOrNull` 或其他截断逻辑把多张参考图折叠为一张；若当前 profile 不支持对应素材，必须在提交前拒绝并说明原因。

### 4.2 统一模型能力描述

每一个可选媒体模型均关联公开、无凭据的能力描述：

```text
supportedAspectRatios
supportedResolutions
supportedQualities
supportedOutputFormats
supportedDurations
maxReferenceImages
supportsFirstFrame
supportsReferenceAudio
supportsMultipleOutputs
```

实现可补充安全的范围字段（例如图片最小 / 最大张数、允许音频 MIME、最大文件大小、语速范围），但 UI 和序列化至少必须遵守上列字段。

能力校验要求：

1. 选项为空时表示“不指定”，只在 profile 明确支持时序列化；
2. 选项非空但不在能力清单内时，在本地返回带字段名的校验错误；
3. `count > 1` 需要 `supportsMultipleOutputs`，并受模型张数范围限制；
4. `referenceImages.length` 不得超过 `maxReferenceImages`；
5. `firstFrameImage` 需要 `supportsFirstFrame`，`referenceAudio` 需要 `supportsReferenceAudio`；
6. 未声明的自定义模型默认不发送比例、分辨率、质量、时长、输出格式或参考素材字段。

### 4.3 Provider / Model profile

每个 profile 唯一负责把经过校验的 Options 转为厂商 wire 字段、端点风格和附件编码；业务层只处理 Options、持久化任务和结果，不猜测字段名。

| Profile | 已知视频字段 | 参考素材约定 | 说明 |
| --- | --- | --- | --- |
| OpenAI / Sora | profile 明确声明的时长、比例、分辨率字段 | `input_reference` 或 profile 指定字段 | 不能因路径相似推断为 xAI。 |
| xAI / Grok | `duration`、`aspect_ratio`、`resolution` | JSON data URI / profile 指定字段 | **时长必须是 `duration`，不是旧的 `seconds`。** |
| OpenAI-compatible | 仅发送该 profile 显式登记的字段 | 按 JSON / multipart profile | 中转站不等于完整 OpenAI 协议。 |
| custom async | 显式字段名与轮询模板 | 按保存的 profile | 不配置即不发送高级字段。 |

以 xAI/Grok 为例，已校验的选项必须形成：

```json
{
  "model": "grok-imagine-video-1.5",
  "prompt": "A paper airplane flying over a city",
  "duration": 8,
  "aspect_ratio": "16:9",
  "resolution": "720p"
}
```

不允许把 `seconds`、`aspectRatio` 或本地文件路径混入通用 JSON。附件必须由 profile 在请求边界转换为 multipart 或 data URI。

## 5. 六项工具验收细则

### 5.1 生成图片

面板字段顺序：**图片模型、提示词、生成数量、参考图、图片比例、分辨率、图片质量、生成按钮**。

- 模型使用能力筛选后的选择列表；自由输入只作为带“未声明能力”提示的兼容入口，不是主入口。
- 数量按模型能力显示（例如 1～10）；请求中的 `n` 必须取 `count`，不得固定为 `1`。
- 参考图支持单张或多张上传、预览、排序、替换和删除。
- 比例示例：`1:1`、`4:3`、`3:4`、`16:9`、`9:16`；分辨率示例：`1K`、`2K`、`4K`；质量示例：自动、低、中、高。实际可选项由模型 capability 决定。
- 不兼容组合在面板中禁用并说明原因；不支持的字段不得写入请求。

### 5.2 语音合成

面板字段顺序：**模型、输入内容、音色、语速、输出格式、试听或生成**。

- 输入内容是本次任务独立多行文本；音色列表同时显示名称和风格说明，支持试听样本。
- 语速默认 `1.0x`，范围和输出格式均按模型能力收敛；可用格式包括 `mp3`、`wav`、`opus`、`aac`、`flac`。
- 普通合成、声音设计和声音克隆是三个并列工具，不能再由全局 TTS 模式互斥控制。

### 5.3 声音设计

面板字段顺序：**模型、输入内容、声音风格、语速、输出格式、生成**。

声音风格为自然语言，例如“温柔自然的年轻女声，普通话标准，语气亲切，适合知识讲解。”每次任务可以调整；用户可显式保存为本地声音预设，但这不会改变当前已提交任务的历史 Options。

### 5.4 声音克隆

面板字段顺序：**模型、输入内容、参考音频、语速、输出格式、生成**。

- 参考音频支持上传、录制、试听、替换和删除；展示文件名、格式、大小和时长。
- 格式、大小和时长限制由模型 capability / profile 决定，不能在 UI 层永久写死 WAV 或 10 MB。
- 选中文件后立即校验；提交前必须取得用户对本次声音使用权的确认。
- 未取得明确授权时，不得长期保存或自动复用参考音频；成功后只清理本次消费的参考项。

### 5.5 识别语音

面板字段顺序：**识别模型、音频文件、识别语言、开始识别**。

语言始终提供：`自动检测`、`中文`、`English`。序列化规则固定：

| 面板值 | wire 字段 |
| --- | --- |
| 自动检测 | 不发送 `language` |
| 中文 | `language: "zh"` |
| English | `language: "en"` |

识别完成后在当前会话创建独立结果卡片，支持查看全文、复制、编辑、保存为 TXT / Markdown、重新识别，以及把结果作为新消息继续提问。该入口不能仅依赖“上传音频后发送消息并自动转写”的隐式路径。

### 5.6 生成视频

“手诊图”统一为**首帧图**。面板字段顺序：**视频模型、提示词、首帧图、参考图、参考音频或参考音色、时长、比例、分辨率、生成**。

- 首帧图、普通参考图和参考音频使用彼此独立的上传区域和 Options 字段。
- 普通参考图支持多张，数量受 `maxReferenceImages` 限制；参考音频支持上传、录制、试听、替换和删除。
- 时长为模型声明的离散选项，不能使用无限制正整数输入。
- 比例和分辨率的实际列表来自 capability；不支持的字段隐藏或带原因禁用。
- xAI/Grok profile 的映射必须验证 `duration` 与 `aspect_ratio`；OpenAI/Sora 和 custom profile 走各自 mapper，不能共享猜测字段。

## 6. Artifact（P3）

### 6.1 定义与创建

Artifact 承载可以独立查看、运行、编辑和下载的成果：HTML、React 页面或组件、SVG、Mermaid、Markdown、纯文本、代码文件，以及后续的数据图表 / 交互页面。普通代码回答仍显示为代码块；只有完整网页、可运行组件或独立文件才创建 Artifact。

Artifact 必须绑定会话和来源消息：

```text
Artifact
- id
- conversationId
- messageId
- title
- type
- files[]
- entryFile
- currentVersion
- versions[]
- previewStatus
- createdAt
- updatedAt

ArtifactFile
- path
- language
- content
- mimeType

ArtifactVersion
- version
- files[]
- changeSummary
- createdAt
```

会话重新打开后，必须恢复 Artifact、当前源码、预览状态和版本记录。

### 6.2 会话卡片与查看器

完成后在消息时间线显示：

```text
网页名称
HTML · 已生成
[打开]
```

卡片显示名称、类型、生成 / 更新时间、缩略图或文件图标、打开按钮，以及下载、复制、重命名、删除的更多菜单。

手机竖屏打开全屏查看器：

```text
[返回]  Artifact 名称                 [更多]

[预览] [源码]

          内容区域

[继续修改]                         [下载]
```

平板、横屏和大屏使用会话 / Artifact 分栏；不得强迫手机竖屏使用狭窄双栏。

### 6.3 预览、安全与源码

预览必须提供刷新、桌面 / 平板 / 手机三种视口、全屏、加载、空白和运行错误状态。预览运行在隔离环境，不得覆盖或控制宿主 Flutter 应用；外部链接须用户确认后才能打开，摄像头、麦克风、定位、剪贴板和文件等敏感权限默认拒绝。

源码模式支持完整源码、语法高亮、文件列表 / 多文件树、搜索、单文件 / 全部复制、编辑、保存和重新运行。编辑后提示未保存状态；运行失败定位到对应文件和错误；每次“继续修改”产生新版本，旧版本可查看 / 恢复，失败时保持上一可用版本，并允许“另存为新 Artifact”。

### 6.4 下载

- HTML、SVG、Markdown 和单个代码文件按原扩展名导出；
- React / 多文件项目打包 `.zip`；
- 导出内容必须是当前**已保存**版本；
- 文件名需净化非法字符和路径穿越片段。

## 7. 实施顺序、兼容迁移与验证

| 优先级 | 范围 | 完成判定 |
| --- | --- | --- |
| P0 | Options、capability、profile、协议 mapper、统一状态 | 六种请求对象有单元测试；图片 `n` 不固定；多参考图不截断；xAI 使用 `duration` / `aspect_ratio`；未知能力不发送高级字段。 |
| P1 | 抽屉、聊天 / 工作、Composer 状态机 | 不影响现有普通聊天；键盘安全区、发送 / 停止唯一入口和草稿保留通过 Widget 验收。 |
| P2 | 六个本次任务面板、草稿 / 持久化 / 恢复 | 六项均可从 `+` 独立完成；失败 / 取消不丢参数和附件；长任务恢复真实状态。 |
| P3 | Artifact 数据、卡片、隔离预览、源码、下载、版本 | Android 全屏查看、隔离预览、编辑重跑、失败回退、单文件和 ZIP 下载完成。 |

迁移约束：保留用户已保存的渠道、Base URL、API Key、TTS/STT 设置和旧媒体 job；旧的 `size`、`seconds` 等仅作为读取兼容输入，新的提交统一经 profile 转换；API Key、本地绝对路径、参考音频字节和未授权素材不能写入日志、Markdown、导出诊断或 Artifact 元数据。

## 8. 最终验收

1. 六项多模态能力均可从 `+` 菜单独立进入；不进入设置页即可完成一次任务。
2. 三种语音工具并列可用，不由全局 TTS 模式互斥。
3. 图片支持模型、数量、多参考图、比例、分辨率和质量，且 `n` 取本次 `count`。
4. 识别语音支持音频文件和自动 / 中文 / English；语言字段映射正确。
5. 视频支持首帧图、多参考图、参考音频、离散时长、比例和分辨率。
6. xAI/Grok 请求正确发送 `duration` 和 `aspect_ratio`；其它 profile 仅发送自身声明字段。
7. 参数按模型能力动态展示；不支持的字段不发送，失败 / 取消不丢失草稿、附件和本次参数。
8. 网页或独立成果会形成 Artifact 卡片；可预览、看源码、编辑、下载、版本恢复。
9. 单文件按原格式下载，多文件可 ZIP；预览在隔离环境中运行。
10. Pixel 8 真机完成键盘避让、后台恢复、任务停止、失败重试和下载验证，并明确记录尚未由真实云端厂商 E2E 覆盖的边界。
