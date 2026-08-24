# SimiChat 移动端模型任务联动与 HTML / Markdown Artifact 工作台完整需求

> **用途**：直接交给 Codex，在现有 SimiChat 代码仓库上完成开发。
> **约束**：这是一个完整目标，不按阶段拆分；不得只制作静态 Demo、效果图或独立新项目。
> **设计基准**：延续当前 SimiChat 的薄荷绿主题、圆角、轻量边框和移动端布局，在现有 UI 上做二次设计。

---

## 1. 最终目标

SimiChat 需要形成一套统一、可扩展的移动端 AI 工作界面：

1. 用户在同一个会话中可以切换聊天、图片、视频、语音合成、声音设计、声音克隆、语音识别和未来音乐等任务。
2. 用户选择任何模型后，**顶部模型名称、当前任务类型、输入表单、可用工具、默认参数和实际请求模型必须同步改变**。
3. 模型切换反馈必须克制，不得向会话中插入显眼的“已切换模型”消息。
4. 模型不支持的能力直接隐藏，包括深入思考、联网搜索、附件、参考图、特定分辨率、特定格式等。
5. AI 生成的 HTML 和 Markdown 不再以大段源码占满移动端聊天页面，而是以 Artifact 成果卡片展示。
6. 点击成果卡片后，进入独立的全屏工作台，支持：
   - HTML 真实效果预览、可视化编辑和源码编辑；
   - Markdown 阅读效果、块级可视化编辑和源码编辑；
   - 保存、版本、下载、AI 定向修改。
7. 所有生成结果继续归属于当前会话，历史会话重新打开后可以恢复模型、任务、成果文件及结果卡片。

最终体验应是：

> **用户选择模型即进入对应任务；生成文件即获得可查看、可编辑、可保存的成果，而不是面对散乱模型列表、明显的状态消息或铺满屏幕的源码。**

---

## 2. 目标 UI 设计图

### 2.1 模型与任务联动

![SimiChat 模型与任务联动 UI](assets/ui_model_task_linkage.png)

该图表达的核心不是重新设计整个 App，而是修复当前状态割裂：

- 顶部仍保留现有会话标题和模型胶囊；
- 模型选择面板按任务分类；
- 选择音频、图片或视频模型后，顶部立即显示新模型；
- 主内容输入区同步切换成相应任务表单；
- 切换提示仅为短暂轻提示，不进入聊天消息时间线。

### 2.2 HTML / Markdown Artifact 移动端工作台

![SimiChat HTML Markdown Artifact 移动端 UI](assets/ui_artifact_mobile.png)

该图表达的核心是：

- 聊天中只展示紧凑的成果文件卡片；
- HTML 默认打开真实运行效果；
- 源码进入独立全屏编辑模式；
- Markdown 使用阅读视图和块级编辑；
- 查看、编辑、源码三种模式不与聊天正文混在一起。

---

## 3. 当前问题与必须修复的结果

### 3.1 顶部模型与实际选择未联动

当前模型下拉列表中已经包含：

- `mimo-v2.5-asr`
- `mimo-v2.5-tts`
- `mimo-v2.5-tts-voiceclone`
- `mimo-v2.5-tts-voicedesign`
- 图片、视频和其他文本模型

但点击音频模型后，顶部仍可能停留在原来的 `gpt-5.3-codex-spark`，任务输入区也没有切换。

必须改成：

- 选中模型项后，顶部模型胶囊立即显示该模型；
- 当前任务类型根据模型能力自动切换；
- 动态输入区立即重新渲染；
- 后端请求中的 `model` 与顶部显示完全一致；
- 当前选中项、模型状态、任务状态和请求状态不得分别维护为互不一致的多份状态。

### 3.2 模型切换消息过于显眼

禁止以下行为：

- 在聊天时间线插入大块“已切换到某模型”的系统消息；
- 用与 AI 正文相同尺寸的卡片提示模型切换；
- 将模型切换提示保存进历史消息；
- 因为切换模型而打断用户阅读位置。

正确反馈层级：

1. **主要反馈**：顶部模型胶囊文字和图标立即更新。
2. **次要反馈**：输入区自动变成新任务表单，用户自然感知已切换。
3. **可选轻提示**：只有任务类型发生变化时，显示约 1.2–1.5 秒的单行浮层，例如：

   ```text
   已切换到语音合成 · mimo-v2.5-tts
   ```

