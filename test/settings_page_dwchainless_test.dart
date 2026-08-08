import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/external_url_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试用外部链接打开器：只记录打开的 URL，不触发真实系统浏览器。
class _FakeExternalUrlOpener implements ExternalUrlOpener {
  final List<String> opened = [];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

void main() {
  const signUpUrl = 'https://api.dwchainless.com/sign-up';
  const homeUrl = 'https://api.dwchainless.com/';

  testWidgets('settings page shows dwchainless promotion card with sign-up', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final opener = _FakeExternalUrlOpener();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          externalUrlOpenerProvider.overrideWithValue(opener),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DW Chainless 中转站'), findsWidgets);
    expect(find.text('去注册获取 Key'), findsOneWidget);
    expect(find.text('一键接入'), findsOneWidget);

    await tester.tap(find.text('去注册获取 Key'));
    await tester.pumpAndSettle();
    expect(opener.opened, contains(signUpUrl));
  });

  testWidgets('one-tap add channel prefills dwchainless preset', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final opener = _FakeExternalUrlOpener();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          externalUrlOpenerProvider.overrideWithValue(opener),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('一键接入'));
    await tester.pumpAndSettle();

    // 添加渠道对话框已打开（“添加渠道”同时作为列表按钮与对话框标题存在）。
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('添加渠道'), findsWidgets);
    // 预设名称与 Base URL 已自动填充。
    expect(find.widgetWithText(TextField, 'DW Chainless 中转站'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'https://api.dwchainless.com/v1'),
      findsOneWidget,
    );
    // 预设提示卡内也提供“去注册”入口。
    expect(find.text('去注册'), findsOneWidget);
  });

  testWidgets('configured dwchainless channel shows has-key status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final opener = _FakeExternalUrlOpener();

    await db.channelDao.createChannel(
      id: 'dw-channel-1',
      name: 'DW Chainless 中转站',
      baseUrl: 'https://api.dwchainless.com/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('sk-dw-test'),
      protocol: 'openai_chat',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          externalUrlOpenerProvider.overrideWithValue(opener),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 已配置 Key 时不再引导注册，展示“已接入”。
    expect(find.textContaining('已接入「DW Chainless 中转站」'), findsOneWidget);
    expect(find.text('去注册获取 Key'), findsNothing);
  });

  testWidgets('dwchainless channel without key still prompts for key', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'dw-channel-empty-key',
      name: 'DW Chainless 中转站',
      baseUrl: 'https://api.dwchainless.com/v1',
      apiKeyEncrypted: '',
      protocol: 'openai_chat',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未填写 API Key'), findsOneWidget);
    expect(find.text('去注册获取 Key'), findsOneWidget);
  });

  testWidgets('about section credits dwchainless relay with icon and link', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final opener = _FakeExternalUrlOpener();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          externalUrlOpenerProvider.overrideWithValue(opener),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.text('鸣谢 · DW Chainless 中转站');
    final listFinder = find.byType(Scrollable);
    // 滚动到页面底部找到“关于”区的鸣谢入口，并确保整块完全可见。
    await tester.scrollUntilVisible(target, 200, scrollable: listFinder.first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    // 兜底再滚动一小段，避免 tile 底部被视口边缘遮住导致点击落空。
    await tester.drag(listFinder.first, const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(target, findsOneWidget);
    expect(find.textContaining(homeUrl), findsOneWidget);

    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(opener.opened, contains(homeUrl));
  });
}
