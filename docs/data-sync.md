# 数据同步、导出与笔记工具集成方案

> 对应模块：M9。状态：本地导出压缩包 + 语音转写状态 / 失败脱敏导出 + 非语音附件原文件导出 / 导入 + 本地聊天核心数据库备份 / 恢复 + 非密钥配置表备份 / 恢复 + Obsidian Markdown Vault 导出 v1 + Obsidian 现有 Vault 增量同步 v1 + Obsidian 附件链接重写 v1 + Obsidian 同步冲突详情界面 v1 + Obsidian 可选覆盖冲突策略 v1 + Obsidian 原始音频附件可选同步 v1 + Obsidian 同名附件链接精确去重 v1 + Obsidian stale 文件安全清理 v1 + Obsidian stale 冲突详情解释 v1 + 移动端系统分享 + 文件级安全导入 / 恢复 + 结构化本地数据备份 / 恢复 v1 + 电脑端本地传输 v1 已落地；云同步、Notion / 语雀 / 思源笔记同步和 Obsidian 双向同步待实现。最后更新：2026-06-27。

## 1. 目标

- 数据默认保存在本机应用私有目录。
- 用户可主动生成本地数据压缩包，用于备份、迁移或系统分享。
- 用户可主动选择 SimiChat 导出包进行安全预览和恢复，默认不覆盖已有文件或已有结构化数据。
- 支持本地传输到电脑端；当前 v1 使用一次性令牌 HTTP 下载。
- 支持后续可选云备份。
- 支持 Obsidian Markdown Vault 本地导出、写入已有 Vault 的单向增量同步、附件复制 / wiki 链接重写、原始音频附件可选同步、同名附件链接精确去重、stale 文件安全清理、stale 冲突详情解释、同步冲突详情展示，以及用户显式选择的覆盖冲突策略；后续继续支持 Notion / 语雀 / 思源笔记同步和 Obsidian 双向同步。

## 2. 当前实现：本地数据导出、系统分享、安全导入与结构化备份 v1

### 2.1 用户入口

- 设置页「对话 Markdown 档案」弹窗提供「导出」按钮。
- 点击后先显示「导出本地数据」确认弹窗：
  - 明确说明会生成本地 `.tar.gz` 压缩包。
  - 明确说明不包含模型 API Key / 渠道密钥、不自动上传，分享前需确认目标应用可信。
  - 当前会同时导出白名单结构化本地数据：Key Points、Dreaming 报告与调度、用户画像与控制记录、外观 / 上下文 / 本地语义搜索开关、系统提示词。
  - 当前会导出 SQLite 附件表中仍可访问的非语音附件原文件，统一放入压缩包 `attachments/`，压缩包路径会脱敏和净化。
  - 当前会导出本地数据库快照 `structured_data/local_database.json`，覆盖 sessions / messages / attachments，并扩展到文件夹、提示词、Skills、MCP、模型渠道与渠道模型等非密钥配置；不包含模型密钥、MCP headers 或本机绝对路径。
  - 可选择是否包含原始语音文件；关闭后只导出语音转文字稿件，不导出 `audio_files/`，同时数据库快照也不恢复 audio 附件记录；非语音附件仍随包导出。语音转写稿件会明确记录 `pending` / `ready` / `empty` / `failed` 状态，失败原因已脱敏。
  - 可生成 Obsidian Markdown Vault 目录，包含会话 Markdown、语音转写 Markdown、附件、索引和 Manifest，便于复制到 Obsidian。
  - 可选择已有 Obsidian Vault 并同步到 `SimiChat/` 子目录，附件会写入 `Attachments/`，会话 Markdown 附件列表会重写为 Obsidian wiki 链接。
  - “包含原始语音文件”开关同样控制 Obsidian audio 原文件：开启时复制到 `Attachments/`，关闭时只保留 `Audio Transcripts/` 转写稿。
  - 点击「同步到 Obsidian」后先选择同步策略：默认「安全同步」会跳过用户手动修改；「覆盖冲突」需要用户显式选择，且仅覆盖普通文件差异。
  - 如果同步发现用户手动修改或非普通文件目标，会弹出冲突详情，展示 Vault 相对路径、中文原因和短 SHA；默认不覆盖。
  - 支持「仅生成压缩包」「电脑端传输」「Obsidian Vault」「同步到 Obsidian」和「生成并系统分享」。
