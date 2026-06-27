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
}
