import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/context/token_estimator.dart';

void main() {
  group('TokenEstimator', () {
    test('empty string returns 0', () {
      expect(TokenEstimator.estimate(''), 0);
    });

    test('Chinese characters count as 2 tokens each', () {
      expect(TokenEstimator.estimate('你好'), 4);
      expect(TokenEstimator.estimate('人工智能'), 8);
    });

    test('English words count as ~1.3x length', () {
      final tokens = TokenEstimator.estimate('Hello world');
      expect(tokens, greaterThan(5));
      expect(tokens, lessThan(20));
    });

    test('mixed Chinese and English', () {
      final tokens = TokenEstimator.estimate('AI助手 hello');
      expect(tokens, greaterThan(4));
    });

    test('punctuation counts as 1 token', () {
      final tokens = TokenEstimator.estimate('你好，世界！');
      // 你好=4, ，=1, 世界=4, ！=1 = 10
      expect(tokens, 10);
    });
  });
}
