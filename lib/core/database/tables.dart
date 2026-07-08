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
