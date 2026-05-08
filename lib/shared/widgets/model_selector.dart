import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/protocol_icons.dart';
import '../../core/database/dao/channel_dao.dart';
import '../providers/channel_provider.dart';

/// 模型选择器：侧边栏顶部，列出所有渠道的全部模型（不去重）
class ModelSelector extends ConsumerWidget {
  final ValueChanged<String> onModelSelected;

  const ModelSelector({super.key, required this.onModelSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(allModelsProvider);
    final selectedId = ref.watch(selectedModelIdProvider);

    return modelsAsync.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => SizedBox(
        height: 48,
        child: Center(child: Text('加载模型失败: $e', style: const TextStyle(fontSize: 12))),
      ),
      data: (models) {
        if (models.isEmpty) {
          return SizedBox(
            height: 48,
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, '/settings'),
              borderRadius: BorderRadius.circular(8),
              child: const Center(
                child: Text(
                  '请先添加模型渠道',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ),
          );
        }

        // 找到当前选中的模型
        ChannelModelWithChannel? selected;
        if (selectedId != null) {
          selected = models.where((m) => m.channelModel.id == selectedId).firstOrNull;
        }
        selected ??= models.first;

        return PopupMenuButton<String>(
          onSelected: (modelId) {
            ref.read(selectedModelIdProvider.notifier).state = modelId;
            onModelSelected(modelId);
          },
          offset: const Offset(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 400),
          itemBuilder: (_) => _buildMenuItems(models, selected!.channelModel.id),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Row(
              children: [
                Icon(
                  getProtocolIcon(selected.channel.protocol),
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected.displayLabel,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.unfold_more, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(
    List<ChannelModelWithChannel> models,
    String? selectedId,
  ) {
    final items = <PopupMenuEntry<String>>[];
    String? lastChannel;

    for (final m in models) {
      // 渠道分组标题
      if (m.channel.name != lastChannel) {
        if (lastChannel != null) {
          items.add(const PopupMenuDivider());
        }
        items.add(PopupMenuItem<String>(
          enabled: false,
          child: Text(
            m.channel.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ));
        lastChannel = m.channel.name;
      }

      items.add(PopupMenuItem<String>(
        value: m.channelModel.id,
        child: Row(
          children: [
            if (m.channelModel.id == selectedId)
              Icon(Icons.check, size: 16, color: Colors.green[600])
            else
              const SizedBox(width: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                m.channelModel.modelName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: m.channelModel.id == selectedId
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    return items;
  }

}
