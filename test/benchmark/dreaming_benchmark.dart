import 'dart:io';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local dreaming benchmark for 1000 messages',
    () async {
      const messageCount = int.fromEnvironment(
        'SIMICHAT_DREAMING_BENCH_MESSAGES',
        defaultValue: 1000,
      );
      final now = DateTime.now();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 'bench-session');
      await db.sessionDao.updateTitle('bench-session', 'Dreaming 性能基线');

      final insertWatch = Stopwatch()..start();
      for (var i = 0; i < messageCount; i++) {
        await db.messageDao.insertMessage(
          id: 'dreaming-message-$i',
          sessionId: 'bench-session',
          role: i.isEven ? 'user' : 'assistant',
          content: i.isEven ? '请记住我的偏好 $i：我喜欢移动端优先、中文总结和本地隐私。' : '已整理第 $i 条回复。',
        );
      }
      insertWatch.stop();

      final runWatch = Stopwatch()..start();
      final digest = await DreamingService(
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
        now: () => now,
      ).runDailyDigest(day: now);
      runWatch.stop();

      stdout.writeln(
        [
          'dreaming_benchmark',
          'messages=$messageCount',
          'insert_ms=${insertWatch.elapsedMilliseconds}',
          'run_ms=${runWatch.elapsedMilliseconds}',
          'digest_elapsed_ms=${digest.elapsedMs}',
          'session_count=${digest.sessionCount}',
          'memory_candidates=${digest.memoryCandidates.length}',
          'has_content=${digest.hasContent}',
        ].join(' '),
      );

      expect(digest.hasContent, isTrue);
      expect(digest.originalMessageCount, messageCount);
      expect(digest.memoryCandidates, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
