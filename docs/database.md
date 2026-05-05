# 数据库设计

使用 `drift`（SQLite ORM），支持全平台。

## 表结构

### model_channels（模型渠道）

```sql
CREATE TABLE model_channels (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  base_url TEXT NOT NULL,
  api_key_encrypted TEXT NOT NULL,
  protocol TEXT NOT NULL,   -- openai_chat | openai_response | claude | gemini
  is_enabled INTEGER NOT NULL DEFAULT 1,
  is_default INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
```

### channel_models（渠道下的模型）

```sql
CREATE TABLE channel_models (
  id TEXT PRIMARY KEY,
  channel_id TEXT NOT NULL REFERENCES model_channels(id) ON DELETE CASCADE,
  model_name TEXT NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0
);
```

### folders（文件夹）

```sql
CREATE TABLE folders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL DEFAULT 'local',
  name TEXT NOT NULL,
  ai_summary TEXT,
  last_summarized_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

### sessions（会话）

```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL DEFAULT 'local',
  title TEXT,                          -- AI 抽取的议题，初始为 null
  folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
  default_channel_model_id TEXT REFERENCES channel_models(id),
  total_tokens INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_message_at INTEGER NOT NULL
);
```

### messages（消息）

```sql
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  role TEXT NOT NULL,                  -- user | assistant | system
  content TEXT NOT NULL,
  thinking_content TEXT,               -- 深度思考内容
  message_type TEXT NOT NULL DEFAULT 'original',  -- original | summary
  summary_start_id TEXT,               -- summary 覆盖起始消息 ID
  summary_end_id TEXT,                 -- summary 覆盖结束消息 ID
  is_summarized INTEGER NOT NULL DEFAULT 0,
  channel_model_id TEXT REFERENCES channel_models(id),
  tokens INTEGER NOT NULL DEFAULT 0,
  response_ms INTEGER,
  created_at INTEGER NOT NULL
);

CREATE INDEX idx_messages_session ON messages(session_id, created_at);
CREATE INDEX idx_messages_unsummarized ON messages(session_id, is_summarized, message_type);
```

### attachments（附件）

```sql
CREATE TABLE attachments (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  file_type TEXT NOT NULL,             -- image | pdf | document
  local_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
```

## DAO 职责划分

| DAO | 职责 |
|-----|------|
| `SessionDao` | CRUD 会话，更新 title/last_message_at/total_tokens |
| `MessageDao` | 插入消息，查询 summary 列表，查询未压缩 original，批量标记 is_summarized |
| `ChannelDao` | CRUD 渠道和模型 |
| `FolderDao` | CRUD 文件夹，更新 ai_summary |
| `AttachmentDao` | 插入/查询附件 |
