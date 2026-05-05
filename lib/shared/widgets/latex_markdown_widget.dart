import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'code_block_widget.dart';
import 'mermaid_widget.dart';

/// 支持 LaTeX 数学公式的 Markdown 渲染组件
/// 处理 $$...$$ 块级公式和 $...$ 行内公式
class LatexMarkdownWidget extends StatelessWidget {
  final String data;
  final bool selectable;
  final MarkdownStyleSheet? styleSheet;

  const LatexMarkdownWidget({
    super.key,
    required this.data,
    this.selectable = true,
    this.styleSheet,
  });

  @override
  Widget build(BuildContext context) {
    final segments = _parseLatex(data);
    final defaultStyle = styleSheet ?? MarkdownStyleSheet(
      p: const TextStyle(fontSize: 14),
      code: TextStyle(
        backgroundColor: Colors.grey[200],
        fontSize: 13,
        fontFamily: 'monospace',
      ),
    );

    // 如果没有 LaTeX 内容，直接用 MarkdownBody
    if (segments.length == 1 && segments[0].type == _SegmentType.markdown) {
      return MarkdownBody(
        data: data,
        selectable: selectable,
        builders: {'code': _CodeBlockBuilder()},
        styleSheet: defaultStyle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: segments.map((seg) {
        switch (seg.type) {
          case _SegmentType.blockLatex:
            return _buildBlockLatex(context, seg.content);
          case _SegmentType.markdown:
            if (seg.content.trim().isEmpty) return const SizedBox.shrink();
            return MarkdownBody(
              data: seg.content,
              selectable: selectable,
              builders: {'code': _CodeBlockBuilder()},
              styleSheet: defaultStyle,
            );
        }
      }).toList(),
    );
  }

  Widget _buildBlockLatex(BuildContext context, String latex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey[200]!,
          width: 0.5,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          latex,
          textStyle: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onErrorFallback: (e) => Text(
            latex,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: Colors.red[400],
            ),
          ),
        ),
      ),
    );
  }

  /// 解析文本，分离 LaTeX 和 Markdown 段落
  List<_Segment> _parseLatex(String text) {
    final segments = <_Segment>[];
    final buffer = StringBuffer();
    int i = 0;

    while (i < text.length) {
      // 检测块级 LaTeX: $$...$$
      if (i + 1 < text.length && text[i] == '\$' && text[i + 1] == '\$') {
        // 保存之前的 markdown
        if (buffer.isNotEmpty) {
          segments.add(_Segment(_SegmentType.markdown, buffer.toString()));
          buffer.clear();
        }
        // 查找结束的 $$
        final endIdx = text.indexOf('\$\$', i + 2);
        if (endIdx == -1) {
          // 没有闭合，当作普通文本
          buffer.write('\$\$');
          i += 2;
          continue;
        }
        final latex = text.substring(i + 2, endIdx).trim();
        if (latex.isNotEmpty) {
          segments.add(_Segment(_SegmentType.blockLatex, latex));
        }
        i = endIdx + 2;
        continue;
      }

      // 检测行内 LaTeX: $...$（但不匹配 $$ 或 \$）
      if (text[i] == '\$' && (i + 1 >= text.length || text[i + 1] != '\$')) {
        // 查找结束的 $
        final endIdx = text.indexOf('\$', i + 1);
        if (endIdx == -1 || endIdx == i + 1) {
          buffer.write(text[i]);
          i++;
          continue;
        }
        // 确保不是转义的 \$
        if (i > 0 && text[i - 1] == '\\') {
          buffer.write(text[i]);
          i++;
          continue;
        }
        // 保存之前的 markdown
        if (buffer.isNotEmpty) {
          segments.add(_Segment(_SegmentType.markdown, buffer.toString()));
          buffer.clear();
        }
        final latex = text.substring(i + 1, endIdx).trim();
        if (latex.isNotEmpty) {
          // 行内 LaTeX 用 markdown 的 inline code 风格模拟
          // 实际渲染为 HTML img 标签会被 flutter_markdown 过滤
          // 所以用特殊标记，在 markdown 中用 Unicode 替代
          buffer.write('`$latex`');
        }
        i = endIdx + 1;
        continue;
      }

      buffer.write(text[i]);
      i++;
    }

    // 保存剩余内容
    if (buffer.isNotEmpty) {
      segments.add(_Segment(_SegmentType.markdown, buffer.toString()));
    }

    return segments;
  }
}

enum _SegmentType { markdown, blockLatex }

class _Segment {
  final _SegmentType type;
  final String content;
  const _Segment(this.type, this.content);
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    String? language;
    final className = element.attributes['class'] ?? '';
    if (className.startsWith('language-')) {
      language = className.substring(9);
    }
    if (language == 'mermaid') {
      return MermaidWidget(code: element.textContent);
    }
    return CodeBlockWidget(code: element.textContent, language: language);
  }
}
