# 功能实现差距分析与实施计划（2026-08-07）

> 目的：把 `AGENTS.md` 中所有“未完成项”逐一映射为明确状态或可执行的实施计划，
> 确保没有“悬空”的功能项。标注为「已实现」的项在本轮已代码落地并通过全量测试；
> 标注为「需外部资源」的项给出精确方案、依赖和验证路径，避免假完成。

---

## 一、本轮已实现（代码落地 + 全量测试 586 项通过）

| 功能 | 落点 | 说明 |
| --- | --- | --- |
| DW Chainless 中转站预置 | `lib/core/ai/model_provider_preset.dart` | 新增 `dwchainless` OpenAI 兼容预设（Base URL `https://api.dwchainless.com/v1`），含注册链接与推荐模型 |
| 无 Key 注册引导 | `lib/features/settings/settings_page.dart`、`lib/shared/widgets/in_app_h5_page.dart` | 设置页渠道区顶部 SimiRouter 推广卡片和预设提示卡提供「获取 Key」；通过内置 H5 直接打开 `https://api.dwchainless.com/sign-up?aff=Bslh`，不跳转浏览器、不显示地址栏 |
| 一键接入 | 同上 | 「一键接入」预填渠道名称 / Base URL / 协议 |
| 关于页鸣谢 | 同上（关于区） | 「鸣谢 · SimiRouter AI 中转站」带图标，点击进入无地址栏的内置官网 H5 页面 |
| 图片生成 | `lib/core/ai/image_generation_service.dart`、`chat_provider.generateImage()`、`chat_input_bar.dart`、设置页「图片生成配置」 | OpenAI 兼容 `/v1/images/generations`：优先 `b64_json` 本地保存，失败回退安全下载远端 URL；聊天输入框「✨」按钮生成，图片作为 assistant 消息附件展示；图片模型可配置（默认 `dall-e-3`），复用当前渠道 Base URL / Key |

新增测试：`test/settings_page_dwchainless_test.dart`、`test/image_generation_service_test.dart`、`test/chat_input_bar_image_generation_test.dart`、`test/settings_page_image_generation_test.dart`；`test/model_provider_preset_test.dart` 扩展 dwchainless 断言。

