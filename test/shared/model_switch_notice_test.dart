import 'package:ai_chat_app/shared/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ModelSwitchNotice renders a compact switch timeline item', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ModelSwitchNotice(
            content: '已切换模型：OpenAI / gpt-4o → Claude / sonnet',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.swap_horiz_outlined), findsOneWidget);
    expect(find.textContaining('已切换模型'), findsOneWidget);
  });
}
