import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/skills/skill.dart';
import '../../core/skills/skill_hub_repository.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/skill_provider.dart';

/// 打开 Skills Hub 全屏页面
void showSkillsHubSheet(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const SkillsHubPage()),
  );
}

class SkillsHubPage extends ConsumerStatefulWidget {
  const SkillsHubPage({super.key});

  @override
  ConsumerState<SkillsHubPage> createState() => _SkillsHubPageState();
}

class _SkillsHubPageState extends ConsumerState<SkillsHubPage> {
  final _importController = TextEditingController();
  final _hubSearchController = TextEditingController();
  bool _importing = false;
  final Set<String> _importingSlugs = {};

  @override
  void initState() {
    super.initState();
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

  void _searchHub() {
    ref.read(skillHubSearchProvider.notifier).search(
          keyword: _hubSearchController.text,
        );
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final skillsAsync = ref.watch(skillsProvider);
    final searchState = ref.watch(skillHubSearchProvider);
    final screenWidth = MediaQuery.of(context).size.width;

    // 响应式列数：根据屏幕宽度自适应
    final crossAxisCount = screenWidth > 1200 ? 4 : screenWidth > 800 ? 3 : 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Skills 市场'),
        actions: [
          TextButton.icon(
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
            icon: const Icon(Icons.link, size: 16),
            label: const Text('skillhub.cn'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              // ─── 搜索栏 ───
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.travel_explore_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '浏览 SkillHub 目录',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _hubSearchController,
                              decoration: InputDecoration(
                                hintText: '搜索 skills...',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                prefixIcon: const Icon(Icons.search, size: 20),
                              ),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _searchHub(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed:
                                searchState.isLoading ? null : _searchHub,
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ─── URL 导入 ───
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _importController,
                      decoration: InputDecoration(
                        hintText: '粘贴 SKILL.md URL（GitHub raw / 直链）',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
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
                ],
              ),
              const SizedBox(height: 24),

              // ─── SkillHub 搜索结果 ───
              if (searchState.result != null) ...[
                Text(
                  searchState.result!.keyword.isEmpty
                      ? '热门 Skills（${searchState.result!.total}）'
                      : '"${searchState.result!.keyword}"（${searchState.result!.total} 个结果）',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisExtent: 160,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: searchState.result!.skills.length,
                  itemBuilder: (_, index) {
                    final s = searchState.result!.skills[index];
                    return _SkillHubCard(
                      summary: s,
                      importing: _importingSlugs.contains(s.slug),
                      onImport: () => _importFromHub(s),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],

              // ─── 已导入 Skills ───
              Text(
                '已导入 Skills',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              skillsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text('加载失败：$e')),
                ),
                data: (skills) {
                  if (skills.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.extension_off_outlined,
                                size: 48, color: scheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              '还没有导入任何 Skill',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisExtent: 140,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: skills.length,
                    itemBuilder: (_, index) {
                      final skill = skills[index];
                      return _SkillCard(
                        skill: skill,
                        onToggle: (enabled) =>
                            _toggleSkill(skill.id, enabled),
                        onDelete: () => _deleteSkill(skill.id),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// SkillHub 搜索结果卡片（网格项）
class _SkillHubCard extends StatelessWidget {
  const _SkillHubCard({
    required this.summary,
    required this.importing,
    required this.onImport,
  });

  final SkillHubSkillSummary summary;
  final bool importing;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metadata = [
      if (summary.ownerName.isNotEmpty) '@${summary.ownerName}',
      if (summary.category.isNotEmpty) summary.category,
      if (summary.version.isNotEmpty) 'v${summary.version}',
    ].join(' · ');

    final stats = [
      '${_compactCount(summary.downloads)} 下载',
      '${_compactCount(summary.stars)} 星',
      if (summary.requiresApiKey) '需要 API key',
    ].join(' · ');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.extension_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                summary.description.isNotEmpty
                    ? summary.description
                    : '暂无描述',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (metadata.isNotEmpty) ...[
              Text(metadata,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
            ],
            if (stats.isNotEmpty) ...[
              Text(stats,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: importing ? null : onImport,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  importing ? '导入中...' : '导入',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已导入 Skill 卡片（网格项）
class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.onToggle,
    required this.onDelete,
  });

  final Skill skill;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: skill.isEnabled ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  skill.isEnabled
                      ? Icons.check_circle_outline
                      : Icons.circle_outlined,
                  size: 18,
                  color: skill.isEnabled ? Colors.green : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    skill.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: skill.isEnabled ? null : scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                skill.description.isNotEmpty ? skill.description : '暂无描述',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (skill.sha256Verified) ...[
              Row(
                children: [
                  Icon(Icons.verified, size: 12, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text('SHA-256 已验证',
                      style: TextStyle(fontSize: 11, color: scheme.primary)),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Switch(
                  value: skill.isEnabled,
                  onChanged: onToggle,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: scheme.error),
                  onPressed: onDelete,
                  tooltip: '删除',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _compactCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
