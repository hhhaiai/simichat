import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../../features/skills/skills_hub_page.dart';
import '../providers/session_provider.dart';
import '../providers/folder_provider.dart';
import '../providers/database_provider.dart';
import '../providers/mcp_provider.dart';
import '../providers/skill_provider.dart';

/// 侧边栏：模型选择器 + 搜索 + 历史会话列表
class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          // 第一行：搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索会话...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(
                  const Duration(milliseconds: 300),
                  () {
                    setState(() => _searchQuery = v);
                  },
                );
              },
            ),
          ),

          // 第二行：文件夹 / MCP / Skills / 设置 / 新建文件夹
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.folder_outlined, size: 20),
                  tooltip: '我的文件夹',
                  onPressed: () => _showFoldersSheet(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.hub_outlined, size: 20),
                  tooltip: 'MCP 市场',
                  onPressed: () => Navigator.pushNamed(context, '/marketplace'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.extension_outlined, size: 20),
                  tooltip: 'Skills Hub',
                  onPressed: () => showSkillsHubSheet(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  tooltip: '设置',
                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                  tooltip: '新建文件夹',
                  onPressed: () => _showCreateFolderDialog(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ),

          _buildWorkspaceStatusSection(),

          // 文件夹列表（可展开）
          _buildFoldersSection(),

          // 历史会话列表
          Expanded(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResults()
                : _buildHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceStatusSection() {
    final mcpServers = ref.watch(mcpManagerProvider);
    final mcpManager = ref.read(mcpManagerProvider.notifier);
    final skillsAsync = ref.watch(skillsProvider);
    final connectedCount = mcpServers
        .where((server) => mcpManager.isConnected(server.id))
        .length;
    final enabledSkillCount =
        skillsAsync.valueOrNull?.where((skill) => skill.isEnabled).length ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _WorkspaceStatusCard(
              icon: Icons.hub_outlined,
              label: 'MCP',
              value: '$connectedCount/${mcpServers.length}',
              color: connectedCount > 0 ? Colors.green : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _WorkspaceStatusCard(
              icon: Icons.extension_outlined,
              label: 'Skills',
              value: enabledSkillCount.toString(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoldersSection() {
    final foldersAsync = ref.watch(foldersProvider);
    final sessionsAsync = ref.watch(sessionsProvider);
    return foldersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (folders) {
        if (folders.isEmpty) return const SizedBox.shrink();
        final sessions = sessionsAsync.valueOrNull ?? [];
        return Column(
          children: [
            const Divider(height: 8),
            for (final f in folders)
              _buildFolderTile(
                f,
                sessions.where((s) => s.folderId == f.id).toList(),
              ),
            const Divider(height: 8),
          ],
        );
      },
    );
  }

  void _showFoldersSheet(BuildContext context) {
    final foldersAsync = ref.read(foldersProvider);
    final folders = foldersAsync.valueOrNull ?? [];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('我的文件夹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showCreateFolderDialog(context);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建'),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (folders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('暂无文件夹', style: TextStyle(color: Colors.grey))),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                itemCount: folders.length,
                itemBuilder: (_, i) {
                  final folderId = folders[i].id;
                  final folderSessions = ref.watch(sessionsProvider).valueOrNull
                          ?.where((s) => s.folderId == folderId)
                          .toList() ??
                      [];
                  return _buildFolderTile(folders[i], folderSessions);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = ref.watch(sessionSearchProvider(_searchQuery));
    return results.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(child: Text('搜索失败: $e')),
      data: (sessions) {
        if (sessions.isEmpty) {
          return const Center(
            child: Text('无搜索结果', style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: sessions.length,
          itemBuilder: (_, i) => _buildSessionTile(sessions[i]),
        );
      },
    );
  }

  Widget _buildHistoryList() {
    final sessionsAsync = ref.watch(sessionsProvider);
    final foldersAsync = ref.watch(foldersProvider);

    return sessionsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (sessions) {
        return foldersAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text('加载失败: $e')),
          data: (folders) {
            // 文件夹 ID 集合（这些会话不显示在日期分组里）
            final folderIds = folders.map((f) => f.id).toSet();
            final unfolderedSessions = sessions.where((s) => s.folderId == null || !folderIds.contains(s.folderId)).toList();

            // 按日期分组（仅限无文件夹的会话）
            final now = DateTime.now();
            final today = <Session>[];
            final yesterday = <Session>[];
            final thisWeek = <Session>[];
            final older = <Session>[];

            for (final s in unfolderedSessions) {
              final dt = DateTime.fromMillisecondsSinceEpoch(s.lastMessageAt);
              final diff = now.difference(dt).inDays;
              if (diff == 0) {
                today.add(s);
              } else if (diff == 1) {
                yesterday.add(s);
              } else if (diff < 7) {
                thisWeek.add(s);
              } else {
                older.add(s);
              }
            }

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                // 日期分组（无文件夹的会话）
                if (today.isNotEmpty) ...[
                  _buildDateHeader('今天'),
                  for (final s in today) _buildSessionTile(s),
                ],
                if (yesterday.isNotEmpty) ...[
                  _buildDateHeader('昨天'),
                  for (final s in yesterday) _buildSessionTile(s),
                ],
                if (thisWeek.isNotEmpty) ...[
                  _buildDateHeader('本周'),
                  for (final s in thisWeek) _buildSessionTile(s),
                ],
                if (older.isNotEmpty) ...[
                  _buildDateHeader('更早'),
                  for (final s in older) _buildSessionTile(s),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  Widget _buildFolderTile(Folder folder, List<Session> folderSessions) {
    return _SimpleExpansionTile(
      key: ValueKey('folder-${folder.id}'),
      title: Text(
        folder.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      leading: const Icon(Icons.folder, size: 18),
      children: folderSessions.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('暂无会话', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ),
            ]
          : folderSessions.map((s) => _buildSessionTile(s)).toList(),
    );
  }

  Widget _buildSessionTile(Session session) {
    final activeId = ref.watch(activeSessionIdProvider);
    final isActive = activeId == session.id;
    final dt = DateTime.fromMillisecondsSinceEpoch(session.lastMessageAt);
    final timeStr = DateFormat('MM-dd HH:mm').format(dt);

    return ListTile(
      dense: true,
      selected: isActive,
      selectedTileColor: Theme.of(context).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      title: Text(
        session.title ?? '新会话',
        style: const TextStyle(fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        timeStr,
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, size: 16, color: Colors.grey[500]),
        padding: EdgeInsets.zero,
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          PopupMenuItem(
            value: 'moveToFolder',
            child: const Text('移动到文件夹'),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
        onSelected: (action) => _handleSessionAction(action, session),
      ),
      onTap: () {
        ref.read(activeSessionIdProvider.notifier).state = session.id;
      },
    );
  }

  void _handleSessionAction(String action, Session session) async {
    final sessionDao = ref.read(sessionDaoProvider);
    switch (action) {
      case 'rename':
        final name = await _showRenameDialog(session.title ?? '新会话');
        if (name != null && name.isNotEmpty) {
          await sessionDao.updateTitle(session.id, name);
          refreshSessions(ref);
        }
        break;
      case 'moveToFolder':
        await _showMoveToFolderDialog(session);
        break;
      case 'delete':
        final confirmed = await _showDeleteConfirmDialog(
          session.title ?? '新会话',
        );
        if (confirmed != true) return;
        await sessionDao.deleteSession(session.id);
        final remaining = await sessionDao.getAllSessions();
        if (remaining.isEmpty) {
          await createNewSession(ref);
        } else if (ref.read(activeSessionIdProvider) == session.id) {
          ref.read(activeSessionIdProvider.notifier).state = remaining.first.id;
          refreshSessions(ref);
        } else {
          refreshSessions(ref);
        }
        break;
    }
  }

  /// 移动会话到文件夹（含"移出文件夹"选项）
  Future<void> _showMoveToFolderDialog(Session session) async {
    final folders = await ref.read(folderDaoProvider).getAllFolders();
    if (!mounted) return;

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          // "移出文件夹" 选项
          if (session.folderId != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ''), // 空字符串 = 移出
              child: const ListTile(
                leading: Icon(Icons.folder_off_outlined),
                title: Text('移出文件夹'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          for (final f in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f.id),
              child: ListTile(
                leading: Icon(
                  session.folderId == f.id
                      ? Icons.folder_special
                      : Icons.folder_outlined,
                  color: session.folderId == f.id ? Colors.amber : null,
                ),
                title: Text(f.name),
                trailing: session.folderId == f.id
                    ? const Icon(Icons.check, size: 18)
                    : null,
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          if (folders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无文件夹，请先创建', style: TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    final sessionDao = ref.read(sessionDaoProvider);
    if (result.isEmpty) {
      // 移出文件夹
      await sessionDao.moveToFolder(session.id, null);
    } else {
      await sessionDao.moveToFolder(session.id, result);
    }
    refreshSessions(ref);
    refreshFolders(ref);
  }

  Future<bool?> _showDeleteConfirmDialog(String title) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除「$title」？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showRenameDialog(String currentName) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _NameInputDialog(
        title: '重命名',
        initialValue: currentName,
        confirmLabel: '确定',
      ),
    );
  }

  Future<void> _showCreateFolderDialog(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _NameInputDialog(
        title: '新建文件夹',
        hintText: '文件夹名称',
        confirmLabel: '创建',
      ),
    );

    if (name == null) return;

    final dao = ref.read(folderDaoProvider);
    await dao.createFolder(id: const Uuid().v4(), name: name);
    if (!mounted) return;
    ref.invalidate(foldersProvider);
  }
}

class _NameInputDialog extends StatefulWidget {
  final String title;
  final String? initialValue;
  final String? hintText;
  final String confirmLabel;

  const _NameInputDialog({
    required this.title,
    required this.confirmLabel,
    this.initialValue,
    this.hintText,
  });

  @override
  State<_NameInputDialog> createState() => _NameInputDialogState();
}

class _NameInputDialogState extends State<_NameInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: widget.hintText == null
            ? null
            : InputDecoration(hintText: widget.hintText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final trimmed = _controller.text.trim();
            Navigator.pop(context, trimmed.isEmpty ? null : trimmed);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// A simple expansion tile without InheritedWidget dependency issues
class _SimpleExpansionTile extends StatefulWidget {
  final Widget title;
  final Widget? leading;
  final List<Widget> children;

  const _SimpleExpansionTile({
    super.key,
    required this.title,
    this.leading,
    required this.children,
  });

  @override
  State<_SimpleExpansionTile> createState() => _SimpleExpansionTileState();
}

class _SimpleExpansionTileState extends State<_SimpleExpansionTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (widget.leading != null) widget.leading!,
                const SizedBox(width: 8),
                Expanded(child: widget.title),
                Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...widget.children,
      ],
    );
  }
}

class _WorkspaceStatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _WorkspaceStatusCard({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
