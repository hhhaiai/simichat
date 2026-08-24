import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 在 WebView 内提供最小、可逆的组件选择能力。只在用户明确点击卡片右下
/// 角“编辑”后注入，不改变普通预览页面的 DOM 行为；选中的叶子节点通过
/// JavaScript channel 回传给 Flutter，文字和颜色修改仍由 Flutter 保存为
/// 当前 Artifact 草稿。
const _visualEditorScript = r'''
(function () {
  if (window.__simichatEditorInstalled) {
    window.__simichatInstallEditor && window.__simichatInstallEditor();
    return;
  }
  window.__simichatEditorInstalled = true;
  window.__simichatSelectedElement = null;
  window.__simichatCleanupEditor = function () {
    document.querySelectorAll('[data-simichat-editor-outline]').forEach(function (el) {
      el.removeAttribute('data-simichat-editor-outline');
      el.style.removeProperty('outline');
      el.style.removeProperty('cursor');
      if (el.__simichatEditorBound) {
        el.onclick = el.__simichatOriginalOnClick || null;
        delete el.__simichatOriginalOnClick;
        delete el.__simichatEditorBound;
      }
    });
    window.__simichatSelectedElement = null;
    window.__simichatEditorInstalled = false;
  };
  window.__simichatInstallEditor = function () {
    document.querySelectorAll('[data-simichat-editor-outline]').forEach(function (el) {
      el.removeAttribute('data-simichat-editor-outline');
      el.style.removeProperty('outline');
      el.style.removeProperty('cursor');
    });
    document.querySelectorAll('body *').forEach(function (el) {
      if (!el.textContent || !el.textContent.trim() || el.children.length > 0) return;
      el.setAttribute('data-simichat-editor-outline', 'true');
      el.style.outline = '1px dashed rgba(80, 100, 220, .45)';
      el.style.cursor = 'text';
      if (!el.__simichatEditorBound) {
        el.__simichatOriginalOnClick = el.onclick;
        el.__simichatEditorBound = true;
      }
      el.onclick = function (event) {
        event.preventDefault();
        event.stopPropagation();
        window.__simichatSelectedElement = el;
        var computed = window.getComputedStyle(el);
        window.simichatEditor.postMessage(JSON.stringify({
          text: el.innerText || el.textContent || '',
          color: computed.color || ''
        }));
      };
    });
  };
  window.__simichatApply = function (text, color) {
    var el = window.__simichatSelectedElement;
    if (!el) return;
    try { el.innerText = text || ''; } catch (_) {}
    if (color && color.trim()) el.style.color = color.trim();
  };
  window.__simichatInstallEditor();
})();
''';

/// HTML / Markdown 生成结果的紧凑成果卡片。
///
/// 聊天时间线只展示文件元数据和操作入口，完整源码与预览统一放在
/// [ArtifactWorkbenchPage] 全屏工作台中，避免长源码挤占消息阅读空间。
class HtmlArtifactCard extends StatelessWidget {
  final String code;
  final String name;

  const HtmlArtifactCard({
    super.key,
    required this.code,
    this.name = 'artifact.html',
  });

  static bool looksLikeHtmlDocument(String code) {
    final lower = code.trim().toLowerCase();
    return lower.startsWith('<!doctype') || lower.startsWith('<html');
  }

  @override
  Widget build(BuildContext context) {
    return ArtifactFileCard(
      key: key,
      name: name,
      type: ArtifactType.html,
      source: code,
    );
  }
}

/// 显式 Markdown 文件（例如 ```markdown ... ```）的成果卡片。
class MarkdownArtifactCard extends StatelessWidget {
  final String markdown;
  final String name;

  const MarkdownArtifactCard({
    super.key,
    required this.markdown,
    this.name = 'artifact.md',
  });

  @override
  Widget build(BuildContext context) {
    return ArtifactFileCard(
      key: key,
      name: name,
      type: ArtifactType.markdown,
      source: markdown,
    );
  }
}

enum ArtifactType { html, markdown }

