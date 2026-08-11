import 'dart:convert';

import 'package:ai_chat_app/core/archive/obsidian_vault_export_service.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  /// 设置页首部的 SimiRouter AI 推广卡片增加了页首高度，操作下方 tile 前先滚动到可见。
  Future<void> scrollToVisible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings page exposes global font scale control', (
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

    expect(find.text('字体大小'), findsOneWidget);
    expect(find.textContaining('当前: 100%'), findsOneWidget);

    await tester.tap(find.text('字体大小'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('恢复默认'), findsOneWidget);
    expect(find.textContaining('SimiChat 会记住你的阅读偏好'), findsOneWidget);
  });

  testWidgets('settings page exposes markdown archive maintenance entry', (
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

    await scrollToVisible(tester, find.text('对话 Markdown 档案'));
    expect(find.text('对话 Markdown 档案'), findsOneWidget);

    await tester.tap(find.text('对话 Markdown 档案'));
    await tester.pumpAndSettle();

    expect(find.text('当前无活跃会话。'), findsOneWidget);
    expect(find.text('待修复队列：0 项'), findsOneWidget);
    expect(find.text('修复队列'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);

    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();

    expect(find.text('导出本地数据'), findsOneWidget);
    expect(find.text('包含原始语音文件'), findsOneWidget);
    expect(find.text('仅生成压缩包'), findsOneWidget);
    expect(find.text('电脑端传输'), findsOneWidget);
    expect(find.text('Obsidian Vault'), findsOneWidget);
    expect(find.text('同步到 Obsidian'), findsOneWidget);
    expect(find.text('生成并系统分享'), findsOneWidget);
  });

  testWidgets('settings page asks for Obsidian sync conflict strategy', (
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

    await scrollToVisible(tester, find.text('对话 Markdown 档案'));
    await tester.tap(find.text('对话 Markdown 档案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步到 Obsidian'));
    await tester.pumpAndSettle();

    expect(find.text('Obsidian 同步策略'), findsOneWidget);
    expect(find.text('安全同步'), findsOneWidget);
    expect(find.text('覆盖冲突'), findsOneWidget);
    expect(find.textContaining('默认使用安全同步'), findsOneWidget);
    expect(find.textContaining('目录、符号链接等非普通文件仍会被跳过'), findsOneWidget);
  });

  testWidgets(
    'settings page applies model provider presets in channel dialog',
    (tester) async {
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

      expect(find.text('厂商预设'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('DeepSeek').last);
      await tester.pumpAndSettle();

      expect(find.text('OpenAI 兼容预设'), findsOneWidget);
      expect(find.text('DeepSeek'), findsWidgets);
      expect(find.text('https://api.deepseek.com/v1'), findsNothing);
      expect(find.textContaining('DeepSeek OpenAI 兼容接口'), findsOneWidget);
      // 内置预设一键接入：只保留 API Key 输入框，名称 / Base URL / 协议隐藏。
      expect(find.text('API Key'), findsOneWidget);
      expect(find.text('渠道名称'), findsNothing);
      expect(find.text('协议类型'), findsNothing);
    },
  );

  testWidgets('settings page shows markdown archive repair queue details', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'archive_repair_queue_v1': jsonEncode([
        {
          'sessionId': 'session-1',
          'operation': 'append-user',
          'error': 'disk full',
          'createdAt': DateTime(2026, 6, 27).toIso8601String(),
        },
      ]),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await scrollToVisible(tester, find.text('对话 Markdown 档案'));
    expect(find.textContaining('1 个待修复项'), findsOneWidget);

    await tester.tap(find.text('对话 Markdown 档案'));
    await tester.pumpAndSettle();

    expect(find.text('待修复队列：1 项'), findsOneWidget);
    expect(find.textContaining('最近失败：append-user · session-1'), findsOneWidget);
    expect(find.text('修复队列'), findsOneWidget);
  });

  testWidgets('obsidian sync conflict details explain safe skipped files', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ObsidianSyncConflictDetails(
            conflicts: [
              ObsidianVaultSyncConflict(
                path: 'Conversations/session-1.md',
                reason: 'target_modified',
                incomingSha256Hex: '1234567890abcdef',
                existingSha256Hex: 'abcdef1234567890',
              ),
              ObsidianVaultSyncConflict(
                path: 'Attachments/m1/a1-file.png',
                reason: 'unsafe_existing_entity',
                incomingSha256Hex: '9999888877776666',
              ),
              ObsidianVaultSyncConflict(
                path: 'Conversations/removed.md',
                reason: 'source_removed_target_modified',
                incomingSha256Hex: '1111222233334444',
                existingSha256Hex: '5555666677778888',
              ),
              ObsidianVaultSyncConflict(
                path: 'Attachments/removed-dir',
                reason: 'stale_unsafe_existing_entity',
                incomingSha256Hex: 'aaaabbbbccccdddd',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('4 个冲突'), findsOneWidget);
    expect(find.text('Conversations/session-1.md'), findsOneWidget);
    expect(find.text('Attachments/m1/a1-file.png'), findsOneWidget);
    expect(find.text('Conversations/removed.md'), findsOneWidget);
    expect(find.text('Attachments/removed-dir'), findsOneWidget);
    expect(find.textContaining('默认不覆盖用户改动'), findsOneWidget);
    expect(find.textContaining('避免写穿或覆盖非预期'), findsOneWidget);
    expect(find.textContaining('已保留以避免误删用户内容'), findsOneWidget);
    expect(find.textContaining('已跳过清理以避免写穿'), findsOneWidget);
    expect(find.textContaining('1234567890ab'), findsOneWidget);
    expect(find.textContaining('abcdef123456'), findsOneWidget);
  });
}
