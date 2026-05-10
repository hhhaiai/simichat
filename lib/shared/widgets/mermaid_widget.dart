import 'package:flutter/foundation.dart';
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
    final supportsWebViewPreview = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

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
            child: supportsWebViewPreview
                ? _MermaidWebView(code: code, isDark: isDark)
                : _MermaidFallback(code: code, isDark: isDark),
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
    final supportsWebViewPreview = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    return Scaffold(
      appBar: AppBar(title: const Text('Mermaid 图表')),
      body: Center(
        child: supportsWebViewPreview
            ? _MermaidWebView(code: code, isDark: isDark)
            : _MermaidFallback(code: code, isDark: isDark, fullScreen: true),
      ),
    );
  }
}

class _MermaidFallback extends StatelessWidget {
  final String code;
  final bool isDark;
  final bool fullScreen;

  const _MermaidFallback({
    required this.code,
    required this.isDark,
    this.fullScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(fullScreen ? 20 : 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(fullScreen ? 0 : 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前平台暂不支持 Mermaid 图表预览，先显示源码。',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.45,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
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

  // Mermaid CDN 地址列表（主 + 备用）
  static const _mermaidSources = [
    'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js',
    'https://unpkg.com/mermaid@10/dist/mermaid.min.js',
    'https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.0/mermaid.min.js',
  ];

  String _buildHtml() {
    final bgColor = widget.isDark ? '#1E1E1E' : '#FFFFFF';
    final textColor = widget.isDark ? '#E0E0E0' : '#333333';
    // Escape the code for HTML
    final escapedCode = widget.code
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');

    // 生成多源加载脚本
    final sourcesJson = _mermaidSources.map((s) => '"$s"').join(',');

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
  .error-message {
    color: #ff6b6b;
    padding: 16px;
    text-align: center;
    font-size: 14px;
  }
</style>
</head>
<body>
<div id="container">
  <pre class="mermaid">$escapedCode</pre>
</div>
<script>
  // 多源加载：依次尝试 CDN，任一成功即渲染
  var sources = [$sourcesJson];
  var idx = 0;

  function tryLoad() {
    if (idx >= sources.length) {
      document.getElementById('container').innerHTML =
        '<div class="error-message">⚠️ 无法加载 Mermaid 库（请检查网络连接）</div>';
      return;
    }
    var script = document.createElement('script');
    script.src = sources[idx];
    script.onload = function() {
      mermaid.initialize({
        startOnLoad: true,
        theme: '${widget.isDark ? 'dark' : 'default'}',
        securityLevel: 'loose',
        fontFamily: 'sans-serif'
      });
    };
    script.onerror = function() {
      idx++;
      tryLoad();
    };
    document.head.appendChild(script);
  }
  tryLoad();
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
