import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extractor turns explicit user preferences into key points', () {
    final items = const KeyPointExtractor().extractFromUserMessage(
      sessionId: 's1',
      sourceMessageId: 'm1',
      content: '请记住：我喜欢中文回复。我的目标是把 SimiChat 做成移动端优先的 AI 伴侣。',
      now: DateTime.utc(2026, 6, 27),
    );

    expect(items, hasLength(2));
    expect(items.first.category, 'preference');
    expect(items.first.content, contains('我喜欢中文回复'));
    expect(items.first.keywords, isNotEmpty);
    expect(items.map((item) => item.sourceMessageId).toSet(), {'m1'});
  });

  test('extractor skips secret-like content', () {
    final items = const KeyPointExtractor().extractFromUserMessage(
      sessionId: 's1',
      sourceMessageId: 'm1',
      content: '请记住我的 API Key 是测试密钥，密码是 123456。',
    );

    expect(items, isEmpty);
  });

  test('rankRelevantKeyPoints prefers same-session keyword overlap', () {
    final now = DateTime.utc(2026, 6, 27);
    final items = [
      KeyPointMemoryItem(
        id: 'a',
        sessionId: 'other',
        sourceMessageId: 'm1',
        category: 'preference',
        content: '我喜欢英文回复',
        keywords: extractMemoryKeywords('我喜欢英文回复'),
        confidence: 0.8,
        createdAt: now,
        updatedAt: now,
      ),
      KeyPointMemoryItem(
        id: 'b',
        sessionId: 's1',
        sourceMessageId: 'm2',
        category: 'preference',
        content: '我喜欢中文回复',
        keywords: extractMemoryKeywords('我喜欢中文回复'),
        confidence: 0.8,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final ranked = rankRelevantKeyPoints(items, '继续用中文回复我', sessionId: 's1');

    expect(ranked.first.id, 'b');
  });

  test('rankRelevantKeyPoints uses local semantic vector recall', () {
    final now = DateTime.utc(2026, 6, 27);
    final items = [
      KeyPointMemoryItem(
        id: 'mobile',
        sessionId: 's1',
        sourceMessageId: 'm1',
        category: 'goal',
        content: '我的目标是把 SimiChat 做成移动端优先的 AI 伙伴',
        keywords: extractMemoryKeywords('我的目标是把 SimiChat 做成移动端优先的 AI 伙伴'),
        confidence: 0.8,
        createdAt: now,
        updatedAt: now,
      ),
      KeyPointMemoryItem(
        id: 'food',
        sessionId: 's2',
        sourceMessageId: 'm2',
        category: 'preference',
        content: '我喜欢川菜和少油少盐',
        keywords: extractMemoryKeywords('我喜欢川菜和少油少盐'),
        confidence: 0.8,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final ranked = rankRelevantKeyPoints(items, '手机端 AI 伙伴体验怎么做？');

    expect(ranked, isNotEmpty);
    expect(ranked.first.id, 'mobile');
    expect(
      cosineSimilarity(
        buildLocalSemanticVector('手机端 AI 伙伴体验'),
        buildLocalSemanticVector('移动端优先的 AI 伙伴'),
      ),
      greaterThan(0.18),
    );
  });

  test('memory prompt is bounded and labeled', () {
    final now = DateTime.utc(2026, 6, 27);
    final prompt = buildKeyPointMemorySystemPrompt([
      KeyPointMemoryItem(
        id: 'a',
        sessionId: 's1',
        sourceMessageId: 'm1',
        category: 'goal',
        content: '我的目标是把 SimiChat 做成稳定生产级 AI 聊天工具',
        keywords: const ['SimiChat', 'AI'],
        confidence: 0.8,
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    expect(prompt, isNotNull);
    expect(prompt, contains(kKeyPointMemoryPromptTitle));
    expect(prompt, contains('[目标]'));
    expect(prompt, contains('稳定生产级'));
  });
}
