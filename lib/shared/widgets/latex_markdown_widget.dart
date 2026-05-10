import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:cached_network_image/cached_network_image.dart';
import 'code_block_widget.dart';
import 'mermaid_widget.dart';
import 'image_viewer.dart';

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
    final defaultStyle = styleSheet ?? _buildMarkdownStyle(context);

    final imgBuilder = _buildImageBuilder(context);

    // 如果没有 LaTeX 内容，直接用 MarkdownBody
    if (segments.length == 1 && segments[0].type == _SegmentType.markdown) {
      return _buildMarkdownSections(
        context,
        data: data,
        styleSheet: defaultStyle,
        imageBuilder: imgBuilder,
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
            return _buildMarkdownSections(
              context,
              data: seg.content,
              styleSheet: defaultStyle,
              imageBuilder: imgBuilder,
            );
        }
      }).toList(),
    );
  }

  Widget _buildMarkdownSections(
    BuildContext context, {
    required String data,
    required MarkdownStyleSheet styleSheet,
    required Widget Function(MarkdownImageConfig) imageBuilder,
  }) {
    final blocks = _parseMarkdownBlocks(data);
    if (blocks.length == 1 && blocks.single.type == _MarkdownBlockType.markdown) {
      return _buildMarkdownBody(
        context,
        data: blocks.single.content,
        styleSheet: styleSheet,
        imageBuilder: imageBuilder,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks.map((block) {
        switch (block.type) {
          case _MarkdownBlockType.markdown:
            if (block.content.trim().isEmpty) return const SizedBox.shrink();
            return _buildMarkdownBody(
              context,
              data: block.content,
              styleSheet: styleSheet,
              imageBuilder: imageBuilder,
            );
          case _MarkdownBlockType.details:
            return _buildDetailsBlock(
              context,
              title: block.title ?? '详情',
              content: block.content,
              styleSheet: styleSheet,
            );
        }
      }).toList(),
    );
  }

  Widget _buildMarkdownBody(
    BuildContext context, {
    required String data,
    required MarkdownStyleSheet styleSheet,
    required Widget Function(MarkdownImageConfig) imageBuilder,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: MarkdownBody(
        data: data,
        selectable: selectable,
        builders: {'code': _CodeBlockBuilder()},
        checkboxBuilder: _buildCheckbox,
        styleSheet: styleSheet,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        softLineBreak: true,
        sizedImageBuilder: imageBuilder,
      ),
    );
  }

  Widget _buildCheckbox(bool checked) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 2),
      child: Icon(
        checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        size: 18,
      ),
    );
  }

  Widget _buildDetailsBlock(
    BuildContext context, {
    required String title,
    required String content,
    required MarkdownStyleSheet styleSheet,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white12 : const Color(0xFFD0D7DE);
    final background = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFF8F9FA);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          children: [
            LatexMarkdownWidget(
              data: content,
              selectable: selectable,
              styleSheet: styleSheet,
            ),
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final codeInlineBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEFF1F3);
    final quoteBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFF8F9FA);
    final quoteBorder = isDark
        ? Colors.white24
        : const Color(0xFFD0D7DE);
    final tableBorder = isDark
        ? Colors.white24
        : const Color(0xFFD0D7DE);

    return MarkdownStyleSheet(
      a: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary.withValues(alpha: 0.55),
      ),
      p: TextStyle(
        fontSize: 15,
        height: 1.8,
        color: scheme.onSurface,
      ),
      pPadding: const EdgeInsets.only(bottom: 10),
      h1: TextStyle(
        fontSize: 28,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      h1Padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
      h2: TextStyle(
        fontSize: 23,
        height: 1.4,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      h2Padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      h3: TextStyle(
        fontSize: 20,
        height: 1.45,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      h3Padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
      h4: TextStyle(
        fontSize: 17,
        height: 1.45,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      h4Padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
      h5: TextStyle(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      h6: TextStyle(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      code: TextStyle(
        backgroundColor: codeInlineBg,
        color: scheme.onSurface,
        fontSize: 13,
        height: 1.5,
        fontFamily: 'monospace',
      ),
      codeblockPadding: EdgeInsets.zero,
      blockquote: TextStyle(
        fontSize: 14,
        height: 1.75,
        color: scheme.onSurfaceVariant,
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      blockquoteDecoration: BoxDecoration(
        color: quoteBg,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: quoteBorder, width: 4)),
      ),
      listBullet: TextStyle(
        fontSize: 15,
        height: 1.8,
        color: scheme.onSurface,
      ),
      listIndent: 22,
      tableHead: TextStyle(
        fontSize: 14,
        height: 1.6,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      tableBody: TextStyle(
        fontSize: 14,
        height: 1.65,
        color: scheme.onSurface,
      ),
      tableBorder: TableBorder.all(color: tableBorder, width: 1),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 8,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : const Color(0xFFEAECEF),
          ),
        ),
      ),
    );
  }

  /// 构建图片渲染器：支持网络图片缓存 + 点击放大 + data URI
  Widget Function(MarkdownImageConfig) _buildImageBuilder(BuildContext context) {
    return (MarkdownImageConfig config) {
      final uri = config.uri;
      final uriStr = uri.toString();

      // data: URI (base64 图片)
      if (uri.scheme == 'data') {
        try {
          final data = uriStr.split(',').last;
          final bytes = base64Decode(data);
          return GestureDetector(
            onTap: () => showImageViewer(
              context,
              imageProvider: MemoryImage(bytes),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          );
        } catch (_) {
          return const SizedBox.shrink();
        }
      }

      // 网络图片
      return GestureDetector(
        onTap: () => showImageViewer(
          context,
          imageProvider: CachedNetworkImageProvider(uriStr),
          imageUrl: uriStr,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: uriStr,
            placeholder: (_, _) => const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (_, _, _) => Container(
              height: 100,
              color: Colors.grey[200],
              child: const Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
            maxWidthDiskCache: 1200,
            fit: BoxFit.contain,
          ),
        ),
      );
    };
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

  List<_MarkdownBlock> _parseMarkdownBlocks(String text) {
    final lines = text.split('\n');
    final blocks = <_MarkdownBlock>[];
    final markdownBuffer = <String>[];
    int index = 0;

    void flushMarkdown() {
      if (markdownBuffer.isEmpty) return;
      blocks.add(
        _MarkdownBlock(
          type: _MarkdownBlockType.markdown,
          content: markdownBuffer.join('\n'),
        ),
      );
      markdownBuffer.clear();
    }

    while (index < lines.length) {
      final trimmed = lines[index].trim();
      final isDetailsStart =
          trimmed.startsWith(':::details') || trimmed.startsWith(':::collapse');
      if (!isDetailsStart) {
        markdownBuffer.add(lines[index]);
        index++;
        continue;
      }

      flushMarkdown();

      final title = trimmed
          .replaceFirst(RegExp(r'^:::(details|collapse)\s*'), '')
          .trim();
      index++;
      final detailsBuffer = <String>[];
      while (index < lines.length && lines[index].trim() != ':::') {
        detailsBuffer.add(lines[index]);
        index++;
      }
      if (index < lines.length && lines[index].trim() == ':::') {
        index++;
      }

      blocks.add(
        _MarkdownBlock(
          type: _MarkdownBlockType.details,
          title: title.isEmpty ? '详情' : title,
          content: detailsBuffer.join('\n').trim(),
        ),
      );
    }

    flushMarkdown();
    return blocks;
  }
}

enum _SegmentType { markdown, blockLatex }

enum _MarkdownBlockType { markdown, details }

class _Segment {
  final _SegmentType type;
  final String content;
  const _Segment(this.type, this.content);
}

class _MarkdownBlock {
  final _MarkdownBlockType type;
  final String content;
  final String? title;

  const _MarkdownBlock({
    required this.type,
    required this.content,
    this.title,
  });
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
