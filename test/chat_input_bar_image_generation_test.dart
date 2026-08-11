import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('composer tap explicitly re-requests the system text input', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final hasText = ValueNotifier<bool>(false);
    addTearDown(hasText.dispose);
    final textInputCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        textInputCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            onSend: (_, _) async => true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(
      textInputCalls.where((call) => call.method == 'TextInput.show').length,
      greaterThanOrEqualTo(2),
    );
  });

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

  testWidgets('attachment menu exposes edit image entry', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final hasText = ValueNotifier<bool>(false);
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
            onEditImage: (imagePath) async => true,
          ),
        ),
      ),
    );

    // 打开加号菜单 → “编辑图片”入口存在。
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    expect(find.text('编辑图片'), findsOneWidget);
  });

  testWidgets('deep think toggle appears and flips notifier', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final hasText = ValueNotifier<bool>(false);
    addTearDown(hasText.dispose);
    final deepThink = ValueNotifier<bool>(false);
    addTearDown(deepThink.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            onSend: (text, attachments) async => true,
            deepThinkNotifier: deepThink,
          ),
        ),
      ),
    );

    final button = find.byKey(const ValueKey('deep-think-button'));
    expect(button, findsOneWidget);
    expect(deepThink.value, isFalse);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(deepThink.value, isTrue);

    // deepThinkNotifier 为 null 时不显示。
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
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deep-think-button')), findsNothing);
  });

  testWidgets(
    'compact composer keeps text usable and moves secondary actions into menu',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController(text: '测试输入');
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final hasText = ValueNotifier<bool>(true);
      addTearDown(hasText.dispose);
      final deepThink = ValueNotifier<bool>(false);
      addTearDown(deepThink.dispose);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                controller: controller,
                focusNode: focusNode,
                isStreaming: false,
                hasTextNotifier: hasText,
                onSend: (text, attachments) async => true,
                onGenerateImage: (text) async => true,
                onEditImage: (path) async => true,
                deepThinkNotifier: deepThink,
                showVoiceInput: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      expect(tester.getSize(textField).width, greaterThanOrEqualTo(120));
      expect(tester.getSize(textField).height, lessThan(100));
      expect(find.byKey(const ValueKey('generate-image-button')), findsNothing);
      expect(find.byKey(const ValueKey('deep-think-button')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      expect(find.text('生成图片'), findsOneWidget);
      expect(find.text('深度思考'), findsOneWidget);
    },
  );

  testWidgets('submitting state disables conflicting composer actions', (
    tester,
  ) async {
    final controller = TextEditingController(text: '正在生成图片');
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final hasText = ValueNotifier<bool>(true);
    addTearDown(hasText.dispose);
    final deepThink = ValueNotifier<bool>(false);
    addTearDown(deepThink.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            isSubmitting: true,
            hasTextNotifier: hasText,
            onSend: (text, attachments) async => true,
            onGenerateImage: (text) async => true,
            deepThinkNotifier: deepThink,
            showVoiceInput: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('generate-image-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('deep-think-button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('voice-record-button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('submit-progress-button')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