4. 轻提示不得：
   - 写入消息数组；
   - 持久化；
   - 占用会话布局高度；
   - 阻断点击；
   - 重复叠加。
5. 同一任务内仅切换模型时，默认不显示轻提示，只更新顶部模型。

### 3.3 移动端 HTML 展示方式错误

当前移动端把完整 HTML 源码直接作为聊天回复展示，导致：

- 数百行代码占满页面；
- 用户需要长距离滚动；
- 代码横向被裁切；
- 普通用户无法理解；
- 真实网页效果与源码混在聊天区；
- 底部输入框和页面阅读被严重干扰。

必须改成：

- 完整 HTML、Markdown 成果默认抽取为 Artifact 文件；
- 会话正文只保留简短说明和成果卡片；
- 不自动展开完整源码；
- 点击“查看效果”进入独立全屏工作台；
- HTML 默认展示真实运行效果；
- Markdown 默认展示排版后的阅读效果；
- 用户主动点击“源码”后才显示源文件。

### 3.4 导航、模型管理和设置入口关系不清晰

当前侧边栏顶部大量使用无文字图标，模型、渠道、设置和会话入口之间的关系不够明确。

二次设计后应做到：

- 会话抽屉主要负责会话历史、搜索和新建会话；
- 顶部模型胶囊负责当前模型切换；
- 模型选择面板提供“管理模型”入口；
- 设置页统一管理模型渠道、外观、上下文、文件与数据；
- 不在会话抽屉中同时堆叠多个含义不明的图标入口。

---

## 4. 整体信息架构

移动端主界面保持现有结构：

```text
状态栏
顶部栏：菜单 / 会话标题 / 更多或设置
当前模型胶囊 + 当前任务标识
会话或任务工作区
动态输入区
底部安全区
```

### 4.1 当前任务类型

统一定义以下任务：

```ts
type SimiTaskType =
  | "chat"
  | "image_generation"
  | "video_generation"
  | "video_edit"
  | "video_extend"
  | "tts"
  | "voice_design"
  | "voice_clone"
  | "asr"
  | "music_generation";
```

这些任务均写入同一个会话时间线，但使用不同输入表单和结果卡片。

### 4.2 顶部栏

保留当前 UI 的基本语言，但调整职责：

- 左侧：打开会话抽屉；
- 中间：会话标题；
- 右侧：更多菜单或设置；
- 标题下方：当前模型胶囊；
- 当前模型属于非聊天任务时，在模型胶囊旁显示紧凑任务标识，例如“语音合成”“图片”“视频”；
- 不在顶部同时放置过多 `+`、刷新、设置等同权重图标。

刷新模型列表放入模型选择面板或模型管理页，不作为主页面常驻按钮。

---

## 5. 模型选择与任务联动

### 5.1 模型选择面板

点击顶部模型胶囊后，移动端打开底部抽屉，不使用超长原生下拉菜单。

面板包含：

- 搜索模型、任务或能力；
- 最近使用；
- 按任务分类的模型列表；
- 当前选中状态；
- 模型能力摘要；
- “管理模型”入口。

分类至少包括：

```text
聊天
图片
视频
语音合成
声音设计
声音克隆
语音识别
音乐
```

模型项展示：

- 显示名称；
- 模型 ID；
- 任务标签；
- 关键能力摘要；
- 当前可用状态；
- 选中标记。

不可用模型可隐藏，或明确显示不可用原因，但不能点击后看似切换成功、实际仍使用旧模型。

### 5.2 单一状态源

模型与任务必须由一份状态统一驱动，例如：

```ts
interface ActiveWorkspaceState {
  conversationId: string;
  activeModelId: string;
  activeTask: SimiTaskType;
  capabilityProfile: ModelCapabilityProfile;
  draftByTask: Partial<Record<SimiTaskType, TaskDraft>>;
  taskParameters: Record<string, unknown>;
}
```

以下位置必须读取同一个 `activeModelId`：

- 顶部模型胶囊；
- 模型选择面板选中项；
- 动态输入区；
- 请求构建器；
- 任务记录；
- 结果卡片元数据。

不得出现“顶部显示 A、表单属于 B、请求实际调用 C”的情况。

### 5.3 模型选择的原子行为

选择模型必须作为一次完整事务执行：

