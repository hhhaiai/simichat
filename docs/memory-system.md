# 记忆、Markdown 原始档案与本地检索系统设计

> 对应模块：M2。状态：Markdown 原始档案、Key Points 本地记忆 v1、Key Points 本地语义向量召回 v1、本地全文检索 v1、历史消息本地语义检索 v1、本地消息语义索引 v1、本地语义搜索用户开关 v1、SQLite FTS 搜索索引 v1、FTS + 语义索引健康检查 / 预热 / 修复入口、Dreaming 本地整理 v1、Dreaming 前台到期调度 v1 已落地；模型 embedding / 真正向量数据库、系统后台 Dreaming 调度和模型驱动画像仍待实现。最后更新：2026-06-27。

## 1. 目标

- 聊天记录全部本地存储，不默认上传云端。
- 每个对话对应 1 个 Markdown 原始文件。
- 从对话中提取核心记忆点，并在后续聊天中检索注入。
- 支持跨对话检索，使本地聊天记录成为本地知识库。
- 支持无限上下文：超出令牌限制时摘要压缩并保留关键事实。

## 2. 当前基础

当前已具备：

- SQLite / drift 消息存储。
- `ContextBuilder` 上下文构建。
- `ContextCompressor` 滚动压缩。
- `TokenEstimator` 令牌估算。
- 全局搜索基础能力。
- Markdown 原始文件同步基础能力：`MarkdownConversationArchive` 可按会话追加和重建，聊天主路径已接入追加。
- Markdown 标题同步、历史消息重建、一致性校验、失败修复队列、一键重试修复。
- 设置页“数据与档案 / 对话 Markdown 档案”维护入口：可查看待修复队列、检查当前会话、重建当前会话、清空队列、一键修复队列。
- Key Points 本地记忆 v1：`KeyPointMemoryItem` 数据结构、`KeyPointExtractor` 明示偏好 / 画像 / 目标 / 任务提取、SharedPreferences 本机持久化、关键词相关性召回、系统提示词注入。
- Key Points 本地语义向量召回 v1：`rankRelevantKeyPoints()` 在关键词重叠基础上加入本地语义别名、中文 n-gram 向量和 cosine similarity；不新增依赖、不调用远端模型、不外发记忆内容。
- 聊天主链路已在用户消息写入后提取记忆点，并在构建模型请求上下文时注入相关记忆；记忆提取 / 检索失败会静默降级，不阻断聊天。
- 本地全文检索 v1：`LocalFullTextSearchService` 对查询分词，合并会话标题、消息内容和 Key Points 记忆命中，按分数排序并生成摘要片段；全局搜索面板已切换到该服务。
- 历史消息本地语义检索 v1：全局搜索复用本地语义向量与 cosine similarity 补足近义表达命中；不新增依赖、不调用远端模型。
- 本地消息语义索引 v1：`message_semantic_index` 本地表保存全部原始消息的内容哈希与轻量语义向量 JSON，搜索不再局限最近 500 条消息；设置页“本地搜索索引”可统一检查、预热和修复 SQLite FTS + 语义索引。
- 本地语义搜索用户开关 v1：`semanticSearchEnabledProvider` 使用 SharedPreferences 持久化；设置页“本地搜索索引”弹窗可关闭 / 开启本地语义搜索，关闭后全局搜索只使用标题、FTS / LIKE 和 Key Points 字面检索。
- SQLite FTS 搜索索引 v1：`MessageDao.ensureMessageFtsIndex()` 按需创建 `messages_fts` 虚拟表与 insert / update / delete 触发器，历史原始消息自动补建索引，搜索时优先使用 FTS 命中并保留 LIKE 回退。
- SQLite FTS 维护 v1：`MessageFtsIndexHealth`、`checkMessageFtsIndexHealth()`、`prewarmMessageFtsIndex()` 已支持健康检查、索引行数一致性检查、历史消息补建和自动修复。
- 本地语义索引维护 v1：`MessageSemanticIndexHealth`、`checkMessageSemanticIndexHealth()`、`prewarmMessageSemanticIndex()` 已支持原始消息数、索引行数、缺失 / 过期行、多余行、重建状态和耗时统计。
- 本地搜索索引性能脚本：`scripts/benchmark_search_index.sh` 可用 Flutter 测试运行 2000 条消息的 FTS 预热、语义索引预热和搜索耗时基线。
- Dreaming 本地整理 v1：`DreamingService` 可汇总今日原始消息，生成日报、会话摘要、关键词和记忆候选；设置页“数据与档案 / Dreaming 夜间整理”已支持手动触发，报告保存在 `dreaming_digest_v1`，记忆候选会写入 Key Points。
- Dreaming 前台到期调度 v1：`DreamingScheduleConfig` 默认 22:00 且默认开启；用户可在设置页开关和修改时间；应用前台初始化时到期自动整理当天一次，并通过 `lastAutoRunDayKey` 防止同日重复自动运行。

