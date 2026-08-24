import 'dart:async';

import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('completed TTS keeps text typed for the next request', (
    tester,
  ) async {
    final controller = TextEditingController(text: '当前合成内容');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    final completed = Completer<bool>();
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
            showVoiceInput: false,
            onSend: (_, _) async => true,
            onOpenSpeechSynthesisTask: (_) => completed.future,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('synthesize-speech-menu-item')));
    await tester.pump();

    controller.text = '下一条草稿不能被旧任务清除';
    hasText.value = true;
    await tester.pump();
    completed.complete(true);
    await tester.pumpAndSettle();

    expect(controller.text, '下一条草稿不能被旧任务清除');
    expect(hasText.value, isTrue);
  });

  testWidgets('successful audio chat send removes the voice draft chip', (
    tester,
  ) async {
    final controller = TextEditingController(text: '请结合语音回答');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    const audio = PendingAttachment(
      id: 'joint-audio',
      path: '/drafts/joint-audio.m4a',
      name: 'joint-audio.m4a',
      type: 'audio',
      fileSize: 128,
    );
    List<PendingAttachment>? sentAttachments;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            showVoiceInput: false,
            initialAttachments: const [audio],
            onSend: (text, attachments) async {
              sentAttachments = attachments;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('pending-attachment-joint-audio')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(sentAttachments, hasLength(1));
    expect(
      find.byKey(const ValueKey('pending-attachment-joint-audio')),
      findsNothing,
    );
  });

  testWidgets(
    'multimodal main send removes only attachment IDs reported by the task',
    (tester) async {
      final controller = TextEditingController(text: '请生成语音');
      final focusNode = FocusNode();
      final hasText = ValueNotifier(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);
      const reference = PendingAttachment(
        id: 'reported-reference',
        path: '/drafts/reference.wav',
        name: 'reference.wav',
        type: 'audio',
      );
      const nextDraft = PendingAttachment(
        id: 'unrelated-next-draft',
        path: '/drafts/next.pdf',
        name: 'next.pdf',
        type: 'pdf',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              showVoiceInput: false,
              initialAttachments: const [reference, nextDraft],
              onSend: (_, _) async => false,
              onSendWithOutcome: (_, _) async =>
                  const ComposerSendOutcome.success(
                    consumedAttachmentIds: {'reported-reference'},
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(
        find.byKey(const ValueKey('pending-attachment-reported-reference')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pending-attachment-unrelated-next-draft')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'voice tools expose synthesis, clone, and design callbacks from the plus menu',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TextEditingController(text: '请朗读这段文字');
      final focusNode = FocusNode();
      final hasText = ValueNotifier(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);

      const referenceAudio = PendingAttachment(
        id: 'voice-reference',
        path: '/drafts/voice-reference.wav',
        name: 'voice-reference.wav',
        type: 'audio',
        fileSize: 1024,
      );
      String? synthesizedText;
      String? designedText;
      List<PendingAttachment>? clonedReferences;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              showVoiceInput: false,
              initialAttachments: const [referenceAudio],
              onSend: (_, _) async => true,
              onSynthesizeSpeech: (text) async {
                synthesizedText = text;
                return true;
              },
              onCloneVoice: (text, references) async {
                clonedReferences = references;
                return text == '用参考音频克隆';
              },
              onDesignVoice: (text) async {
                designedText = text;
                return true;
              },
            ),
          ),
        ),
      );

      Future<void> openMenu() async {
        await tester.tap(find.byTooltip('添加附件'));
        await tester.pumpAndSettle();
      }

      Future<void> tapMenuItem(Key key) async {
        final finder = find.byKey(key);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await openMenu();
      expect(
        find.byKey(const ValueKey('synthesize-speech-menu-item')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('clone-voice-menu-item')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('design-voice-menu-item')),
        findsOneWidget,
      );
      expect(find.text('将当前文字转换为语音'), findsOneWidget);
      expect(find.text('使用当前参考音频生成克隆语音'), findsOneWidget);
      expect(find.text('用文字描述生成声音'), findsOneWidget);

      await tapMenuItem(const ValueKey('synthesize-speech-menu-item'));
      expect(synthesizedText, '请朗读这段文字');
      expect(controller.text, isEmpty);
      expect(
        find.byKey(const ValueKey('pending-attachment-voice-reference')),
        findsOneWidget,
      );

      controller.text = '用参考音频克隆';
      await tester.pump();
      await openMenu();
      await tapMenuItem(const ValueKey('clone-voice-menu-item'));
      expect(clonedReferences, hasLength(1));
      expect(clonedReferences!.single.name, 'voice-reference.wav');
      expect(controller.text, isEmpty);
      expect(
        find.byKey(const ValueKey('pending-attachment-voice-reference')),
        findsNothing,
      );

      controller.text = '年轻、清晰、带一点气声的女声';
      await tester.pump();
      await openMenu();
      await tapMenuItem(const ValueKey('design-voice-menu-item'));
      expect(designedText, '年轻、清晰、带一点气声的女声');
      expect(controller.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('synthesis task callback takes precedence over legacy callback', (
    tester,
  ) async {
    final controller = TextEditingController(text: '面板合成内容');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    var panelCalls = 0;
    var legacyCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            showVoiceInput: false,
            onSend: (_, _) async => true,
            onOpenSpeechSynthesisTask: (text) async {
              panelCalls++;
              expect(text, '面板合成内容');
              return true;
            },
            onSynthesizeSpeech: (_) async {
              legacyCalls++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('synthesize-speech-menu-item')));
    await tester.pumpAndSettle();
    expect(panelCalls, 1);
    expect(legacyCalls, 0);
    expect(controller.text, isEmpty);
  });

  testWidgets('design and clone task callbacks take precedence', (
    tester,
  ) async {
    final controller = TextEditingController(text: '任务语音');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    const reference = PendingAttachment(
      id: 'task-reference',
      path: '/tmp/task-reference.wav',
      name: 'task-reference.wav',
      type: 'audio',
      fileSize: 10,
    );
    var designPanelCalls = 0;
    var clonePanelCalls = 0;
    var designLegacyCalls = 0;
    var cloneLegacyCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            showVoiceInput: false,
            initialAttachments: const [reference],
            onSend: (_, _) async => true,
            onOpenVoiceDesignTask: (_) async {
              designPanelCalls++;
              return true;
            },
            onDesignVoice: (_) async {
              designLegacyCalls++;
              return true;
            },
            onOpenVoiceCloneTask: (_, references) async {
              clonePanelCalls++;
              expect(references.single.name, 'task-reference.wav');
              return true;
            },
            onCloneVoice: (_, _) async {
              cloneLegacyCalls++;
              return true;
            },
          ),
        ),
      ),
    );
    Future<void> openMenu() async {
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
    }

    await openMenu();
    await tester.tap(find.byKey(const ValueKey('design-voice-menu-item')));
    await tester.pumpAndSettle();
    expect(designPanelCalls, 1);
    expect(designLegacyCalls, 0);

    controller.text = '克隆任务';
    hasText.value = true;
    await tester.pump();
    await openMenu();
    await tester.tap(find.byKey(const ValueKey('clone-voice-menu-item')));
    await tester.pumpAndSettle();
    expect(clonePanelCalls, 1);
    expect(cloneLegacyCalls, 0);
  });

  testWidgets('speech recognition task exposes selected audio attachments', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final hasText = ValueNotifier(false);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    const audio = PendingAttachment(
      id: 'asr-audio',
      path: '/tmp/asr.wav',
      name: 'asr.wav',
      type: 'audio',
      fileSize: 42,
    );
    List<PendingAttachment>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            showVoiceInput: false,
            initialAttachments: const [audio],
            onSend: (_, _) async => true,
            onOpenSpeechRecognitionTask: (attachments) async {
              selected = attachments;
              return <String>{attachments.single.stableId};
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('recognize-speech-menu-item')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('recognize-speech-menu-item')));
    await tester.pumpAndSettle();
    expect(selected, hasLength(1));
    expect(selected!.single.name, 'asr.wav');
    expect(
      find.byKey(ValueKey('pending-attachment-${audio.stableId}')),
      findsNothing,
    );
  });

  testWidgets(
    'voice clone stays disabled until a reference audio is attached',
    (tester) async {
      final controller = TextEditingController(text: '克隆这段声音');
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
              showVoiceInput: false,
              onSend: (_, _) async => true,
              onCloneVoice: (_, _) async => true,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      final cloneTile = tester.widget<ListTile>(
        find.byKey(const ValueKey('clone-voice-menu-item')),
      );
      expect(cloneTile.enabled, isFalse);
      expect(cloneTile.onTap, isNull);
      expect(find.text('先通过“选择文件”附加参考音频'), findsOneWidget);
    },
  );

  testWidgets(
    'voice action disabled reasons remain visible and block callbacks',
    (tester) async {
      final controller = TextEditingController(text: '声音提示词');
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
              showVoiceInput: false,
              onSend: (_, _) async => true,
              onSynthesizeSpeech: (_) async => true,
              onCloneVoice: (_, _) async => true,
              onDesignVoice: (_) async => true,
              speechActionDisabledReason: '当前渠道未配置 TTS',
              cloneVoiceActionDisabledReason: '当前渠道未接入声音克隆',
              designVoiceActionDisabledReason: '当前渠道未接入声音设计',
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();

      for (final key in const [
        ValueKey('synthesize-speech-menu-item'),
        ValueKey('clone-voice-menu-item'),
        ValueKey('design-voice-menu-item'),
      ]) {
        expect(tester.widget<ListTile>(find.byKey(key)).enabled, isFalse);
      }
      expect(find.text('当前渠道未配置 TTS'), findsOneWidget);
      expect(find.text('当前渠道未接入声音克隆'), findsOneWidget);
      expect(find.text('当前渠道未接入声音设计'), findsOneWidget);
    },
  );

  testWidgets(
    'configured clone reference can be supplied by the parent without a draft audio attachment',
    (tester) async {
      final controller = TextEditingController(text: '使用已配置音色');
      final focusNode = FocusNode();
      final hasText = ValueNotifier(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);
      List<PendingAttachment>? references;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              showVoiceInput: false,
              onSend: (_, _) async => true,
              onCloneVoice: (_, value) async {
                references = value;
                return true;
              },
              useConfiguredVoiceCloneReferenceAudio: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      final cloneTile = tester.widget<ListTile>(
        find.byKey(const ValueKey('clone-voice-menu-item')),
      );
      expect(cloneTile.enabled, isTrue);
      expect(find.text('使用设置中已配置的参考音频生成语音'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('clone-voice-menu-item')));
      await tester.pumpAndSettle();
      expect(references, isEmpty);
      expect(controller.text, isEmpty);
    },
  );

  testWidgets('an attached clone reference wins over the configured fallback', (
    tester,
  ) async {
    final controller = TextEditingController(text: '优先使用这条参考音频');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    const attached = PendingAttachment(
      id: 'attached-clone-reference',
      path: '/drafts/attached-clone-reference.wav',
      name: 'attached-clone-reference.wav',
      type: 'audio',
      fileSize: 128,
    );
    List<PendingAttachment>? references;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            showVoiceInput: false,
            initialAttachments: const [attached],
            onSend: (_, _) async => true,
            onCloneVoice: (_, value) async {
              references = value;
              return true;
            },
            useConfiguredVoiceCloneReferenceAudio: true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    expect(find.text('使用当前参考音频生成克隆语音'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clone-voice-menu-item')));
    await tester.pumpAndSettle();

    expect(references, hasLength(1));
    expect(references!.single.stableId, attached.stableId);
    expect(controller.text, isEmpty);
    expect(
      find.byKey(const ValueKey('pending-attachment-attached-clone-reference')),
      findsNothing,
    );
  });
}