- 当前移动端 / 桌面端会在应用文档目录下生成 `exports/` 子目录并写入压缩包。
- Android / iOS 已通过原生平台通道打开系统分享面板。
- Web 平台暂不支持本地压缩包导出。
- 尚未实现 macOS / Windows / Linux 的原生分享面板；这些平台仍可先生成本地压缩包。

### 2.2 实现文件

- `lib/core/archive/data_export_service.dart`：本地导出服务、manifest 结构、非语音附件收集 / 路径净化、自实现 ustar tar writer、gzip 压缩。
- `lib/core/media/audio_transcript_archive.dart`：语音转写 Markdown sidecar 生成与脱敏，导出 / Obsidian 同步会直接复制这些 Markdown；状态覆盖 `pending` / `ready` / `empty` / `failed`，失败说明不包含本机绝对路径、密钥、令牌或 URL。
- `lib/core/archive/structured_data_backup.dart`：SharedPreferences 白名单结构化数据导出 / 恢复服务，只处理允许键，不读取模型渠道密钥。
- `lib/core/archive/local_database_snapshot.dart`：本地数据库快照导出 / 预览 / 恢复服务，覆盖 sessions / messages / attachments / folders / prompts / skills / mcp_servers / model_channels / channel_models；模型渠道密钥与 MCP headers 不导出，恢复后的模型渠道与 MCP 默认禁用。
- `lib/core/archive/archive_attachment_path.dart`：附件归档相对路径净化工具。
- `lib/core/archive/data_export_share_service.dart`：Dart 侧系统分享服务，限制只分享 `simichat-export-*.tar.gz`。
- `lib/core/archive/local_transfer_server.dart`：电脑端本地传输服务，使用临时 `HttpServer`、一次性随机令牌、过期时间和单次下载限制。
- `lib/core/archive/obsidian_vault_export_service.dart`：Obsidian Markdown Vault 导出 / 现有 Vault 增量同步服务，复制会话 / 语音转写 Markdown、可安全读取的附件，并按开关决定是否复制 audio 原文件，生成 `README.md`、`SimiChat-Index.md`、`SimiChat-Manifest.md`、`SimiChat-Sync-State.json`，把会话 Markdown 附件列表重写为 Obsidian wiki 链接，同一消息同名附件按出现顺序分别链接，安全清理源端已删除且目标未被用户改动的 stale 文件，并为同步冲突提供可解释原因。
- `lib/features/settings/settings_page.dart`：设置页导出确认弹窗、本地生成 / 系统分享 / Obsidian 同步入口、Obsidian 同步策略弹窗、同步结果提示和冲突详情弹窗；冲突详情会解释 `target_modified`、`unsafe_existing_entity`、`source_removed_target_modified`、`stale_unsafe_existing_entity` 等原因。
- `lib/core/archive/data_import_service.dart`：本地导入服务，支持预览、manifest 校验、SHA-256 校验、路径安全校验、`attachments/` 导入白名单和冲突跳过。
- `android/app/src/main/kotlin/com/aichat/ai_chat_app/MainActivity.kt`：Android `MethodChannel` + `ACTION_SEND` 分享。
- `android/app/src/main/res/xml/simichat_file_paths.xml`：Android `FileProvider` 路径白名单，不使用 `<root-path>`。
- `android/app/src/main/AndroidManifest.xml`：声明不可导出的 `FileProvider`，只授予临时读权限。
- `ios/Runner/AppDelegate.swift`：iOS `MethodChannel` + `UIActivityViewController` 分享。
- `test/core/data_export_service_test.dart`：导出包内容、manifest、排除旧导出包、排除原始音频选项、结构化快照入包、非语音附件原文件导出、聊天核心数据库快照、非密钥配置表快照、密钥 / headers / 路径脱敏测试。
- `test/core/structured_data_backup_test.dart`：结构化白名单导出、空白名单跳过、默认不覆盖恢复、覆盖恢复、格式错误测试。
- `test/core/data_export_share_service_test.dart`：Dart 分享服务参数、文件名限制、缺失文件拦截测试。
- `test/core/local_transfer_server_test.dart`：电脑端本地传输下载、错误令牌、过期、非法路径 / 方法、文件名限制测试。
- `test/core/data_import_service_test.dart`：导入预览、恢复、附件文件恢复、聊天核心数据库快照恢复、非密钥配置表恢复、冲突跳过、checksum 失败、路径穿越、缺失 manifest 测试。
- `test/core/obsidian_vault_export_service_test.dart`：Obsidian Vault 导出内容、增量同步、附件复制 / wiki 链接重写、同名附件按出现顺序分别链接、stale 文件安全删除 / 目标修改保护、audio 附件默认跳过与显式包含、索引、manifest、空 vault 和绝对路径脱敏测试。
- `test/core/data_export_share_platform_test.dart`：Android / iOS 分享通道安全配置静态测试。
- `test/benchmark/data_export_benchmark.dart`：导出性能基线。
- `test/benchmark/data_import_benchmark.dart`：导入性能基线。
- `test/benchmark/local_transfer_benchmark.dart`：电脑端本地传输 1 MB 下载性能基线。
- `test/benchmark/obsidian_vault_export_benchmark.dart`：Obsidian Vault 导出 200 个 Markdown 文件性能基线。
- `test/benchmark/obsidian_vault_sync_benchmark.dart`：Obsidian 现有 Vault 增量同步 200 个 Markdown + 200 个非语音附件性能基线。
- `scripts/benchmark_data_export.sh`：导出性能脚本入口。
- `scripts/benchmark_data_import.sh`：导入性能脚本入口。
- `scripts/benchmark_local_transfer.sh`：电脑端本地传输性能脚本入口。
- `scripts/benchmark_obsidian_vault_export.sh`：Obsidian Vault 导出性能脚本入口。
- `scripts/benchmark_obsidian_vault_sync.sh`：Obsidian 现有 Vault 增量同步性能脚本入口。

