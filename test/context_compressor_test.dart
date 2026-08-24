import 'package:ai_chat_app/core/context/context_compressor.dart';
import 'package:ai_chat_app/core/context/context_builder.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rolling compression replaces old summaries and keeps every raw message',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      const sessionId = 'rolling-context-session';
      await db.sessionDao.createSession(id: sessionId);
      await db.messageDao.insertSummary(
        id: 'legacy-summary',
        sessionId: sessionId,
        content: '早期事实：用户项目代号是 Aurora。',
        summaryStartId: 'legacy-start',
        summaryEndId: 'legacy-end',
        tokens: 20,
      );
      for (var i = 0; i < 14; i++) {
        await db.messageDao.insertMessage(
          id: 'message-$i',
          sessionId: sessionId,
          role: i.isEven ? 'user' : 'assistant',
          content: '第 $i 条原始消息，保留 rolling-fact-$i。',
          tokens: 20,
        );
      }

      final prompts = <String>[];
      final compressor = ContextCompressor(
        db.messageDao,
        summaryGenerator:
            ({
              required protocol,
              required baseUrl,
              required apiKey,
              required model,
              required prompt,
            }) async {
              prompts.add(prompt);
              return '滚动摘要：Aurora；rolling-fact-0 到 rolling-fact-3。';
            },
      );

      final compressed = await compressor.compressIfNeeded(
        sessionId: sessionId,
        threshold: 100,
        protocol: 'openai_chat',
        baseUrl: 'https://example.invalid/v1',
        apiKey: 'test-only',
        model: 'gpt-5.3-codex-spark',
      );

      expect(compressed, isTrue);
      expect(prompts, hasLength(1));
      expect(prompts.single, contains('早期事实：用户项目代号是 Aurora'));
      expect(prompts.single, contains('rolling-fact-0'));
      expect(prompts.single, contains('rolling-fact-3'));
      expect(prompts.single, isNot(contains('rolling-fact-4')));

      final summaries = await db.messageDao.getSummaries(sessionId);
      expect(summaries, hasLength(1));
      expect(summaries.single.id, isNot('legacy-summary'));
      expect(summaries.single.content, contains('Aurora'));

      final unsummarized = await db.messageDao.getUnsummarizedOriginals(
        sessionId,
      );
      expect(unsummarized.map((message) => message.id), [
        for (var i = 4; i < 14; i++) 'message-$i',
      ]);

      final allRows = await db.messageDao.getMessagesBySession(sessionId);
      final rawRows = allRows
          .where((message) => message.messageType == 'original')
          .toList();
      expect(rawRows, hasLength(14));
      expect(rawRows.where((message) => message.isSummarized), hasLength(4));

      final (_, context) = await ContextBuilder(
        db.messageDao,
      ).buildContext(sessionId, maxInputTokens: 4096);
      expect(
        context.map((message) => message.content).join('\n'),
        contains('滚动摘要：Aurora'),
      );
      expect(
        context.map((message) => message.content).join('\n'),
        contains('rolling-fact-13'),
      );
    },
  );

  test(
    'concurrent compression shares one model request per conversation',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      const sessionId = 'concurrent-context-session';
      await db.sessionDao.createSession(id: sessionId);
      for (var i = 0; i < 12; i++) {
        await db.messageDao.insertMessage(
          id: 'concurrent-$i',
          sessionId: sessionId,
          role: i.isEven ? 'user' : 'assistant',
          content: '并发上下文 $i',
          tokens: 20,
        );
      }

      var calls = 0;
      final compressor = ContextCompressor(
        db.messageDao,
        summaryGenerator:
            ({
              required protocol,
              required baseUrl,
              required apiKey,
              required model,
              required prompt,
            }) async {
              calls++;
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return '并发滚动摘要';
            },
      );
      Future<bool> run() => compressor.compressIfNeeded(
        sessionId: sessionId,
        threshold: 20,
        protocol: 'openai_chat',
        baseUrl: 'https://example.invalid/v1',
        apiKey: 'test-only',
        model: 'gpt-5.3-codex-spark',
      );

      final results = await Future.wait([run(), run()]);

      expect(results, everyElement(isTrue));
      expect(calls, 1);
      expect(await db.messageDao.getSummaries(sessionId), hasLength(1));
    },
  );
}
