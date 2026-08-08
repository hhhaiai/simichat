import 'dart:io';

import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local semantic key point recall benchmark',
    () {
      const itemCount = int.fromEnvironment(
        'SIMICHAT_KEY_POINT_BENCH_ITEMS',
        defaultValue: 5000,
      );
      const iterations = int.fromEnvironment(
        'SIMICHAT_KEY_POINT_BENCH_ITERATIONS',
        defaultValue: 20,
      );
      final now = DateTime.now();
      final items = <KeyPointMemoryItem>[];
      for (var i = 0; i < itemCount; i++) {
        final content = _benchmarkContent(i);
        items.add(
          KeyPointMemoryItem(
            id: makeMemoryItemId('bench-${i % 64}', content),
            sessionId: 'bench-${i % 64}',
            sourceMessageId: 'bench-$i',
            category: i.isEven ? 'preference' : 'goal',
            content: content,
            keywords: extractMemoryKeywords(content),
            confidence: 0.8,
            createdAt: now,
            updatedAt: now.add(Duration(milliseconds: i)),
          ),
        );
      }

      final watch = Stopwatch()..start();
      List<KeyPointMemoryItem> ranked = const [];
      for (var i = 0; i < iterations; i++) {
        ranked = rankRelevantKeyPoints(
          items,
          '手机端 AI 伙伴体验、本机隐私和 Dreaming 夜间整理怎么继续推进？',
          sessionId: 'bench-${i % 64}',
          limit: 8,
        );
      }
      watch.stop();

      stdout.writeln(
        [
          'key_point_memory_benchmark',
          'items=$itemCount',
          'iterations=$iterations',
          'search_ms=${watch.elapsedMilliseconds}',
          'avg_search_ms=${(watch.elapsedMilliseconds / iterations).toStringAsFixed(2)}',
          'result_count=${ranked.length}',
          'top=${ranked.isEmpty ? 'none' : ranked.first.id}',
        ].join(' '),
      );

      expect(ranked, isNotEmpty);
      expect(
        ranked.map((item) => item.content).join('\n'),
        anyOf(contains('移动端优先'), contains('本地优先'), contains('Dreaming')),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

String _benchmarkContent(int i) {
  switch (i % 4) {
    case 0:
      return '请记住我的偏好 $i：我喜欢中文、结构化总结和移动端优先。';
    case 1:
      return '我的目标 $i 是把 SimiChat 做成可靠的本地 AI 伙伴。';
    case 2:
      return '我的作息 $i：晚上适合做 Dreaming 夜间整理和画像复盘。';
    default:
      return '我的任务 $i 是关注语音转写、多模态图片和技能市场。';
  }
}
