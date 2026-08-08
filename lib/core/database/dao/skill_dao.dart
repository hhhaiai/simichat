import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'skill_dao.g.dart';

@DriftAccessor(tables: [Skills])
class SkillDao extends DatabaseAccessor<AppDatabase> with _$SkillDaoMixin {
  SkillDao(super.db);

  Future<List<Skill>> getAllSkills() {
    return (select(skills)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  Future<List<Skill>> getEnabledSkills() {
    return (select(skills)
          ..where((t) => t.isEnabled.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<Skill?> getSkill(String id) {
    return (select(skills)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Skill?> getSkillByName(String name) {
    return (select(
      skills,
    )..where((t) => t.name.equals(name))).getSingleOrNull();
  }

  Future<int> insertSkill({
    required String id,
    required String name,
    required String description,
    required String instructions,
    String? sourceUrl,
    String? sourceSha256,
    bool sha256Verified = false,
    bool online = false,
    bool isEnabled = true,
  }) {
    return into(skills).insert(
      SkillsCompanion.insert(
        id: id,
        name: name,
        description: Value(description),
        instructions: instructions,
        sourceUrl: Value(sourceUrl),
        sourceSha256: Value(sourceSha256),
        sha256Verified: Value(sha256Verified),
        online: Value(online),
        isEnabled: Value(isEnabled),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Installs a mobile Skill idempotently. Marketplace retries and app
  /// restarts must not turn a valid package into a duplicate-key failure.
  Future<int> upsertSkill({
    required String id,
    required String name,
    required String description,
    required String instructions,
    String? sourceUrl,
    String? sourceSha256,
    bool sha256Verified = false,
    bool online = false,
    bool isEnabled = true,
  }) {
    return into(skills).insertOnConflictUpdate(
      SkillsCompanion.insert(
        id: id,
        name: name,
        description: Value(description),
        instructions: instructions,
        sourceUrl: Value(sourceUrl),
        sourceSha256: Value(sourceSha256),
        sha256Verified: Value(sha256Verified),
        online: Value(online),
        isEnabled: Value(isEnabled),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> updateSkill({
    required String id,
    String? name,
    String? description,
    String? instructions,
    bool? isEnabled,
  }) {
    return (update(skills)..where((t) => t.id.equals(id))).write(
      SkillsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        description: description != null
            ? Value(description)
            : const Value.absent(),
        instructions: instructions != null
            ? Value(instructions)
            : const Value.absent(),
        isEnabled: isEnabled != null ? Value(isEnabled) : const Value.absent(),
      ),
    );
  }

  Future<void> toggleEnabled(String id, bool enabled) {
    return (update(skills)..where((t) => t.id.equals(id))).write(
      SkillsCompanion(isEnabled: Value(enabled)),
    );
  }

  Future<void> deleteSkill(String id) {
    return (delete(skills)..where((t) => t.id.equals(id))).go();
  }
}
