import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/widgets/in_app_h5_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const signUpUrl = 'https://api.dwchainless.com/sign-up?aff=Bslh';
  const homeUrl = 'https://api.dwchainless.com/';

  testWidgets('settings page shows dwchainless promotion card with sign-up', (
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

    expect(find.text('SimiRouter AI 中转站'), findsWidgets);
    expect(find.text('获取 Key'), findsOneWidget);
    expect(find.text('一键接入'), findsOneWidget);
    expect(find.byType(InAppH5Prewarm), findsOneWidget);
    expect(find.text('数据默认不落盘'), findsNothing);
    expect(find.text('计费公开透明'), findsNothing);

    await tester.tap(find.text('获取 Key'));
    await tester.pumpAndSettle();
    final page = tester.widget<InAppH5Page>(find.byType(InAppH5Page));
    expect(page.initialUrl, signUpUrl);
    expect(find.text(signUpUrl), findsNothing);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('官网'));
    await tester.pumpAndSettle();
    final homePage = tester.widget<InAppH5Page>(find.byType(InAppH5Page));
    expect(homePage.initialUrl, homeUrl);
    expect(find.text(homeUrl), findsNothing);
  });

  testWidgets('one-tap add channel prefills dwchainless preset', (
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

    await tester.tap(find.text('一键接入'));
    await tester.pumpAndSettle();

    // 添加渠道对话框已打开（“添加渠道”同时作为列表按钮与对话框标题存在）。
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('添加渠道'), findsWidgets);
    // 一键接入：名称 / Base URL 由预设锁定，不再显示可编辑输入框，只留 API Key。
    expect(find.text('API Key'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'SimiRouter AI 中转站'), findsNothing);
    expect(
      find.widgetWithText(TextField, 'https://api.dwchainless.com/v1'),
      findsNothing,
    );
    // 预设名称仍显示在下拉框与提示卡中。
    expect(find.text('SimiRouter AI 中转站'), findsWidgets);
    // 预设提示卡内也提供内置 H5 的“获取 Key / 访问官网”入口。
    expect(find.text('获取 Key'), findsWidgets);
    expect(find.text('访问官网'), findsWidgets);
    expect(find.text('https://api.dwchainless.com/'), findsNothing);
  });

  testWidgets('configured dwchainless channel shows has-key status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'dw-channel-1',
      name: 'SimiRouter AI 中转站',
      baseUrl: 'https://api.dwchainless.com/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('sk-dw-test'),
      protocol: 'openai_chat',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 已配置 Key 时展示紧凑状态，不再渲染六项营销标签。
    expect(find.text('已接入 · 可管理模型和 API Key'), findsOneWidget);
    expect(find.text('获取 Key'), findsNothing);
    expect(find.text('管理'), findsOneWidget);
    expect(find.text('多模型统一接入'), findsNothing);
    expect(find.text('数据默认不落盘'), findsNothing);
    expect(find.text('高并发低延迟'), findsNothing);
    expect(find.text('计费公开透明'), findsNothing);
    expect(find.text('智能路由容灾'), findsNothing);
    expect(find.text('企业级管理'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('simirouter_channel_card'))).height,
      lessThan(190),
    );

    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('编辑渠道'), findsOneWidget);
  });

  testWidgets('dwchainless channel without key still prompts for key', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'dw-channel-empty-key',
      name: 'SimiRouter AI 中转站',
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
    expect(find.text('获取 Key'), findsOneWidget);
    expect(find.text('补充 Key'), findsOneWidget);
  });

  testWidgets('lookalike, custom port and user-info URLs are not SimiRouter', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'lookalike-channel',
      name: 'Lookalike',
      baseUrl: 'https://api.dwchainless.com.evil.example/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('sk-lookalike'),
      protocol: 'openai_chat',
    );
    await db.channelDao.createChannel(
      id: 'custom-port-channel',
      name: 'Custom port',
      baseUrl: 'https://api.dwchainless.com:8443/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('sk-custom-port'),
      protocol: 'openai_chat',
    );
    await db.channelDao.createChannel(
      id: 'user-info-channel',
      name: 'User info',
      baseUrl: 'https://user:pass@api.dwchainless.com/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('sk-user-info'),
      protocol: 'openai_chat',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主流模型统一接入 · 智能路由'), findsOneWidget);
    expect(find.text('获取 Key'), findsOneWidget);
  });

  testWidgets('compact SimiRouter card fits 320px width at 120% text scale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final card = find.byKey(const Key('simirouter_channel_card'));
    expect(card, findsOneWidget);
    // Container 的测量宽度包含左右各 16px margin；320px 视口下内容区为
    // 288px，整卡外框仍不会超过视口。
    expect(tester.getSize(card).width, lessThanOrEqualTo(320));
    expect(tester.getSize(card).height, lessThan(170));
    final keyButton = find.widgetWithText(FilledButton, '获取 Key');
    final addButton = find.widgetWithText(OutlinedButton, '一键接入');
    final homeButton = find.widgetWithText(TextButton, '官网');
    expect(keyButton, findsOneWidget);
    expect(addButton, findsOneWidget);
    expect(homeButton, findsOneWidget);
    for (final button in [keyButton, addButton, homeButton]) {
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    }
    expect(tester.getCenter(keyButton).dy, tester.getCenter(addButton).dy);
    expect(tester.getCenter(addButton).dy, tester.getCenter(homeButton).dy);
  });

  testWidgets('about section credits dwchainless relay with icon and link', (
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

    final target = find.text('鸣谢 · SimiRouter AI 中转站');
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
    expect(find.textContaining('点击查看官网'), findsOneWidget);

    await tester.tap(target);
    await tester.pumpAndSettle();
    final page = tester.widget<InAppH5Page>(find.byType(InAppH5Page));
    expect(page.initialUrl, homeUrl);
    expect(find.text(homeUrl), findsNothing);
  });
}
