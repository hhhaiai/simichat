import 'package:ai_chat_app/core/ai/model_tester.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelTestResult', () {
    test('classifies authentication failures with status code', () {
      final result = ModelTestResult.failure(
        'Exception: [401] invalid_api_key',
      );

      expect(result.success, false);
      expect(result.statusCode, 401);
      expect(result.summary, '认证失败');
      expect(result.compactMessage, contains('HTTP 401'));
      expect(result.suggestion, contains('API Key'));
    });

    test('classifies rate limit failures', () {
      final result = ModelTestResult.failure('[429] too many requests');

      expect(result.statusCode, 429);
      expect(result.summary, '请求过于频繁或额度不足');
      expect(result.suggestion, contains('额度'));
    });

    test('sanitizes secrets from raw provider errors', () {
      const fakeKey =
          'sk-'
          'test-secret-token';
      final result = ModelTestResult.failure(
        'Exception: Authorization Bearer $fakeKey failed',
      );

      expect(result.detail, isNot(contains(fakeKey)));
      expect(result.detail, contains('Bearer ***'));
    });

    test('classifies timeout failures without status code', () {
      final result = ModelTestResult.failure('测试超时（30秒），请检查网络');

      expect(result.statusCode, isNull);
      expect(result.summary, '测试超时');
      expect(result.suggestion, contains('网络'));
    });

    test('compact message includes retry count after retry', () {
      final result = ModelTestResult.failure(
        '[500] provider down',
        attempts: 2,
      );

      expect(result.retried, true);
      expect(result.retryCount, 1);
      expect(result.compactMessage, contains('已重试 1 次'));
    });
  });

  group('ModelTestRetryPolicy', () {
    const policy = ModelTestRetryPolicy(initialDelay: Duration.zero);

    test('retries transient status and timeout failures', () {
      expect(policy.shouldRetry(ModelTestResult.failure('[429] rate')), true);
      expect(policy.shouldRetry(ModelTestResult.failure('[500] down')), true);
      expect(policy.shouldRetry(ModelTestResult.failure('测试超时（30秒）')), true);
    });

    test('does not retry permanent configuration failures', () {
      expect(
        policy.shouldRetry(ModelTestResult.failure('[401] bad key')),
        false,
      );
      expect(
        policy.shouldRetry(ModelTestResult.failure('[403] forbidden')),
        false,
      );
      expect(
        policy.shouldRetry(ModelTestResult.failure('[404] not found')),
        false,
      );
      expect(policy.shouldRetry(ModelTestResult.failure('不支持的协议: x')), false);
    });
  });

  group('ModelTester retry', () {
    const retryPolicy = ModelTestRetryPolicy(
      maxAttempts: 3,
      initialDelay: Duration.zero,
    );

    test(
      'automatically retries transient failure and returns success',
      () async {
        var calls = 0;
        final result = await ModelTester.testModelDetailed(
          protocol: 'openai_chat',
          baseUrl: 'https://example.invalid',
          apiKey: 'test-key',
          model: 'test-model',
          retryPolicy: retryPolicy,
          testRunner: () async {
            calls += 1;
            return calls == 1 ? '[429] too many requests' : null;
          },
        );

        expect(calls, 2);
        expect(result.success, true);
        expect(result.attempts, 2);
        expect(result.compactMessage, '连接成功 · 已重试 1 次');
      },
    );

    test('does not retry authentication failures', () async {
      var calls = 0;
      final result = await ModelTester.testModelDetailed(
        protocol: 'openai_chat',
        baseUrl: 'https://example.invalid',
        apiKey: 'test-key',
        model: 'test-model',
        retryPolicy: retryPolicy,
        testRunner: () async {
          calls += 1;
          return '[401] invalid_api_key';
        },
      );

      expect(calls, 1);
      expect(result.success, false);
      expect(result.summary, '认证失败');
      expect(result.attempts, 1);
    });

    test('stops after max attempts for repeated transient failures', () async {
      var calls = 0;
      final result = await ModelTester.testModelDetailed(
        protocol: 'openai_chat',
        baseUrl: 'https://example.invalid',
        apiKey: 'test-key',
        model: 'test-model',
        retryPolicy: retryPolicy,
        testRunner: () async {
          calls += 1;
          return '[500] provider down';
        },
      );

      expect(calls, 3);
      expect(result.success, false);
      expect(result.statusCode, 500);
      expect(result.attempts, 3);
      expect(result.compactMessage, contains('已重试 2 次'));
    });
  });

  group('media capability dispatch', () {
  test('video models are skipped without running a request', () async {
    var calls = 0;
    final result = await ModelTester.testModelDetailed(
      protocol: 'openai_chat',
      baseUrl: 'https://example.invalid',
      apiKey: 'test-key',
      model: 'grok-imagine-video',
      capability: 'video',
      testRunner: () async {
        calls += 1;
        return null;
      },
    );

    expect(calls, 0);
    expect(result.skipped, true);
    expect(result.success, false);
    expect(result.compactMessage, contains('不参与连通性测试'));
  });

  test('music models are skipped without running a request', () async {
    final result = await ModelTester.testModelDetailed(
      protocol: 'openai_chat',
      baseUrl: 'https://example.invalid',
      apiKey: 'test-key',
      model: 'musicgen',
      capability: 'music',
      testRunner: () async => null,
    );

    expect(result.skipped, true);
  });

  test('asr-named audio models are skipped without running a request', () async {
    final result = await ModelTester.testModelDetailed(
      protocol: 'openai_chat',
      baseUrl: 'https://example.invalid',
      apiKey: 'test-key',
      model: 'mimo-v2.5-asr',
      capability: 'audio',
      testRunner: () async => null,
    );

    expect(result.skipped, true);
    expect(result.compactMessage, contains('语音识别'));
  });

  test('chat models still route through the injected runner', () async {
    var calls = 0;
    final result = await ModelTester.testModelDetailed(
      protocol: 'openai_chat',
      baseUrl: 'https://example.invalid',
      apiKey: 'test-key',
      model: 'test-model',
      capability: 'chat',
      testRunner: () async {
        calls += 1;
        return null;
      },
    );

    expect(calls, 1);
    expect(result.skipped, false);
    expect(result.success, true);
  });

  test('skipped results never retry', () async {
    final result = await ModelTester.testModelDetailed(
      protocol: 'openai_chat',
      baseUrl: 'https://example.invalid',
      apiKey: 'test-key',
      model: 'sora-2',
      capability: 'video',
      retryPolicy: const ModelTestRetryPolicy(maxAttempts: 3),
      testRunner: () async => '[500] provider down',
    );

    expect(result.skipped, true);
    expect(result.attempts, 1);
  });
});
}