```ts
selectModel(modelId)
  -> load capability profile
  -> determine task type
  -> validate current draft and parameters
  -> update activeModelId
  -> update activeTask
  -> normalize supported parameters
  -> render task composer
  -> persist conversation draft state
```

用户选择 `mimo-v2.5-tts` 后，必须同时出现：

- 顶部：`mimo-v2.5-tts`；
- 任务标识：语音合成；
- 表单：朗读文本、音色、语速、输出格式；
- 请求：使用 `mimo-v2.5-tts`；
- 结果：音频结果卡片。

用户选择 `mimo-v2.5-asr` 后，必须同时出现：

- 顶部：`mimo-v2.5-asr`；
- 任务标识：语音识别；
- 表单：上传音频/视频、识别语言、输出格式；
- 请求：使用 ASR 接口参数；
- 结果：转写结果卡片。

### 5.4 多任务模型

一个模型可能同时支持多项任务。

此时：

- 模型和任务是两个独立但关联的状态；
- 选择模型后默认进入该模型的推荐任务；
- 用户可以在该模型支持的任务之间切换；
- 切换任务不必重新选择模型；
- 任务选择器只显示当前模型支持的任务。

### 5.5 草稿保护

每种任务保留独立草稿：

```ts
interface TaskDraft {
  text?: string;
  files?: UploadedAsset[];
  parameters?: Record<string, unknown>;
  updatedAt: number;
}
```

例如用户从聊天切到 TTS，再切回聊天时，原聊天输入内容仍在。

只有在以下情况才弹出确认：

- 当前已有文件或参数无法被新模型支持；
- 切换将导致明确的数据丢失；
- 用户已输入但尚未提交的重要内容无法转换。

普通参数自动归一化不弹窗，只做轻提示或静默处理。

### 5.6 切换失败

模型能力加载失败或模型不可用时：

- 不更新顶部模型；
- 不清空当前草稿；
- 保持原任务界面；
- 显示普通错误提示；
- 请求层不得使用半更新状态。

---

## 6. 模型能力驱动

前端不得通过模型名称字符串分散硬编码页面。

需要统一能力配置：

```ts
interface ModelCapabilityProfile {
  id: string;
  displayName: string;
  providerId: string;
  taskTypes: SimiTaskType[];

  reasoning?: {
    supported: boolean;
    levels?: Array<"auto" | "off" | "low" | "medium" | "high" | "xhigh">;
  };

  search?: {
    web?: boolean;
    x?: boolean;
    simultaneous?: boolean;
  };

  attachments?: {
    image?: boolean;
    file?: boolean;
    audio?: boolean;
    video?: boolean;
    mimeTypes?: string[];
    maxFiles?: number;
    maxFileSizeMB?: number;
  };

  image?: {
    referenceImage?: boolean;
    edit?: boolean;
    qualities?: string[];
    aspectRatios?: string[];
    resolutions?: string[];
    sizes?: string[];
    maxOutputs?: number;
    customSize?: boolean;
  };

  video?: {
    operations?: Array<"generate" | "edit" | "extend">;
    firstFrame?: boolean;
    lastFrame?: boolean;
    referenceImage?: boolean;
    referenceAudio?: boolean;
    durations?: number[];
    aspectRatios?: string[];
    resolutions?: string[];
  };

  tts?: {
    voices?: string[];
    languages?: string[];
    speeds?: number[];
    formats?: string[];
  };

  voiceDesign?: {
    formats?: string[];
  };

  voiceClone?: {
    referenceMimeTypes?: string[];
    formats?: string[];
  };

  asr?: {
    languages?: string[];
    outputFormats?: string[];
    timestamps?: boolean;
    diarization?: boolean;
    punctuation?: boolean;
  };

  music?: {
    durations?: number[];
    styles?: string[];
    vocalModes?: string[];
    formats?: string[];
  };
}
```

后端暂时没有完整能力字段时，可以建立集中式本地能力注册表，但必须满足：

- 所有模型能力在一个模块维护；
- 页面组件只读取能力，不判断模型名称；
- 后续可直接替换为后端配置；
- `/v1/models` 只负责发现模型时，仍需由 SimiChat 能力配置补充任务与参数信息。

---

## 7. 动态任务输入区

输入区由 `activeTask + capabilityProfile` 动态渲染。

### 7.1 聊天

显示：