### 2.3 导出格式

当前 v1 输出 `.tar.gz`，不是 `.zip`。

```text
应用文档目录/
└── exports/
    └── simichat-export-YYYYMMDD-HHMMSS.tar.gz
```

压缩包内容：

```text
simichat-export-YYYYMMDD-HHMMSS.tar.gz
├── manifest.json
├── conversations/
├── audio_transcripts/
├── audio_files/            # 默认包含，可在导出确认弹窗关闭
├── attachments/            # 非语音附件原文件，按 message-id / attachment-id 归档
└── structured_data/
    ├── shared_preferences.json
    └── local_database.json
```

`manifest.json` 关键字段：

- `export_format: simichat.data_export.v1`
- `created_at`
- `file_count`
- `uncompressed_bytes`
- `include_audio_files`
- `privacy.local_only: true`
- `privacy.contains_api_keys: false`
- `entries[].path / size / sha256`

`structured_data/shared_preferences.json` 关键字段：

- `format: simichat.structured_preferences.v1`
- `exported_at`
- `privacy.contains_model_api_keys: false`
- `allowed_keys`：结构化数据白名单
- `values.<key>.type / value`：仅保存 string / bool / int / double / stringList

Obsidian Vault v1 输出目录：

```text
应用文档目录/
└── exports/
    └── obsidian-vault-YYYYMMDD-HHMMSS/
        ├── README.md
        ├── SimiChat-Index.md
        ├── SimiChat-Manifest.md
        ├── Conversations/
        ├── Audio Transcripts/
        └── Attachments/
```

- `README.md`：说明格式、隐私边界和入口。
- `SimiChat-Index.md`：生成 Obsidian wiki link 索引，按会话、语音转写和附件分组。
- `SimiChat-Manifest.md`：记录 vault 内相对路径、类型、大小和 SHA-256，不记录源设备绝对路径。
- `Attachments/`：保存可安全读取的附件原文件，路径形如 `Attachments/<message-id>/<attachment-id>-<safe-file-name>`。
- audio 原始文件受“包含原始语音文件”开关控制：关闭时不进入 Obsidian 附件同步，仅通过 `Audio Transcripts/` 暴露转写稿；开启时复制到 `Attachments/` 并生成 wiki 链接。
- 当前不复制数据库、API Key、渠道密钥、MCP headers 或应用内部配置。

### 2.4 当前导出范围

已包含：

