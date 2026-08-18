import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'code_block_widget.dart';

/// HTML 页面工件：AI 生成的完整 HTML 文档不再是普通代码块，而是
/// 「可预览 / 可复制 / 可下载」的工件卡片。预览在应用内 WebView 打开，
/// 支持再次点击重复查看。
class HtmlArtifactCard extends StatelessWidget {
  final String code;

  const HtmlArtifactCard({super.key, required this.code});

  static bool looksLikeHtmlDocument(String code) {
    final lower = code.trim().toLowerCase();
    return lower.startsWith('<!doctype') ||
        lower.startsWith('<html');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Icon(Icons.web_asset_outlined, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'HTML 页面工件',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('html-artifact-preview'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _HtmlArtifactPage(code: code),
                      ),
                    );
                  },
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('预览', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          CodeBlockWidget(code: code, language: 'html'),
        ],
      ),
    );
  }
}

/// 全屏 HTML 预览页：应用内 WebView 渲染，不落文件、不暴露地址。
class _HtmlArtifactPage extends StatefulWidget {
  const _HtmlArtifactPage({required this.code});

  final String code;

  @override
  State<_HtmlArtifactPage> createState() => _HtmlArtifactPageState();
}

class _HtmlArtifactPageState extends State<_HtmlArtifactPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // 工件内的链接一律外跳系统浏览器，避免被页面劫持。
            if (request.isMainFrame && request.url.startsWith('http')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(widget.code);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('页面预览')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