- 文本输入；
- 模型选择；
- 发送和停止；
- 当前模型支持时显示附件；
- 支持推理时显示深入思考；
- 支持搜索时显示联网或 X 搜索。

不支持深入思考或联网的模型：

- 不显示对应控件；
- 不保留空位；
- 不发送相关请求参数。

### 7.2 图片生成

显示：

- 提示词；
- 参考图；
- 质量；
- 宽高比；
- 清晰度（1K / 2K / 4K）；
- 像素分辨率（width x height）；
- 生成数量；
- 自定义尺寸；
- 生成按钮。

只显示模型支持的选项和数量上限。清晰度与像素分辨率是两个独立维度：前者序列化为 `resolution`，后者序列化为 `size`，不得把 `2K` 当作 `size`。

### 7.3 视频

根据模型能力显示：

- 生成、编辑、延长；
- 提示词；
- 首帧、尾帧、参考图、参考音频；
- 时长；
- 宽高比；
- 分辨率；
- 生成按钮。

### 7.4 标准 TTS

显示：

- 朗读文本；
- 音色；
- 语言；
- 语速；
- 输出格式；
- 生成并试听。

音色较多时使用可搜索底部抽屉，不使用超长系统下拉菜单。

### 7.5 声音设计

显示：

- 朗读文本；
- 声音自然语言描述；
- 风格快捷标签；
- 语速；
- 输出格式；
- 生成并试听。

### 7.6 声音克隆

显示：

- 朗读文本；
- 参考音频上传；
- 参考音频播放、删除和重新上传；
- 语速；
- 输出格式；
- 生成并试听。

未上传参考音频时不可提交。

### 7.7 语音识别

显示：

- 上传音频或视频；
- 录音；
- 识别语言；
- 时间戳；
- 说话人区分；
- 输出格式；
- 开始识别。

### 7.8 未来音乐

显示：

- 音乐描述；
- 风格；
- 情绪；
- 时长；
- 人声模式；
- 歌词；
- 参考音频；
- 输出格式；
- 生成音乐。

没有配置音乐 API 时显示真实空状态，不伪造生成结果。

---

## 8. 会话抽屉与设置中心

### 8.1 会话抽屉

会话抽屉继续使用当前左侧覆盖式结构，但简化职责。

内容顺序：

```text
账号与当前渠道摘要
搜索会话
新建会话
会话历史
更多历史
设置
```

要求：

- 会话条目显示标题、时间和更多菜单；
- 当前会话有明确选中状态；
- 搜索同时支持标题和会话内容；
- MCP、Skills 等入口如保留，应使用有文字说明的卡片或独立工具区；
- 不用一排无文字图标承担文件、MCP、Skills、设置等多个重要入口；
- 设置入口固定在抽屉底部或清晰的工具区。

### 8.2 设置中心

设置页统一包含：

- 账号与套餐；
- 模型渠道；
- 当前默认渠道；
- 模型和能力配置；
- 外观与字体；
- 上下文与记忆；
- 文件和 Artifact 数据；
- 数据、档案与导出；
- 隐私和安全；
- 关于 SimiChat。

当前模型选择面板中的“管理模型”直接打开设置中心的“模型与渠道”页面。

---

## 9. Artifact 成果卡片

### 9.1 触发条件

以下内容应创建 Artifact：

- AI 明确生成的完整 HTML；
- AI 明确生成的 Markdown 文件；
- 用户上传的 `.html`、`.htm`、`.md`、`.markdown`；
- 用户要求保存为文件的完整结果。

不要把所有零散代码都强制转为 Artifact。无法可靠判断时，可提供“作为 HTML / Markdown 打开”的操作。

### 9.2 会话内卡片

HTML 卡片显示：

```text
文件名
HTML · 文件大小 · 可交互预览
查看效果
源码 / 下载 / 更多
```

Markdown 卡片显示：

```text
文件名
Markdown · 文件大小
查看效果
编辑 / 下载 / 更多
```

会话内不得默认显示完整源文件。

### 9.3 消息数据

AI 消息可包含文本摘要和 Artifact 引用：

```ts
interface ArtifactMessagePart {
  type: "artifact";
  artifactId: string;
  artifactType: "html" | "markdown";
  name: string;
  size?: number;
  currentVersionId: string;
}
```

历史会话必须能恢复卡片和文件状态。

---

## 10. 移动端 Artifact 工作台

