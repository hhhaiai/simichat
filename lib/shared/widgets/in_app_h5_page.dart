import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

const MethodChannel _inAppH5ProfileChannel = MethodChannel(
  'simichat/in_app_h5_profile',
);

/// 请求原生 WebView 把当前持久 profile 的 Cookie 变更提交到底层存储。
///
/// 登录态本身仍由系统 WebView 的默认持久 profile 保存（Cookie、
/// localStorage、IndexedDB 和磁盘资源缓存），App 不读取、复制或重建认证
/// Cookie，避免丢失 Secure / HttpOnly / SameSite / expires 等安全属性。
Future<bool> flushPersistentInAppH5Profile({
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (kIsWeb) return false;
  try {
    return await _inAppH5ProfileChannel
            .invokeMethod<bool>('flush')
            .timeout(timeout, onTimeout: () => false) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  } catch (_) {
    return false;
  }
}

/// Returns a safe HTTPS URI for an in-app H5 page.
///
/// The page intentionally accepts only web URLs. In particular, custom schemes
/// such as `intent:`, `mailto:` and `tel:` are never handed to the operating
/// system, so a registration or documentation link cannot jump out to another
/// app or the external browser.
Uri? normalizeInAppH5Url(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https') return null;
  if (uri.userInfo.isNotEmpty) return null;
  return uri;
}

/// 内置 H5 只允许留在初始可信 HTTPS host，阻止伪装成 SimiRouter 的跨域
/// 页面以及 HTTPS -> HTTP 降级。
bool isAllowedInAppH5Navigation(Uri target, Uri initialUri) {
  return target.scheme == 'https' &&
      target.userInfo.isEmpty &&
      target.host.toLowerCase() == initialUri.host.toLowerCase() &&
      target.port == initialUri.port;
}

bool get _supportsInAppWebView {
  if (kIsWeb || WebViewPlatform.instance == null) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    _ => false,
  };
}

/// 用一个短生命周期的隐藏 WebView 预热官方首页。
///
/// SimiRouter 的首页和注册页共享同一批带内容 hash 的 JS/CSS。WebView 默认
/// 使用系统持久磁盘缓存；设置页出现时先加载一次首页，用户随后点击“官网”或
/// “获取 Key”时可复用相同 profile 的资源缓存、Cookie 和 localStorage。
/// 预热完成或超时后立即销毁隐藏 WebView，避免长期占用内存。
class InAppH5Prewarm extends StatefulWidget {
  const InAppH5Prewarm({super.key, required this.url});

  final String url;

  @override
  State<InAppH5Prewarm> createState() => _InAppH5PrewarmState();
}

class _InAppH5PrewarmState extends State<InAppH5Prewarm> {
  static final Set<String> _activeOrigins = <String>{};
  static final Set<String> _completedOrigins = <String>{};

  WebViewController? _controller;
  Timer? _timeout;
  String? _origin;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final uri = normalizeInAppH5Url(widget.url);
    if (!_supportsInAppWebView || uri == null) return;
    final origin = uri.origin;
    if (_completedOrigins.contains(origin) || !_activeOrigins.add(origin)) {
      return;
    }
    _origin = origin;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final target = Uri.tryParse(request.url);
            return target != null && isAllowedInAppH5Navigation(target, uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageFinished: (_) => _finish(completed: true),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) _finish();
          },
        ),
      );
    _controller = controller;
    _timeout = Timer(const Duration(seconds: 12), _finish);
    unawaited(_load(controller, uri));
  }

  Future<void> _load(WebViewController controller, Uri uri) async {
    try {
      await controller.loadRequest(uri);
    } catch (_) {
      _finish();
    }
  }

  void _finish({bool completed = false}) {
    if (!mounted || _finished) return;
    _timeout?.cancel();
    final origin = _origin;
    if (origin != null) {
      _activeOrigins.remove(origin);
      if (completed) _completedOrigins.add(origin);
    }
    setState(() => _finished = true);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    final origin = _origin;
    if (!_finished && origin != null) _activeOrigins.remove(origin);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || _finished) return const SizedBox.shrink();
    return Offstage(
      offstage: true,
      child: SizedBox(
        width: 1,
        height: 1,
        child: WebViewWidget(controller: controller),
      ),
    );
  }
}

