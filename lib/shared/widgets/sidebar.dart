import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../providers/session_provider.dart';
import '../providers/folder_provider.dart';
import '../providers/database_provider.dart';

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
          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _createNewSession(context),
                    icon: const Icon(Icons.edit_square, size: 18),
                    label: const Text('新聊天'),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  tooltip: '设置',
                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 搜索框 + 新建文件夹
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
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
                const SizedBox(width: 8),
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
            // 按日期分组
            final now = DateTime.now();
            final today = <Session>[];
            final yesterday = <Session>[];
            final thisWeek = <Session>[];
            final older = <Session>[];

            for (final s in sessions) {
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
                // 文件夹
                if (folders.isNotEmpty) ...[
                  for (final f in folders)
                    _buildFolderTile(
                      f,
                      sessions.where((s) => s.folderId == f.id).toList(),
                    ),
                  const Divider(height: 16),
                ],

                // 日期分组
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

  Widget _buildFolderTile(Folder folder, List<Session> sessions) {
    return ExpansionTile(
      title: Text(
        folder.name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.only(left: 16),
      initiallyExpanded: false,
      children: sessions.map((s) => _buildSessionTile(s)).toList(),
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
    final controller = TextEditingController(text: currentName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await ref
                    .read(folderDaoProvider)
                    .createFolder(id: const Uuid().v4(), name: controller.text);
                refreshFolders(ref);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _createNewSession(BuildContext context) async {
    await createNewSession(ref);
  }
}
