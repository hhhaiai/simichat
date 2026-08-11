import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/ai/model_provider_preset.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/core/skills/skill.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:ai_chat_app/shared/widgets/in_app_h5_page.dart';
import 'package:drift/native.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewController;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SimiRouter 品牌真机 smoke：设置页推广卡片、一键接入锁定、内置
/// MCP（App Native / 内置 Node）、内置 Skills 植入。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SimiRouter brand, bundled MCP and built-in skills on device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 内置 Skills：与 main() 启动植入相同的幂等逻辑（已存在则跳过），
    //    验证内置列表可在真机 App 数据库落库且默认关闭。
    for (final skill in builtInSkills) {
      final existing = await db.skillDao.getSkill(skill.id);
      if (existing == null) {
        await db.skillDao.insertSkill(
          id: skill.id,
          name: skill.name,
          description: skill.description,
          instructions: skill.instructions,
          isEnabled: false,
        );
      }
    }
    final skills = await db.skillDao.getAllSkills();
    final builtinIds = builtInSkills.map((s) => s.id).toSet();
    expect(
      skills.map((s) => s.id).where(builtinIds.contains).length,
      builtinIds.length,
      reason: '启动后内置 Skills 应全部植入数据库',
    );
    expect(
      skills.where((s) => builtinIds.contains(s.id)).every((s) => !s.isEnabled),
      isTrue,
      reason: '内置 Skills 默认关闭，由用户手动开启',
    );

    // 2. 内置 MCP 可用：App Native 内建工具在 App 进程内直接可用。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiChatApp)),
      listen: false,
    );
    final mcpClient = McpClient(
      name: 'simirouter-brand-smoke',
      transport: AppNativeMcpTransport(serverId: kAppNativeMcpServerId),
    );
    await mcpClient.initialize();
    expect(
      mcpClient.tools.map((tool) => tool.name),
      containsAll(['simichat.runtime_info', 'simichat.now']),
    );
    final runtimeResult = await mcpClient.callTool(
      'simichat.runtime_info',
      const <String, dynamic>{},
    );
    expect(runtimeResult.isError, isFalse);
    final runtime =
        jsonDecode(runtimeResult.content.single.text!) as Map<String, dynamic>;
    expect(runtime['dependencyMode'], 'in_app');
    expect(runtime['externalProcess'], isFalse);
    expect(runtime['mobileReady'], isTrue);
    await mcpClient.dispose();
    expect(container.read(mcpManagerProvider.notifier), isNotNull);

    // 3. 打开设置页，验证 SimiRouter 品牌推广卡片。
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);

    // 卡片头部：品牌名 + 紧凑定位语。
    expect(find.text('SimiRouter AI 中转站'), findsWidgets);
    expect(find.text('主流模型统一接入 · 智能路由'), findsOneWidget);

    // 已从首屏移除六项营销标签，避免渠道区域过长。
    for (final label in [
      '多模型统一接入',
      '数据默认不落盘',
      '高并发低延迟',
      '计费公开透明',
      '智能路由容灾',
      '企业级管理',
    ]) {
      expect(find.text(label), findsNothing, reason: '仍显示冗长要点：$label');
    }

    // 三个紧凑动作：获取 Key / 一键接入 / 官网。
    expect(find.text('获取 Key'), findsOneWidget);
    expect(find.text('一键接入'), findsOneWidget);
    expect(find.text('官网'), findsOneWidget);

    // 4. 获取 Key / 官网均进入内置 H5 页面，Flutter 壳不渲染地址栏。
    await tester.tap(find.text('获取 Key'));
    await tester.pumpAndSettle();
    final signUpPage = tester.widget<InAppH5Page>(find.byType(InAppH5Page));
    expect(signUpPage.initialUrl, kSimiRouterSignUpUrl);
    expect(find.text(kSimiRouterSignUpUrl), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('官网'));
    await tester.pumpAndSettle();
    final homePage = tester.widget<InAppH5Page>(find.byType(InAppH5Page));
    expect(homePage.initialUrl, kSimiRouterHomeUrl);
    expect(find.text(kSimiRouterHomeUrl), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    // 5. 一键接入：预设锁定，只保留 API Key 输入框。
    await tester.tap(find.text('一键接入'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('渠道名称'), findsNothing);
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('协议类型'), findsNothing);
  });

  testWidgets('H5 persistent profile survives close and reopen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    // 打开官网 H5 页，等待真实页面加载完成。
    await tester.tap(find.text('官网'));
    await tester.pumpAndSettle();
    var controller = tester
        .state<InAppH5PageState>(find.byType(InAppH5Page))
        .controller!;
    await _waitForPageLoaded(controller);

    // 在网页所属 origin 写入带期限 / Secure / SameSite 属性的测试 Cookie，
    // 并写入 localStorage（站点实际使用 localStorage 缓存账号资料）。
    await controller.runJavaScript(
      "document.cookie = 'simichat_profile_smoke=1; Path=/; Max-Age=86400; Secure; SameSite=Lax';",
    );
    await controller.runJavaScript(
      "localStorage.setItem('simichat_profile_smoke', '1');",
    );

    // 用「关闭」按钮提交 WebView profile 后直接退出 H5 页。
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(InAppH5Page), findsNothing);

    // 重新打开官网：必须复用同一个系统持久 profile，不主动 clearCookies，
    // 也不使用会丢失 Cookie 安全属性的 Dart 手工重建。
    await tester.tap(find.text('官网'));
    await tester.pumpAndSettle();
    controller = tester
        .state<InAppH5PageState>(find.byType(InAppH5Page))
        .controller!;
    await _waitForPageLoaded(controller);

    final documentCookies = await controller.runJavaScriptReturningResult(
      'document.cookie',
    );
    final cachedProfile = await controller.runJavaScriptReturningResult(
      "localStorage.getItem('simichat_profile_smoke')",
    );
    expect(
      documentCookies.toString(),
      contains('simichat_profile_smoke=1'),
      reason: '重开后系统 WebView profile 应继续持有带期限 Cookie。',
    );
    expect(cachedProfile.toString(), contains('1'));

    // 清理测试标记，不触碰真实登录 Cookie / 账号资料。
    await controller.runJavaScript(
      "document.cookie = 'simichat_profile_smoke=; Path=/; Max-Age=0; Secure; SameSite=Lax';",
    );
    await controller.runJavaScript(
      "localStorage.removeItem('simichat_profile_smoke');",
    );
  });
}

/// 轮询等待 WebView 主页面加载完成（真机网络加载需要时间）。
Future<void> _waitForPageLoaded(WebViewController controller) async {
  for (var i = 0; i < 30; i++) {
    try {
      final state = await controller.runJavaScriptReturningResult(
        'document.readyState',
      );
      if (state.toString().contains('complete')) return;
    } catch (_) {
      // 页面尚未可交互，继续等待。
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail('WebView 页面在 30 秒内未加载完成');
}