/// A native-feeling shell for a web flow that must stay inside SimiChat.
///
/// There is deliberately no address bar and the current URL is never rendered
/// as user-facing text. The top bar exposes only native navigation and refresh
/// actions; WebView history is used before the page itself is dismissed.
class InAppH5Page extends StatefulWidget {
  const InAppH5Page({
    super.key,
    required this.initialUrl,
    required this.title,
    this.brandAsset,
  });

  final String initialUrl;
  final String title;
  final String? brandAsset;

  @override
  State<InAppH5Page> createState() => InAppH5PageState();
}

class InAppH5PageState extends State<InAppH5Page> with WidgetsBindingObserver {
  /// 原生 profile flush 合并队列，避免页面完成、SPA 路由和生命周期事件
  /// 在短时间内堆积多个平台调用。执行中的请求最多再合并一个尾随请求。
  Future<void>? _profileFlushWork;
  bool _profileFlushQueued = false;

  WebViewController? _controller;
  Uri? _initialUri;
  String? _errorMessage;
  double _progress = 0;
  bool _loading = true;
  bool _closing = false;
  DateTime? _lastBlockedNavigationNoticeAt;

  /// 当前 WebView 控制器，供集成测试等外部访问（页面未就绪时为 null）。
  WebViewController? get controller => _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialUri = normalizeInAppH5Url(widget.initialUrl);
    if (!_supportsInAppWebView || _initialUri == null) {
      _loading = false;
      _errorMessage = _initialUri == null ? '页面地址无效' : '当前设备暂不支持内置 H5 页面';
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final uri = Uri.tryParse(request.url);
            if (uri != null && isAllowedInAppH5Navigation(uri, _initialUri!)) {
              return NavigationDecision.navigate;
            }
            _showBlockedNavigationNotice();
            // Keep cross-origin, intent/mailto/tel and other custom schemes
            // inside the app instead of silently handing them to the OS.
            return NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _progress = 0;
              _errorMessage = null;
            });
          },
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress.clamp(0, 100) / 100;
              _loading = progress < 100;
            });
          },
          onPageFinished: (url) {
            // 登录 / 跳转完成后让原生 WebView 提交 Cookie 变更；账号资料与
            // 资源缓存由同一个默认持久 profile 自动保留。
            _queueProfileFlush();
            if (!mounted) return;
            setState(() {
              _progress = 1;
              _loading = false;
            });
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url == null) return;
            // SPA 登录常通过 history API 切换路由，不一定再次触发
            // onPageFinished；URL 变化时也提交一次 Cookie 变更。
            _queueProfileFlush();
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame != true) return;
            setState(() {
              _loading = false;
              _errorMessage = '页面暂时无法加载，请检查网络后重试';
            });
          },
        ),
      );
    _controller = controller;
    // WebViewController 使用系统默认的持久数据 profile；登录后的 Cookie、
    // localStorage 与网页缓存会在官网 / 获取 Key / 关于页之间复用。
    unawaited(_loadInitialPage(controller, _initialUri!));
  }

  Future<void> _loadInitialPage(
    WebViewController controller,
    Uri initialUri,
  ) async {
    try {
      await controller.loadRequest(initialUri);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '页面暂时无法加载，请检查网络后重试';
      });
    }
  }

  void _showBlockedNavigationNotice() {
    if (!mounted || _closing) return;
    final now = DateTime.now();
    final last = _lastBlockedNavigationNoticeAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastBlockedNavigationNoticeAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('为保护账号，应用内只打开当前官方站点')));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 退出页面时兜底提交一次 Cookie 变更；不阻塞 Widget 销毁。
    if (_controller != null && !_closing) _queueProfileFlush();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_controller != null) _queueProfileFlush();
    }
  }

  Future<void> _queueProfileFlush() {
    _profileFlushQueued = true;
    final active = _profileFlushWork;
    if (active != null) return active;

    late final Future<void> work;
    work = _drainProfileFlushQueue();
    _profileFlushWork = work;
    unawaited(
      work.whenComplete(() {
        if (!identical(_profileFlushWork, work)) return;
        _profileFlushWork = null;
        // 若请求恰好发生在 drain 循环退出与 whenComplete 执行之间，
        // 旧 work 已无法再消费 queued 标记；这里补启动一轮，避免最后
        // 一次登录 Cookie 提交被极窄竞态遗漏。
        if (_profileFlushQueued) _queueProfileFlush();
      }),
    );
    return work;
  }

  Future<void> _drainProfileFlushQueue() async {
    while (_profileFlushQueued) {
      _profileFlushQueued = false;
      await flushPersistentInAppH5Profile();
    }
  }

  Future<void> _flushProfileAndClose() async {
    if (_closing) return;
    _closing = true;
    if (_controller != null) {
      // 不让 WebView 平台通道拖住关闭交互；已有与尾随 flush 会继续在后台
      // 安全收尾，但用户最多等待一个 flush 超时窗口。
      await _queueProfileFlush().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    }
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null) {
      // PopScope 需要拦截系统返回键以优先处理 WebView 历史；显式关闭则
      // 直接移除当前 H5 路由，避免再被 canPop=false 拦截。
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _handleBack() async {
    final controller = _controller;
    if (controller != null) {
      try {
        if (await controller.canGoBack()) {
          await controller.goBack();
          return;
        }
      } catch (_) {
        // WebView 已销毁或平台调用失败时仍允许退出当前页面。
      }
    }
    await _flushProfileAndClose();
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _errorMessage = null;
      _loading = true;
      _progress = 0;
    });
    try {
      await controller.reload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '页面暂时无法加载，请检查网络后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => _handleBack(),
          ),
          titleSpacing: 0,
          title: Row(
            children: [
              if (widget.brandAsset != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    widget.brandAsset!,
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            if (_controller != null)
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
                onPressed: () => _reload(),
              ),
            // 直接关闭整个 H5 页面，避免登录 / 注册完成后只能一步步返回。
            IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close),
              onPressed: () => _flushProfileAndClose(),
            ),
          ],
        ),
        body: _buildBody(context, scheme),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme scheme) {
    final controller = _controller;
    if (controller == null) {
      return _H5StatusView(
        icon: _initialUri == null
            ? Icons.link_off_outlined
            : Icons.web_asset_off_outlined,
        title: _errorMessage ?? '无法打开页面',
        message: _initialUri == null
            ? '请稍后重试'
            : '请在 Android、iPhone 或 Mac 上使用内置页面访问。',
        onBack: () => unawaited(_flushProfileAndClose()),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: controller),
        if (_loading && _progress == 0)
          Positioned.fill(
            child: ColoredBox(
              color: scheme.surface,
              child: _H5LoadingView(
                title: widget.title,
                brandAsset: widget.brandAsset,
              ),
            ),
          ),
        if (_loading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 2,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        if (_errorMessage != null)
          Positioned.fill(
            child: ColoredBox(
              color: scheme.surface,
              child: _H5StatusView(
                icon: Icons.cloud_off_outlined,
                title: _errorMessage!,
                message: '网络恢复后可以点击刷新重新加载。',
                onBack: () => unawaited(_flushProfileAndClose()),
                onRetry: () => _reload(),
              ),
            ),
          ),
      ],
    );
  }
}

class _H5LoadingView extends StatelessWidget {
  const _H5LoadingView({required this.title, this.brandAsset});

  final String title;
  final String? brandAsset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (brandAsset != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                brandAsset!,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            )
          else
            Icon(Icons.language, size: 56, color: scheme.primary),
          const SizedBox(height: 16),
          Text('正在打开$title', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '正在复用网页缓存和登录状态…',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ],
      ),
    );
  }
}

class _H5StatusView extends StatelessWidget {
  const _H5StatusView({
    required this.icon,
    required this.title,
    required this.message,
    required this.onBack,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                OutlinedButton(onPressed: onBack, child: const Text('返回')),
                if (onRetry != null)
                  FilledButton(onPressed: onRetry, child: const Text('刷新')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
