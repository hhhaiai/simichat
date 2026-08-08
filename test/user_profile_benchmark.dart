import 'dart:io';

import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local user profile benchmark for 1000 key points',
    () {
      const itemCount = int.fromEnvironment(
        'SIMICHAT_USER_PROFILE_BENCH_ITEMS',
        defaultValue: 1000,
      );
      final now = DateTime.now();
      final items = <KeyPointMemoryItem>[];
      for (var i = 0; i < itemCount; i++) {
        final content = _benchmarkContent(i);
        items.add(
          KeyPointMemoryItem(
            id: makeMemoryItemId('bench', content),
            sessionId: 'bench',
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
      var controls = const UserProfileControls();
      for (var i = 0; i < 10 && i < itemCount; i++) {
        controls = controls.hideSignal(_benchmarkContent(i));
      }
      for (var i = 10; i < 20 && i < itemCount; i++) {
        controls = controls.editSignal(
          _benchmarkContent(i),
          '${_benchmarkContent(i)} 已由用户确认。',
        );
      }

      final watch = Stopwatch()..start();
      final profile = const UserProfileBuilder().build(
        keyPoints: items,
        controls: controls,
        now: now,
      );
      watch.stop();

      stdout.writeln(
        [
          'user_profile_benchmark',
          'items=$itemCount',
          'build_ms=${watch.elapsedMilliseconds}',
          'source_count=${profile.sourceCount}',
          'signal_count=${profile.totalSignalCount}',
          'keyword_count=${profile.keywords.length}',
          'hidden_controls=${controls.hiddenCount}',
          'edited_controls=${controls.editedCount}',
          'has_content=${profile.hasContent}',
        ].join(' '),
      );

      expect(profile.hasContent, isTrue);
      expect(profile.sourceCount, itemCount - controls.hiddenCount);
      expect(profile.preferences, isNotEmpty);
      expect(profile.goals, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

String _benchmarkContent(int i) {
  return i.isEven
      ? '请记住我的偏好 $i：我喜欢中文、结构化总结和移动端优先。'
      : '我的目标 $i 是把 SimiChat 做成可靠的本地 AI 伙伴。';
}
