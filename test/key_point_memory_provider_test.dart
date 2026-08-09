import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/shared/providers/key_point_memory_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('KeyPointMemoryNotifier persists and deduplicates key points', () async {
    final notifier = KeyPointMemoryNotifier();
    await notifier.ready;

    final now = DateTime.utc(2026, 6, 27);
    final item = KeyPointMemoryItem(
      id: makeMemoryItemId('s1', '我喜欢中文回复'),
      sessionId: 's1',
      sourceMessageId: 'm1',
      category: 'preference',
      content: '我喜欢中文回复',
      keywords: extractMemoryKeywords('我喜欢中文回复'),
      confidence: 0.8,
      createdAt: now,
      updatedAt: now,
    );

    await notifier.rememberAll([item]);
    await notifier.rememberAll([item.copyWith(sourceMessageId: 'm2')]);

    expect(notifier.state, hasLength(1));

    final reloaded = KeyPointMemoryNotifier();
    await reloaded.ready;
    expect(reloaded.state, hasLength(1));
    expect(reloaded.state.single.content, '我喜欢中文回复');
  });

  test('KeyPointMemoryNotifier search updates last used timestamp', () async {
    final notifier = KeyPointMemoryNotifier();
    await notifier.ready;

    final now = DateTime.utc(2026, 6, 27);
    await notifier.rememberAll([
      KeyPointMemoryItem(
        id: 'memory-1',
        sessionId: 's1',
        sourceMessageId: 'm1',
        category: 'preference',
        content: '我喜欢中文回复',
        keywords: extractMemoryKeywords('我喜欢中文回复'),
        confidence: 0.8,
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    final results = await notifier.searchRelevant('请继续中文回复', sessionId: 's1');

    expect(results.map((item) => item.id), contains('memory-1'));
    expect(notifier.state.single.lastUsedAt, isNotNull);
  });

  test(
    'KeyPointMemoryNotifier supports an isolated local storage key',
    () async {
      const storageKey = 'key_point_memory_device_smoke_v1';
      final notifier = KeyPointMemoryNotifier(storageKey: storageKey);
      await notifier.ready;

      final now = DateTime.utc(2026, 8, 9);
      await notifier.rememberAll([
        KeyPointMemoryItem(
          id: 'isolated-memory-1',
          sessionId: 'isolated-session',
          sourceMessageId: 'isolated-message',
          category: 'preference',
          content: '以后优先使用本地能力',
          keywords: extractMemoryKeywords('以后优先使用本地能力'),
          confidence: 0.9,
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(storageKey), contains('isolated-memory-1'));
      expect(prefs.getString(kKeyPointMemoryStorageKey), isNull);

      final reloaded = KeyPointMemoryNotifier(storageKey: storageKey);
      await reloaded.ready;
      expect(reloaded.state.single.id, 'isolated-memory-1');
    },
  );
}