尚未具备：
- SQLite FTS 的后台周期预热 / 真机长会话维护策略。
- 完整对话向量检索：Key Points 本地语义向量召回、本地消息语义索引已落地；模型 embedding、真正向量数据库 / ANN、增量维护优化、真机长会话性能基线仍待实现。
- Dreaming 系统后台定时调度 / 模型驱动的自动画像提取。

## 3. Markdown 原始档案

### 3.1 文件位置

用户提出约定为 `docs/conversations/`。生产实现需区分：

- 开发仓库：`docs/conversations/` 只保存说明和示例，不提交真实用户数据。
- 应用运行时：使用应用数据目录下的 `conversations/` 存放用户真实 Markdown 原始档案。
- 导出时：可生成 `docs/conversations/<session-id>.md` 形式的压缩包结构。

### 3.2 文件格式

```markdown
# 会话标题

- session_id: xxx
- created_at: 2026-06-27T00:00:00+08:00
- default_model: OpenAI / gpt-4o

## 消息

### 2026-06-27 00:00 用户

正文

### 2026-06-27 00:01 助手

正文

## 附件

- file: attachments/xxx.png
```

### 3.3 一致性策略

- SQLite 是查询权威源。
- Markdown 是原始档案和导出友好格式。
- 每次写消息后追加 Markdown。
- 如果追加失败，记录待修复队列，不阻断聊天；同一会话同一操作失败会去重保留最新错误。
- 提供“从 SQLite 重建 Markdown”工具；当前设置页已暴露当前会话检查、重建、队列清空和队列一键重试入口。

## 4. Key Points

### 4.1 当前 v1 结构

当前先不新增 Drift 表，避免在轻量记忆策略尚未稳定前扩大迁移面；采用 Riverpod `KeyPointMemoryNotifier` 持有内存态，并用 SharedPreferences 本机持久化到 `key_point_memory_v1`。

```text
KeyPointMemoryItem
- id：基于 sessionId + 归一化 content 的稳定去重 id
- sessionId
- sourceMessageId
- category: preference / profile / goal / task / note
- content：归一化后的核心记忆文本，最长 240 字
- keywords：本地关键词集合，用于轻量召回和语义向量构建
- confidence：启发式置信度
- createdAt / updatedAt / lastUsedAt
```

### 4.2 提取规则

- 仅从用户消息中提取。
- 只提取用户明示内容：`记住`、`以后`、`下次`、`我喜欢`、`我不喜欢`、`偏好`、`习惯`、`作息`、`我是`、`我叫`、`我的`、`目标`、`计划`、`打算`、`希望`、`todo` 等。
- 命中 API Key、Authorization、password、secret、token、密钥、密码、常见密钥字面量时直接跳过，避免把敏感凭据写入记忆。
- 同一内容按稳定 id 去重；更新时保留最早创建时间和最近使用时间。
- 单机最多保留 300 条，按更新时间保留最近项。

