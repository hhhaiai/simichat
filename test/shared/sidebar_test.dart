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
}