- `conversations/`：每个会话的 Markdown 原始档案。
- `audio_transcripts/`：语音转文字稿件 Markdown，包含 `pending` / `ready` / `empty` / `failed` 明确状态；失败说明已脱敏。
- `audio_files/`：原始语音文件归档，默认包含，可在导出前关闭。
- `attachments/`：SQLite 附件表中仍存在且可读取的非语音附件原文件，路径形如 `attachments/<message-id>/<attachment-id>-<safe-file-name>`。
- `structured_data/shared_preferences.json`：白名单 SharedPreferences 本地数据快照，当前包含：
  - `key_point_memory_v1`
  - `dreaming_digest_v1`
  - `dreaming_schedule_v1`
  - `user_profile_v1`
  - `user_profile_controls_v1`
  - `user_profile_history_v1`
  - `user_profile_change_proposals_v1`
  - `theme_mode`
  - `compress_threshold`
  - `font_scale`
  - `semantic_search_enabled`
  - `system_prompts`
- `structured_data/local_database.json`：SQLite 业务表快照，当前包含：
  - `sessions` / `messages` / `attachments`：会话、消息与附件元数据。
  - `folders`：文件夹与摘要信息。
  - `prompts`：提示词库。
  - `skills`：本地技能定义、来源与 SHA-256 校验元数据。
  - `mcp_servers`：MCP 服务非密钥元数据；不导出 `headers`，疑似含 token 的 `args` / `url` 会置空。
  - `model_channels`：模型渠道非密钥元数据；不导出 `apiKeyEncrypted`，疑似含 token 的 `base_url` 会置空。
  - `channel_models`：渠道模型名称、能力与默认标记。

当前 v1 暂不包含：

- 模型 API Key / 渠道密钥、安全存储内容、MCP headers。
- 模型测试历史等非白名单 SharedPreferences 数据。
- 搜索索引缓存；导入后可由现有逻辑重建搜索索引。
- 云上传、Notion / 语雀 / 思源笔记写入和 Obsidian 双向同步。

## 3. 安全导入 / 恢复实现边界

### 3.1 导入入口

- 设置页「对话 Markdown 档案」弹窗新增「导入」按钮。
- 点击后通过文件选择器选择 `.tar.gz` / `.tgz` 导出包。
- 导入前先进行预览，不直接写入：
  - 显示导出格式、导出时间、可导入文件数、结构化数据项数、已有冲突数、不支持项数量和总大小。
  - 明确提示：默认不会覆盖已有文件或已有结构化数据，冲突项会被跳过。

### 3.2 校验规则

- 只支持 gzip 压缩的 tar 包：`.tar.gz` / `.tgz`。
- 必须包含 `manifest.json`。
- `manifest.export_format` 必须为 `simichat.data_export.v1`。
- 每个导入文件必须在 manifest 中有 SHA-256 校验值，导入前逐项校验。
- 拒绝绝对路径、反斜杠路径和 `..` 路径穿越。
- 只允许导入白名单目录：
  - `conversations/`
  - `audio_transcripts/`
  - `audio_files/`
  - `attachments/`
  - `structured_data/shared_preferences.json`
  - `structured_data/local_database.json`
- 默认不覆盖已有文件；已有文件冲突计数并跳过。
- 结构化数据只恢复白名单键；默认不覆盖本机已存在的白名单键，`overwriteExisting=true` 时才覆盖。
- 结构化快照格式必须为 `simichat.structured_preferences.v1`，格式错误会拒绝导入。

### 3.3 当前恢复范围

当前 v1 可恢复：

- 会话 Markdown 原始档案。
- 语音转文字稿件。
- 原始语音文件。
- 非语音附件原文件，恢复到 `attachments/` 目录。
- 聊天核心数据库：sessions / messages / attachments。
- 非密钥配置表：folders / prompts / skills / mcp_servers / model_channels / channel_models。
- SharedPreferences 白名单结构化数据：Key Points、Dreaming 报告 / 调度、用户画像 / 控制 / 历史 / 待确认变更、主题 / 字体 / 上下文阈值 / 本地语义搜索开关、系统提示词。

当前 v1 暂不恢复：

- 模型 API Key / 渠道密钥、安全存储内容、MCP headers。
- 模型测试历史等非白名单偏好数据。
- 搜索索引缓存等可重建数据。

> 说明：当前导入已从“文件级恢复”扩展到“文件 + 白名单结构化偏好 + 聊天核心数据库 + 非密钥配置表恢复”。模型渠道和 MCP 恢复后默认禁用，需要用户重新填写密钥 / headers 并手动启用，避免误以为导入包可直接调用外部服务。

## 4. 系统分享实现边界

### 4.1 Dart 侧

