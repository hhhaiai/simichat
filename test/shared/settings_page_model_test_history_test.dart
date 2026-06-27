import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings page shows persisted model test history', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'model_test_history_v1': jsonEncode([
        {
          'modelId': 'model-1',
          'modelName': 'gpt-4o-mini',
          'channelId': 'channel-1',
          'channelName': 'OpenAI',
          'success': false,
          'summary': '认证失败',
          'suggestion': '请检查 API Key',
          'statusCode': 401,
          'attempts': 2,
          'testedAt': DateTime(2026, 6, 27, 3, 30).toIso8601String(),
        },
      ]),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.channelDao.createChannel(
      id: 'channel-1',
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      apiKeyEncrypted: 'encrypted-test-key',
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'model-1',
      channelId: 'channel-1',
      modelName: 'gpt-4o-mini',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();

    expect(find.text('gpt-4o-mini'), findsOneWidget);
    expect(
      find.textContaining('最近测试：认证失败 · HTTP 401 · 已重试 1 次'),
      findsOneWidget,
    );
    expect(find.textContaining('03:30'), findsOneWidget);
    expect(find.textContaining('encrypted-test-key'), findsNothing);
    expect(find.textContaining('请检查 API Key'), findsNothing);
  });
}