点击成果卡片后进入独立全屏页面，不在聊天页面内展开源码。

### 10.1 顶部栏

包含：

- 返回；
- 文件名；
- 保存状态；
- 更多菜单。

更多菜单包含：

- 重命名；
- 版本历史；
- 另存为；
- 下载；
- 删除。

### 10.2 模式切换

HTML 和 Markdown 均提供：

```text
查看效果
可视化编辑
源码
```

模式切换固定在顶部栏下方，不放在页面最底部，避免与系统手势和键盘冲突。

### 10.3 打开规则

- 点击“查看效果”直接进入查看效果；
- 点击卡片中的“源码”直接进入源码；
- 关闭工作台后回到原会话和原滚动位置；
- 工作台是路由级或全屏 Overlay，不是聊天消息内部展开区域。

---

## 11. HTML 查看效果

### 11.1 真实运行

HTML 必须在安全 iframe 或等效沙箱中运行，而不是转为截图。

支持：

- HTML 和内嵌 CSS；
- CSS 动画；
- SVG；
- Canvas；
- 基础 JavaScript 交互；
- 音视频；
- 触摸、鼠标和键盘事件；
- 响应式布局。

### 11.2 移动端适配

默认行为：

- 使用当前手机宽度作为预览 viewport；
- 自动适应工作台可用宽度；
- 页面高度在 iframe 内滚动；
- 不把整个桌面网页缩成一张过小图片；
- 不让主应用页面与 iframe 同时横向滚动；
- 不直接裁切网页右侧内容。

工具栏提供：

```text
适应宽度
原始尺寸
手机 / 平板 / 桌面
缩放
刷新
全屏
```

对于固定宽度网页：

- 默认“适应宽度”；
- 用户可切到“原始尺寸”并在 iframe 内横向滚动；
- 支持双指缩放或明确缩放控件；
- 缩放只改变预览，不修改 HTML 源码。

### 11.3 安全要求

HTML 不得直接插入 SimiChat 主页面 DOM。

默认安全策略：

- 隔离 Cookie、LocalStorage、API Key 和主页面 DOM；
- 禁止顶层跳转；
- 禁止自动弹窗；
- 禁止未经用户确认的下载；
- 外部网络资源受控；
- 父页面与 iframe 只通过校验后的 `postMessage` 通信。

支持“安全模式”和“交互模式”，但即使交互模式也不能获得 SimiChat 主页面权限。

---

## 12. Markdown 查看效果

Markdown 默认进入阅读模式，支持 GitHub Flavored Markdown：

- 标题；
- 段落；
- 粗体、斜体、删除线；
- 有序和无序列表；
- 任务列表；
- 引用；
- 表格；
- 链接和图片；
- 行内代码与代码块；
- 代码高亮和复制；
- 分割线；
- 脚注。

移动端阅读要求：

- 内容宽度等于可用屏幕宽度；
- 正文有合理左右留白；
- 表格可在表格容器内横向滚动，不使整个页面横向溢出；
- 代码块独立横向滚动；
- 图片最大宽度为容器宽度；
- 标题、正文和代码字号适合移动端阅读。

Markdown 中的危险 HTML 需要清洗后再渲染。

---

## 13. 可视化编辑

### 13.1 HTML

进入可视化编辑后：

- 悬停或触摸选中元素；
- 选中元素显示边框和元素类型；
- 双击文字直接编辑；
- 长按打开元素操作菜单；
- 移动端属性使用底部抽屉。

支持修改：

- 文字；
- 字体、字号、字重、颜色、行高、对齐；
- 背景；
- 边框、圆角、阴影；
- 间距和尺寸；
- 图片替换和裁剪；
- 图标替换、颜色和大小；
- 链接地址和打开方式；
- 复制、隐藏、删除、前移和后移。

第一版完整目标中不要求任意 PPT 式绝对拖动，但必须支持安全的同级排序和基础尺寸调整，避免破坏响应式布局。

### 13.2 Markdown

Markdown 可视化编辑采用文档块模型：

- 标题；
- 段落；
- 引用；
- 列表；
- 任务项；
- 表格；
- 图片；
- 代码块；
- 分割线。

支持：

- 直接编辑内容；
- 切换块类型；
- 上移、下移、复制、删除；
- 表格增删行列；
- 图片替换；
- 让 AI 改写当前块。

---

