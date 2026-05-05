import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/session_provider.dart';

/// 全局搜索：搜索会话标题 + 消息内容
void showSearchSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SearchSheet(),
  );
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  bool _isSearching = false;
  List<_SearchResult> _results = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _results = [];
      });
      return;
    }

    setState(() {
      _query = trimmed;
      _isSearching = true;
    });

    try {
      final sessionDao = ref.read(sessionDaoProvider);
      final messageDao = ref.read(messageDaoProvider);

      final sessions = await sessionDao.searchSessions(trimmed);
      final messages = await messageDao.searchAll(trimmed);

      final sessionMap = <String, Session>{};
      for (final s in sessions) {
        sessionMap[s.id] = s;
      }

      // 收集消息关联的会话（去重）
      final messageSessionIds = messages.map((m) => m.sessionId).toSet();
      for (final sid in messageSessionIds) {
        if (!sessionMap.containsKey(sid)) {
          final s = await sessionDao.getSession(sid);
          if (s != null) sessionMap[sid] = s;
        }
      }

      final results = <_SearchResult>[];

      // 会话标题匹配
      for (final s in sessions) {
        results.add(_SearchResult(
          sessionId: s.id,
          title: s.title ?? '新会话',
          subtitle: '会话标题匹配',
          matchType: _MatchType.title,
        ));
      }

      // 消息内容匹配（按会话分组）
      final messagesBySession = <String, List<Message>>{};
      for (final m in messages) {
        messagesBySession.putIfAbsent(m.sessionId, () => []).add(m);
      }
      for (final entry in messagesBySession.entries) {
        final s = sessionMap[entry.key];
        if (s == null) continue;
        // 跳过已在标题匹配中出现的会话
        if (sessions.any((ts) => ts.id == entry.key)) continue;
        final snippet = _extractSnippet(entry.value.first.content, trimmed);
        results.add(_SearchResult(
          sessionId: entry.key,
          title: s.title ?? '新会话',
          subtitle: snippet,
          matchType: _MatchType.message,
          matchCount: entry.value.length,
        ));
      }

      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  String _extractSnippet(String content, String query) {
    final lower = content.toLowerCase();
    final idx = lower.indexOf(query.toLowerCase());
    if (idx == -1) return content.length > 80 ? '${content.substring(0, 80)}...' : content;
    final start = (idx - 30).clamp(0, content.length);
    final end = (idx + query.length + 50).clamp(0, content.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < content.length ? '...' : '';
    return '$prefix${content.substring(start, end)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: '搜索会话和消息...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _controller.clear();
                          _doSearch('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) {
                setState(() {});
                _doSearch(v);
              },
              onSubmitted: _doSearch,
            ),
          ),

          // 结果
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _query.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text(
                              '输入关键词搜索会话标题和消息内容',
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off, size: 48, color: scheme.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(
                                  '未找到匹配结果',
                                  style: TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            itemCount: _results.length,
                            itemBuilder: (_, i) => _buildResultTile(_results[i], scheme),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultTile(_SearchResult result, ColorScheme scheme) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: Icon(
        result.matchType == _MatchType.title ? Icons.chat_bubble_outline : Icons.message_outlined,
        size: 20,
        color: scheme.primary,
      ),
      title: Text(
        result.title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        result.subtitle,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: result.matchCount != null && result.matchCount! > 1
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${result.matchCount}',
                style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer),
              ),
            )
          : null,
      onTap: () {
        ref.read(activeSessionIdProvider.notifier).state = result.sessionId;
        Navigator.pop(context);
      },
    );
  }
}

enum _MatchType { title, message }

class _SearchResult {
  final String sessionId;
  final String title;
  final String subtitle;
  final _MatchType matchType;
  final int? matchCount;

  const _SearchResult({
    required this.sessionId,
    required this.title,
    required this.subtitle,
    required this.matchType,
    this.matchCount,
  });
}