extension on ArtifactType {
  String get label => this == ArtifactType.html ? 'HTML' : 'Markdown';

  String get extension => this == ArtifactType.html ? 'html' : 'md';
}

class ArtifactFileCard extends StatefulWidget {
  const ArtifactFileCard({
    super.key,
    required this.name,
    required this.type,
    required this.source,
  });

  final String name;
  final ArtifactType type;
  final String source;

  @override
  State<ArtifactFileCard> createState() => _ArtifactFileCardState();
}

class _ArtifactFileCardState extends State<ArtifactFileCard> {
  late String _source;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
  }

  @override
  void didUpdateWidget(covariant ArtifactFileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A newly rendered assistant artifact is authoritative until the user
    // edits this card locally. Parent rebuilds with the same source must not
    // discard a draft that is still visible in the current timeline.
    if (oldWidget.source != widget.source && oldWidget.source != _source) {
      _source = widget.source;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = _formatBytes(_source.length);
    return Container(
      key: ValueKey('artifact-card-${widget.name}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.type == ArtifactType.html ? 'H' : 'M',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.type.label} · $size · ${widget.type == ArtifactType.html ? '可交互预览' : '阅读视图'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  key: ValueKey('artifact-preview-${widget.name}'),
                  onPressed: () =>
                      _openWorkbench(context, ArtifactWorkbenchMode.preview),
                  child: const Text('查看效果'),
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                TextButton(
                  key: ValueKey('artifact-source-${widget.name}'),
                  onPressed: () =>
                      _openWorkbench(context, ArtifactWorkbenchMode.source),
                  child: const Text('源码'),
                ),
                TextButton(
                  key: ValueKey('artifact-download-${widget.name}'),
                  onPressed: () => _saveArtifact(context),
                  child: const Text('下载'),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  key: ValueKey('artifact-edit-${widget.name}'),
                  onPressed: () =>
                      _openWorkbench(context, ArtifactWorkbenchMode.visual),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('编辑'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openWorkbench(BuildContext context, ArtifactWorkbenchMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ArtifactWorkbenchPage(
          name: widget.name,
          type: widget.type,
          source: _source,
          initialMode: mode,
          onSave: (updatedSource) {
            if (!mounted) return;
            setState(() => _source = updatedSource);
          },
        ),
      ),
    );
  }

  Future<void> _saveArtifact(BuildContext context) async {
    try {
      final root = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(root.path, 'artifact_exports'));
      await dir.create(recursive: true);
      // Artifact names can originate from model output. Keep the export
      // inside artifact_exports instead of allowing ../ or platform path
      // separators to escape the intended directory.
      final candidate = p.basename(widget.name.trim().replaceAll('\\', '/'));
      final safeName =
          candidate.isEmpty || candidate == '.' || candidate == '..'
          ? 'artifact.${widget.type.extension}'
          : candidate.replaceAll(RegExp(r'[^A-Za-z0-9._\-\u4e00-\u9fff]'), '_');
      final path = p.join(dir.path, safeName);
      await File(path).writeAsString(_source);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已保存：$path')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

enum ArtifactWorkbenchMode { preview, visual, source }

/// HTML / Markdown 独立全屏工作台。源码编辑为本地草稿，关闭页面前保留在
/// 当前页面状态中；接入 Artifact DAO 时只需把 [onSave] 接到版本服务。
class ArtifactWorkbenchPage extends StatefulWidget {
  const ArtifactWorkbenchPage({
    super.key,
    required this.name,
    required this.type,
    required this.source,
    this.initialMode = ArtifactWorkbenchMode.preview,
    this.onSave,
  });

  final String name;
  final ArtifactType type;
  final String source;
  final ArtifactWorkbenchMode initialMode;
  final ValueChanged<String>? onSave;

  @override
  State<ArtifactWorkbenchPage> createState() => _ArtifactWorkbenchPageState();
}

class _ArtifactWorkbenchPageState extends State<ArtifactWorkbenchPage> {
  late ArtifactWorkbenchMode _mode;
  late final TextEditingController _sourceController;
  late final WebViewController _webController;
  bool _dirty = false;
  bool _wrapLines = true;
  bool _visualEditing = false;
  final _visualTextController = TextEditingController();
  final _visualColorController = TextEditingController();
  Future<void>? _previewLoadFuture;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _sourceController = TextEditingController(text: widget.source)
      ..addListener(_onSourceChanged);
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'simichatEditor',
        onMessageReceived: _handleEditorMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // HTML 只能在当前沙箱文档内导航，避免页面接管主应用路由；
            // 外部链接由用户在源码 / 下载后主动打开。
            if (request.isMainFrame &&
                (request.url.startsWith('http://') ||
                    request.url.startsWith('https://'))) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    _loadHtmlPreview();
  }

  void _onSourceChanged() {
    if (mounted && !_dirty) setState(() => _dirty = true);
  }

  void _handleEditorMessage(JavaScriptMessage message) {
    try {
      final value = jsonDecode(message.message);
      if (value is! Map) return;
      final text = value['text'] is String ? value['text'] as String : '';
      final color = value['color'] is String ? value['color'] as String : '';
      if (!mounted) return;
      setState(() {
        _visualEditing = true;
        _visualTextController.text = text;
        _visualColorController.text = color;
      });
    } catch (_) {
      // WebView 消息只来自编辑器注入脚本；格式异常时不打断预览。
    }
  }

  Future<void> _enableVisualEditing() async {
    if (widget.type != ArtifactType.html) return;
    try {
      // The FAB is available immediately after navigation. Wait for the
      // initial document load so the editor script is not sent to an empty
      // WebView, then leave the page in preview mode if the platform rejects
      // the early JavaScript call.
      await _previewLoadFuture;
      await _webController.runJavaScript(_visualEditorScript);
      if (mounted) setState(() => _visualEditing = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('页面尚未加载完成，请稍后再试')));
      }
    }
  }

  Future<void> _applyVisualElementChanges() async {
    if (!_visualEditing) return;
    final text = jsonEncode(_visualTextController.text);
    final color = jsonEncode(_visualColorController.text.trim());
    await _webController.runJavaScript(
      'window.__simichatApply($text, $color);',
    );
    final result = await _webController.runJavaScriptReturningResult(
      'document.documentElement.outerHTML',
    );
    final html = _decodeJavaScriptString(result);
    if (html != null && html.trim().isNotEmpty) {
      _sourceController.value = TextEditingValue(
        text: html,
        selection: TextSelection.collapsed(offset: html.length),
      );
    }
    await _loadHtmlPreview();
    await _webController.runJavaScript(_visualEditorScript);
  }

  String? _decodeJavaScriptString(Object? value) {
    if (value is! String) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is String ? decoded : value;
    } catch (_) {
      return value;
    }
  }

  Future<void> _loadHtmlPreview() async {
    if (widget.type != ArtifactType.html) return;
    final load = _webController.loadHtmlString(_sourceController.text);
    _previewLoadFuture = load;
    await load;
  }

  Future<void> _disableVisualEditing() async {
    if (!_visualEditing || widget.type != ArtifactType.html) return;
    try {
      await _webController.runJavaScript(
        'window.__simichatCleanupEditor && window.__simichatCleanupEditor();',
      );
    } catch (_) {
      // The WebView may already be disposed while navigating away.
    }
    if (mounted) setState(() => _visualEditing = false);
  }

  @override
  void dispose() {
    _sourceController
      ..removeListener(_onSourceChanged)
      ..dispose();
    _visualTextController.dispose();
    _visualColorController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave?.call(_sourceController.text);
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('草稿已保存'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            key: const ValueKey('artifact-workbench-save'),
            onPressed: _dirty ? _save : null,
            child: Text(_dirty ? '保存' : '已保存'),
          ),
          PopupMenuButton<String>(
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'versions', child: Text('版本历史')),
              PopupMenuItem(value: 'download', child: Text('下载')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildModeBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildModeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SegmentedButton<ArtifactWorkbenchMode>(
        key: const ValueKey('artifact-workbench-mode-bar'),
        segments: const [
          ButtonSegment(
            value: ArtifactWorkbenchMode.preview,
            label: Text('查看效果'),
          ),
          ButtonSegment(
            value: ArtifactWorkbenchMode.visual,
            label: Text('可视化编辑'),
          ),
          ButtonSegment(value: ArtifactWorkbenchMode.source, label: Text('源码')),
        ],
        selected: {_mode},
        onSelectionChanged: (values) async {
          final next = values.single;
          if (_mode == ArtifactWorkbenchMode.visual &&
              next != ArtifactWorkbenchMode.visual) {
            await _disableVisualEditing();
          }
          if (mounted) setState(() => _mode = next);
          if (next == ArtifactWorkbenchMode.preview) await _loadHtmlPreview();
        },
      ),
    );
  }

  Widget _buildBody() {
    return switch (_mode) {
      ArtifactWorkbenchMode.preview =>
        widget.type == ArtifactType.html
            ? Column(
                children: [
                  _buildPreviewToolbar(),
                  Expanded(child: WebViewWidget(controller: _webController)),
                ],
              )
            : _buildMarkdownPreview(),
      ArtifactWorkbenchMode.visual => _buildVisualEditor(),
      ArtifactWorkbenchMode.source => _buildSourceEditor(),
    };
  }

  Widget _buildPreviewToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        children: [
          ActionChip(label: const Text('适应宽度'), onPressed: _loadHtmlPreview),
          ActionChip(label: const Text('手机'), onPressed: _loadHtmlPreview),
          ActionChip(label: const Text('刷新'), onPressed: _loadHtmlPreview),
        ],
      ),
    );
  }

  Widget _buildMarkdownPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: MarkdownBody(
        data: _sourceController.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: const TextStyle(fontSize: 15, height: 1.6),
          h1: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          h2: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          code: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }

  Widget _buildVisualEditor() {
    if (widget.type == ArtifactType.html) {
      return Stack(
        children: [
          WebViewWidget(controller: _webController),
          if (!_visualEditing)
            Positioned(
              right: 16,
              bottom: 18,
              child: FloatingActionButton.extended(
                key: const ValueKey('artifact-visual-edit-fab'),
                onPressed: _enableVisualEditing,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
            ),
          if (_visualEditing) _buildVisualEditorPanel(),
        ],
      );
    }
    return _buildSourceEditor(showVisualHint: true);
  }

  Widget _buildVisualEditorPanel() {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.touch_app_outlined, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '点击页面中的组件后修改文字或颜色',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: '退出编辑',
                    onPressed: _disableVisualEditing,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              TextField(
                key: const ValueKey('artifact-visual-text-editor'),
                controller: _visualTextController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '组件文字',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('artifact-visual-color-editor'),
                controller: _visualColorController,
                decoration: const InputDecoration(
                  labelText: '文字颜色（#RRGGBB 或 CSS 颜色）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('artifact-visual-apply'),
                  onPressed: _applyVisualElementChanges,
                  icon: const Icon(Icons.check, size: 17),
                  label: const Text('应用修改'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceEditor({bool showVisualHint = false}) {
    return Column(
      children: [
        if (showVisualHint)
          const ListTile(
            dense: true,
            leading: Icon(Icons.view_agenda_outlined),
            title: Text('块级编辑'),
            subtitle: Text('可先编辑当前内容，后续版本将支持块类型、排序和 AI 定向修改。'),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text(
                widget.type.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(_wrapLines ? '自动换行' : '横向滚动'),
              Switch(
                value: _wrapLines,
                onChanged: (value) => setState(() => _wrapLines = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: TextField(
            key: const ValueKey('artifact-source-editor'),
            controller: _sourceController,
            expands: true,
            maxLines: null,
            minLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            ),
          ),
        ),
      ],
    );
  }
}
