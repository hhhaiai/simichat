import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';
import 'dao/session_dao.dart';
import 'dao/message_dao.dart';
import 'dao/channel_dao.dart';
import 'dao/folder_dao.dart';
import 'dao/attachment_dao.dart';
import 'dao/prompt_dao.dart';
import 'dao/mcp_dao.dart';
import 'dao/skill_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    ModelChannels,
    ChannelModels,
    Folders,
    Sessions,
    Messages,
    Attachments,
    Prompts,
    McpServers,
    Skills,
  ],
  daos: [
    SessionDao,
    MessageDao,
    ChannelDao,
    FolderDao,
    AttachmentDao,
    PromptDao,
    McpDao,
    SkillDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(prompts);
      }
      if (from < 3) {
        await m.addColumn(channelModels, channelModels.capability);
      }
      if (from < 4) {
        await m.createTable(mcpServers);
      }
      if (from < 5) {
        await m.createTable(skills);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'ai_chat', 'db.sqlite'));
    file.parent.createSync(recursive: true);
    return NativeDatabase.createInBackground(file);
  });
}
