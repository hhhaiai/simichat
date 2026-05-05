import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'latex_markdown_widget.dart';

const double _kChatContentMaxWidth = 860;

/// ChatGPT-style message row: assistant answers are plain content blocks;
/// user messages are compact right-aligned bubbles.
class MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final String? thinkingContent;
  final int tokens;
  final int? responseMs;
  final bool isUser;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;
  final VoidCallback? onFork;

  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.thinkingContent,
    this.tokens = 0,
    this.responseMs,
    required this.isUser,
    this.onRetry,
    this.onCopy,
    this.onFork,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kChatContentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: isUser
              ? _buildUserMessage(context)
              : _buildAssistantMessage(context),
        ),
      ),
    );
  }

  Widget _buildUserMessage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(22),
            ),
            child: SelectableText(
              content,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssistantMessage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thinkingContent != null && thinkingContent!.isNotEmpty)
          _ThinkingBlock(content: thinkingContent!),
        LatexMarkdownWidget(data: content),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            _IconActionButton(
              icon: Icons.copy_all_outlined,
              tooltip: '复制',
              onTap: () {
                if (onCopy != null) {
                  onCopy!();
                } else {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
            _IconActionButton(
              icon: Icons.refresh,
              tooltip: '重新生成',
              onTap: onRetry ?? () {},
            ),
            if (onFork != null)
              _IconActionButton(
                icon: Icons.call_split,
                tooltip: '复制分支',
                onTap: onFork!,
              ),
            if (tokens > 0 || responseMs != null)
              _MessageMeta(tokens: tokens, responseMs: responseMs),
          ],
        ),
      ],
    );
  }
}

class _ThinkingBlock extends StatefulWidget {
  final String content;
  const _ThinkingBlock({required this.content});

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_alt_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '思考过程',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                widget.content,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        visualDensity: VisualDensity.compact,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        style: IconButton.styleFrom(minimumSize: const Size(32, 32)),
      ),
    );
  }
}

class _MessageMeta extends StatelessWidget {
  final int tokens;
  final int? responseMs;

  const _MessageMeta({required this.tokens, this.responseMs});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (tokens > 0) parts.add('$tokens tokens');
    if (responseMs != null) {
      parts.add(
        responseMs! >= 1000
            ? '${(responseMs! / 1000).toStringAsFixed(1)}s'
            : '${responseMs!}ms',
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        parts.join(' · '),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