### 4.3 后续结构演进

稳定后可迁移到 SQLite / Drift 表：

```text
MemoryPoint
- id
- sourceSessionId
- sourceMessageIds
- type: fact / preference / task / style / relationship / decision
- content
- confidence
- tags
- embedding
- createdAt
- updatedAt
- lastUsedAt
```

## 5. 检索与注入

```text
用户新消息
  -> 写入 SQLite / Markdown 原始档案
  -> KeyPointExtractor 提取明示记忆点
  -> KeyPointMemoryNotifier 去重并本机持久化
  -> 基于当前输入做关键词相关性 + 本地语义向量召回
  -> buildKeyPointMemorySystemPrompt 生成“用户核心记忆（本地提取）”
  -> ContextBuilder 注入系统提示词
  -> 后续迭代再叠加完整对话 embedding / 持久化向量索引
```

### 5.0 Key Points 本地语义向量召回 v1

当前聊天主链路已使用增强后的 `rankRelevantKeyPoints()`：

- 查询和记忆内容会转换为本地归一化语义向量，向量由关键词、中文 2/3-gram、英文 / 数字 token 和少量产品域语义别名组成。
- 语义别名覆盖移动端 / 手机端、本地 / 本机 / 隐私、Dreaming / 夜间整理、数字孪生 / 镜像数字人、语音 / STT、多模态 / 图片、模型 / 渠道、Skills / 插件、提醒 / 日历 / 闹钟等高频产品域表达。
- 排序分数综合：关键词重叠、语义向量 cosine similarity、置信度、同会话加权、最近使用加权。
- 无关键词重叠且语义相似度过低的记忆会降权，避免无关记忆污染系统提示词。
- `buildLocalSemanticVector()` 和 `cosineSimilarity()` 为纯本地函数，便于测试和后续替换为真实 embedding。
- 性能脚本：`scripts/benchmark_key_point_memory.sh` 运行 `test/key_point_memory_benchmark.dart`，当前覆盖 5000 条 Key Points、20 次召回。

边界：

- 这不是完整向量数据库；当前只增强 Key Points 召回，不持久化消息 embedding。
- 后续对话级 RAG 仍需引入 MemoryPoint/Message embedding 表、增量索引、索引维护和真机长会话基线。

### 5.1 本地全文检索 v1

全局搜索面板当前使用 `LocalFullTextSearchService`：

- 对查询做归一化和轻量分词，支持中文片段、英文 / 数字标识、多关键词组合。
- 同时召回：会话标题、原始消息内容、Key Points 本地记忆。
- 过滤 `message_type = model_switch` 等非原始聊天记录，避免模型切换时间线污染搜索结果。
- 优先使用 SQLite FTS5 虚拟表 `messages_fts` 检索原始消息，FTS 不可用或分词未命中时继续用本地 LIKE 回退，保证中文短片段与旧环境可用。
- 按命中类型、FTS 命中、关键词覆盖和同会话记忆相关度打分排序。
- 生成本地摘要片段，只展示命中上下文，不写日志、不外发。
- 当前 FTS 索引按需创建，无新增依赖；设置页可手动检查、预热和修复索引；后续长会话规模变大后需要接入后台调度、真机性能基线和向量索引。

### 5.1.1 历史消息本地语义检索 / 本地消息语义索引 v1

当前全局搜索在 FTS / LIKE / Key Points 召回之外，增加一层轻量历史消息语义索引：

