import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/ai/model_switch_record.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/dreaming_provider.dart';
import 'package:ai_chat_app/shared/providers/user_profile_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppDatabase> pumpMobileApp(
    WidgetTester tester, {
    Future<void> Function(AppDatabase db)? seed,
    Map<String, Object>? initialPrefs,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs ?? {});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    if (seed != null) {
      await seed(db);
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('mobile main flow smoke: session, settings, send guard', (
    tester,
  ) async {
    final db = await pumpMobileApp(tester);

    expect(find.text('AI Chat'), findsWidgets);
    expect(find.text('未选择模型'), findsOneWidget);
    expect(await db.sessionDao.getAllSessions(), hasLength(1));

    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    expect(await db.sessionDao.getAllSessions(), hasLength(2));

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('数据与档案'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '你好 SimiChat');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('还没有可用模型'), findsOneWidget);
    expect(find.text('请先去设置里添加模型渠道和模型，然后再发送消息。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile history smoke: drawer search selects existing session', (
    tester,
  ) async {
    final db = await pumpMobileApp(tester);
    final sessionId = (await db.sessionDao.getAllSessions()).single.id;
    await db.sessionDao.updateTitle(sessionId, '项目复盘记录');
    await db.messageDao.insertMessage(
      id: 'message-1',
      sessionId: sessionId,
      role: 'user',
      content: '今天复盘移动端主链路',
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final drawerSearch = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索会话...',
    );
    expect(drawerSearch, findsOneWidget);

    await tester.enterText(drawerSearch, '项目复盘');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('项目复盘记录'), findsOneWidget);
    await tester.tap(find.text('项目复盘记录'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile due dreaming smoke: creates pending profile proposal', (
    tester,
  ) async {
    await pumpMobileApp(
      tester,
      initialPrefs: {
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 0,
          'minute': 0,
        }),
      },
      seed: (db) async {
        await db.sessionDao.createSession(id: 'session-dreaming');
        await db.messageDao.insertMessage(
          id: 'message-dreaming-1',
          sessionId: 'session-dreaming',
          role: 'user',
          content: '请记住我喜欢移动端优先和本地隐私。',
        );
      },
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
    expect(prefs.getString(kUserProfileStorageKey), isNull);
    final proposals = decodeUserProfileChangeProposals(
      prefs.getString(kUserProfileChangeProposalsStorageKey),
    );
    expect(proposals, hasLength(1));
    expect(proposals.single.diff.hasChanges, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile model switch smoke: records timeline event', (
    tester,
  ) async {
    final db = await pumpMobileApp(
      tester,
      seed: (db) async {
        await db.channelDao.createChannel(
          id: 'channel-openai',
          name: 'OpenAI',
          baseUrl: 'https://example.invalid',
          apiKeyEncrypted: KeyEncryptor.encrypt('test-api-key'),
          protocol: 'openai_chat',
        );
        await db.channelDao.addModel(
          id: 'model-gpt-4o',
          channelId: 'channel-openai',
          modelName: 'gpt-4o',
        );
        await db.channelDao.addModel(
          id: 'model-gpt-4o-mini',
          channelId: 'channel-openai',
          modelName: 'gpt-4o-mini',
        );
        await db.sessionDao.createSession(
          id: 'session-1',
          defaultChannelModelId: 'model-gpt-4o',
        );
      },
    );

    expect(find.text('OpenAI / gpt-4o'), findsOneWidget);

    await tester.tap(find.text('OpenAI / gpt-4o'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-4o-mini').last);
    await tester.pumpAndSettle();

    final session = await db.sessionDao.getSession('session-1');
    expect(session?.defaultChannelModelId, 'model-gpt-4o-mini');

    final messages = await db.messageDao.getMessagesBySession('session-1');
    expect(messages, hasLength(1));
    expect(messages.single.messageType, kModelSwitchMessageType);
    expect(messages.single.role, 'system');
    expect(messages.single.content, contains('OpenAI / gpt-4o'));
    expect(messages.single.content, contains('OpenAI / gpt-4o-mini'));
    expect(find.textContaining('已切换模型'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
