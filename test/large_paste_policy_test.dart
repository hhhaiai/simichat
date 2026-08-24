import 'package:ai_chat_app/core/context/token_estimator.dart';
import 'package:ai_chat_app/core/media/large_paste_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LargePastePolicy', () {
    const policy = LargePastePolicy(
      characterThreshold: 16,
      utf8ByteThreshold: 64,
      estimatedTokenThreshold: 20,
    );

    test('keeps a small inserted fragment in the composer', () {
      final decision = policy.evaluate('short text');

      expect(decision.shouldArchive, isFalse);
      expect(decision.trigger, isNull);
      expect(decision.characterCount, 10);
    });

    test('archives when the inserted fragment exceeds character threshold', () {
      final decision = policy.evaluate('0123456789abcdef');

      expect(decision.shouldArchive, isTrue);
      expect(decision.trigger, LargePasteTrigger.characterCount);
      expect(decision.characterCount, 16);
    });

    test('archives UTF-8 heavy text even with a small character count', () {
      const bytePolicy = LargePastePolicy(
        characterThreshold: 100,
        utf8ByteThreshold: 8,
        estimatedTokenThreshold: 100,
      );

      final decision = bytePolicy.evaluate('你好🙂');

      expect(decision.shouldArchive, isTrue);
      expect(decision.trigger, LargePasteTrigger.utf8ByteCount);
      expect(decision.utf8ByteCount, greaterThanOrEqualTo(10));
    });

    test(
      'archives when the token estimate crosses the configured threshold',
      () {
        const tokenPolicy = LargePastePolicy(
          characterThreshold: 100,
          utf8ByteThreshold: 1000,
          estimatedTokenThreshold: 4,
        );

        final decision = tokenPolicy.evaluate('中文内容');

        expect(decision.shouldArchive, isTrue);
        expect(decision.trigger, LargePasteTrigger.estimatedTokens);
        expect(decision.estimatedTokens, TokenEstimator.estimate('中文内容'));
      },
    );

    test('recognises markdown without rewriting the original source text', () {
      const source = '# 标题\n\n```dart\nprint("保真");\n```\n';

      expect(isLikelyMarkdown(source), isTrue);
      expect(isLikelyMarkdown('普通文本\n第二行'), isFalse);
      expect(inferPastedTextExtension(source), 'md');
      expect(inferPastedTextExtension('普通文本'), 'txt');
    });

    test(
      'removes exactly the inserted range and preserves surrounding draft',
      () {
        const before = '请检查下面代码：\n';
        const inserted = '很长的粘贴内容';
        const after = '\n谢谢';
        final result = removeInsertedText(
          before + inserted + after,
          insertionStart: before.length,
          insertionEnd: before.length + inserted.length,
        );

        expect(result, before + after);
      },
    );
  });
}