- `MessageDao.searchOriginalMessagesSemantic()` 接收查询本地语义向量，读取 `message_semantic_index` 中已预热的消息向量并计算 cosine similarity。
- 全局搜索调用 `LocalFullTextSearchService(enableSemanticMessageSearch: ...)`，由 `semanticSearchEnabledProvider` 控制是否启用本地语义消息召回。
- `message_semantic_index` 是本地 SQLite 普通表，字段包括 `message_id`、`session_id`、`content_hash`、`vector_json`、`updated_at`；`content_hash` 用于判断消息内容是否过期，`vector_json` 保存本地轻量语义向量。
- `MessageDao.prewarmMessageSemanticIndex()` 会为全部 `message_type = original` 消息生成 / 重建语义索引；`summary`、`model_switch` 等非原始记录不参与。
- `MessageDao.checkMessageSemanticIndexHealth()` 会统计原始消息数、已索引行数、缺失 / 过期行、多余行、是否重建和耗时。
- 查询文本和消息正文复用 `buildLocalSemanticVector()`，以产品域语义别名、中文 2/3-gram、英文 / 数字 token 组成本地向量。
- 使用 `cosineSimilarity()` 计算相似度；当前阈值为 `0.22`，低于阈值的消息不进入结果。
- 语义命中会写入 `_MessageHit.semanticScore`，并在最终分数中加入 `semanticScore * 32`，与 FTS 分数、关键词覆盖和基础消息分共同排序。
- 纯语义命中没有关键词 token 时，摘要前缀显示 `语义匹配：`，方便用户区分“近义命中”和“字面命中”。
- 设置页“本地搜索索引”已升级为 SQLite FTS + 本地语义索引统一检查 / 预热 / 修复，并明确不上传搜索词、消息内容、语义向量或文件路径。
- 设置页同一弹窗提供“启用本地语义搜索”开关；关闭后不会读取 `message_semantic_index` 做语义召回，但仍可保留索引维护能力，方便用户随时重新开启。

边界：

- 这是持久化的本地轻量语义索引，不是模型 embedding，也不是真正向量数据库 / ANN。
- 当前向量 JSON 仍需在搜索时本机读取并逐条计算相似度；长会话规模变大后需引入更高效的向量检索结构、增量维护和清理策略。
- 后续仍需设计模型 embedding、可选本地 / 远端 embedding provider、索引压缩 / 清理、真机长会话性能基线和用户可控开关。

### 5.2 SQLite FTS + 本地语义索引健康检查与预热

当前维护能力：

- `MessageFtsIndexHealth` 返回索引可用性、原始消息数、已索引行数、一致性、是否重建、耗时和脱敏失败原因。
- `MessageSemanticIndexHealth` 返回语义索引可用性、原始消息数、已索引行数、缺失 / 过期行、多余行、是否重建、耗时和失败原因。
- `checkMessageFtsIndexHealth()` / `checkMessageSemanticIndexHealth()` 只创建必要索引对象并读取健康状态；不自动修复，适合设置页检查。
- `prewarmMessageFtsIndex()` 会创建 FTS 对象、对比 `message_type = original` 原始消息数与 `messages_fts` 行数，并在不一致时重建索引。
- `prewarmMessageSemanticIndex()` 会创建 `message_semantic_index`，为全部原始消息生成本地语义向量，并在内容哈希不一致或行数不一致时重建索引。
- insert / update / delete 触发器继续维护后续原始消息变更；`summary`、`model_switch` 等非原始消息不进入 FTS。
- 语义索引不靠 SQLite 触发器生成向量；`MessageDao.insertMessage()` / `deleteMessage()` 会在主写入 / 删除路径同步维护语义索引，历史数据、外部修改或异常状态可通过检查发现缺失 / 过期，再由预热 / 修复重建。
- 设置页入口只展示数量、状态和耗时，不展示搜索词、消息正文、语义向量、完整本地路径或密钥。
- `scripts/benchmark_search_index.sh` 运行 `test/search_index_benchmark.dart`，用于记录本地搜索索引在 2000 条消息下的插入、FTS 预热、语义索引预热和搜索耗时。

## 6. 无限上下文

当前滚动压缩继续保留，但需要加强：

- 摘要必须包含事实、偏好、任务、决策、未完成事项。
- 摘要和 Key Points 分离：摘要服务单会话上下文，Key Points 服务跨会话长期记忆。
- 压缩后保留可追溯 sourceMessageIds。

