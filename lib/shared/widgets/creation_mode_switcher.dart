import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/creation_mode_provider.dart';

/// 移动端优先的一级模式切换。它只负责导航状态，不在 UI 层按模型名称猜测
/// 能力；当前工作区会根据 [creationModeProvider] 选择对应的真实任务入口。
class CreationModeSwitcher extends ConsumerWidget {
  const CreationModeSwitcher({super.key, this.onModeChanged});

  final ValueChanged<CreationMode>? onModeChanged;

  static const switcherKey = ValueKey<String>('creation-mode-switcher');

  static const _modes = <CreationMode>[
    CreationMode.chat,
    CreationMode.image,
    CreationMode.video,
    CreationMode.voice,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(creationModeProvider);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '创作模式，当前为${selected.label}',
      child: Material(
        key: switcherKey,
        color: scheme.surface,
        child: SizedBox(
          height: 44,
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in _modes) ...[
                    _ModeChoice(
                      mode: mode,
                      selected: selected == mode,
                      onTap: () {
                        ref.read(creationModeProvider.notifier).state = mode;
                        onModeChanged?.call(mode);
                      },
                    ),
                    if (mode != _modes.last) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final CreationMode mode;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (mode) {
    CreationMode.chat => Icons.chat_bubble_outline_rounded,
    CreationMode.image => Icons.image_outlined,
    CreationMode.video => Icons.movie_outlined,
    CreationMode.voice => Icons.graphic_eq_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label}模式',
      child: InkWell(
        key: ValueKey<String>('creation-mode-${mode.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icon,
                size: 16,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                mode.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