| 功能 | 落点 | 说明 |
| --- | --- | --- |
| WebDAV 云备份 | `lib/core/backup/webdav_backup_service.dart`、`webdav_backup_provider.dart`、设置页「云备份 (WebDAV)」 | 导出包用**用户口令 E2E 加密**（`KeyEncryptor.encryptWithPassword`，口令不落盘）后 PUT 上传；PROPFIND 列表；下载解密后用 `DataImportService` 恢复。测试含本地 mock WebDAV 服务器（`webdav_backup_service_test`） |
| 网页搜索 / RAG | `lib/core/search/web_search_service.dart` + MCP 内建工具 `simichat.web_search` | DuckDuckGo Instant Answer（免 Key）搜索；注册为 App 内建 MCP 工具，AI 可在对话中检索增强。测试：`web_search_service_test`、`mcp_web_search_tool_test` |
| Telegram Bot 社交通道 | `lib/core/channels/channel_adapter.dart`、`telegram_bot_adapter.dart`、`channel_bot_gateway.dart`、`telegram_bot_provider.dart`、设置页「社交通道 / Telegram Bot」 | `ChannelAdapter` 抽象（供飞书 / Discord 复用）；Bot API getMe / getUpdates 长轮询 / sendMessage；网关用默认聊天模型应答，每用户有界历史。测试：`telegram_bot_adapter_test`、`channel_bot_gateway_test` |
| Notion 同步 | `lib/core/archive/notion_sync_service.dart`、`notion_sync_provider.dart`、设置页「Notion 同步」 | Integration Token（Bearer）在父页面下创建子页面并写入 heading / paragraph 块；设置页可批量导出会话。测试：`notion_sync_service_test`、`settings_page_notion_sync_test` |
| 多源技能市场 | `lib/core/skills/skill_marketplace_source.dart` | `SkillMarketplaceSource` 抽象（统一 search / install + SHA-256 校验）+ `SkillHubMarketplaceSource` 适配器 + `GenericHttpSkillMarketplaceSource`（自定义 HTTP 技能源，OpenClaw 风格 index.json）。测试：`skill_marketplace_source_test` |
| 语雀同步 | `lib/core/archive/yuque_sync_service.dart`、`note_sync_providers.dart`、设置页「语雀同步」 | Token 在仓库（namespace）下创建 markdown 文档；批量导出会话。测试：`yuque_sync_service_test` |
| 思源同步 | `lib/core/archive/siyuan_sync_service.dart`、`note_sync_providers.dart`、设置页「思源同步」 | Token 通过 `/api/filetree/createDocWithMd` 在笔记本下创建文档。测试：`siyuan_sync_service_test` |
| S3 云备份 | `lib/core/backup/s3_backup_service.dart`、`s3_backup_provider.dart`、设置页「S3 云备份」 | AWS SigV4 签名 + PUT/GET/ListObjectsV2，导出包口令 E2E 加密；兼容 AWS / MinIO / R2 / COS。测试：`s3_backup_service_test` |
| Discord Bot | `lib/core/channels/discord_bot_adapter.dart`、`discord_bot_provider.dart`、设置页「Discord Bot」 | REST getMe / sendMessage + Gateway WebSocket 收 MESSAGE_CREATE，AI 应答网关。测试：`discord_bot_adapter_test`（本地 WebSocket 网关） |
| 飞书 Bot | `lib/core/channels/feishu_bot_adapter.dart`、`feishu_bot_provider.dart`、设置页「飞书 Bot」 | tenant_access_token + im/v1/messages 发送 + 本地 webhook 收件箱接收（回调 URL 公网隧道）。测试：`feishu_bot_adapter_test` |
| 数字孪生 v1 | `lib/core/twin/persona_profile.dart`、设置页「数字孪生 / 镜像数字人」 | `PersonaProfileGenerator` 把画像蒸馏为人格配置（替身 system prompt 模板）+ `MediaPersonaAnalyzer` 统计 emoji / 语音 / 图片媒体信号。测试：`persona_profile_test`、`settings_page_digital_twin_test` |
| WhatsApp 适配器 | `lib/core/channels/whatsapp_cloud_adapter.dart` | Business Cloud API：Bearer 鉴权 + 发送 + 本地 webhook 收件箱解析。测试：`social_webhook_adapters_test` |
| Slack 适配器 | `lib/core/channels/slack_bot_adapter.dart` | auth.test + chat.postMessage + Events API webhook 解析（忽略 bot 消息）。测试同上 |
| 微信公众号适配器 | `lib/core/channels/wechat_mp_adapter.dart` | access_token + 客服消息 + XML 回调解析。测试同上 |
| QQ 适配器 | `lib/core/channels/qq_bot_adapter.dart` | 开放平台 REST 发送 + C2C_MESSAGE_CREATE webhook 解析。测试同上 |
| 通用 Webhook 社交通道 | `lib/shared/providers/webhook_bot_provider.dart`、设置页「Webhook 社交通道」 | 一个入口覆盖 WhatsApp / Slack / 微信公众号 / QQ，选择平台 + 填凭据 + 启停，AI 应答网关 |
| OneDrive 云盘备份 | `lib/core/backup/one_drive_backup_service.dart`、`one_drive_backup_provider.dart`、设置页「OneDrive 云盘备份」 | Microsoft Graph 上传 / 列出 / 下载，导出包口令 E2E 加密。测试：`one_drive_backup_service_test` |
| 替身回复授权 | `lib/shared/providers/persona_provider.dart`、`chat_provider.generatePersonaReply`、聊天附件菜单「替身回复」 | 显式授权（持久化 + 时间戳）后才可用；聊天页以镜像人格为最近用户消息生成回复。测试：`persona_reply_test` |
| 替身审计日志落库 | `lib/core/database/tables.dart`（`persona_audit_logs` 表 + schema v8）+ `persona_audit_log_dao.dart` + 授权 / 撤销 / 替身回复自动落库 + 设置页「审计日志」历史查看 / 清空 | 每次授权、撤销、替身回复（会话 / 消息 / 摘要 / 时间）均可追溯。测试：`persona_audit_log_dao_test` |
| 数字人直播 v1 | `lib/core/twin/live_stream_service.dart` + 设置页「数字人直播」 | `LiveStreamScriptGenerator` 从镜像人格生成直播脚本（开场 / 话题 / 结束）+ RTMP 目标配置校验 + 开播会话记录。测试：`live_stream_service_test`、`settings_page_live_stream_test` |

---

## 二、已具备代码基线与自动化入口、待真机 / 环境补证的项

