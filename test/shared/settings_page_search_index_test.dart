import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings page can prewarm and repair local search index', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.messageDao.insertMessage(
      id: 'm1',
      sessionId: 's1',
      role: 'user',
      content: '这是一条需要进入本地搜索索引的历史消息。',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('本地搜索索引'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('本地搜索索引'), findsOneWidget);
    expect(find.textContaining('SQLite FTS + 本地语义索引'), findsOneWidget);

    await tester.tap(find.text('本地搜索索引'));
    await tester.pumpAndSettle();

    expect(find.text('预热 / 修复'), findsOneWidget);
    expect(find.text('启用本地语义搜索'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('semantic_search_enabled'), isFalse);

    await tester.tap(find.text('预热 / 修复'));
    await tester.pumpAndSettle();

    expect(find.textContaining('搜索索引已预热并修复'), findsOneWidget);

    final health = await db.messageDao.checkMessageFtsIndexHealth();
    expect(health.isHealthy, isTrue);
    expect(health.indexedRowCount, 1);
    final semanticHealth = await db.messageDao
        .checkMessageSemanticIndexHealth();
    expect(semanticHealth.isHealthy, isTrue);
    expect(semanticHealth.indexedRowCount, 1);
  });
}
