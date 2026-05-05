import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/skills/skill.dart';
import '../../core/skills/skill_hub_repository.dart';
import 'database_provider.dart';

/// SkillHub 仓库实例
final skillHubRepositoryProvider = Provider<SkillHubRepository>((ref) {
  return SkillHubRepository();
});

/// 所有本地 Skills（数据库 + 线上已导入）
final skillsProvider = FutureProvider<List<Skill>>((ref) async {
  final dbSkills = await ref.watch(skillDaoProvider).getAllSkills();
  return dbSkills
      .map((s) => Skill(
            id: s.id,
            name: s.name,
            description: s.description,
            instructions: s.instructions,
            sourceUrl: s.sourceUrl,
            sourceSha256: s.sourceSha256,
            sha256Verified: s.sha256Verified,
            online: s.online,
            isEnabled: s.isEnabled,
            createdAt: s.createdAt,
          ))
      .toList();
});

/// 已启用的 Skills（注入 system prompt）
final enabledSkillsProvider = FutureProvider<List<Skill>>((ref) async {
  final dbSkills = await ref.watch(skillDaoProvider).getEnabledSkills();
  return dbSkills
      .map((s) => Skill(
            id: s.id,
            name: s.name,
            description: s.description,
            instructions: s.instructions,
            sourceUrl: s.sourceUrl,
            sourceSha256: s.sourceSha256,
            sha256Verified: s.sha256Verified,
            online: s.online,
            isEnabled: s.isEnabled,
            createdAt: s.createdAt,
          ))
      .toList();
});

/// SkillHub 搜索状态
class SkillHubSearchState {
  const SkillHubSearchState({
    this.result,
    this.isLoading = false,
    this.error,
  });

  final SkillHubSearchResult? result;
  final bool isLoading;
  final String? error;

  SkillHubSearchState copyWith({
    SkillHubSearchResult? result,
    bool? isLoading,
    String? error,
  }) {
    return SkillHubSearchState(
      result: result ?? this.result,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// SkillHub 搜索 Notifier
class SkillHubSearchNotifier extends StateNotifier<SkillHubSearchState> {
  SkillHubSearchNotifier(this._repository) : super(const SkillHubSearchState());

  final SkillHubRepository _repository;

  Future<void> search({String keyword = ''}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.searchSkillHub(keyword: keyword);
      state = SkillHubSearchState(result: result);
    } on SkillImportException catch (e) {
      state = SkillHubSearchState(error: e.message);
    } catch (e) {
      state = SkillHubSearchState(error: '搜索失败：$e');
    }
  }
}

final skillHubSearchProvider =
    StateNotifierProvider<SkillHubSearchNotifier, SkillHubSearchState>((ref) {
  final repo = ref.watch(skillHubRepositoryProvider);
  return SkillHubSearchNotifier(repo);
});

/// 安装 Skill 到数据库
Future<void> installSkill(WidgetRef ref, Skill skill) async {
  final dao = ref.read(skillDaoProvider);
  await dao.insertSkill(
    id: skill.id,
    name: skill.name,
    description: skill.description,
    instructions: skill.instructions,
    sourceUrl: skill.sourceUrl,
    sourceSha256: skill.sourceSha256,
    sha256Verified: skill.sha256Verified,
    online: skill.online,
    isEnabled: true,
  );
  ref.invalidate(skillsProvider);
  ref.invalidate(enabledSkillsProvider);
}

/// 切换 Skill 启用状态
Future<void> toggleSkill(WidgetRef ref, String skillId, bool enabled) async {
  await ref.read(skillDaoProvider).toggleEnabled(skillId, enabled);
  ref.invalidate(skillsProvider);
  ref.invalidate(enabledSkillsProvider);
}

/// 卸载在线 Skill
Future<void> uninstallSkill(WidgetRef ref, String skillId) async {
  await ref.read(skillDaoProvider).deleteSkill(skillId);
  ref.invalidate(skillsProvider);
  ref.invalidate(enabledSkillsProvider);
}