| 项 | 现状 | 需要什么才能标记完成 |
| --- | --- | --- |
| 移动端真机主链路冒烟 | 大量 smoke 脚本 + Pixel 8 / iPhone13 补证记录 | 物理设备在场时按 `scripts/smoke_*` 复跑 |
| iOS BGTask 系统后台执行 | 代码基线 + 真机诊断 `backgroundRefreshStatus=denied` | 用户在系统设置开启「后台 App 刷新」后复跑 `scripts/smoke_ios_release_*` |
| Android 跨日 / Doze / OEM 长期可靠性 | 跨日任务已在 Pixel 8 等待 | 长周期观察与 `verify` |
| OpenAI Relay 真机长时间运行 | 本地 benchmark + 真机接口补证 | 真机局域网长跑 + 第三方客户端兼容 |
| 更多 STT / TTS 厂商 | OpenAI 兼容 + 厂商预设 + iOS 系统 Speech 兜底 | 逐个接入目标厂商协议与预设 |

---

## 三、需外部资源 / 新依赖 / 明确产品决策的项（给出方案）

### 3.1 模型 embedding 与真正向量数据库（Phase 2）
- **现状**：本地轻量语义向量 + SQLite FTS 已落地，缺模型 embedding / ANN。
- **方案**：
  1. 新增 OpenAI 兼容 `/v1/embeddings` 客户端（复用中转站与现有渠道），对消息与 Key Points 生成 embedding；
  2. 新增 `message_embeddings` / `key_point_embeddings` Drift 表；
  3. 检索阶段对候选做余弦相似度排序（本地量级可用暴力扫描，量级大时引入 `sqlite-vec` 或离线 ANN）。
- **依赖**：可用的 embedding 模型名与额度（中转站 `/v1/embeddings` 是否开放需用 Key 实测）。

### 3.2 社交平台接入（Phase 3：飞书 / Telegram / Discord 等）
- **已实现 v1**：`ChannelAdapter` 抽象 + Telegram（长轮询）+ Discord（Gateway WebSocket）+ 飞书 + **WhatsApp / Slack / 微信公众号 / QQ**（REST 发送 + 本地 webhook 收件箱，共用 `WebhookChannelAdapter` 基类与「Webhook 社交通道」设置入口）+ `ChannelBotGateway`（AI 应答循环）。全部带 mock 服务器 / 本地 WebSocket / webhook 测试。
- **待扩展**：外部消息落本地 SQLite `messages` 与命令白名单仍待产品决策。
- **依赖**：各平台 Bot Token / 应用凭据、可接收 webhook 的公网隧道（webhook 类平台）。

### 3.3 多源技能市场（Phase 3：OpenClaw、腾讯）
- **已实现 v1**：`SkillMarketplaceSource` 抽象（search / install + SHA-256 校验）+ `SkillHubMarketplaceSource` 适配器 + `GenericHttpSkillMarketplaceSource`（自定义 HTTP 技能源，兼容 OpenClaw 风格 index.json，见上表）。测试含 mock HTTP 与 SHA-256 篡改拒绝。
- **待扩展**：技能页 UI 展示多来源切换；腾讯技能市场需先确认开放 API 与授权方式。
- **依赖**：腾讯技能市场的公开 API / 文档。

### 3.4 定时任务 → 系统日历 / 闹钟联动（Phase 3）
- **现状**：Dreaming 前台到期通知 + Android WorkManager 系统后台已落地。
- **方案**：
  1. 新增日历插件（`add_2_calendar`）或原生 EventKit / CalendarContract MethodChannel；
  2. 把 AI 从对话中提取的提醒（时间 + 事项）写入系统日历；
  3. 系统闹钟联动通过 Intent / Shortcut 触发，需二次确认避免打扰。
- **依赖**：新增 Flutter 插件依赖与平台权限（日历写入声明）。

### 3.5 网页搜索 / RAG（Phase 3）
- **已实现 v1**：`WebSearchService`（DuckDuckGo Instant Answer，免 Key）+ MCP 内建工具 `simichat.web_search`（见上表），AI 可在对话中检索增强。
- **待扩展**：若中转站提供搜索端点则优先复用；结果缓存与更多来源（SerpAPI 等）可后续接入。

### 3.6 MCP 运行时 / 旁车（Phase 3）
- **现状**：App 内建 Runtime + PC Node 容器侧车 v1 已落地。
- **方案**：
  1. Runtime 状态表持久化（进程状态 / 端口 / 最后心跳）到 SQLite；
  2. 设置页「MCP Runtime」完善启动 / 停止 / 日志查看；
  3. 第三方 Node MCP 包白名单安装（版本固定 + SHA 校验）；
  4. 权限治理矩阵（每个工具可访问的资源边界）。
- **依赖**：无（纯代码，工作量中等）。

