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
  TextColumn get defaultChannelModelId =>
      text().nullable().references(ChannelModels, #id)();
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
  TextColumn get messageType =>
      text().withDefault(const Constant('original'))(); // original | summary
  TextColumn get summaryStartId => text().nullable()();
  TextColumn get summaryEndId => text().nullable()();
  BoolColumn get isSummarized => boolean().withDefault(const Constant(false))();
  TextColumn get channelModelId =>
      text().nullable().references(ChannelModels, #id)();
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
  TextColumn get fileType => text()(); // image | pdf | document
  TextColumn get localPath => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
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
