import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/prompt_dao.dart';
import 'database_provider.dart';

const _uuid = Uuid();

/// 所有提示词模板
final promptsProvider =
    FutureProvider<List<Prompt>>((ref) {
  return ref.watch(promptDaoProvider).getAllPrompts();
});

/// 提示词操作
class PromptNotifier extends StateNotifier<AsyncValue<List<Prompt>>> {
  final PromptDao _dao;

  PromptNotifier(this._dao) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = AsyncValue.data(await _dao.getAllPrompts());
  }

  Future<void> addPrompt({
    required String name,
    required String content,
    String category = 'general',
  }) async {
    await _dao.insertPrompt(
      id: _uuid.v4(),
      name: name,
      content: content,
      category: category,
    );
    await _load();
  }

  Future<void> updatePrompt({
    required String id,
    required String name,
    required String content,
    String? category,
  }) async {
    await _dao.updatePrompt(
      id: id,
      name: name,
      content: content,
      category: category,
    );
    await _load();
  }

  Future<void> deletePrompt(String id) async {
    await _dao.deletePrompt(id);
    await _load();
  }
}

final promptNotifierProvider =
    StateNotifierProvider<PromptNotifier, AsyncValue<List<Prompt>>>((ref) {
  return PromptNotifier(ref.watch(promptDaoProvider));
});