- `DataExportShareService` 只允许分享文件名符合 `simichat-export-*.tar.gz` 的已存在文件。
- 分享参数只包含文件路径、文件名、MIME、标题和安全提示，不包含用户聊天内容、接口密钥或压缩包内容。
- 缺失文件和非 SimiChat 导出包会在调用原生前被拦截。

### 4.2 Android

- 通过 `MethodChannel('simichat/data_export_share')` 调用原生分享。
- 原生侧再次校验：
  - 文件存在且为普通文件。
  - 文件名必须为 `simichat-export-*.tar.gz`。
  - 文件必须位于应用私有目录下。
- 使用不可导出的 `FileProvider` 生成 `content://` URI。
- `simichat_file_paths.xml` 只开放 `files/`、`../app_flutter/` 和 `cache/`，不使用 `<root-path>`。
- 通过 `FLAG_GRANT_READ_URI_PERMISSION` 临时授予目标应用读取权限。

### 4.3 iOS

- 通过 `MethodChannel('simichat/data_export_share')` 调用原生分享。
- 原生侧再次校验：
  - 文件存在。
  - 文件名必须为 `simichat-export-*.tar.gz`。
  - 文件必须位于应用沙盒目录下。
- 使用 `UIActivityViewController` 打开系统分享面板。
- iPad 弹窗使用 `popoverPresentationController` 设置锚点，避免崩溃。

## 5. 安全与隐私边界

- 导出服务读取本机应用数据目录下的白名单目录：`conversations/`、`audio_transcripts/`、`audio_files/`，读取 SharedPreferences 白名单键，并读取 SQLite 中 sessions / messages / attachments / folders / prompts / skills / mcp_servers / model_channels / channel_models 业务表。
- 导出时跳过 `exports/`，避免把旧备份包嵌套进新备份包；附件源文件若不存在、不是普通文件、是符号链接或位于 `exports/` 下，会被跳过，不阻断整包导出。
- `manifest.json` 只记录压缩包内相对路径、大小和 SHA-256，不写入本机绝对路径；附件文件名、message id、attachment id 都会净化为安全相对路径片段。
- `structured_data/local_database.json` 中附件只记录 `archive_path`，导入时根据目标应用目录重建 `localPath`；不保存源设备绝对路径；非密钥配置表只保存可迁移元数据。
- `audio_transcripts/` 中的失败稿件只写入脱敏错误说明，不保存完整本机路径、STT 令牌、API Key、Bearer token、带密钥查询串的 URL 或原始厂商错误详情。
- 导入数据库快照时默认跳过已有 sessions / messages / attachments / folders / prompts / skills / mcp_servers / model_channels / channel_models；显式覆盖使用 upsert 更新，避免 SQLite `REPLACE` 触发外键级联误删。
- 数据库快照恢复会安全处理外键：`folderId` 仅在目标库中存在对应文件夹时恢复；`defaultChannelModelId`、`channelModelId` 导入时仍置空，避免导入后自动绑定缺少密钥的模型渠道。
- `manifest.json` 明确标注 `local_only: true` 与 `contains_api_keys: false`。
- 当前导出不包含模型 API Key / 渠道密钥，不读取安全存储，不导出渠道数据库密钥字段，不写入明文密钥；MCP `headers` 不导出，疑似含 token 的 MCP `args` / `url` 和渠道 `base_url` 会置空。
- 日志 / Snack 不输出用户文件内容、接口密钥、完整本地路径。
- 分享动作必须由用户点击「生成并系统分享」触发；压缩包一旦被用户分享给外部应用，外部存储和传输风险由用户确认。

## 6. 电脑端本地传输与后续同步策略

### 6.1 当前实现：电脑端本地传输 v1

- 设置页「导出本地数据」弹窗新增「电脑端传输」按钮。
- 点击后先生成标准 SimiChat `.tar.gz` 导出包，再启动临时本地 HTTP 下载服务。
- 下载链接包含一次性随机令牌，默认 10 分钟过期。
- 只允许 `GET /download?token=...`，其他路径、方法或错误令牌不会暴露文件内容或本机绝对路径。
- 只允许传输文件名匹配 `simichat-export-*.tar.gz` / `.tgz` 的导出包。
- 下载响应使用 `application/gzip`、`Content-Disposition: attachment`、`Cache-Control: no-store` 和 `X-Content-Type-Options: nosniff`。
- 单次下载成功后会标记链接已使用并短延迟关闭服务；用户关闭传输弹窗也会停止服务。
- Android release manifest 已声明 `INTERNET`；iOS `Info.plist` 已声明 `NSLocalNetworkUsageDescription`。
- 当前 UI 展示 loopback 与可枚举的局域网 IPv4 地址；真机局域网连通仍需要设备网络环境验证。

