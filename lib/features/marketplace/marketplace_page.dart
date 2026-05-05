import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/marketplace/marketplace_models.dart';
import '../../shared/providers/marketplace_provider.dart';
import '../../shared/providers/mcp_provider.dart';

/// MCP 市场页面
class MarketplacePage extends ConsumerStatefulWidget {
  const MarketplacePage({super.key});

  @override
  ConsumerState<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends ConsumerState<MarketplacePage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(marketplaceProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP 市场'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索 MCP 服务器...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(marketplaceProvider.notifier).setKeyword('');
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) {
                ref.read(marketplaceProvider.notifier).setKeyword(v);
                setState(() {});
              },
            ),
          ),

          // 分类 chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: marketplaceCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = marketplaceCategories[i];
                final selected = state.category == cat;
                return FilterChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) {
                    ref.read(marketplaceProvider.notifier).setCategory(cat);
                  },
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              },
            ),
          ),

          // 结果列表
          Expanded(
            child: state.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(
                          '未找到匹配的 MCP 服务器',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: state.items.length,
                    itemBuilder: (_, i) => _buildItemCard(state.items[i], scheme),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(MarketplaceItem item, ColorScheme scheme) {
    final servers = ref.watch(mcpManagerProvider);
    final installed = servers.any((s) => s.name == item.name);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：名称 + 分类
            Row(
              children: [
                Icon(
                  item.isStdio ? Icons.terminal : Icons.cloud_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (item.author.isNotEmpty)
                        Text(
                          item.author,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.category,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 描述
            Text(
              item.description,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 10),

            // 标签
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: item.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // 安装命令预览 + 安装按钮
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.isStdio
                          ? '${item.command} ${(item.args).join(" ")}'
                          : item.url ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                installed
                    ? FilledButton.tonal(
                        onPressed: null,
                        child: const Text('已安装', style: TextStyle(fontSize: 12)),
                      )
                    : FilledButton.icon(
                        onPressed: () => _installItem(item),
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('安装', style: TextStyle(fontSize: 12)),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _installItem(MarketplaceItem item) async {
    final manager = ref.read(mcpManagerProvider.notifier);

    final config = McpServerConfig(
      id: const Uuid().v4(),
      name: item.name,
      transport: item.transport,
      command: item.command,
      args: item.args.isEmpty ? null : item.args,
      url: item.url,
      isEnabled: true,
      source: 'marketplace',
      marketplaceId: item.id,
    );

    manager.addServer(config);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已安装: ${item.name}'),
        action: SnackBarAction(
          label: '连接',
          onPressed: () => manager.connectServer(config),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MCP 市场'),
        content: const Text(
          'MCP (Model Context Protocol) 服务器可以扩展 AI 的能力，'
          '如文件访问、数据库查询、网页搜索等。\n\n'
          '选择一个服务器安装后，需要在设置中手动连接。'
          '部分服务器需要额外的环境变量（如 API Key）。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }
}
