import 'dart:convert';

import 'package:ai_chat_app/core/ai/model_tester.dart';
import 'package:ai_chat_app/shared/providers/model_test_history_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('ModelTestHistoryNotifier', () {
    test('records successful test result', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(modelTestHistoryProvider.notifier);
      await notifier.ready;

      await notifier.recordResult(
        modelId: 'model-1',
        modelName: 'gpt-4o-mini',
        channelId: 'channel-1',
        channelName: 'OpenAI',
        result: ModelTestResult.success(),
        testedAt: DateTime(2026, 6, 27, 3, 30),
      );

      final item = container.read(modelTestHistoryProvider)['model-1'];
      expect(item, isNotNull);
      expect(item!.success, true);
      expect(item.compactStatus, '成功');
      expect(item.attempts, 1);
      expect(item.channelName, 'OpenAI');
      expect(item.testedAt, DateTime(2026, 6, 27, 3, 30));
    });

    test('records failed result with status code and suggestion', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(modelTestHistoryProvider.notifier);
      await notifier.ready;

      await notifier.recordResult(
        modelId: 'model-1',
        modelName: 'claude-3-5-sonnet',
        channelId: 'channel-1',
        channelName: 'Claude',
        result: ModelTestResult.failure('[401] invalid key', attempts: 2),
      );

      final item = container.read(modelTestHistoryProvider)['model-1']!;
      expect(item.success, false);
      expect(item.summary, '认证失败');
      expect(item.statusCode, 401);
      expect(item.suggestion, contains('API Key'));
      expect(item.attempts, 2);
      expect(item.compactStatus, '认证失败 · HTTP 401 · 已重试 1 次');
    });

    test('overwrites previous item for the same model id', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(modelTestHistoryProvider.notifier);
      await notifier.ready;

      await notifier.recordResult(
        modelId: 'model-1',
        modelName: 'old-name',
        channelId: 'channel-1',
        channelName: 'Old',
        result: ModelTestResult.failure('[404] not found'),
        testedAt: DateTime(2026, 6, 27, 1),
      );
      await notifier.recordResult(
        modelId: 'model-1',
        modelName: 'new-name',
        channelId: 'channel-2',
        channelName: 'New',
        result: ModelTestResult.success(),
        testedAt: DateTime(2026, 6, 27, 2),
      );

      final state = container.read(modelTestHistoryProvider);
      expect(state, hasLength(1));
      expect(state['model-1']!.modelName, 'new-name');
      expect(state['model-1']!.success, true);
      expect(state['model-1']!.channelId, 'channel-2');
    });

    test('loads persisted history from shared preferences', () async {
      SharedPreferences.setMockInitialValues({
        'model_test_history_v1': jsonEncode([
          {
            'modelId': 'model-1',
            'modelName': 'deepseek-chat',
            'channelId': 'channel-1',
            'channelName': 'DeepSeek',
            'success': false,
            'summary': '请求过于频繁或额度不足',
            'suggestion': '稍后重试',
            'statusCode': 429,
            'attempts': 3,
            'testedAt': DateTime(2026, 6, 27, 4, 5).toIso8601String(),
          },
        ]),
      });
      final container = createContainer();
      final notifier = container.read(modelTestHistoryProvider.notifier);
      await notifier.ready;

      final item = container.read(modelTestHistoryProvider)['model-1'];
      expect(item, isNotNull);
      expect(item!.channelName, 'DeepSeek');
      expect(item.statusCode, 429);
      expect(item.attempts, 3);
      expect(item.compactStatus, '请求过于频繁或额度不足 · HTTP 429 · 已重试 2 次');
    });

    test('does not persist raw provider details or secrets', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(modelTestHistoryProvider.notifier);
      await notifier.ready;
      const fakeKey =
          'sk-'
          'test-secret-token';
      const fakeBearer = 'Bearer $fakeKey';

      await notifier.recordResult(
        modelId: 'model-1',
        modelName: 'gpt-4o-mini',
        channelId: 'channel-1',
        channelName: 'OpenAI',
        result: ModelTestResult.failure(
          'Exception: [401] Authorization $fakeBearer failed with body content',
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('model_test_history_v1')!;
      expect(raw, isNot(contains(fakeKey)));
      expect(raw, isNot(contains(fakeBearer)));
      expect(raw, isNot(contains('body content')));
      expect(raw, contains('认证失败'));
    });
  });
}
