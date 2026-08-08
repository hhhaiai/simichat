import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('generate image button appears and invokes callback', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final hasText = ValueNotifier<bool>(false);
    addTearDown(hasText.dispose);
    String? invokedPrompt;
    var invoked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            onSend: (text, attachments) async => true,
            onGenerateImage: (text) async {
              invoked = true;
              invokedPrompt = text;
              return true;
            },
          ),
        ),
      ),
    );

    final button = find.byKey(const ValueKey('generate-image-button'));
    expect(button, findsOneWidget);
    // 无文本时按钮禁用。
    expect(tester.widget<IconButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '一只在月球上的猫');
    hasText.value = true;
    await tester.pump();

    expect(tester.widget<IconButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(invoked, isTrue);
    expect(invokedPrompt, '一只在月球上的猫');
    // 成功后清空输入框。
    expect(controller.text, isEmpty);
    expect(hasText.value, isFalse);
  });

  testWidgets('generate image button is hidden when callback is null', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final hasText = ValueNotifier<bool>(true);
    addTearDown(hasText.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            onSend: (text, attachments) async => true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('generate-image-button')), findsNothing);
  });
}
