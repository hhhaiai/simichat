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
import 'dao/dreaming_dao.dart';
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
    DreamingJobs,
    DreamingReports,
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
    DreamingDao,
    PromptDao,
    McpDao,
    SkillDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

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
      if (from < 6) {
        // 重建 Sessions 和 Messages 表以添加外键级联规则
        // SQLite 不支持 ALTER TABLE 修改外键，需要重建表
        await customStatement('PRAGMA foreign_keys = OFF');

        // 重建 Sessions 表
        await customStatement('ALTER TABLE sessions RENAME TO sessions_old');
        await m.createTable(sessions);
        await customStatement(
          'INSERT INTO sessions SELECT * FROM sessions_old',
        );
        await customStatement('DROP TABLE sessions_old');

        // 重建 Messages 表
        await customStatement('ALTER TABLE messages RENAME TO messages_old');
        await m.createTable(messages);
        await customStatement(
          'INSERT INTO messages SELECT * FROM messages_old',
        );
        await customStatement('DROP TABLE messages_old');

        await customStatement('PRAGMA foreign_keys = ON');
      }
      if (from < 7) {
        await m.createTable(dreamingJobs);
        await m.createTable(dreamingReports);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'ai_chat', 'db.sqlite'));
    file.parent.createSync(recursive: true);
    return NativeDatabase.createInBackground(
      file,
      setup: (db) {
        db.execute('PRAGMA foreign_keys = ON');
      },
    );
  });
}
