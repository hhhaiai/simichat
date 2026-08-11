import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:cached_network_image/cached_network_image.dart';
import 'code_block_widget.dart';
import 'drawio_widget.dart';
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
    if (blocks.length == 1 &&
        blocks.single.type == _MarkdownBlockType.markdown) {
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
          case _MarkdownBlockType.footnotes:
            return _buildFootnotesBlock(
              context,
              content: block.content,
              styleSheet: styleSheet,
              imageBuilder: imageBuilder,
            );
          case _MarkdownBlockType.media:
            return _buildMediaBlock(
              context,
              type: block.title ?? 'media',
              source: block.content,
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
        data: _normalizeLegacyMarkdown(data),
        selectable: selectable,
        builders: {
          'code': _CodeBlockBuilder(),
          'math': _InlineMathBuilder(),
          'table': _StyledTableBuilder(),
        },
        inlineSyntaxes: [_InlineMathSyntax()],
        checkboxBuilder: _buildCheckbox,
        paddingBuilders: {
          'p': _FixedPaddingBuilder(const EdgeInsets.only(bottom: 10)),
          'blockquote': _FixedPaddingBuilder(
            const EdgeInsets.symmetric(vertical: 8),
          ),
          'table': _FixedPaddingBuilder(
            const EdgeInsets.symmetric(vertical: 10),
          ),
          'h1': _FixedPaddingBuilder(const EdgeInsets.only(top: 8, bottom: 8)),
          'h2': _FixedPaddingBuilder(const EdgeInsets.only(top: 6, bottom: 6)),
          'h3': _FixedPaddingBuilder(const EdgeInsets.only(top: 4, bottom: 4)),
          'section': _FootnoteSectionPaddingBuilder(),
        },
        styleSheet: styleSheet,
        extensionSet: md.ExtensionSet.gitHubWeb,
        softLineBreak: true,
        sizedImageBuilder: imageBuilder,
      ),
    );
  }

  Widget _buildCheckbox(bool checked) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 2),
      child: Icon(
        checked
            ? Icons.check_box_rounded
            : Icons.check_box_outline_blank_rounded,
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

  Widget _buildFootnotesBlock(
    BuildContext context, {
    required String content,
    required MarkdownStyleSheet styleSheet,
    required Widget Function(MarkdownImageConfig) imageBuilder,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white12 : const Color(0xFFEAECEF);
    final titleColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '脚注',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: titleColor,
              ),
            ),
          ),
          _buildMarkdownBody(
            context,
            data: content,
            styleSheet: styleSheet,
            imageBuilder: imageBuilder,
          ),
        ],
      ),
    );
  }

  Widget _buildMediaBlock(
    BuildContext context, {
    required String type,
    required String source,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isVideo = type.toLowerCase() == 'video';
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFD0D7DE),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isVideo ? Icons.smart_display_outlined : Icons.audiotrack_outlined,
            size: 22,
            color: scheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVideo ? '视频附件' : '音频附件',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  source.trim().isEmpty ? '未找到媒体地址' : source.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final tableBorder = isDark ? Colors.white24 : const Color(0xFFD0D7DE);

    return MarkdownStyleSheet(
      a: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary.withValues(alpha: 0.55),
      ),
      blockSpacing: 14,
      p: TextStyle(fontSize: 15, height: 1.6, color: scheme.onSurface),
      pPadding: const EdgeInsets.only(bottom: 10),
      h1: TextStyle(
        fontSize: 22,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: scheme.primary,
      ),
      h1Padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
      h2: TextStyle(
        fontSize: 20,
        height: 1.4,
        fontWeight: FontWeight.w700,
        color: scheme.primary.withValues(alpha: 0.85),
      ),
      h2Padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      h3: TextStyle(
        fontSize: 18,
        height: 1.45,
        fontWeight: FontWeight.w600,
        color: scheme.primary.withValues(alpha: 0.7),
      ),
      h3Padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
      h4: TextStyle(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      h4Padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
      h5: TextStyle(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      h6: TextStyle(
        fontSize: 14,
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
        border: Border(
          left: BorderSide(color: scheme.primary.withValues(alpha: 0.6), width: 6),
        ),
      ),
      listBullet: TextStyle(fontSize: 15, height: 1.6, color: scheme.onSurface),
      listIndent: 22,
      listBulletPadding: const EdgeInsets.only(right: 8),
      checkbox: TextStyle(fontSize: 15, color: scheme.primary),
      tableHead: TextStyle(
        fontSize: 14,
        height: 1.6,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      tableBody: TextStyle(fontSize: 14, height: 1.65, color: scheme.onSurface),
      tableBorder: TableBorder.all(color: tableBorder, width: 1),
      tableColumnWidth: const FlexColumnWidth(),
      tableScrollbarThumbVisibility: true,
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
  Widget Function(MarkdownImageConfig) _buildImageBuilder(
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white12 : const Color(0xFFD0D7DE);
    final background = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFF8F9FA);

    Widget wrapImage(Widget child) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
      );
    }

    return (MarkdownImageConfig config) {
      final uri = config.uri;
      final uriStr = uri.toString();

      // data: URI (base64 图片)
      if (uri.scheme == 'data') {
        try {
          final data = uriStr.split(',').last;
          final bytes = base64Decode(data);
          return GestureDetector(
            onTap: () =>
                showImageViewer(context, imageProvider: MemoryImage(bytes)),
            child: wrapImage(Image.memory(bytes, fit: BoxFit.contain)),
          );
        } catch (_) {
          return const SizedBox.shrink();
        }
      }

      // 本地文件或相对路径图片（移动端优先）。
      if (uri.scheme == 'file' || uri.scheme.isEmpty) {
        final path = uri.scheme == 'file' ? uri.toFilePath() : uriStr;
        return GestureDetector(
          onTap: () =>
              showImageViewer(context, imageProvider: FileImage(File(path))),
          child: wrapImage(Image.file(File(path), fit: BoxFit.contain)),
        );
      }

      // 网络图片
      return GestureDetector(
        onTap: () => showImageViewer(
          context,
          imageProvider: CachedNetworkImageProvider(uriStr),
          imageUrl: uriStr,
        ),
        child: wrapImage(
          CachedNetworkImage(
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

  String _normalizeLegacyMarkdown(String text) {
    var normalized = text;
    normalized = _normalizeLegacyImageSyntax(normalized);
    normalized = _normalizeLegacyDiagramSyntax(normalized);
    normalized = _wrapRawDrawioXmlBlocks(normalized);
    return normalized;
  }

  String _normalizeLegacyImageSyntax(String text) {
    var normalized = text.replaceAllMapped(
      RegExp(r'\[\[(?:img|image):([^\]]+)\]\]', caseSensitive: false),
      (match) {
        final source = match.group(1)?.trim() ?? '';
        if (source.isEmpty) return match.group(0)!;
        return _markdownImage(source: source);
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'!\[\[([^\]]+)\]\]', caseSensitive: false),
      (match) {
        final raw = match.group(1)?.trim() ?? '';
        final source = raw.split('|').first.trim();
        if (source.isEmpty) return match.group(0)!;
        return _markdownImage(source: source, alt: source.split('/').last);
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'\[(?:img|image):([^\]]+)\]', caseSensitive: false),
      (match) {
        final source = match.group(1)?.trim() ?? '';
        if (source.isEmpty) return match.group(0)!;
        return _markdownImage(source: source);
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'<img\b[^>]*>', caseSensitive: false),
      (match) {
        final tag = match.group(0) ?? '';
        final source = _extractHtmlAttribute(tag, 'src');
        if (source == null || source.isEmpty) return tag;
        return _markdownImage(
          source: source,
          alt: _extractHtmlAttribute(tag, 'alt') ?? 'image',
        );
      },
    );
    return normalized;
  }

  String _normalizeLegacyDiagramSyntax(String text) {
    var normalized = _normalizeColonDiagramBlocks(text);
    normalized = normalized.replaceAllMapped(
      RegExp(
        r'\[(mermaid|drawio|draw\.io|mxgraph|diagrams\.net)\]\s*([\s\S]*?)\s*\[/\1\]',
        caseSensitive: false,
      ),
      (match) {
        final language = _normalizeDiagramLanguage(match.group(1) ?? '');
        final code = match.group(2)?.trim() ?? '';
        if (code.isEmpty) return match.group(0)!;
        return '```$language\n$code\n```';
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(
        r'''<(?:div|pre)\b[^>]*class=["'][^"']*\bmermaid\b[^"']*["'][^>]*>([\s\S]*?)</(?:div|pre)>''',
        caseSensitive: false,
      ),
      (match) {
        final code = match.group(1)?.trim() ?? '';
        if (code.isEmpty) return match.group(0)!;
        return '```mermaid\n$code\n```';
      },
    );
    return normalized;
  }

  String _normalizeColonDiagramBlocks(String text) {
    final lines = text.split('\n');
    final output = <String>[];
    var index = 0;
    while (index < lines.length) {
      final match = RegExp(
        r'^:::\s*(mermaid|drawio|draw\.io|mxgraph|diagrams\.net)\s*$',
        caseSensitive: false,
      ).firstMatch(lines[index].trim());
      if (match == null) {
        output.add(lines[index]);
        index++;
        continue;
      }

      final language = _normalizeDiagramLanguage(match.group(1) ?? '');
      index++;
      final buffer = <String>[];
      while (index < lines.length && lines[index].trim() != ':::') {
        buffer.add(lines[index]);
        index++;
      }
      if (index < lines.length && lines[index].trim() == ':::') {
        index++;
      }
      output
        ..add('```$language')
        ..add(buffer.join('\n').trim())
        ..add('```');
    }
    return output.join('\n');
  }

  String _wrapRawDrawioXmlBlocks(String text) {
    final lines = text.split('\n');
    final output = <String>[];
    var index = 0;
    var inFence = false;
    while (index < lines.length) {
      final trimmed = lines[index].trim();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = !inFence;
        output.add(lines[index]);
        index++;
        continue;
      }

      final lower = trimmed.toLowerCase();
      final isMxFile = lower.startsWith('<mxfile');
      final isMxGraph = lower.startsWith('<mxgraphmodel');
      if (inFence || (!isMxFile && !isMxGraph)) {
        output.add(lines[index]);
        index++;
        continue;
      }

      final closingTag = isMxFile ? '</mxfile>' : '</mxgraphmodel>';
      final buffer = <String>[];
      while (index < lines.length) {
        buffer.add(lines[index]);
        if (lines[index].toLowerCase().contains(closingTag)) {
          index++;
          break;
        }
        index++;
      }
      output
        ..add('```drawio')
        ..add(buffer.join('\n').trim())
        ..add('```');
    }
    return output.join('\n');
  }

  String _markdownImage({required String source, String alt = 'image'}) {
    final safeAlt = alt.replaceAll('[', '').replaceAll(']', '').trim();
    final value = source.trim();
    final wrappedSource =
        RegExp(r'\s').hasMatch(value) &&
            !value.startsWith('<') &&
            !value.endsWith('>')
        ? '<$value>'
        : value;
    return '![${safeAlt.isEmpty ? 'image' : safeAlt}]($wrappedSource)';
  }

  String _normalizeDiagramLanguage(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'mermaid') return 'mermaid';
    return 'drawio';
  }

  String? _extractHtmlAttribute(String html, String name) {
    final escapedName = RegExp.escape(name);
    final match = RegExp(
      "$escapedName\\s*=\\s*[\"']([^\"']+)[\"']",
      caseSensitive: false,
    ).firstMatch(html);
    return match?.group(1)?.trim();
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
      final mediaMatch = RegExp(
        r'^<(audio|video)\b',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (mediaMatch != null) {
        flushMarkdown();
        final tag = mediaMatch.group(1)!.toLowerCase();
        final mediaBuffer = <String>[];
        while (index < lines.length) {
          mediaBuffer.add(lines[index]);
          if (lines[index].toLowerCase().contains('</$tag>')) {
            index++;
            break;
          }
          index++;
        }
        final html = mediaBuffer.join('\n');
        blocks.add(
          _MarkdownBlock(
            type: _MarkdownBlockType.media,
            title: tag,
            content: _extractHtmlMediaSource(html) ?? html.trim(),
          ),
        );
        continue;
      }

      if (trimmed.startsWith(RegExp(r'<details\b', caseSensitive: false))) {
        flushMarkdown();
        final detailsBuffer = <String>[];
        while (index < lines.length) {
          detailsBuffer.add(lines[index]);
          if (lines[index].toLowerCase().contains('</details>')) {
            index++;
            break;
          }
          index++;
        }
        final parsed = _parseHtmlDetails(detailsBuffer.join('\n'));
        blocks.add(
          _MarkdownBlock(
            type: _MarkdownBlockType.details,
            title: parsed.title.isEmpty ? '详情' : parsed.title,
            content: parsed.content,
          ),
        );
        continue;
      }

      if (trimmed == '<section class="footnotes">') {
        flushMarkdown();
        index++;
        final footnoteBuffer = <String>[];
        while (index < lines.length && lines[index].trim() != '</section>') {
          footnoteBuffer.add(lines[index]);
          index++;
        }
        if (index < lines.length && lines[index].trim() == '</section>') {
          index++;
        }
        blocks.add(
          _MarkdownBlock(
            type: _MarkdownBlockType.footnotes,
            content: footnoteBuffer.join('\n').trim(),
          ),
        );
        continue;
      }

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

  _HtmlDetails _parseHtmlDetails(String html) {
    final summaryMatch = RegExp(
      r'<summary>([\s\S]*?)</summary>',
      caseSensitive: false,
    ).firstMatch(html);
    final title = summaryMatch?.group(1)?.trim() ?? '详情';
    var content = html
        .replaceFirst(RegExp(r'^<details[^>]*>\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'</details>\s*$', caseSensitive: false), '');
    if (summaryMatch != null) {
      content = content.replaceFirst(summaryMatch.group(0)!, '');
    }
    return _HtmlDetails(title: title, content: content.trim());
  }

  String? _extractHtmlMediaSource(String html) {
    final sourceMatch = RegExp(
      r'''<source[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (sourceMatch != null) return sourceMatch.group(1)?.trim();
    final directMatch = RegExp(
      r'''<(?:audio|video)[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    return directMatch?.group(1)?.trim();
  }
}

enum _SegmentType { markdown, blockLatex }

enum _MarkdownBlockType { markdown, details, footnotes, media }

class _Segment {
  final _SegmentType type;
  final String content;
  const _Segment(this.type, this.content);
}

class _MarkdownBlock {
  final _MarkdownBlockType type;
  final String content;
  final String? title;

  const _MarkdownBlock({required this.type, required this.content, this.title});
}

class _HtmlDetails {
  final String title;
  final String content;

  const _HtmlDetails({required this.title, required this.content});
}

class _InlineMathSyntax extends md.InlineSyntax {
  _InlineMathSyntax()
    : super(r'(?<!\\)\$(?!\$)([^$\n]+?)(?<!\\)\$', startCharacter: 36);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final latex = match.group(1)?.trim();
    if (latex == null || latex.isEmpty) return false;
    parser.addNode(md.Element.text('math', latex));
    return true;
  }
}

class _FixedPaddingBuilder extends MarkdownPaddingBuilder {
  final EdgeInsets padding;

  _FixedPaddingBuilder(this.padding);

  @override
  EdgeInsets getPadding() => padding;
}

class _FootnoteSectionPaddingBuilder extends MarkdownPaddingBuilder {
  bool _isFootnotes = false;

  @override
  void visitElementBefore(md.Element element) {
    _isFootnotes = element.attributes['class'] == 'footnotes';
  }

  @override
  EdgeInsets getPadding() =>
      _isFootnotes ? const EdgeInsets.fromLTRB(0, 16, 0, 0) : EdgeInsets.zero;
}

/// 自定义表格：表头行背景 + 斑马纹交替行 + 圆角边框。
///
/// flutter_markdown 默认表格只有边框，这里解析 `table/tr/th/td` 结构
/// 渲染为视觉更清晰的样式；不支持的复杂结构（如合并单元格）按普通行渲染。
class _StyledTableBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final rows = <List<String>>[];
    final isHeader = <bool>[];
    final elementChildren = element.children ?? const <md.Node>[];
    for (final row in elementChildren.whereType<md.Element>()) {
      final cells = <String>[];
      var header = false;
      final rowChildren = row.children ?? const <md.Node>[];
      for (final cell in rowChildren.whereType<md.Element>()) {
        final tag = cell.tag.toLowerCase();
        header = header || tag == 'th';
        cells.add(cell.textContent.trim());
      }
      if (cells.isNotEmpty) {
        rows.add(cells);
        isHeader.add(header);
      }
    }
    if (rows.isEmpty) return null;
    return _StyledTable(rows: rows, isHeader: isHeader);
  }
}

class _StyledTable extends StatelessWidget {
  final List<List<String>> rows;
  final List<bool> isHeader;

  const _StyledTable({required this.rows, required this.isHeader});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white24 : const Color(0xFFD0D7DE);
    final headerBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : const Color(0xFFF0F2F5);
    final zebraBg = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : const Color(0xFFFAFBFC);

    final columnCount = rows.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Table(
        border: TableBorder(
          horizontalInside: BorderSide(color: borderColor, width: 0.5),
          verticalInside: BorderSide(color: borderColor, width: 0.5),
        ),
        defaultColumnWidth: const FlexColumnWidth(),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: BoxDecoration(
                color: isHeader[r]
                    ? headerBg
                    : (r.isOdd ? zebraBg : null),
              ),
              children: [
                for (var c = 0; c < columnCount; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    child: Text(
                      c < rows[r].length ? rows[r][c] : '',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: scheme.onSurface,
                        fontWeight: isHeader[r]
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    String? language;
    final className = element.attributes['class'] ?? '';
    if (className.startsWith('language-')) {
      language = className.substring(9);
    }
    final code = element.textContent;
    final normalizedLanguage = language?.toLowerCase();
    if (_isMermaidLanguage(normalizedLanguage) ||
        (language == null && _looksLikeMermaid(code))) {
      return MermaidWidget(code: code);
    }
    if (_isDrawioLanguage(normalizedLanguage) || _looksLikeDrawio(code)) {
      return DrawioWidget(code: code);
    }
    if (language == null && !code.contains('\n')) {
      return null;
    }
    return CodeBlockWidget(code: code, language: language);
  }

  bool _isMermaidLanguage(String? language) {
    return language == 'mermaid' || language == 'mmd';
  }

  bool _isDrawioLanguage(String? language) {
    return language == 'drawio' ||
        language == 'draw.io' ||
        language == 'mxgraph' ||
        language == 'diagrams.net';
  }

  bool _looksLikeMermaid(String code) {
    final firstLine = code
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '')
        .toLowerCase();
    return firstLine.startsWith('graph ') ||
        firstLine.startsWith('flowchart ') ||
        firstLine.startsWith('sequencediagram') ||
        firstLine.startsWith('classdiagram') ||
        firstLine.startsWith('statediagram') ||
        firstLine.startsWith('erdiagram') ||
        firstLine.startsWith('gantt') ||
        firstLine.startsWith('journey') ||
        firstLine.startsWith('pie') ||
        firstLine.startsWith('mindmap') ||
        firstLine.startsWith('timeline') ||
        firstLine.startsWith('gitgraph') ||
        firstLine.startsWith('quadrantchart') ||
        firstLine.startsWith('xychart');
  }

  bool _looksLikeDrawio(String code) {
    final lower = code.toLowerCase();
    return lower.contains('<mxgraphmodel') ||
        lower.contains('<mxfile') ||
        lower.contains('<mxcell');
  }
}

class _InlineMathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final latex = element.textContent.trim();
    if (latex.isEmpty) return const SizedBox.shrink();
    final baseStyle =
        parentStyle ?? preferredStyle ?? DefaultTextStyle.of(context).style;
    final textStyle = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 15) * 0.98,
      color: baseStyle.color ?? Theme.of(context).colorScheme.onSurface,
    );
    return Math.tex(
      latex,
      textStyle: textStyle,
      onErrorFallback: (_) =>
          Text(latex, style: textStyle.copyWith(fontFamily: 'monospace')),
    );
  }
}
