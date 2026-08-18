import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/widgets/sidebar.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creating a folder from sidebar does not crash', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: Sidebar())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建文件夹'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '资料');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      (await db.folderDao.getAllFolders()).map((folder) => folder.name),
      contains('资料'),
    );
  });

  testWidgets('creating a folder while another folder is expanded does not crash', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.folderDao.createFolder(id: 'folder-z', name: '资料夹Z');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: Sidebar())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料夹Z'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建文件夹'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'A资料夹');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      (await db.folderDao.getAllFolders()).map((folder) => folder.name),
      containsAll(<String>['资料夹Z', 'A资料夹']),
    );
  });

  testWidgets('new chat button creates a session', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: Sidebar())),
      ),
    );
    await tester.pumpAndSettle();

    expect(await db.sessionDao.getAllSessions(), isEmpty);

    await tester.tap(find.text('新建对话'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await db.sessionDao.getAllSessions(), hasLength(1));
  });

  testWidgets('pinned session renders above unpinned sessions in its own group', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.sessionDao.createSession(id: 's-pinned');
    await db.sessionDao.createSession(id: 's-normal');
    await db.sessionDao.updateTitle('s-pinned', '置顶会话');
    await db.sessionDao.updateTitle('s-normal', '普通会话');
    await db.sessionDao.setPinned('s-pinned', true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: Sidebar())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已置顶'), findsOneWidget);
    expect(find.text('置顶会话'), findsOneWidget);
    expect(find.text('普通会话'), findsOneWidget);
    final pinnedY = tester.getTopLeft(find.text('置顶会话')).dy;
    final normalY = tester.getTopLeft(find.text('普通会话')).dy;
    expect(pinnedY, lessThan(normalY));
  });

  testWidgets('pin and unpin via session popup menu flips db state', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.sessionDao.createSession(id: 's-popup');
    await db.sessionDao.updateTitle('s-popup', '待置顶会话');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: Sidebar())),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, '待置顶会话');
    await tester.tap(
      find.descendant(of: tile, matching: find.byIcon(Icons.more_vert)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect((await db.sessionDao.getSession('s-popup'))!.isPinned, isTrue);

    await tester.tap(
      find.descendant(of: tile, matching: find.byIcon(Icons.more_vert)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消置顶'));
    await tester.pumpAndSettle();
    expect((await db.sessionDao.getSession('s-popup'))!.isPinned, isFalse);
  });
}
