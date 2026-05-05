import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final sessionDaoProvider = Provider((ref) => ref.watch(databaseProvider).sessionDao);
final messageDaoProvider = Provider((ref) => ref.watch(databaseProvider).messageDao);
final channelDaoProvider = Provider((ref) => ref.watch(databaseProvider).channelDao);
final folderDaoProvider = Provider((ref) => ref.watch(databaseProvider).folderDao);
final attachmentDaoProvider = Provider((ref) => ref.watch(databaseProvider).attachmentDao);
final promptDaoProvider = Provider((ref) => ref.watch(databaseProvider).promptDao);
