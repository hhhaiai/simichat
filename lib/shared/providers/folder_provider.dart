import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import 'database_provider.dart';

/// 所有文件夹
final foldersProvider = FutureProvider<List<Folder>>((ref) async {
  final dao = ref.read(folderDaoProvider);
  return dao.getAllFolders();
});

/// 刷新文件夹列表
void refreshFolders(WidgetRef ref) {
  ref.invalidate(foldersProvider);
}
