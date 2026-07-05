import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'code_block_widget.dart';

/// Draw.io / mxGraph 嵌入块。
///
/// 移动端先做安全识别、源码预览、复制和全屏查看，不执行嵌入 XML 中的任意
/// HTML / JavaScript。后续如接入 diagrams.net 可视化预览，应继续保留当前
/// 源码回退路径。
class DrawioWidget extends StatelessWidget {
  final String code;

  const DrawioWidget({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE1E4E8),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFFAFBFC),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schema_outlined, size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Draw.io 图',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '复制源码',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy, size: 16),
                ),
                IconButton(
                  tooltip: '全屏查看',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showFullScreen(context),
                  icon: const Icon(Icons.fullscreen, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已识别 Draw.io / mxGraph XML。移动端先提供安全源码预览。',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      code,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draw.io 源码已复制'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Draw.io 图')),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: CodeBlockWidget(code: code, language: 'xml'),
          ),
        ),
      ),
    );
  }
}
