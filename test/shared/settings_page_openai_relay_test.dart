import 'dart:convert';

import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/relay/openai_compatible_relay_server.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/openai_relay_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'settings page can generate token and start or stop local relay',
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

      await tester.scrollUntilVisible(
        find.text('个人接口中转 / 本地 OpenAI Relay'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('个人接口中转 / 本地 OpenAI Relay'), findsOneWidget);
      expect(find.textContaining('仅本机访问'), findsWidgets);

      await tester.tap(find.text('个人接口中转 / 本地 OpenAI Relay'));
      await tester.pumpAndSettle();

      expect(find.text('本地 OpenAI Relay'), findsOneWidget);
      expect(find.text('状态：未运行'), findsOneWidget);
      expect(find.textContaining('默认仅绑定 127.0.0.1'), findsOneWidget);
      expect(find.text('允许局域网设备访问'), findsOneWidget);
      expect(find.text('并发上限'), findsOneWidget);
      expect(find.text('4 个聊天请求'), findsOneWidget);
      expect(find.textContaining('并发保护：最多 4 个聊天请求'), findsOneWidget);
      expect(find.textContaining('用量统计：暂无累计用量'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '清空统计'), findsOneWidget);
      expect(find.textContaining('最近审计：暂无持久化审计明细'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '复制审计 JSON'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '清空审计'), findsOneWidget);
      expect(find.text('路由策略'), findsOneWidget);
      expect(find.textContaining('simichat:default'), findsOneWidget);
      expect(find.text('允许下载远端图片 URL'), findsOneWidget);
      expect(find.textContaining('默认关闭'), findsOneWidget);
      expect(find.textContaining('<YOUR_RELAY_TOKEN>'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8 个聊天请求').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('并发保护：最多 8 个聊天请求'), findsOneWidget);
      final prefsAfterConcurrency = await SharedPreferences.getInstance();
      expect(
        prefsAfterConcurrency.getInt(
          kOpenAiRelayMaxConcurrentRequestsStorageKey,
        ),
        8,
      );

      await tester.ensureVisible(find.text('路由策略'));
      await tester.tap(
        find.byType(DropdownButtonFormField<OpenAiRelayRouteStrategy>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('免费优先').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('路由：免费优先'), findsOneWidget);

      await tester.ensureVisible(find.text('允许下载远端图片 URL'));
      await tester.tap(find.text('允许下载远端图片 URL'));
      await tester.pumpAndSettle();
      expect(find.text('确认允许下载远端图片？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          kOpenAiRelayRemoteImageDownloadStorageKey,
        ),
        isNull,
      );

      await tester.tap(find.text('允许下载远端图片 URL'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认开启'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已开启远端图片 URL 安全下载'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          kOpenAiRelayRemoteImageDownloadStorageKey,
        ),
        isTrue,
      );

      await tester.ensureVisible(find.byTooltip('生成新令牌'));
      await tester.tap(find.byTooltip('生成新令牌'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final encryptedToken = prefs.getString(kOpenAiRelayTokenStorageKey);
      expect(encryptedToken, isNotNull);
      expect(
        KeyEncryptor.decrypt(encryptedToken!).length,
        greaterThanOrEqualTo(16),
      );

      await tester.tap(find.widgetWithText(FilledButton, '启动'));
      await tester.pumpAndSettle();

      expect(find.text('状态：已运行'), findsOneWidget);
      expect(find.textContaining('http://127.0.0.1:'), findsWidgets);
      expect(find.textContaining('<YOUR_RELAY_TOKEN>'), findsOneWidget);
      expect(find.textContaining('并发保护：最多'), findsOneWidget);
      expect(find.textContaining('暂无请求'), findsOneWidget);
      expect(find.textContaining('用量统计：暂无累计用量'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '停止'));
      await tester.pumpAndSettle();

      expect(find.text('状态：未运行'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('settings page shows and clears persisted relay usage stats', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kOpenAiRelayUsageStatsStorageKey: jsonEncode(
        const OpenAiRelayUsageStats(
          totalRequests: 3,
          chatCompletionRequests: 2,
          successfulRequests: 2,
          rejectedRequests: 1,
          unauthorizedRequests: 1,
          totalDurationMs: 120,
          lastStatusCode: 401,
          lastCode: 'unauthorized',
        ).toJson(),
      ),
      kOpenAiRelayAuditLogStorageKey: jsonEncode([
        OpenAiRelayAuditLogEntry(
          method: 'GET',
          path: '/v1/models',
          statusCode: 401,
          code: 'unauthorized',
          authorized: false,
          completedAt: DateTime.utc(2026, 6, 27, 10),
          durationMs: 4,
        ).toJson(),
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

    await tester.scrollUntilVisible(
      find.text('个人接口中转 / 本地 OpenAI Relay'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('个人接口中转 / 本地 OpenAI Relay'));
    await tester.pumpAndSettle();

    expect(find.textContaining('用量统计：累计 3 次'), findsOneWidget);
    expect(find.textContaining('聊天 2 次'), findsOneWidget);
    expect(find.textContaining('最近审计：已本地脱敏保存 1 条'), findsOneWidget);
    expect(
      find.textContaining('GET /v1/models → 401/unauthorized'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, '清空统计'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '复制审计 JSON'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清空审计'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(TextButton, '清空统计'));
    await tester.tap(find.widgetWithText(TextButton, '清空统计'));
    await tester.pumpAndSettle();

    expect(find.textContaining('用量统计：暂无累计用量'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kOpenAiRelayUsageStatsStorageKey), isNull);

    await tester.ensureVisible(find.widgetWithText(TextButton, '清空审计'));
    await tester.tap(find.widgetWithText(TextButton, '清空审计'));
    await tester.pumpAndSettle();

    expect(find.textContaining('最近审计：暂无持久化审计明细'), findsOneWidget);
    expect(prefs.getString(kOpenAiRelayAuditLogStorageKey), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('settings page requires confirmation before LAN relay access', (
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

    await tester.scrollUntilVisible(
      find.text('个人接口中转 / 本地 OpenAI Relay'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('个人接口中转 / 本地 OpenAI Relay'));
    await tester.pumpAndSettle();

    expect(find.textContaining('默认仅绑定 127.0.0.1'), findsOneWidget);
    expect(find.text('允许局域网设备访问'), findsOneWidget);

    await tester.tap(find.text('允许局域网设备访问'));
    await tester.pumpAndSettle();
    expect(find.text('确认开放局域网访问？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.textContaining('默认仅绑定 127.0.0.1'), findsOneWidget);
    expect(find.text('局域网候选地址'), findsNothing);

    await tester.tap(find.text('允许局域网设备访问'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认开放'));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前已允许局域网访问'), findsOneWidget);
    expect(find.text('局域网候选地址'), findsOneWidget);
    expect(find.textContaining('绑定：0.0.0.0（局域网）'), findsWidgets);

    await tester.tap(find.text('允许局域网设备访问'));
    await tester.pumpAndSettle();
    expect(find.textContaining('默认仅绑定 127.0.0.1'), findsOneWidget);
    expect(find.text('局域网候选地址'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
