import 'package:flutter/material.dart';
import 'latex_markdown_widget.dart';

const double _kChatContentMaxWidth = 860;

/// ChatGPT-style streaming assistant block.
class StreamingBubble extends StatelessWidget {
  final String content;
  final String thinking;

  const StreamingBubble({super.key, required this.content, this.thinking = ''});

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
