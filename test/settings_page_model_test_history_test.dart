import 'dart:convert';

import 'dart:async';

import 'package:ai_chat_app/core/ai/model_tester.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
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

  testWidgets('model test button shows spinner while testing and result after', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.channelDao.createChannel(
      id: 'btn-channel',
      name: 'Btn Channel',
      baseUrl: 'https://api.example.com/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'btn-model-id',
      channelId: 'btn-channel',
      modelName: 'btn-model',
    );

    final gate = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: SettingsPage(
            modelTestRunner:
                ({
                  required protocol,
                  required baseUrl,
                  required apiKey,
                  required model,
                  required capability,
                }) async {
                  await gate.future;
                  return ModelTestResult.success();
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Btn Channel'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Btn Channel'));
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('test-model-btn-model-id'));
    expect(button, findsOneWidget);
    // 40px 最小可点击目标。
    expect(tester.getSize(button).width, greaterThanOrEqualTo(40));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(40));

    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    // 测试中：按钮禁用并显示 spinner。
    expect(find.descendant(of: button, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    final iconButton = tester.widget<IconButton>(button);
    expect(iconButton.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    // 完成后显示成功图标，按钮恢复可点。
    expect(find.descendant(of: button, matching: find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
  });
}

