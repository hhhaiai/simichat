import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'folder_dao.g.dart';

@DriftAccessor(tables: [Folders])
class FolderDao extends DatabaseAccessor<AppDatabase> with _$FolderDaoMixin {
  FolderDao(super.db);

  Future<List<Folder>> getAllFolders() {
    return (select(folders)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  Future<Folder?> getFolder(String id) {
    return (select(folders)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> createFolder({required String id, required String name}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(folders).insert(FoldersCompanion.insert(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> updateName(String id, String name) {
    return (update(folders)..where((t) => t.id.equals(id))).write(FoldersCompanion(
      name: Value(name),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> updateAiSummary(String id, String summary) {
    return (update(folders)..where((t) => t.id.equals(id))).write(FoldersCompanion(
      aiSummary: Value(summary),
      lastSummarizedAt: Value(DateTime.now().millisecondsSinceEpoch),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> deleteFolder(String id) {
    return (delete(folders)..where((t) => t.id.equals(id))).go();
  }
}