## 14. 源码模式

源码必须是独立全屏编辑模式，不是聊天中的普通代码块。

HTML 和 Markdown 均支持：

- 行号；
- 语法高亮；
- 查找和替换；
- 撤销和重做；
- 格式化；
- 错误提示；
- 保存状态；
- 自动保存草稿；
- 跳转到选中元素或块。

移动端要求：

- 默认开启视觉自动换行，且不修改真实源码；
- 可切换“不换行 + 编辑器内横向滚动”；
- 页面本身不得横向溢出；
- 键盘弹出后，顶部模式栏和保存入口仍可使用；
- 输入区不得被底部系统安全区遮挡。

源码有语法错误时：

- 保留用户源码；
- 显示错误位置；
- 查看效果继续保留最近一次成功渲染版本；
- 不自动覆盖或丢弃用户修改。

---

## 15. AI 定向修改

用户可选中 HTML 元素或 Markdown 块后输入自然语言：

```text
把这个标题改成金色
把这张图片换成夜晚城市
将这一段压缩到 80 字
优化这个区域的手机端布局
```

AI 应返回结构化 Patch，而不是默认重写整个文件：

```ts
type ArtifactPatch =
  | { type: "setText"; nodeId: string; value: string }
  | { type: "setAttribute"; nodeId: string; name: string; value: string }
  | { type: "setStyle"; nodeId: string; property: string; value: string }
  | { type: "replaceAsset"; nodeId: string; assetId: string }
  | { type: "moveNode"; nodeId: string; targetNodeId: string; position: string }
  | { type: "deleteNode"; nodeId: string }
  | { type: "replaceMarkdownBlock"; nodeId: string; markdown: string };
```

应用前显示简短修改摘要。应用后必须可撤销。

全局修改整个文件时，应创建可恢复版本，并给出修改摘要。

---

## 16. Artifact 保存、版本和下载

每个 Artifact 支持：

- 自动保存草稿；
- 保存当前版本；
- 另存为新版本；
- 版本历史；
- 恢复版本；
- 下载当前文件；
- Markdown 导出 HTML；
- 后续多资源 HTML 导出 ZIP。

数据结构建议：

```ts
type ArtifactType = "html" | "markdown";

interface Artifact {
  id: string;
  conversationId: string;
  type: ArtifactType;
  name: string;
  mimeType: string;
  currentVersionId: string;
  draftSource?: string;
  previewConfig: {
    device: "responsive" | "desktop" | "tablet" | "mobile";
    zoom: number;
    width?: number;
    height?: number;
    allowScripts?: boolean;
    allowExternalResources?: boolean;
  };
  createdAt: string;
  updatedAt: string;
}

interface ArtifactVersion {
  id: string;
  artifactId: string;
  versionNumber: number;
  source: string;
  sourceHash: string;
  changeType: "initial" | "visual_edit" | "source_edit" | "ai_edit" | "upload" | "restore";
  changeSummary?: string;
  createdAt: string;
}
```

浏览器不支持覆盖原本地文件时，应客观显示“下载替换文件”，不得承诺无授权直接覆盖本地文件。

---

## 17. 统一会话结果卡片

所有任务结果均写入当前会话，采用统一卡片语言：

- 文本：文本消息；
- 图片：图片网格卡片；
- 视频：播放器卡片；
- TTS、声音设计、声音克隆、音乐：音频播放器卡片；
- ASR：转写文本卡片；
- HTML / Markdown：Artifact 文件卡片。

每个结果记录：

- 任务类型；
- 模型 ID；
- 参数；
- 状态；
- 创建时间；
- 输出文件；
- 错误信息。

切换模型不会修改历史消息使用的模型元数据，只影响下一次任务草稿和请求。

---

## 18. 接口与请求层要求

前端页面不得直接针对各供应商拼装不同请求。

建立 Provider Adapter：

```ts
interface ProviderAdapter {
  chat?: (request: ChatRequest) => Promise<ChatResult>;
  imageGenerate?: (request: ImageRequest) => Promise<ImageResult>;
  videoGenerate?: (request: VideoRequest) => Promise<VideoResult>;
  videoEdit?: (request: VideoEditRequest) => Promise<VideoResult>;
  videoExtend?: (request: VideoExtendRequest) => Promise<VideoResult>;
  textToSpeech?: (request: TtsRequest) => Promise<AudioResult>;
  voiceDesign?: (request: VoiceDesignRequest) => Promise<AudioResult>;
  voiceClone?: (request: VoiceCloneRequest) => Promise<AudioResult>;
  speechToText?: (request: AsrRequest) => Promise<TranscriptResult>;
  musicGenerate?: (request: MusicRequest) => Promise<AudioResult>;
}
```

