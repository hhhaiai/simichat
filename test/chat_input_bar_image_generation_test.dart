import 'dart:io';

import 'package:ai_chat_app/core/ai/universal_media_service.dart';
import 'package:ai_chat_app/shared/providers/universal_media_provider.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'mobile composer keeps newline input multiline and derives action state from the controller',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TextEditingController();
      final focusNode = FocusNode();
      final hasText = ValueNotifier<bool>(false);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);
      var sendCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              onSend: (_, _) async {
                sendCount++;
                return true;
              },
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '第一行');
      await tester.pump();
      expect(hasText.value, isTrue);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '发送',
              ),
            )
            .onPressed,
        isNotNull,
      );

      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();

      expect(sendCount, 0);
      expect(controller.text, '第一行');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'streaming composer disables media actions until the response stops',
    (tester) async {
      final controller = TextEditingController(text: '媒体提示词');
      final focusNode = FocusNode();
      final hasText = ValueNotifier<bool>(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: true,
              hasTextNotifier: hasText,
              showVoiceInput: false,
              onSend: (_, _) async => true,
              onGenerateVideo: (_, _) async => true,
              onSynthesizeSpeech: (_) async => true,
              onGenerateMusic: (_) async => true,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('generate-video-menu-item')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('synthesize-speech-menu-item')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('generate-music-menu-item')),
            )
            .enabled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('media callback errors keep the draft and show retry feedback', (
    tester,
  ) async {
    final controller = TextEditingController(text: '保留这段图片提示词');
    final focusNode = FocusNode();
    final hasText = ValueNotifier<bool>(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            onSend: (_, _) async => true,
            onGenerateImage: (_) async => throw StateError('network failed'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('generate-image-button')));
    await tester.pumpAndSettle();

    expect(controller.text, '保留这段图片提示词');
    expect(hasText.value, isTrue);
    expect(find.text('图片生成失败，已保留当前输入和附件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reference image generation receives current attachments and clears them on success',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'simichat-composer-reference-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final image = File('${directory.path}/reference.png')
        ..writeAsBytesSync(_onePixelPng);
      final controller = TextEditingController(text: '让参考图变成水彩风格');
      final focusNode = FocusNode();
      final hasText = ValueNotifier<bool>(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);
      List<PendingAttachment>? received;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              initialAttachments: [
                PendingAttachment(
                  path: image.path,
                  name: 'reference.png',
                  type: 'image',
                  fileSize: image.lengthSync(),
                ),
              ],
              showImageAttachmentPreviews: false,
              onSend: (_, _) async => true,
              onGenerateImageWithAttachments: (text, attachments) async {
                received = attachments;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('reference.png'), findsOneWidget);
      expect(find.textContaining('B'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('generate-image-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(received, hasLength(1));
      expect(received!.single.path, image.path);
      expect(controller.text, isEmpty);
      expect(find.text('reference.png'), findsNothing);
    },
  );

  testWidgets('image edit prefers the image already selected in the composer', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'simichat-composer-edit-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = File('${directory.path}/selected.png')
      ..writeAsBytesSync(_onePixelPng);
    final controller = TextEditingController(text: '改成油画风格');
    final focusNode = FocusNode();
    final hasText = ValueNotifier<bool>(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    String? editedPath;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            initialAttachments: [
              PendingAttachment(
                path: image.path,
                name: 'selected.png',
                type: 'image',
                fileSize: image.lengthSync(),
              ),
            ],
            showImageAttachmentPreviews: false,
            onSend: (_, _) async => true,
            onEditImage: (path) async {
              editedPath = path;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑图片'));
    await tester.pumpAndSettle();

    expect(editedPath, image.path);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful image edit consumes only its selected reference', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'simichat-composer-edit-consume-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final referenceFile = File('${directory.path}/edit-reference.png')
      ..writeAsBytesSync(_onePixelPng);
    final controller = TextEditingController(text: '改成水彩风格');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    final reference = PendingAttachment(
      id: 'edit-reference',
      path: referenceFile.path,
      name: 'edit-reference.png',
      type: 'image',
      fileSize: referenceFile.lengthSync(),
    );
    const retained = PendingAttachment(
      id: 'edit-retained',
      path: '/drafts/edit-retained.pdf',
      name: 'edit-retained.pdf',
      type: 'pdf',
      fileSize: 200,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            initialAttachments: [reference, retained],
            showImageAttachmentPreviews: false,
            onSend: (_, _) async => true,
            onEditImage: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑图片'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pending-attachment-edit-reference')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('pending-attachment-edit-retained')),
      findsOneWidget,
    );
    expect(controller.text, '改成水彩风格');
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
    var stopCount = 0;

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
            onStop: () async => stopCount++,
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
    final submitStop = tester.widget<IconButton>(
      find.byKey(const ValueKey('submit-stop-button')),
    );
    expect(submitStop.onPressed, isNotNull);
    expect(find.byTooltip('停止'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('submit-stop-button')));
    await tester.pump();
    expect(stopCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer tools expose video, speech, and music actions', (
    tester,
  ) async {
    final controller = TextEditingController(text: '一段温柔的海边旋律');
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final hasText = ValueNotifier<bool>(true);
    addTearDown(hasText.dispose);
    var videoCalled = false;
    var speechCalled = false;
    var musicCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            onSend: (_, _) async => true,
            onGenerateVideo: (text, attachments) async {
              videoCalled = text == '一段温柔的海边旋律' && attachments.isEmpty;
              return true;
            },
            onSynthesizeSpeech: (text) async {
              speechCalled = text == '请读出这句话';
              return true;
            },
            onGenerateMusic: (text) async {
              musicCalled = text == '生成一段钢琴曲';
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('generate-video-menu-item')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('synthesize-speech-menu-item')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('generate-music-menu-item')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('generate-video-menu-item')));
    await tester.pumpAndSettle();
    expect(videoCalled, isTrue);
    expect(controller.text, isEmpty);

    // 每次动作都遵循“输入 → 工具 → 结果消息”流程，文本成功后清空。
    controller.text = '请读出这句话';
    hasText.value = true;
    await tester.pump();
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('synthesize-speech-menu-item')));
    await tester.pumpAndSettle();
    expect(speechCalled, isTrue);

    controller.text = '生成一段钢琴曲';
    hasText.value = true;
    await tester.pump();
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('generate-music-menu-item')));
    await tester.pumpAndSettle();
    expect(musicCalled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'media action reports cleared text while retaining unrelated attachments',
    (tester) async {
      final controller = TextEditingController(text: '生成无参考图视频');
      final focusNode = FocusNode();
      final hasText = ValueNotifier(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);
      const retainedAttachment = PendingAttachment(
        id: 'retained-document',
        path: '/drafts/retained.txt',
        name: 'retained.txt',
        type: 'document',
        fileSize: 12,
      );
      ChatComposerDraft? latestDraft;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              initialAttachments: const [retainedAttachment],
              onDraftChanged: (draft) => latestDraft = draft,
              onSend: (_, _) async => true,
              onGenerateVideo: (text, attachments) async {
                expect(text, '生成无参考图视频');
                expect(attachments, isEmpty);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generate-video-menu-item')));
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(hasText.value, isFalse);
      expect(latestDraft?.text, isEmpty);
      expect(
        latestDraft?.attachments.map((attachment) => attachment.stableId),
        contains(retainedAttachment.stableId),
      );
      expect(
        find.byKey(const ValueKey('pending-attachment-retained-document')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'universal media task shows queue, generation, saving, and independent stop',
    (tester) async {
      final controller = TextEditingController(text: '生成媒体');
      final focusNode = FocusNode();
      final hasText = ValueNotifier(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);
      var stopCount = 0;

      UniversalMediaTaskState task(UniversalMediaTaskPhase phase) {
        return UniversalMediaTaskState(
          operationId: 'operation-1',
          kind: UniversalMediaKind.video,
          phase: phase,
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              isSubmitting: true,
              hasTextNotifier: hasText,
              mediaTask: task(UniversalMediaTaskPhase.pending),
              onSend: (_, _) async => true,
              onStop: () async => stopCount++,
            ),
          ),
        ),
      );

      expect(find.text('视频排队中…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byTooltip('停止'), findsOneWidget);
      await tester.tap(find.byTooltip('停止'));
      await tester.pump();
      expect(stopCount, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              isSubmitting: true,
              hasTextNotifier: hasText,
              mediaTask: task(UniversalMediaTaskPhase.polling),
              onSend: (_, _) async => true,
              onStop: () async => stopCount++,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('视频生成中…'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              isSubmitting: true,
              hasTextNotifier: hasText,
              mediaTask: task(UniversalMediaTaskPhase.saving),
              onSend: (_, _) async => true,
              onStop: () async => stopCount++,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('视频保存中…'), findsOneWidget);
      expect(find.byTooltip('停止'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('media retry clears only returned attachment IDs', (
    tester,
  ) async {
    final controller = TextEditingController(text: '再次生成');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    final consumed = const PendingAttachment(
      id: 'consumed-id',
      path: '/drafts/consumed.png',
      name: 'consumed.png',
      type: 'image',
    );
    final retained = const PendingAttachment(
      id: 'retained-id',
      path: '/drafts/retained.pdf',
      name: 'retained.pdf',
      type: 'pdf',
    );
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            isSubmitting: false,
            hasTextNotifier: hasText,
            sessionId: 'retry-session-one',
            initialAttachments: [consumed, retained],
            mediaTask: const UniversalMediaTaskState(
              operationId: 'operation-retry',
              kind: UniversalMediaKind.video,
              phase: UniversalMediaTaskPhase.failed,
              error: '上游失败',
            ),
            onSend: (_, _) async => true,
            onRetryMedia: () async {
              retryCount++;
              return {consumed.stableId};
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('media-task-retry-button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('media-task-retry-button')));
    await tester.pump();

    expect(retryCount, 1);
    expect(controller.text, isEmpty);
    expect(
      find.byKey(const ValueKey('pending-attachment-consumed-id')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('pending-attachment-retained-id')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller..text = '失败后保留',
            focusNode: focusNode,
            sessionId: 'retry-session-two',
            isStreaming: false,
            hasTextNotifier: hasText..value = true,
            initialAttachments: [consumed, retained],
            mediaTask: const UniversalMediaTaskState(
              operationId: 'operation-failed-again',
              kind: UniversalMediaKind.video,
              phase: UniversalMediaTaskPhase.failed,
              error: '再次失败',
            ),
            onSend: (_, _) async => true,
            onRetryMedia: () async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('media-task-retry-button')));
    await tester.pump();

    expect(controller.text, '失败后保留');
    expect(
      find.byKey(const ValueKey('pending-attachment-consumed-id')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pending-attachment-retained-id')),
      findsOneWidget,
    );
  });

  testWidgets('video action consumes only its reference image', (tester) async {
    final controller = TextEditingController(text: '参考图视频');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    final image = const PendingAttachment(
      id: 'video-reference',
      path: '/drafts/reference.png',
      name: 'reference.png',
      type: 'image',
    );
    final other = const PendingAttachment(
      id: 'video-extra',
      path: '/drafts/extra.pdf',
      name: 'extra.pdf',
      type: 'pdf',
    );
    List<PendingAttachment>? received;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            initialAttachments: [image, other],
            onSend: (_, _) async => true,
            onGenerateVideo: (text, attachments) async {
              received = attachments;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('generate-video-menu-item')));
    await tester.pump();

    expect(received, hasLength(1));
    expect(received!.single.stableId, image.stableId);
    expect(
      find.byKey(const ValueKey('pending-attachment-video-reference')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('pending-attachment-video-extra')),
      findsOneWidget,
    );
  });

  testWidgets(
    'video and music actions show explicit disabled capability reasons',
    (tester) async {
      final controller = TextEditingController(text: '测试媒体');
      final focusNode = FocusNode();
      final hasText = ValueNotifier(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              onSend: (_, _) async => true,
              onGenerateVideo: (_, _) async => true,
              onGenerateMusic: (_) async => true,
              videoActionDisabledReason: '正在检测当前模型和媒体配置…',
              musicActionDisabledReason: '请先在当前渠道配置 API Key 后再生成音乐',
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();

      final video = tester.widget<ListTile>(
        find.byKey(const ValueKey('generate-video-menu-item')),
      );
      final music = tester.widget<ListTile>(
        find.byKey(const ValueKey('generate-music-menu-item')),
      );
      expect(video.enabled, isFalse);
      expect(music.enabled, isFalse);
      expect(find.text('正在检测当前模型和媒体配置…'), findsOneWidget);
      expect(find.text('请先在当前渠道配置 API Key 后再生成音乐'), findsOneWidget);
    },
  );
}

const _onePixelPng = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0xf8,
  0xcf,
  0xc0,
  0xf0,
  0x1f,
  0x00,
  0x05,
  0x00,
  0x01,
  0xff,
  0x89,
  0x99,
  0x3d,
  0x1d,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