### 6.2 后续增强：电脑端本地传输

- 二维码配对。
- 电脑端接收页和传输进度。
- 传输完成后自动导入 / 校验。
- 局域网地址不可达时的诊断提示。
- 默认只暴露用户刚确认的导出包，不直接暴露整个应用数据目录。

### 6.3 云备份

- WebDAV / S3 / 云盘。
- 云同步默认关闭。
- 端到端加密。
- 增量同步。
- 冲突解决：保留两份并生成冲突报告。
- 同步凭证必须使用安全存储。

### 6.4 笔记工具

#### 当前实现：Obsidian Markdown Vault 导出 / 增量同步 v1

- 设置页「导出本地数据」弹窗提供「Obsidian Vault」按钮。
- 导出结果写入应用文档目录 `exports/obsidian-vault-YYYYMMDD-HHMMSS/`。
- 复制 `conversations/` 下会话 Markdown 到 `Conversations/`。
- 复制 `audio_transcripts/` 下语音转写 Markdown 到 `Audio Transcripts/`。
- 复制 SQLite 附件表中仍可读取的附件到 `Attachments/<message-id>/<attachment-id>-<safe-file-name>`；缺失文件、符号链接和旧导出目录会跳过。audio 原文件由“包含原始语音文件”开关控制，关闭时跳过。
- 会话 Markdown 中带 `<!-- simichat-message-id: ... -->` 的 `attachments` 列表会按 `messageId + fileName` 匹配附件，并重写为 Obsidian wiki 链接，例如 `[[Attachments/m1/att_1-file.png|图 片.png]]`；同一消息内多个同名附件会按 Markdown 附件项出现顺序逐条消耗对应链接，避免全部指向第一条。
- 生成 `README.md`、`SimiChat-Index.md` 和 `SimiChat-Manifest.md`，便于 Obsidian 打开后从索引进入；索引中也包含附件分组。
- Manifest 只记录 vault 内相对路径、类型、大小和 SHA-256；不写本机绝对路径。
- 设置页同一弹窗提供「同步到 Obsidian」按钮，可选择用户已有 Obsidian Vault 文件夹，并写入该 vault 下的 `SimiChat/` 子目录。
- 增量同步使用 `SimiChat/SimiChat-Sync-State.json` 记录上次成功同步的相对路径与 SHA-256；目标文件未变时自动跳过，目标文件仍等于上次同步版本时安全更新。
- 如果上次同步状态中存在某个文件，但当前源会话 / 转写 / 附件列表已不再包含它：目标文件仍等于上次同步 SHA 时自动删除并计入 `sync_deleted`；目标文件已被用户修改时记录 `source_removed_target_modified` 冲突并保留，避免误删用户在 Obsidian 侧保留的内容。
- 点击同步前会先选择策略：`安全同步` 为默认；`覆盖冲突` 需要用户显式选择，用 SimiChat 当前档案覆盖普通文件差异。
- 如果用户在 Obsidian 中手动修改过同名 Markdown，安全同步默认不覆盖，记录 `target_modified` 冲突并跳过该文件；覆盖冲突模式会更新该普通文件。
- 如果目标路径是目录、符号链接等非普通文件，记录 `unsafe_existing_entity` 冲突并跳过，避免写穿链接或覆盖非预期文件。
- 如果同步结果存在冲突，设置页会弹出「Obsidian 同步冲突详情」，展示冲突相对路径、中文原因说明、新版本 / 现有版本短 SHA，并提示本次没有覆盖或删除用户文件；stale 清理冲突会明确说明“源端已删除但目标已修改，因此保留”或“目标不是普通文件，因此跳过清理”。
- 同步目标不能位于 SimiChat 源档案目录 `conversations/` 或 `audio_transcripts/` 内，避免把同步产物重新纳入源数据。
- 当前 v1 不做双向同步；同一消息同名附件已经按出现顺序精确链接，后续仍可继续增强 Obsidian 侧展示样式。

#### 后续增强

