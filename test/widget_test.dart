import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_chat_app/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiChatApp()));
    expect(find.byType(AiChatApp), findsOneWidget);
  });

  testWidgets('SnackBar uses floating layout above bottom input area', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: AiChatApp()));

    final context = tester.element(find.byType(ResponsiveShell));
    final snackBarTheme = Theme.of(context).snackBarTheme;

    expect(snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(
      snackBarTheme.insetPadding,
      const EdgeInsets.fromLTRB(16, 8, 16, 120),
    );
  });
}
