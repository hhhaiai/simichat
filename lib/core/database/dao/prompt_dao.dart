import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'prompt_dao.g.dart';

@DriftAccessor(tables: [Prompts])
class PromptDao extends DatabaseAccessor<AppDatabase>
    with _$PromptDaoMixin {
  PromptDao(super.db);

  Future<List<Prompt>> getAllPrompts() {
    return (select(prompts)..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<List<Prompt>> getPromptsByCategory(String category) {
    return (select(prompts)
          ..where((t) => t.category.equals(category))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<Prompt?> getPrompt(String id) {
    return (select(prompts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertPrompt({
    required String id,
    required String name,
    required String content,
    String category = 'general',
  }) {
    return into(prompts).insert(PromptsCompanion.insert(
      id: id,
      name: name,
      content: content,
      category: Value(category),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> updatePrompt({
    required String id,
    required String name,
    required String content,
    String? category,
  }) {
    return (update(prompts)..where((t) => t.id.equals(id))).write(
      PromptsCompanion(
        name: Value(name),
        content: Value(content),
        category: category != null ? Value(category) : const Value.absent(),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> deletePrompt(String id) {
    return (delete(prompts)..where((t) => t.id.equals(id))).go();
  }
}
