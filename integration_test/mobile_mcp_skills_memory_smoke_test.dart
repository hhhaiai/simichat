import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/core/skills/skill_hub_repository.dart';
import 'package:ai_chat_app/features/search/search_sheet.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/skill_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile MCP Skills and memory UI smoke', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.mcpDao.insertServer(
      id: 'mobile-native-mcp',
      name: 'SimiChat 内建工具',
      transport: kMcpTransportAppNative,
      isEnabled: true,
      source: 'marketplace',
      marketplaceId: kAppNativeMcpServerId,
    );
    await db.skillDao.insertSkill(
      id: 'mobile-skill',
      name: 'mobile-skill',
      description: '移动端稳定性测试 Skill',
      instructions: '只用于移动端测试。',
      online: false,
      isEnabled: true,
    );
    await db.sessionDao.createSession(id: 'mobile-memory-session');
    await db.sessionDao.updateTitle('mobile-memory-session', '移动端记忆稳定性');
    await db.messageDao.insertMessage(
      id: 'mobile-memory-message',
      sessionId: 'mobile-memory-session',
      role: 'user',
      content: '请记住移动端优先和本地记忆稳定工作。',
    );

    final skillRepository = SkillHubRepository(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'total': 1,
              'skills': [
                {
                  'slug': 'mobile-skill',
                  'name': 'mobile-skill',
                  'description': '移动端稳定性测试 Skill',
                  'ownerName': 'SimiChat',
                  'category': '测试',
                  'source': 'local',
                  'version': '1.0.0',
                  'downloads': 1,
                  'installs': 1,
                  'stars': 1,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(skillRepository.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          skillHubRepositoryProvider.overrideWithValue(skillRepository),
        ],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'initial app');

    // Skills Hub：真实移动端 Navigator / 页面加载 / HTTP 搜索状态。
    await _openMobileDrawer(tester);
    await tester.tap(find.byTooltip('Skills Hub').last);
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'Skills Hub open');
    expect(find.text('Skills 市场'), findsOneWidget);
    await _pumpUntil(
      tester,
      () async => find.text('热门 Skills（1）').evaluate().isNotEmpty,
    );
    _expectNoFlutterException(tester, 'Skills Hub loaded');
    expect(find.text('mobile-skill'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'settings open');

    // MCP 与本地搜索 / 记忆入口：滚动到设置页的移动端真实 section。
    await _openMobileDrawer(tester);
    await tester.tap(find.byTooltip('设置').last);
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'MCP server dialog');
    expect(find.text('设置'), findsOneWidget);

    await _scrollUntilText(tester, 'MCP 服务器');
    expect(find.text('MCP Runtime（内建 / PC 容器）'), findsOneWidget);
    expect(find.text('SimiChat 内建工具'), findsOneWidget);

    await _scrollUntilText(tester, '添加 MCP 服务器');
    await tester.tap(find.text('添加 MCP 服务器'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'local search index dialog');
    expect(find.text('添加 MCP 服务器'), findsWidgets);
    expect(find.text('Stdio（PC 高级 / Runtime）'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'local search index warmed');

    await _scrollUntilText(tester, '本地搜索索引', delta: 600);
    await tester.tap(find.text('本地搜索索引'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'global search sheet');
    expect(find.text('预热 / 修复'), findsOneWidget);
    await tester.tap(find.text('预热 / 修复'));
    await tester.pumpAndSettle();
    await _pumpUntil(
      tester,
      () async => find.textContaining('搜索索引').evaluate().isNotEmpty,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 全局搜索：真实 bottom sheet、SQLite FTS / semantic / Key Point 路径。
    showSearchSheet(tester.element(find.byType(Scaffold).first));
    await tester.pumpAndSettle();
    final searchField = find.byType(TextField).last;
    await tester.enterText(searchField, '移动端优先');
    await _pumpUntil(
      tester,
      () async => find.text('移动端记忆稳定性').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
    );
    expect(find.text('移动端记忆稳定性'), findsWidgets);
    _expectNoFlutterException(tester, 'global search results');
    // All HTTP data above comes from an in-process MockClient; no external
    // service, Node executable, npx command, or remote MCP is used.
    // ignore: avoid_print
    print('SIMICHAT_MCP_SKILLS_MEMORY_UI_READY');
  });
}

void _expectNoFlutterException(WidgetTester tester, String stage) {
  final exception = tester.takeException();
  if (exception != null) {
    fail('$stage raised a Flutter exception:\n$exception');
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('Timed out waiting for mobile MCP / Skills / memory UI state');
}

Future<void> _scrollUntilText(
  WidgetTester tester,
  String text, {
  double delta = -600,
}) async {
  final scrollable = find.byType(Scrollable).last;
  for (var attempt = 0; attempt < 30; attempt++) {
    final target = find.text(text);
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.last);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(scrollable, Offset(0, delta));
    await tester.pumpAndSettle();
  }
  fail('Timed out scrolling to $text');
}

Future<void> _openMobileDrawer(WidgetTester tester) async {
  if (find.byType(Drawer).evaluate().isNotEmpty) return;
  await tester.tap(find.byIcon(Icons.menu).first);
  await tester.pumpAndSettle();
  expect(find.byType(Drawer), findsOneWidget);
}
