import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';

void main() {
  Future<void> pumpTestApp(WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
  }

  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await pumpTestApp(tester);
    expect(find.byType(AiChatApp), findsOneWidget);
  });

  testWidgets('SnackBar uses floating layout above bottom input area', (
    WidgetTester tester,
  ) async {
    await pumpTestApp(tester);

    final context = tester.element(find.byType(ResponsiveShell));
    final snackBarTheme = Theme.of(context).snackBarTheme;

    expect(snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(
      snackBarTheme.insetPadding,
      const EdgeInsets.fromLTRB(16, 8, 16, 120),
    );
  });
}