### 3.7 Notion / 语雀 / 思源笔记同步（Phase 4）
- **已实现 v1**：Notion（Integration Token + 创建子页面）、语雀（仓库下创建 markdown 文档）、思源（createDocWithMd）均已落地（见上表），设置页可批量导出会话。
- **待扩展**：双向同步与更完整冲突处理。
- **依赖**：各平台 API token / 凭据。

### 3.8 Obsidian 双向同步（Phase 4）
- **现状**：单向增量同步 + 冲突跳过。
- **方案**：基于 `SimiChat-Sync-State.json` 指纹 diff，把 vault 内 SimiChat Markdown 的用户改动解析回 SQLite；用户逐条确认合并，冲突保留双向副本。
- **依赖**：无（纯代码，但冲突合并需谨慎设计）。

### 3.9 云备份 WebDAV / S3 / 云盘（Phase 4）
- **已实现 v1**：WebDAV（PROPFIND / PUT / GET）+ S3（AWS SigV4 + ListObjectsV2，兼容 AWS / MinIO / R2 / COS）+ **OneDrive 云盘**（Microsoft Graph 上传 / 列出 / 下载）均已落地（见上表），导出包均用用户口令 E2E 加密，口令不落盘。
- **待扩展**：其他云盘（百度网盘 / iCloud）复用同一「加密导出包 + 上传 / 恢复」抽象。
- **依赖**：用户自备 WebDAV / S3 / OneDrive 凭据（OneDrive 需在应用内 OAuth 或提供 Graph token）。

### 3.10 数字孪生：声音 / 图像 / 表情（Phase 5）
- **已实现 v1**：`PersonaProfileGenerator`（画像 → 人格配置 / 替身 system prompt）+ `MediaPersonaAnalyzer`（emoji 使用统计、语音 / 图片附件倾向）已落地（见上表）；设置页可预览人格配置。
- **待扩展**：深层语义分析（语音情绪、图像内容理解）需外部多模态模型（若中转站开放可复用）。

### 3.11 镜像数字人生成（Phase 5）
- **已实现 v1**：人格配置生成与替身 system prompt 模板、**替身回复显式授权开关（持久化 + 时间戳）**、聊天页「替身回复」入口、**替身审计日志落库（`persona_audit_logs` 表，授权 / 撤销 / 回复全记录 + 设置页历史查看 / 清空）** 均已落地（见上表）。
- **待扩展**：深层语义分析（需多模态模型）。

### 3.12 数字人直播（长期）
- **已实现 v1**：`LiveStreamScriptGenerator` 从镜像人格生成直播脚本（开场 / 话题 / 结束）+ RTMP 推流目标配置与校验 + 开播会话记录 + 设置页入口（见上表）。实际视频推流由用户在 OBS 等工具指向配置的 RTMP 地址。
- **待扩展**：应用内直接推流（需 RTMP 客户端 / 平台 SDK）、直播平台开放 API 对接。

---

## 四、技术债（AGENTS.md 审计清单）

| 项 | 状态 | 说明 |
| --- | --- | --- |
| MED-5 i18n 覆盖 | 待做 | ARB 框架 + 少量 key，界面大量硬编码中文；迁移工作量大，建议按页渐进 |
| MED-1 Dropdown `initialValue` | 待做 | 已知问题，升级 Flutter 后应改用 `value` 语义并回归 |
| MED-2/3/4/7/8/9/10/12、LOW-* | 部分已修 | 按审计清单逐项处理，多数为死代码清理与资源释放 |

---

## 五、验证基线（本轮）

- `flutter --no-version-check analyze --no-pub`：无问题。
- 全量 `flutter --no-version-check test --no-pub -r expanded`：**652 项全部通过**。
- 新增测试（五轮合计 82 项）：前四轮 73 项 + 替身审计日志 DAO 2 + 直播服务 4 + 直播设置 1 + schema v8 迁移回归；相关回归适配（设置页新增区块后滚动 / `ensureVisible` 后点击）。

## 六、真机验证（2026-08-07）

- **Android（Pixel 8 · 37101FDJH0077P）**：release 安装 / 启动 ✅、设置页真机 smoke ✅（含全部新设置区块）、真实发送真机 smoke ✅；debug 集成测试会重置测试机应用数据（AGENTS.md 已记录，Pixel 8 为专用测试机）。
- **iOS（iPhone13）**：release 构建 ✅（40.7MB，bundle `top.simitalk.aichat`）；安装被 provisioning profile 阻止（`0xe8008012`，需在 Apple Developer 后台把设备 UDID 加入描述文件）。
