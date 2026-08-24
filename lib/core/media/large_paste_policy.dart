import 'dart:convert';

import '../context/token_estimator.dart';

/// 触发“将本次粘贴内容转换为私有文本附件”的原因。
///
/// 该枚举只描述本地 Composer 决策，不会被传给模型或写入远端请求。
enum LargePasteTrigger { characterCount, utf8ByteCount, estimatedTokens }

/// [LargePastePolicy] 的一次评估结果。
class LargePasteDecision {
  const LargePasteDecision({
    required this.characterCount,
    required this.utf8ByteCount,
    required this.estimatedTokens,
    this.trigger,
  });

  final int characterCount;
  final int utf8ByteCount;
  final int estimatedTokens;
  final LargePasteTrigger? trigger;

  bool get shouldArchive => trigger != null;
}

/// 大粘贴阈值的集中配置。
///
/// 这些默认值来自产品需求，而不是写在 TextField / Widget 内。调用方可以
/// 通过注入不同实例为渠道、设置页或测试提供覆盖；本策略只检查“本次插入
/// 的片段”，不读取整个 Composer 的既有文本。
class LargePastePolicy {
  static const defaultCharacterThreshold = 16000;
  static const defaultUtf8ByteThreshold = 64 * 1024;
  static const defaultEstimatedTokenThreshold = 8000;

  const LargePastePolicy({
    this.characterThreshold = defaultCharacterThreshold,
    this.utf8ByteThreshold = defaultUtf8ByteThreshold,
    this.estimatedTokenThreshold = defaultEstimatedTokenThreshold,
  }) : assert(characterThreshold > 0),
       assert(utf8ByteThreshold > 0),
       assert(estimatedTokenThreshold > 0);

  final int characterThreshold;
  final int utf8ByteThreshold;
  final int estimatedTokenThreshold;

  LargePasteDecision evaluate(String insertedText) {
    final characterCount = insertedText.length;
    final utf8ByteCount = utf8.encode(insertedText).length;
    final estimatedTokens = TokenEstimator.estimate(insertedText);
    final trigger = characterCount >= characterThreshold
        ? LargePasteTrigger.characterCount
        : utf8ByteCount >= utf8ByteThreshold
        ? LargePasteTrigger.utf8ByteCount
        : estimatedTokens >= estimatedTokenThreshold
        ? LargePasteTrigger.estimatedTokens
        : null;
    return LargePasteDecision(
      characterCount: characterCount,
      utf8ByteCount: utf8ByteCount,
      estimatedTokens: estimatedTokens,
      trigger: trigger,
    );
  }
}

/// 只根据文本的明显 Markdown 特征选择展示扩展名，绝不改写 [text]。
bool isLikelyMarkdown(String text) {
  if (text.isEmpty) return false;
  return RegExp(r'(^|\n)#{1,6}\s+\S', multiLine: true).hasMatch(text) ||
      RegExp(r'(^|\n)\s*[-*+]\s+\S', multiLine: true).hasMatch(text) ||
      RegExp(r'(^|\n)\s*\d+[.)]\s+\S', multiLine: true).hasMatch(text) ||
      text.contains('```') ||
      RegExp(r'(^|\n)\|.+\|\s*$', multiLine: true).hasMatch(text);
}

String inferPastedTextExtension(String text) =>
    isLikelyMarkdown(text) ? 'md' : 'txt';

/// 移除已识别为“本次插入”的半开区间。无效边界保守地返回原文，防止在
/// 输入法提供异常 selection 时破坏用户草稿。
String removeInsertedText(
  String fullText, {
  required int insertionStart,
  required int insertionEnd,
}) {
  if (insertionStart < 0 ||
      insertionEnd < insertionStart ||
      insertionEnd > fullText.length) {
    return fullText;
  }
  return fullText.replaceRange(insertionStart, insertionEnd, '');
}
