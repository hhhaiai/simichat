import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'latex_markdown_widget.dart';

/// 消息气泡组件（用户/AI）
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome, size: 16,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 思考内容（可折叠）
                if (!isUser && thinkingContent != null && thinkingContent!.isNotEmpty)
                  _ThinkingBlock(content: thinkingContent!),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: isUser
                      ? SelectableText(
                          content,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 14,
                          ),
                        )
                      : LatexMarkdownWidget(data: content),
                ),
                // AI 消息的操作按钮
                if (!isUser)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ActionButton(
                          icon: Icons.copy,
                          tooltip: '复制',
                          onTap: () {
                            if (onCopy != null) {
                              onCopy!();
                            } else {
                              Clipboard.setData(ClipboardData(text: content));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                              );
                            }
                          },
                        ),
                        _ActionButton(
                          icon: Icons.refresh,
                          tooltip: '重试',
                          onTap: onRetry ?? () {},
                        ),
                        if (onFork != null)
                          _ActionButton(
                            icon: Icons.call_split,
                            tooltip: '复制会话',
                            onTap: onFork!,
                          ),
                      ],
                    ),
                  ),
                // AI 消息元数据
                if (!isUser && (tokens > 0 || responseMs != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _MessageMeta(tokens: tokens, responseMs: responseMs),
                  ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              child: Icon(Icons.person, size: 16, color: Theme.of(context).colorScheme.tertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 可折叠的思考内容块
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey[300]!,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.psychology, size: 14,
                      color: isDark ? Colors.white54 : Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    '思考过程',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.grey[500],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SelectableText(
                widget.content,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 2),
            Text(tooltip, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
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
      if (responseMs! >= 1000) {
        parts.add('${(responseMs! / 1000).toStringAsFixed(1)}s');
      } else {
        parts.add('${responseMs!}ms');
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline, size: 12, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(parts.join(' · '), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
      ],
    );
  }
}
