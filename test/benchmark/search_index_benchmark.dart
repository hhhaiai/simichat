import 'dart:io';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/search/local_full_text_search.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local search index benchmark for 2000 messages',
    () async {
      const messageCount = int.fromEnvironment(
        'SIMICHAT_SEARCH_BENCH_MESSAGES',
        defaultValue: 2000,
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 'bench-session');
      await db.sessionDao.updateTitle('bench-session', '本地搜索索引性能基线');

      final insertWatch = Stopwatch()..start();
      for (var i = 0; i < messageCount; i++) {
        await db.messageDao.insertMessage(
          id: 'bench-message-$i',
          sessionId: 'bench-session',
          role: i.isEven ? 'user' : 'assistant',
          content: 'SimiChat 本地搜索索引性能基线消息 $i，移动端优先，记忆检索，Dreaming 夜间整理。',
        );
      }
      insertWatch.stop();

      final health = await db.messageDao.prewarmMessageFtsIndex();
      final semanticHealth = await db.messageDao.prewarmMessageSemanticIndex();

      final searchWatch = Stopwatch()..start();
      final results = await LocalFullTextSearchService(
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
      ).search('SimiChat 性能基线', limit: 10);
      searchWatch.stop();

      stdout.writeln(
        [
          'search_index_benchmark',
          'messages=$messageCount',
          'insert_ms=${insertWatch.elapsedMilliseconds}',
          'prewarm_ms=${health.elapsedMs}',
          'indexed_rows=${health.indexedRowCount}',
          'semantic_prewarm_ms=${semanticHealth.elapsedMs}',
          'semantic_indexed_rows=${semanticHealth.indexedRowCount}',
          'search_ms=${searchWatch.elapsedMilliseconds}',
          'result_count=${results.length}',
          'healthy=${health.isHealthy}',
        ].join(' '),
      );

      expect(health.isHealthy, isTrue);
      expect(health.indexedRowCount, messageCount);
      expect(semanticHealth.isHealthy, isTrue);
      expect(semanticHealth.indexedRowCount, messageCount);
      expect(results, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
