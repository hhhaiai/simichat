import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开外部链接（注册页 / 文档 / 鸣谢页）的抽象。
///
/// 独立成接口以便 widget 测试注入假的实现，避免在测试中触发真实系统浏览器。
abstract interface class ExternalUrlOpener {
  /// 尝试在系统浏览器中打开 [url]。
  ///
  /// 仅允许 HTTP(S) 链接，避免被恶意 / 误输入的自定义 scheme 拖入其他应用。
  /// 返回是否成功打开；失败时调用方应回退为“复制链接”提示。
  Future<bool> open(String url);
}

/// 生产实现：调用系统浏览器打开外部链接。
class SystemBrowserUrlOpener implements ExternalUrlOpener {
  const SystemBrowserUrlOpener();

  @override
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    // 只放行 HTTP(S)：注册 / 文档 / 鸣谢页均为公网站点。
    if (uri.scheme != 'https' && uri.scheme != 'http') return false;
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 默认使用系统浏览器；测试可通过 provider override 替换。
final externalUrlOpenerProvider = Provider<ExternalUrlOpener>((ref) {
  return const SystemBrowserUrlOpener();
});