要求：

- 复用现有 Base URL、API Key、渠道和协议配置；
- API Key 不得进入前端日志、Artifact 或错误提示；
- `activeModelId` 是请求模型的唯一来源；
- 请求前再次按能力配置清理不支持参数；
- 流式聊天支持停止；
- 文件上传支持进度和取消；
- 生成失败支持重试；
- 任务切换不会导致旧请求误写入当前新任务界面。

---

## 19. 移动端视觉与交互要求

重点适配：

```text
360px
375px
390px
414px
430px
```

必须满足：

- 无页面级横向滚动；
- 触控按钮有足够点击面积；
- 底部输入区避开安全区；
- 软键盘不遮挡发送、保存和主要字段；
- 模型面板、音色面板和参数面板使用底部抽屉；
- 抽屉支持下滑关闭、遮罩关闭和系统返回键；
- HTML iframe、代码块、Markdown 表格内部可以独立滚动；
- 主页面滚动与内部滚动边界清晰；
- 当前薄荷绿主题继续使用，不改成完全不同的品牌风格；
- 深色模式沿用现有主题系统。

---

## 20. 验收标准

### 20.1 模型切换

- 选择 `mimo-v2.5-tts` 后，顶部立即显示该模型。
- 页面立即切换为 TTS 输入界面。
- 实际请求的 `model` 为该模型。
- 选择 ASR、图片、视频、声音设计或声音克隆模型时同样成立。
- 不再出现顶部停留在旧模型的情况。

### 20.2 切换反馈

- 会话中没有大型“模型已切换”消息。
- 切换模型不改变会话滚动位置。
- 同任务切换仅更新模型胶囊。
- 跨任务切换最多显示短暂轻提示。
- 轻提示不进入历史消息和数据库消息记录。

### 20.3 能力显示

- 不支持深入思考的模型不显示深入思考。
- 不支持联网的模型不显示联网入口。
- 不支持附件的模型不显示附件按钮。
- 不支持的参数不显示，也不发送到接口。

### 20.4 HTML 移动端

- 会话中只显示 HTML 成果卡片，不铺开数百行代码。
- 点击“查看效果”进入全屏工作台。
- 默认显示真实 HTML 运行效果。
- 页面自动适应手机宽度，无主页面横向溢出。
- 可以切换适应宽度、原始尺寸、刷新和全屏。
- 源码只在源码模式显示。
- 源码模式支持换行或编辑器内部横向滚动。

### 20.5 Markdown 移动端

- Markdown 默认显示排版后的阅读效果。
- 标题、列表、表格、代码块和图片正确渲染。
- 表格和代码块不会撑破整个页面。
- 可切换可视化编辑和源码。

### 20.6 编辑和保存

- HTML 文字、颜色、图片、图标和链接可以编辑。
- Markdown 块可以编辑、排序和转换。
- 源码修改可以更新预览。
- 自动保存草稿可用。
- 支持正式版本、版本恢复和下载。
- AI 定向修改可以预览、应用和撤销。

### 20.7 工程约束

- 直接修改现有 SimiChat 项目，不建立脱离主项目的独立 Demo。
- 不根据模型名称在多个页面散落硬编码。
- 不把不可信 HTML 直接插入主页面 DOM。
- 不暴露完整 API Key。
- 不因实现 Artifact 破坏现有聊天、会话和渠道配置。
- 类型检查、Lint、测试和生产构建通过。

---

## 21. Codex 最终交付说明

Codex 应直接完成代码，并在结束时说明：

- 实际修改的文件；
- 新增的核心组件和状态模块；
- 模型能力配置来源；
- 模型与任务原子切换的实现；
- 模型切换轻反馈的实现；
- HTML / Markdown Artifact 数据结构；
- HTML 沙箱和移动端适配方案；
- 已接入的真实接口；
- 尚未配置接口但已完成适配结构的任务；
- 测试、类型检查和构建结果；
- 当前已知限制。

不得只给出计划、伪代码或页面截图。
