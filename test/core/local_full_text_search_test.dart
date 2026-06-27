import 'package:ai_chat_app/core/ai/model_switch_record.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/search/local_full_text_search.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local search finds multi-token message matches across sessions',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's1');
      await db.sessionDao.updateTitle('s1', '产品规划');
      await db.messageDao.insertMessage(
        id: 'm1',
        sessionId: 's1',
        role: 'user',
        content: '我喜欢中文回复，SimiChat 要坚持移动端优先。',
      );

      final results = await LocalFullTextSearchService(
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
      ).search('中文 SimiChat');

      expect(results, isNotEmpty);
      expect(results.first.sessionId, 's1');
      expect(results.first.matchType, LocalSearchMatchType.message);
      expect(results.first.subtitle, contains('中文回复'));
    },
  );

  test('message dao full text index returns original message hits', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.messageDao.insertMessage(
      id: 'm1',
      sessionId: 's1',
      role: 'user',
      content: 'SimiChat 支持本地全文检索和移动端优先体验。',
    );

    final hits = await db.messageDao.searchOriginalMessagesFullText(
      tokenizeLocalSearchQuery('SimiChat 本地全文检索'),
    );

    expect(hits.map((hit) => hit.message.id), contains('m1'));
  });

  test('message dao can check and repair full text index health', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.messageDao.insertMessage(
      id: 'm1',
      sessionId: 's1',
      role: 'user',
      content: '先写入历史消息，再创建搜索索引。',
    );

    final staleHealth = await db.messageDao.checkMessageFtsIndexHealth();
    expect(staleHealth.isAvailable, isTrue);
    expect(staleHealth.isConsistent, isFalse);
    expect(staleHealth.originalMessageCount, 1);
    expect(staleHealth.indexedRowCount, 0);
    expect(staleHealth.rebuilt, isFalse);

    final repairedHealth = await db.messageDao.prewarmMessageFtsIndex();
    expect(repairedHealth.isHealthy, isTrue);
    expect(repairedHealth.rebuilt, isTrue);
    expect(repairedHealth.originalMessageCount, 1);
    expect(repairedHealth.indexedRowCount, 1);

    await db.messageDao.insertMessage(
      id: 'm2',
      sessionId: 's1',
      role: 'assistant',
      content: '触发器会继续维护新增原始消息。',
    );

    final triggerHealth = await db.messageDao.checkMessageFtsIndexHealth();
    expect(triggerHealth.isHealthy, isTrue);
    expect(triggerHealth.originalMessageCount, 2);
    expect(triggerHealth.indexedRowCount, 2);
    expect(triggerHealth.rebuilt, isFalse);
  });

  test('message dao can prewarm local semantic message index', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.messageDao.insertMessage(
      id: 'm1',
      sessionId: 's1',
      role: 'user',
      content: '移动端优先，本地隐私保护，长期记忆检索。',
    );

    final freshHealth = await db.messageDao.checkMessageSemanticIndexHealth();
    expect(freshHealth.isHealthy, isTrue);
    expect(freshHealth.originalMessageCount, 1);
    expect(freshHealth.indexedRowCount, 1);

    await db.customStatement(
      "DELETE FROM message_semantic_index WHERE message_id = 'm1'",
    );

    final staleHealth = await db.messageDao.checkMessageSemanticIndexHealth();
    expect(staleHealth.isAvailable, isTrue);
    expect(staleHealth.isConsistent, isFalse);
    expect(staleHealth.originalMessageCount, 1);
    expect(staleHealth.indexedRowCount, 0);
    expect(staleHealth.staleIndexCount, 1);

    final repairedHealth = await db.messageDao.prewarmMessageSemanticIndex();
    expect(repairedHealth.isHealthy, isTrue);
    expect(repairedHealth.rebuilt, isTrue);
    expect(repairedHealth.originalMessageCount, 1);
    expect(repairedHealth.indexedRowCount, 1);

    await db.messageDao.insertMessage(
      id: 'm2',
      sessionId: 's1',
      role: 'assistant',
      content: '新增原始消息后需要重新预热语义索引。',
    );

    final changedHealth = await db.messageDao.checkMessageSemanticIndexHealth();
    expect(changedHealth.isHealthy, isTrue);
    expect(changedHealth.originalMessageCount, 2);
    expect(changedHealth.indexedRowCount, 2);
    expect(changedHealth.staleIndexCount, 0);

    await db.messageDao.deleteMessage('m1');
    final deleteHealth = await db.messageDao.checkMessageSemanticIndexHealth();
    expect(deleteHealth.isHealthy, isTrue);
    expect(deleteHealth.originalMessageCount, 1);
    expect(deleteHealth.indexedRowCount, 1);
  });

  test('local search ignores model switch timeline records', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.messageDao.insertMessage(
      id: 'switch-1',
      sessionId: 's1',
      role: 'system',
      content: buildModelSwitchRecordContent(
        fromLabel: 'OpenAI / gpt-4o',
        toLabel: 'Claude / sonnet',
      ),
      messageType: kModelSwitchMessageType,
    );

    final results = await LocalFullTextSearchService(
      sessionDao: db.sessionDao,
      messageDao: db.messageDao,
    ).search('Claude sonnet');

    expect(results, isEmpty);
  });

  test('local search can surface key point memory matches', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.sessionDao.updateTitle('s1', '个人偏好');
    final now = DateTime.utc(2026, 6, 27);

    final results = await LocalFullTextSearchService(
      sessionDao: db.sessionDao,
      messageDao: db.messageDao,
      memoryItems: [
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
      ],
    ).search('继续中文回复');

    expect(results, isNotEmpty);
    expect(results.first.sessionId, 's1');
    expect(results.first.matchType, LocalSearchMatchType.memory);
    expect(results.first.subtitle, contains('记忆：'));
  });

  test('local search can surface semantic message matches', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 'mobile');
    await db.sessionDao.updateTitle('mobile', '产品方向');
    await db.messageDao.insertMessage(
      id: 'm-mobile',
      sessionId: 'mobile',
      role: 'user',
      content: '我希望 SimiChat 坚持移动端优先策略，并保持本地隐私。',
    );
    await db.sessionDao.createSession(id: 'food');
    await db.messageDao.insertMessage(
      id: 'm-food',
      sessionId: 'food',
      role: 'user',
      content: '我喜欢周末研究川菜和少油少盐食谱。',
    );

    final results = await LocalFullTextSearchService(
      sessionDao: db.sessionDao,
      messageDao: db.messageDao,
    ).search('手机端方案');

    expect(results, isNotEmpty);
    expect(results.first.sessionId, 'mobile');
    expect(results.first.matchType, LocalSearchMatchType.message);
    expect(results.first.subtitle, contains('语义匹配：'));
  });

  test('local search can disable semantic message matches', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 'mobile');
    await db.messageDao.insertMessage(
      id: 'm-mobile',
      sessionId: 'mobile',
      role: 'user',
      content: '我希望 SimiChat 坚持移动端优先策略，并保持本地隐私。',
    );

    final results = await LocalFullTextSearchService(
      sessionDao: db.sessionDao,
      messageDao: db.messageDao,
      enableSemanticMessageSearch: false,
    ).search('手机端方案');

    expect(results, isEmpty);
  });

  test(
    'semantic message search is not capped to recent 500 messages',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 'mobile');
      await db.sessionDao.updateTitle('mobile', '很早以前的产品方向');
      await db.messageDao.insertMessage(
        id: 'm-old-mobile',
        sessionId: 'mobile',
        role: 'user',
        content: '我希望 SimiChat 坚持移动端优先策略，并保持本地隐私。',
      );
      await db.customStatement(
        "UPDATE messages SET created_at = 1 WHERE id = 'm-old-mobile'",
      );

      await db.sessionDao.createSession(id: 'filler');
      for (var i = 0; i < 505; i++) {
        await db.messageDao.insertMessage(
          id: 'm-filler-$i',
          sessionId: 'filler',
          role: 'user',
          content: '第 $i 条普通历史消息，讨论做饭、散步和周末安排。',
        );
      }

      final results = await LocalFullTextSearchService(
        sessionDao: db.sessionDao,
        messageDao: db.messageDao,
      ).search('手机端方案');

      expect(results, isNotEmpty);
      expect(results.first.sessionId, 'mobile');
      expect(results.first.subtitle, contains('语义匹配：'));
    },
  );

  test('tokenizer removes wildcard characters and keeps useful terms', () {
    expect(tokenizeLocalSearchQuery('%中文 SimiChat_2026%'), contains('中文'));
    expect(
      tokenizeLocalSearchQuery('%中文 SimiChat_2026%'),
      contains('simichat_2026'),
    );
    expect(
      tokenizeLocalSearchQuery('%中文 SimiChat_2026%'),
      isNot(contains('%')),
    );
  });
}
