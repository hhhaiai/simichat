import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Mermaid 图表渲染组件
/// 使用 WebView 渲染 mermaid 语法
class MermaidWidget extends StatelessWidget {
  final String code;

  const MermaidWidget({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey[300]!,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 工具栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(Icons.account_tree, size: 14,
                    color: isDark ? Colors.white54 : Colors.grey[600]),
                const SizedBox(width: 6),
                Text('Mermaid 图表',
                    style: TextStyle(fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey[600])),
                const Spacer(),
                InkWell(
                  onTap: () => _showFullScreen(context),
                  child: Icon(Icons.fullscreen, size: 18,
                      color: isDark ? Colors.white54 : Colors.grey[600]),
                ),
              ],
            ),
          ),
          // 图表预览
          SizedBox(
            height: 200,
            child: _MermaidWebView(code: code, isDark: isDark),
          ),
        ],
      ),
    );
  }

  void _showFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MermaidFullScreen(code: code),
      ),
    );
  }
}

class _MermaidFullScreen extends StatelessWidget {
  final String code;
  const _MermaidFullScreen({required this.code});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Mermaid 图表')),
      body: Center(
        child: _MermaidWebView(code: code, isDark: isDark),
      ),
    );
  }
}

class _MermaidWebView extends StatefulWidget {
  final String code;
  final bool isDark;
  const _MermaidWebView({required this.code, required this.isDark});

  @override
  State<_MermaidWebView> createState() => _MermaidWebViewState();
}

class _MermaidWebViewState extends State<_MermaidWebView> {
  late final WebViewController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loaded = true);
        },
      ))
      ..loadHtmlString(_buildHtml());
  }

  String _buildHtml() {
    final bgColor = widget.isDark ? '#1E1E1E' : '#FFFFFF';
    final textColor = widget.isDark ? '#E0E0E0' : '#333333';
    // Escape the code for HTML
    final escapedCode = widget.code
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');

    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body {
    background: $bgColor;
    margin: 0;
    padding: 16px;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
    box-sizing: border-box;
  }
  #container {
    max-width: 100%;
    overflow: auto;
  }
  .mermaid {
    color: $textColor;
  }
</style>
</head>
<body>
<div id="container">
  <pre class="mermaid">$escapedCode</pre>
</div>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<script>
  mermaid.initialize({
    startOnLoad: true,
    theme: '${widget.isDark ? 'dark' : 'default'}',
    securityLevel: 'loose',
    fontFamily: 'sans-serif'
  });
</script>
</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return WebViewWidget(controller: _controller);
  }
}
