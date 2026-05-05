import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/skills/skill.dart';
import '../../core/skills/skill_hub_repository.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/skill_provider.dart';

/// 打开 Skills Hub 底部弹出 sheet
Future<void> showSkillsHubSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SkillsHubSheet(),
  );
}

class _SkillsHubSheet extends ConsumerStatefulWidget {
  const _SkillsHubSheet();

  @override
  ConsumerState<_SkillsHubSheet> createState() => _SkillsHubSheetState();
}

class _SkillsHubSheetState extends ConsumerState<_SkillsHubSheet> {
  final _importController = TextEditingController();
  final _hubSearchController = TextEditingController();
  bool _importing = false;
  final Set<String> _importingSlugs = {};

  @override
  void initState() {
    super.initState();
    // 自动加载市场
    Future.microtask(() {
      ref.read(skillHubSearchProvider.notifier).search();
    });
  }

  @override
  void dispose() {
    _importController.dispose();
    _hubSearchController.dispose();
    super.dispose();
  }

  // ─── 导入操作 ───

  Future<void> _importFromUrl() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final repo = ref.read(skillHubRepositoryProvider);
      final skill = await repo.importFromUrl(_importController.text);
      await _saveSkillToDb(skill);
      if (!mounted) return;
      _importController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入：${skill.name}')),
      );
    } on SkillImportException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromHub(SkillHubSkillSummary summary) async {
    if (_importingSlugs.contains(summary.slug)) return;
    setState(() => _importingSlugs.add(summary.slug));
    try {
      final repo = ref.read(skillHubRepositoryProvider);
      final skill = await repo.importSkillHubSkill(summary.slug);
      await _saveSkillToDb(skill);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已从 SkillHub 导入：${skill.name}')),
      );
    } on SkillImportException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importingSlugs.remove(summary.slug));
    }
  }

  Future<void> _saveSkillToDb(Skill skill) async {
    final dao = ref.read(skillDaoProvider);
    final existing = await dao.getSkillByName(skill.name);
    if (existing != null) {
      await dao.updateSkill(
        id: existing.id,
        description: skill.description,
        instructions: skill.instructions,
      );
    } else {
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
    }
    ref.invalidate(skillsProvider);
    ref.invalidate(enabledSkillsProvider);
  }

  Future<void> _toggleSkill(String id, bool enabled) async {
    await ref.read(skillDaoProvider).toggleEnabled(id, enabled);
    ref.invalidate(skillsProvider);
    ref.invalidate(enabledSkillsProvider);
  }

  Future<void> _deleteSkill(String id) async {
    await ref.read(skillDaoProvider).deleteSkill(id);
    ref.invalidate(skillsProvider);
    ref.invalidate(enabledSkillsProvider);
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final skillsAsync = ref.watch(skillsProvider);
    final searchState = ref.watch(skillHubSearchProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomInset),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.86,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            children: [
              // ─── 标题 ───
              Row(
                children: [
                  Icon(Icons.extension_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Skills 市场',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '从 SkillHub.cn 搜索并导入 Skills，导入后注入到系统提示词中使用。',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              // ─── SkillHub 搜索区 ───
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.travel_explore_outlined, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '浏览 SkillHub 目录',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Clipboard.setData(const ClipboardData(
                                text: SkillHubRepository.skillHubHomeUrl,
                              ));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已复制 SkillHub.cn 链接'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Text('skillhub.cn'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _hubSearchController,
                              decoration: InputDecoration(
                                hintText: '搜索 skills...',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _searchHub(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: searchState.isLoading ? null : _searchHub,
                            child: searchState.isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('搜索'),
                          ),
                        ],
                      ),
                      if (searchState.error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          searchState.error!,
                          style: TextStyle(
                            color: scheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (searchState.result != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          searchState.result!.keyword.isEmpty
                              ? '热门：${searchState.result!.total} 个 skills'
                              : '"${searchState.result!.keyword}"：${searchState.result!.total} 个结果',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        for (final s in searchState.result!.skills.take(10))
                          _SkillHubTile(
                            summary: s,
                            importing: _importingSlugs.contains(s.slug),
                            onImport: () => _importFromHub(s),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ─── URL 导入 ───
              TextField(
                controller: _importController,
                decoration: InputDecoration(
                  hintText: '粘贴 SKILL.md URL（GitHub raw / 直链）',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _importing ? null : _importFromUrl,
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 18),
                  label: Text(_importing ? '导入中...' : '从 URL 导入'),
                ),
              ),
              const SizedBox(height: 18),

              // ─── 已导入 Skills ───
              Text(
                '已导入 Skills',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              skillsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('加载失败：$e'),
                ),
                data: (skills) {
                  if (skills.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          '还没有导入任何 Skill',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final skill in skills)
                        _SkillTile(
                          skill: skill,
                          onToggle: (enabled) =>
                              _toggleSkill(skill.id, enabled),
                          onDelete: () => _deleteSkill(skill.id),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _searchHub() {
    ref.read(skillHubSearchProvider.notifier).search(
          keyword: _hubSearchController.text,
        );
  }
}

/// SkillHub 搜索结果条目
class _SkillHubTile extends StatelessWidget {
  const _SkillHubTile({
    required this.summary,
    required this.importing,
    required this.onImport,
  });

  final SkillHubSkillSummary summary;
  final bool importing;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (summary.ownerName.isNotEmpty) '@${summary.ownerName}',
      if (summary.category.isNotEmpty) summary.category,
      if (summary.version.isNotEmpty) 'v${summary.version}',
      '${_compactCount(summary.downloads)} 下载',
      '${_compactCount(summary.stars)} 星',
      if (summary.requiresApiKey) '需要 API key',
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.extension_outlined, size: 22),
      title: Text(summary.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        [if (summary.description.isNotEmpty) summary.description, metadata]
            .join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: TextButton(
        onPressed: importing ? null : onImport,
        child: Text(importing ? '导入中' : '导入'),
      ),
    );
  }
}

/// 已导入 Skill 条目
class _SkillTile extends StatelessWidget {
  const _SkillTile({
    required this.skill,
    required this.onToggle,
    required this.onDelete,
  });

  final Skill skill;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        skill.isEnabled
            ? Icons.check_circle_outline
            : Icons.circle_outlined,
        size: 22,
        color: skill.isEnabled ? Colors.green : null,
      ),
      title: Text(skill.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        [
          skill.description,
          if (skill.online && skill.sourceUrl != null)
            '来源：${skill.sourceUrl}',
          if (skill.sha256Verified) 'SHA-256 已验证',
        ].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: skill.isEnabled,
            onChanged: onToggle,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
            tooltip: '删除',
          ),
        ],
      ),
    );
  }
}

String _compactCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