## 7. 测试要求

- Markdown 追加格式测试。
- SQLite 与 Markdown 重建一致性测试。
- Key Points 提取结果结构测试。
- 敏感内容跳过测试：API Key / 密码 / token 等不能写入记忆。
- 记忆 Provider 持久化与去重测试。
- 检索排序测试。
- Key Points 本地语义向量召回测试：移动端 / 手机端、本地 / 隐私、Dreaming 等近义表达可召回相关记忆，低相关记忆不应排到前面。
- 上下文系统提示词注入测试。
- 本地全文检索测试：多关键词消息命中、模型切换记录过滤、Key Points 记忆命中、通配符字符清理、SQLite FTS 命中、历史消息语义命中、超过最近 500 条后仍可语义命中。
- 本地语义搜索开关测试：设置持久化、设置页切换、关闭后不再返回纯语义消息命中。
- SQLite FTS 维护测试：历史消息索引缺失可检测、预热 / 修复后行数一致、触发器继续维护新增消息、设置页可手动预热 / 修复。
- 本地语义索引维护测试：语义索引缺失可检测、预热后行数一致、新增消息后能发现缺失 / 过期、设置页可统一预热 / 修复。
- 搜索索引性能基线：2000 条消息下记录插入、FTS 预热、语义索引预热、搜索耗时和索引健康状态。
- Key Points 语义召回性能基线：5000 条 Key Points、20 次召回的总耗时和平均耗时。
- 历史消息语义检索性能观察：在 2000 条消息搜索索引基线中记录语义索引预热和整体搜索耗时；后续完整向量索引前需补真机长会话专项基线。
- 长会话上下文构建性能测试。
- 用户数据不进入仓库、不进入日志的安全测试。

## 8. 近期 TODO

- [x] 新增 MarkdownConversationArchive 服务。
- [x] 新增 Key Points v1 数据结构、启发式提取、SharedPreferences 本地持久化和关键词召回。
- [x] 新增 Key Points 本地语义向量召回 v1：语义别名、中文 n-gram、cosine similarity 和性能基线脚本。
- [ ] 稳定后新增 MemoryPoint 表和 DAO，并迁移 SharedPreferences 记忆数据。
- [x] 实现 SQLite → Markdown 重建基础服务能力。
- [x] 实现 SQLite ↔ Markdown 一致性校验基础能力。
- [x] 实现 Markdown 标题同步基础能力。
- [x] 暴露 SQLite → Markdown 手动修复入口、异常修复队列和一键重试修复。
- [x] 先做轻量关键词召回并注入系统提示词。
- [x] 本地全文检索 v1：标题 / 消息 / Key Points 统一召回和排序。
- [x] 历史消息本地语义检索 v1：全局搜索基于本地语义向量和 cosine similarity 做近义召回。
- [x] 本地消息语义索引 v1：`message_semantic_index` 持久化全部原始消息的内容哈希和轻量语义向量 JSON，设置页可检查 / 预热 / 修复。
- [x] 本地语义搜索用户开关 v1：设置页可关闭 / 开启语义消息召回，关闭后仅保留字面检索路径。
- [x] 接入 SQLite FTS 全文检索 v1：按需建表、触发器同步、历史补建和 LIKE 回退。
- [x] 完善 SQLite FTS 手动健康检查、预热 / 修复入口和 2000 条消息性能基线。
- [x] Dreaming 本地整理 v1：手动生成日报、会话摘要、关键词和记忆候选。
- [x] Dreaming 前台到期调度 v1：默认 22:00、可配置时间、到期前台自动整理当天一次。
- [ ] 接入 SQLite FTS 后台周期预热与真机长会话性能基线。
- [ ] 接入完整对话向量检索：模型 embedding、真正向量数据库 / ANN、增量维护优化、用户可控开关和真机长会话基线。
