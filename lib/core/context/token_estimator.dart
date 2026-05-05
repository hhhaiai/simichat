/// 简易 Token 估算器
/// 目的：触发压缩阈值，不需要精确到 billing 级别
class TokenEstimator {
  // 预编译正则
  static final _wordRe = RegExp(r'[a-zA-Z0-9]+');

  /// 估算文本的 token 数
  /// 中文字符 × 2，英文单词 × 1.3，标点/空格 × 1
  static int estimate(String text) {
    if (text.isEmpty) return 0;

    int count = 0;
    int pos = 0;

    while (pos < text.length) {
      final char = text[pos];

      // 中文字符
      if (_isChinese(char)) {
        count += 2;
        pos++;
        continue;
      }

      // 英文单词
      final wordMatch = _wordRe.matchAsPrefix(text, pos);
      if (wordMatch != null) {
        count += (wordMatch.group(0)!.length * 1.3).ceil();
        pos += wordMatch.group(0)!.length;
        continue;
      }

      // 空白和标点
      count += 1;
      pos++;
    }

    return count;
  }

  static bool _isChinese(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF);
  }
}
