import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/github.dart';
import 'package:flutter_highlighter/themes/dracula.dart';

/// 代码块组件：语法高亮 + 行号 + 语言标签 + 复制按钮
/// 参考 GitHub / VS Code 的代码块渲染风格
class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String? language;

  const CodeBlockWidget({
    super.key,
    required this.code,
    this.language,
  });

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  bool _copied = false;
  bool _expanded = true; // 长代码默认展开

  static const _maxCollapsedLines = 10;

  String get _language => widget.language ?? 'text';

  late final List<String> _lines = widget.code.split('\n');

  bool get _isLong => _lines.length > _maxCollapsedLines;

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// 获取语言对应的图标
  IconData _getLanguageIcon() {
    switch (_language.toLowerCase()) {
      case 'dart':
        return Icons.flutter_dash;
      case 'python':
      case 'py':
        return Icons.code;
      case 'javascript':
      case 'js':
      case 'typescript':
      case 'ts':
        return Icons.javascript;
      case 'html':
      case 'xml':
        return Icons.html;
      case 'css':
      case 'scss':
      case 'less':
        return Icons.css;
      case 'json':
        return Icons.data_object;
      case 'yaml':
      case 'yml':
        return Icons.settings;
      case 'bash':
      case 'sh':
      case 'shell':
      case 'zsh':
        return Icons.terminal;
      case 'sql':
        return Icons.storage;
      case 'markdown':
      case 'md':
        return Icons.description;
      case 'rust':
        return Icons.build;
      case 'go':
        return Icons.g_mobiledata;
      case 'java':
      case 'kotlin':
        return Icons.coffee;
      case 'swift':
      case 'objc':
        return Icons.phone_iphone;
      case 'c':
      case 'cpp':
      case 'csharp':
        return Icons.memory;
      default:
        return Icons.code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF8F9FA);
    final borderColor = isDark ? Colors.white10 : const Color(0xFFE1E4E8);
    final headerBg = isDark ? const Color(0xFF2D2D3F) : const Color(0xFFFAFBFC);
    final lineNumColor = isDark ? Colors.white24 : Colors.grey[400];
    final code = _expanded || !_isLong ? widget.code : widget.code.split('\n').take(_maxCollapsedLines).join('\n');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部：语言标签 + 操作按钮
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(
                bottom: BorderSide(color: borderColor, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(_getLanguageIcon(), size: 14, color: isDark ? Colors.white54 : Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  _language.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white54 : Colors.grey[600],
                  ),
                ),
                if (_isLong) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${_lines.length} 行',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.grey[400],
                    ),
                  ),
                ],
                const Spacer(),
                // 展开/折叠按钮
                if (_isLong)
                  InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _expanded ? Icons.unfold_less : Icons.unfold_more,
                            size: 14,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _expanded ? '折叠' : '展开',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 复制按钮
                InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 14,
                          color: _copied ? Colors.green : (isDark ? Colors.white54 : Colors.grey[600]),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? '已复制' : '复制',
                          style: TextStyle(
                            fontSize: 11,
                            color: _copied ? Colors.green : (isDark ? Colors.white54 : Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 代码内容（带行号）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 行号列
                Container(
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: borderColor, width: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      code.split('\n').length,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.5,
                            color: lineNumColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 代码内容
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: HighlightView(
                    code,
                    language: _language,
                    theme: isDark ? draculaTheme : githubTheme,
                    textStyle: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 底部：折叠时显示展开提示
          if (_isLong && !_expanded)
            InkWell(
              onTap: () => setState(() => _expanded = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border(top: BorderSide(color: borderColor, width: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.expand_more, size: 16, color: isDark ? Colors.white54 : Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '展开剩余 ${_lines.length - _maxCollapsedLines} 行',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
