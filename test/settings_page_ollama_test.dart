import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings exposes a no-key Ollama local-model setup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加渠道'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    final presetItems = find.byType(
      DropdownMenuItem<String>,
      skipOffstage: false,
    );
    await tester.ensureVisible(presetItems.last);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(presetItems.last));
    await tester.pumpAndSettle();

    expect(find.text('API Key（可选）'), findsOneWidget);
    // 内置预设一键接入：名称 / Base URL 不再作为可编辑输入框出现。
    expect(find.widgetWithText(TextField, 'Ollama 本地模型'), findsNothing);
    expect(
      find.widgetWithText(TextField, 'http://localhost:11434'),
      findsNothing,
    );
    // 预设仍显示在下拉框与提示卡中。
    expect(find.text('Ollama 本地模型'), findsWidgets);
  });
}
