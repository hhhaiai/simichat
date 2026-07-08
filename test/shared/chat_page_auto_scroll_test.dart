import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/chat/chat_page.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sending from history view returns focus to latest messages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedScrollableChat(db);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        activeSessionIdProvider.overrideWith((ref) => 'session-scroll'),
        selectedModelIdProvider.overrideWith((ref) => 'model-scroll'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChatPage())),
      ),
    );
    await tester.pumpAndSettle();

    final position = _messageListPosition(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(position.extentAfter, lessThan(1));

    await tester.drag(_messageListFinder(), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(position.extentAfter, greaterThan(200));

    await tester.enterText(find.byType(TextField), '发送后应该回到底部');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await _pumpUntil(tester, () async {
      final stored = (await db.messageDao.getMessagesBySession(
        'session-scroll',
      )).any((message) => message.content == '发送后应该回到底部');
      final input = tester.widget<TextField>(find.byType(TextField));
      return stored && input.controller?.text.isEmpty == true;
    });
    await _pumpFor(tester, const Duration(milliseconds: 800));

    expect(_messageListPosition(tester).extentAfter, lessThan(80));
    expect(find.text('发送后应该回到底部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('condition was not met in time');
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    const step = Duration(milliseconds: 50);
    await tester.pump(step);
    elapsed += step;
  }
}

Future<void> _seedScrollableChat(AppDatabase db) async {
  await db.channelDao.createChannel(
    id: 'channel-scroll',
    name: 'Scroll Mock',
    baseUrl: 'http://127.0.0.1:1',
    apiKeyEncrypted: KeyEncryptor.encrypt('scroll-test-key'),
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'model-scroll',
    channelId: 'channel-scroll',
    modelName: 'scroll-model',
  );
  await db.sessionDao.createSession(
    id: 'session-scroll',
    defaultChannelModelId: 'model-scroll',
  );

  for (var i = 0; i < 18; i++) {
    await db.messageDao.insertMessage(
      id: 'scroll-user-$i',
      sessionId: 'session-scroll',
      role: 'user',
      content: '用户历史消息 $i\n请保留这段内容用于撑开列表。',
      channelModelId: 'model-scroll',
    );
    await db.messageDao.insertMessage(
      id: 'scroll-assistant-$i',
      sessionId: 'session-scroll',
      role: 'assistant',
      content: '助手历史回复 $i\n${'这是一段较长的历史回复。' * 4}',
      channelModelId: 'model-scroll',
    );
  }
}

ScrollPosition _messageListPosition(WidgetTester tester) {
  final listView = _messageListFinder();
  final scrollable = find
      .descendant(of: listView, matching: find.byType(Scrollable))
      .first;
  return tester.state<ScrollableState>(scrollable).position;
}

Finder _messageListFinder() {
  return find.byWidgetPredicate(
    (widget) => widget is ListView && widget.controller != null,
  );
}
