import 'package:flutter/material.dart';
import 'latex_markdown_widget.dart';

const double _kChatContentMaxWidth = 860;

/// ChatGPT-style streaming assistant block.
class StreamingBubble extends StatelessWidget {
  final String content;
  final String thinking;
  final String? modelName;

  const StreamingBubble({super.key, required this.content, this.thinking = '', this.modelName});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
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