- Notion：同步摘要、会话索引、任务。
- 语雀：同步 Markdown 文档。
- Obsidian：双向同步、更完整的冲突处理流程、同名附件更清晰的展示命名。
- 思源笔记：块级文档同步。
- 写入前需要明确文档结构、覆盖策略、冲突策略和撤销方式。

## 7. 测试要求

已覆盖：

- 导出包 `manifest.json` 完整性测试。
- Markdown / 语音转写稿 / 原始语音文件导出测试。
- 旧 `exports/` 文件不进入新导出包。
- `includeAudioFiles=false` 排除原始音频测试。
- 非语音附件原文件导出测试：复制到 `attachments/`，净化 `../` 与空格等不安全片段，跳过 audio / 缺失附件，manifest 不泄露源目录。
- 本地数据库快照导出测试：`structured_data/local_database.json` 包含 sessions / messages / attachments / folders / prompts / skills / mcp_servers / model_channels / channel_models，附件只记录 archive_path，不记录本机绝对路径，模型密钥与 MCP headers 不入包。
- manifest 不包含本机绝对路径。
- 不包含 API Key 的 manifest 标记测试。
- 导出确认弹窗、包含原始语音文件开关、「仅生成压缩包」「生成并系统分享」入口测试。
- 安全导入预览、恢复、`attachments/` 文件恢复、聊天核心数据库快照恢复、非密钥配置表恢复、冲突跳过、checksum 失败、路径穿越、缺失 manifest 测试。
- 结构化数据白名单导出 / 恢复测试：不导出任意 `api_key` / 渠道密钥键，默认不覆盖已有偏好，覆盖导入可显式覆盖，格式错误拒绝。
- 设置页导入入口测试。
- Dart 分享服务文件名限制、缺失文件拦截、平台通道参数测试。
- Android / iOS 平台通道安全配置静态测试。
- Android debug APK 构建验证。
- iOS simulator 构建验证。
- 200 个 Markdown 文件导出性能基线。
- 200 个 Markdown 文件导入预览 / 恢复性能基线。
- 电脑端本地传输一次性令牌下载、错误令牌、过期、非法路径 / 方法测试。
- 1 MB 本地传输下载性能基线。
- Obsidian Vault 导出测试：会话 / 语音转写 Markdown 复制、README / Index / Manifest 生成、空 vault、忽略非 Markdown 和旧 exports、Manifest 不泄露本机绝对路径。
- Obsidian Vault 200 个 Markdown 文件导出性能基线。
- Obsidian 现有 Vault 增量同步测试：首次写入、二次未变跳过、源文件变更安全更新、目标手动修改冲突跳过、符号链接目标不写穿、源档案目录内目标拒绝。
- Obsidian 附件复制 / wiki 链接重写测试：附件进入 `Attachments/`，会话 Markdown 附件项重写，audio 默认跳过、显式开启后复制且不泄露本机绝对路径。
- Obsidian 同步冲突详情界面测试：展示冲突数量、Vault 相对路径、`target_modified` / `unsafe_existing_entity` 中文原因和短 SHA。
- Obsidian 可选覆盖冲突策略测试：服务层显式 `overwriteConflicts` 可覆盖普通文件差异，设置页同步前展示安全同步 / 覆盖冲突策略选择。
- Obsidian 原始音频附件可选同步测试：`includeAudioAttachments` 开启后 audio 原文件进入 `Attachments/` 并重写为 wiki 链接。
- Obsidian 同名附件链接精确去重测试：同一消息内两个同名附件按出现顺序分别重写为不同 `Attachments/` wiki 链接，且不泄露本机绝对路径。
- Obsidian stale 文件安全清理测试：源文件删除后安全删除未被修改的旧同步文件；目标已被用户修改时记录 `source_removed_target_modified` 冲突并保留。
- Obsidian stale 冲突详情解释测试：设置页冲突详情展示 stale 冲突中文说明、原因代码和短 SHA，避免用户只看到内部 reason。
- Obsidian 现有 Vault 200 个 Markdown + 200 个附件首次同步 / 二次同步性能基线；默认非语音附件，audio 显式开启后复用同一复制与链接重写路径。

后续仍需覆盖：

- 真机打开系统分享面板、本地传输局域网下载的交互验证。
- 大附件 / 长会话 / 真机导出性能测试。
- 加密导出包测试。
- Notion / 语雀 / 思源笔记同步失败可恢复测试。
- 明文密钥不进入任何导出或同步包的端到端测试。
