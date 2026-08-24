import 'package:drift/drift.dart';

class ModelChannels extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get apiKeyEncrypted => text()();
  TextColumn get protocol =>
      text()(); // openai_chat | openai_response | claude | gemini
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class ChannelModels extends Table {
  TextColumn get id => text()();
  TextColumn get channelId =>
      text().references(ModelChannels, #id, onDelete: KeyAction.cascade)();
  TextColumn get modelName => text()();
  TextColumn get capability =>
      text().withDefault(const Constant('chat'))(); // chat | embedding
  /// JSON array of all declared capabilities returned by the provider. The
  /// legacy `capability` column remains the primary selector value so older
  /// snapshots and callers stay compatible.
  TextColumn get capabilities => text().withDefault(const Constant('[]'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().withDefault(const Constant('local'))();
  TextColumn get name => text()();
  TextColumn get aiSummary => text().nullable()();
  IntColumn get lastSummarizedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().withDefault(const Constant('local'))();
  TextColumn get title => text().nullable()();
  TextColumn get folderId =>
      text().nullable().references(Folders, #id, onDelete: KeyAction.setNull)();
  TextColumn get defaultChannelModelId => text().nullable().references(
    ChannelModels,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get totalTokens => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get lastMessageAt => integer()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()(); // user | assistant | system
  TextColumn get content => text()();
  TextColumn get thinkingContent => text().nullable()();
  TextColumn get messageType => text().withDefault(
    const Constant('original'),
  )(); // original | summary | model_switch
  TextColumn get summaryStartId => text().nullable()();
  TextColumn get summaryEndId => text().nullable()();
  BoolColumn get isSummarized => boolean().withDefault(const Constant(false))();
  TextColumn get channelModelId => text().nullable().references(
    ChannelModels,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get tokens => integer().withDefault(const Constant(0))();
  IntColumn get responseMs => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [];
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get messageId =>
      text().references(Messages, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileType => text()(); // image | pdf | audio | document
  TextColumn get localPath => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class DreamingJobs extends Table {
  TextColumn get id => text()();
  TextColumn get dayKey => text()();
  IntColumn get scheduledFor => integer()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get trigger => text().withDefault(const Constant('foreground'))();
  IntColumn get messageLimit => integer().withDefault(const Constant(5000))();
  IntColumn get startedAt => integer().nullable()();
  IntColumn get finishedAt => integer().nullable()();
  TextColumn get error => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class DreamingReports extends Table {
  TextColumn get id => text()();
  TextColumn get dayKey => text()();
  TextColumn get jobId => text().nullable().references(
    DreamingJobs,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get generatedAt => integer()();
  TextColumn get markdown => text()();
  TextColumn get digestJson => text()();
  IntColumn get sessionCount => integer()();
  IntColumn get originalMessageCount => integer()();
  IntColumn get totalOriginalMessageCount => integer()();
  IntColumn get memoryCandidateCount => integer()();
  BoolColumn get isTruncated => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {dayKey},
  ];
}

class PersonaAuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get eventType => text()(); // authorize | revoke | persona_reply
  TextColumn get sessionId => text().nullable().references(
    Sessions,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get messageId => text().nullable()();
  TextColumn get summary => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [];
}

class Prompts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get content => text()();
  TextColumn get category => text().withDefault(const Constant('general'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Skills extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get instructions => text()();
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get sourceSha256 => text().nullable()();
  BoolColumn get sha256Verified =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get online => boolean().withDefault(const Constant(false))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class McpServers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get transport => text()(); // 'app_native' | 'stdio' | 'sse'
  TextColumn get command => text().nullable()();
  TextColumn get args => text().nullable()(); // JSON array string
  TextColumn get url => text().nullable()();
  TextColumn get headers => text().nullable()(); // JSON map string
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get source => text().withDefault(
    const Constant('manual'),
  )(); // 'manual' | 'marketplace'
  TextColumn get marketplaceId => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 可恢复的超长文本分批任务。
///
/// 原始正文保留在已归档的附件文件中；此表只保存附件引用、无凭据请求
/// 快照、chunk 执行状态和中间结果，避免把每一段伪装成普通聊天消息。
class ChunkedContentTasks extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get sourceMessageId => text()();
  TextColumn get sourceAttachmentId => text()();
  TextColumn get originalPrompt => text()();
  TextColumn get channelModelId => text()();
  TextColumn get providerId => text()();
  TextColumn get strategy => text()(); // mapReduce | orderedTransform
  TextColumn get requestSnapshot => text()(); // credential-free JSON
  TextColumn get status => text()();
  TextColumn get phase => text()();
  IntColumn get totalChunks => integer().withDefault(const Constant(0))();
  IntColumn get completedChunks => integer().withDefault(const Constant(0))();
  TextColumn get chunkResults => text().withDefault(const Constant('[]'))();
  TextColumn get retryMetadata => text().withDefault(const Constant('{}'))();
  TextColumn get finalResponseMessageId => text().nullable()();
  TextColumn get error => text().nullable()();
  TextColumn get leaseId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 可恢复的图片 / 视频 / 音乐异步任务。
///
/// 这里只保存重新定位服务端任务所需的元数据，不保存 API Key、授权头或
/// 媒体二进制。媒体结果落盘后只记录应用私有路径和 MIME 元数据。
class MediaJobs extends Table {
  /// 本地 operation id；没有独立 operation id 时使用服务端 job id 的本地标识。
  TextColumn get id => text()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get kind => text()(); // image | video | music
  TextColumn get provider => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get endpoint => text().nullable()();
  TextColumn get status =>
      text()(); // pending | running | completed | failed | expired | cancelled
  IntColumn get progress => integer().nullable()(); // 0..100
  TextColumn get phase => text().nullable()();
  TextColumn get requestUrl => text().nullable()();
  TextColumn get providerJobId => text().nullable()();
  TextColumn get requestId => text().nullable()();
  TextColumn get pollUrl => text().nullable()();
  TextColumn get cancelUrl => text().nullable()();
  TextColumn get contentUrl => text().nullable()();
  TextColumn get assetPath => text().nullable()();
  TextColumn get assetMime => text().nullable()();
  TextColumn get assetExtension => text().nullable()();
  TextColumn get prompt => text().nullable()();
  TextColumn get error => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deadline => integer().nullable()();
  TextColumn get endpointStyle => text().nullable()();

  /// 当前 running worker 的不透明所有者 token；不包含凭据或授权信息。
  TextColumn get leaseId => text().nullable()();

  /// 提交时实际选中的聊天模型。它只是一条不可歧义的渠道引用，不是
  /// 凭据；即使用户后来切换默认模型，恢复任务仍按这条引用重建路由。
  TextColumn get channelModelId => text().nullable()();

  /// 本地会话交付的幂等键。所有 ID 都在提交前生成并持久化，恢复时只
  /// 能复用这些 ID，不能重新随机生成第二套消息 / 附件。
  TextColumn get deliveryUserMessageId => text().nullable()();
  TextColumn get deliveryAssistantMessageId => text().nullable()();
  TextColumn get deliveryAttachmentId => text().nullable()();
  TextColumn get deliverySourceAttachmentId => text().nullable()();
  TextColumn get deliveryPhase => text().nullable()();
  TextColumn get deliveryUserContent => text().nullable()();
  TextColumn get deliveryAssistantContent => text().nullable()();
  TextColumn get deliveryFileType => text().nullable()();
  TextColumn get deliverySourcePath => text().nullable()();
  TextColumn get deliverySourceFileName => text().nullable()();
  TextColumn get deliverySourceFileType => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
