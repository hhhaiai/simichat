import 'package:flutter/material.dart';
import 'latex_markdown_widget.dart';

const double _kChatContentMaxWidth = 860;

/// ChatGPT-style streaming assistant block.
class StreamingBubble extends StatelessWidget {
  final String content;
  final String thinking;
  final String? modelName;

  const StreamingBubble({
    super.key,
    required this.content,
    this.thinking = '',
    this.modelName,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kChatContentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (modelName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    modelName!,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              if (content.isEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          thinking.isNotEmpty ? '思考中...' : '正在生成...',
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    // 深度思考：流式中实时展示思考过程（可折叠）。
                    if (thinking.isNotEmpty)
                      _StreamingThinkingBlock(thinking: thinking),
                  ],
                )
              else
                LatexMarkdownWidget(data: '$content ▌', selectable: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// 流式思考过程：默认折叠，点击展开实时内容。
class _StreamingThinkingBlock extends StatefulWidget {
  final String thinking;

  const _StreamingThinkingBlock({required this.thinking});

  @override
  State<_StreamingThinkingBlock> createState() =>
      _StreamingThinkingBlockState();
}

class _StreamingThinkingBlockState extends State<_StreamingThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.psychology_alt_outlined,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '思考过程',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              SelectableText(
                widget.thinking,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
