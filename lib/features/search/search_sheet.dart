import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/search/local_full_text_search.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/key_point_memory_provider.dart';
import '../../shared/providers/settings_provider.dart';
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
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String query) async {
    final generation = ++_searchGeneration;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _query = '';
        _results = [];
        _isSearching = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _query = trimmed;
      _isSearching = true;
    });

    try {
      final searchService = LocalFullTextSearchService(
        sessionDao: ref.read(sessionDaoProvider),
        messageDao: ref.read(messageDaoProvider),
        memoryItems: ref.read(keyPointMemoryProvider),
        enableSemanticMessageSearch: ref.read(semanticSearchEnabledProvider),
      );
      final results = (await searchService.search(trimmed))
          .map(
            (result) => _SearchResult(
              sessionId: result.sessionId,
              title: result.title,
              subtitle: result.subtitle,
              matchType: _mapMatchType(result.matchType),
              matchCount: result.matchCount,
            ),
          )
          .toList();

      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _isSearching = false);
    }
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
                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                  _doSearch(v);
                });
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
                        Icon(
                          Icons.search,
                          size: 48,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '输入关键词搜索会话标题和消息内容',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: scheme.onSurfaceVariant,
                        ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (_, i) =>
                        _buildResultTile(_results[i], scheme),
                  ),
          ),
        ],
      ),
    );
  }

  /// 紧凑结果卡片：小图标 + 类型徽标 + 单行摘要，取代整行长条目。
  Widget _buildResultTile(_SearchResult result, ColorScheme scheme) {
    final typeLabel = switch (result.matchType) {
      _MatchType.title => '标题',
      _MatchType.message => '消息',
      _MatchType.memory => '记忆',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            ref.read(activeSessionIdProvider.notifier).state = result.sessionId;
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _iconForMatchType(result.matchType),
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        result.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withValues(
                          alpha: 0.7,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    if (result.matchCount != null && result.matchCount! > 1) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${result.matchCount} 处',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForMatchType(_MatchType type) {
    switch (type) {
      case _MatchType.title:
        return Icons.chat_bubble_outline;
      case _MatchType.memory:
        return Icons.psychology_outlined;
      case _MatchType.message:
        return Icons.message_outlined;
    }
  }
}

_MatchType _mapMatchType(LocalSearchMatchType type) {
  switch (type) {
    case LocalSearchMatchType.title:
      return _MatchType.title;
    case LocalSearchMatchType.memory:
      return _MatchType.memory;
    case LocalSearchMatchType.message:
      return _MatchType.message;
  }
}

enum _MatchType { title, message, memory }

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
