# 移动端一级多模态模式导航

## 历史实现（2026-08-21）

> 该版本的一级模式条与常驻工作区已在 2026-08-22 收敛为统一 Composer；以下内容保留
> 作为迁移记录，不代表当前主界面仍显示四个独立工作区。

移动端与桌面聊天外壳新增统一的一级模式切换：`聊天`、`图片`、`视频`、`语音`。
模式状态由 `creationModeProvider` 管理，`CreationModeSwitcher` 只负责导航状态，
不通过模型名称判断能力。

`ChatPage` 根据当前模式在会话时间线前显示对应的轻量工作区：

- 图片：提示词、参考图 / 质量 / 比例 / 分辨率 / 数量摘要和生成入口；
- 视频：提示词、首帧 / 多参考图 / 参考音频 / 时长 / 比例 / 分辨率摘要和一次性 typed 参数面板；
- 语音：按已配置的 TTS / STT / 音乐能力显示合成、识别、音乐入口；未声明的入口隐藏；
- 聊天：保持现有消息时间线与 Composer，不改变发送、停止、重试和会话持久化。

非聊天模式下 Composer 的主发送动作也跟随当前模式：图片进入图片任务面板，视频
走视频生成任务，语音优先进入已配置的 TTS（无 TTS 时才使用已声明的音乐能力），
不会把创作提示词静默发送为普通聊天消息。语音识别会读取当前会话 Composer 的音频
草稿；没有音频时给出添加音频的操作提示。

图片与视频入口继续调用现有 typed 任务面板，语音入口继续调用现有 TTS / STT /
音乐服务，任务结果仍写入当前会话时间线。没有可用模型时显示去设置空状态，不伪造
生成结果。

## 最终 PRD 联动补充（2026-08-21）

依据 `docs/SimiChat_移动端模型联动与Artifact工作台_PRD.md`，顶部模型胶囊现在
使用 `activeCreationModelIdProvider` 作为非聊天工作区的选中模型源：

- 窄屏保留紧凑 PopupMenu 降级；常规移动端打开可搜索的底部模型抽屉；
- 抽屉按渠道和能力展示模型，包含当前选中标记和“管理模型”入口；
- 点击图片 / 视频 / 语音模型会原子更新工作区模型、任务类型和对应工具配置，
  不改写会话的聊天默认模型；点击聊天模型仍只更新会话默认模型；
- 语音模型支持 `tts` / `asr` / `voice_design` / `voice_clone` 等显式能力标签，
  旧的 `audio` 元数据保留 TTS 兼容回退；顶部任务标识显示“语音合成 / 语音识别 /
  声音设计 / 声音克隆 / 音乐”。

模型切换在顶部使用短时 SnackBar 反馈，不再由移动端顶部选择器写入
`model_switch` 系统消息或聊天 Markdown 档案；历史消息中的既有模型元数据不会被
重写。

### Artifact 成果卡片与工作台

`HtmlArtifactCard` 已改为紧凑文件卡片：聊天中不再展开完整 HTML 源码，显示文件名、
类型、大小、“查看效果 / 源码 / 编辑 / 下载”入口。完整 HTML（含未 fenced 的文档）
和显式 `markdown` fenced 内容分别进入 `ArtifactWorkbenchPage`，工作台提供：

- HTML WebView 真实预览（独立页面、适应宽度 / 手机 / 刷新工具、阻止顶层外部跳转）；
- Markdown 阅读视图；
- HTML / Markdown 源码全屏编辑、自动换行切换和本地草稿保存状态；
- 可视化编辑入口、下载到应用私有 `artifact_exports` 目录。

版本历史、跨会话 Artifact DAO、AI 结构化 Patch 和多资源 ZIP 仍按最终 PRD 标记为
后续接入项，当前不会伪造已保存的远端版本。

### 任务参数动态化补充（2026-08-21）

- 视频任务面板现在从当前视频模型的集中 `MediaRequestProviderProfile` 读取时长、比例、分辨率、首帧图、参考图数量和参考音频能力；未声明的字段不显示，默认值从支持列表中选择，避免 Sora / xAI 等模型收到不支持的固定 `6s / 1080p` 参数。
- 语音工作区的参数摘要随二级任务切换：TTS 展示输入内容 / 音色 / 语速 / 输出格式，ASR 展示语音文件 / 识别语言，音乐展示风格 / 情绪 / 时长 / 人声模式，声音设计展示声音风格，声音克隆展示参考音频；不再用一组跨任务的“音色 / 风格”固定摘要误导用户。
- 新增 `ModelCapability.voiceCapabilityForModel()` 作为旧 `audio` 元数据的唯一兼容解析点。显式 `tts` / `asr` / `voice_design` / `voice_clone` / `music` 优先；旧 `mimo-v2.5-asr` 等音频模型的任务推断集中在能力注册表内，顶部胶囊、工作区和配置动作共享同一结论。

## 验证

- `flutter --no-version-check analyze --no-pub`
- `flutter --no-version-check test --no-pub --no-test-assets test/creation_mode_switcher_test.dart`
- 移动端聊天 / 模型选择 / 主流程 smoke 聚焦测试通过。
- Artifact 卡片、完整 HTML 抽取、Markdown 工作台和模型任务联动聚焦测试通过。
- 最终串行全量测试：`1185` 项可见 / `204` 项隐藏，`0` errors，`1389` success，`0` fail。
- Pixel 8 `37101FDJH0077P` 最终 Production Release：`ANDROID_RELEASE_PARITY status=verified`；APK / 设备 hash `14a4a1958cffc2193f91ff1adf1d883034404cf6733d3a6e1e967e0187e52322`；语音模式 UI Automator 已确认 `mimo-v2.5-asr + 语音识别`、ASR 参数摘要和可搜索模型底部抽屉。

## 当前交互（2026-08-22）

- AppBar 仅保留会话标题和当前聊天模型，不再显示 `聊天 / 图片 / 视频 / 语音` 一级切换条。
- `ChatPage` 不再在消息列表上方插入图片、视频或语音常驻工作区；普通文字、图片、
  视频和音频均从同一个底部 `ChatInputBar` 输入 / 附件条发送。
- `+` 菜单是媒体能力入口。选择“生成图片 / 生成视频 / 声音合成 / 识别语音”等动作
  后才打开对应 bottom sheet；任务 sheet 仍按设置中绑定的能力模型展示参数，图片模型
  过滤为图片能力模型。
- `creationModeProvider` 和 `CreationModeSwitcher` 测试组件暂时保留给旧 deep-link /
  兼容测试，不再参与生产聊天页渲染或发送路由。
