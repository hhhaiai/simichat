import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/channel_provider.dart';
import '../../core/database/dao/channel_dao.dart';

/// 紧凑模型选择器：用于对话输入区域，~32px 高
class CompactModelSelector extends ConsumerWidget {
  final ValueChanged<String>? onModelSelected;
  final String? selectedModelId;

  const CompactModelSelector({
    super.key,
    this.onModelSelected,
    this.selectedModelId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(allModelsProvider);
    final sessionModelId = ref.watch(selectedModelIdProvider);
    final activeId = selectedModelId ?? sessionModelId;

    return modelsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (models) {
        if (models.isEmpty) return const SizedBox.shrink();

        ChannelModelWithChannel? current;
        if (activeId != null) {
          try {
            current = models.firstWhere((m) => m.channelModel.id == activeId);
          } catch (_) {}
        }
        current ??= models.first;

        return PopupMenuButton<String>(
          onSelected: onModelSelected,
          offset: const Offset(0, -8),
          itemBuilder: (ctx) => _buildMenuItems(ctx, models, current!),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    current.channelModel.modelName,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.unfold_more, size: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(
    BuildContext context,
    List<ChannelModelWithChannel> models,
    ChannelModelWithChannel current,
  ) {
    final items = <PopupMenuEntry<String>>[];

    // 按渠道分组
    final grouped = <String, List<ChannelModelWithChannel>>{};
    for (final m in models) {
      final key = m.channel.name;
      grouped.putIfAbsent(key, () => []).add(m);
    }

    for (final entry in grouped.entries) {
      // 渠道标题
      items.add(PopupMenuItem<String>(
        enabled: false,
        child: Text(
          entry.key,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500],
          ),
        ),
      ));

      for (final m in entry.value) {
        final isSelected = m.channelModel.id == current.channelModel.id;
        items.add(PopupMenuItem<String>(
          value: m.channelModel.id,
          child: Row(
            children: [
              if (isSelected)
                Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  m.channelModel.modelName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ));
      }
    }

    return items;
  }
}
