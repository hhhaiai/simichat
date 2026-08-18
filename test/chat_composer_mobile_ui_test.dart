import 'package:ai_chat_app/core/ai/universal_media_service.dart';
import 'package:ai_chat_app/shared/providers/universal_media_provider.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'mobile composer keeps its primary controls usable with keyboard inset',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      final controller = TextEditingController(
        text: List<String>.filled(18, '一行较长的移动端输入').join('\n'),
      );
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
              showVoiceInput: true,
              initialAttachments: const [
                PendingAttachment(
                  id: 'keyboard-attachment',
                  path: '/drafts/report.pdf',
                  name: 'report.pdf',
                  type: 'pdf',
                  fileSize: 1024,
                ),
              ],
              mediaTask: const UniversalMediaTaskState(
                operationId: 'keyboard-operation',
                kind: UniversalMediaKind.video,
                phase: UniversalMediaTaskPhase.pending,
              ),
              onSend: (_, _) async => true,
              onStop: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      final composerField = tester.widget<TextField>(find.byType(TextField));
      expect(composerField.maxLines, isNull);
      expect(composerField.keyboardType, TextInputType.multiline);
      expect(composerField.textInputAction, TextInputAction.newline);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('添加附件')).width,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('voice-record-button'))).width,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.byTooltip('停止')).width,
        greaterThanOrEqualTo(44),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'composer shows a bounded card for every supported attachment kind',
    (tester) async {
      tester.view.physicalSize = const Size(240, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TextEditingController();
      final focusNode = FocusNode();
      final hasText = ValueNotifier<bool>(false);
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
              initialAttachments: const [
                PendingAttachment(
                  id: 'image',
                  path: '/drafts/image.png',
                  name: 'image.png',
                  type: 'image',
                  fileSize: 1024,
                ),
                PendingAttachment(
                  id: 'video',
                  path: '/drafts/video.mp4',
                  name: 'video.mp4',
                  type: 'video',
                  fileSize: 2048,
                ),
                PendingAttachment(
                  id: 'audio',
                  path: '/drafts/audio.m4a',
                  name: 'audio.m4a',
                  type: 'audio',
                  fileSize: 3072,
                ),
                PendingAttachment(
                  id: 'pdf',
                  path: '/drafts/report.pdf',
                  name: 'report.pdf',
                  type: 'pdf',
                  fileSize: 4096,
                ),
                PendingAttachment(
                  id: 'document',
                  path: '/drafts/notes.custom',
                  name: 'notes.custom',
                  type: 'document',
                  fileSize: 5120,
                ),
              ],
              onSend: (_, _) async => true,
            ),
          ),
        ),
      );
      await tester.pump();

      final attachmentScroll = find.ancestor(
        of: find.byKey(const ValueKey('composer-pending-attachments-scroll')),
        matching: find.byType(Scrollable),
      );
      for (final name in const [
        'image.png',
        'video.mp4',
        'audio.m4a',
        'report.pdf',
        'notes.custom',
      ]) {
        await tester.scrollUntilVisible(
          find.text(name),
          220,
          scrollable: attachmentScroll,
        );
        expect(find.text(name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('plus menu groups actions and remains vertically scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController(text: '工具提示');
    final focusNode = FocusNode();
    final hasText = ValueNotifier<bool>(true);
    final deepThink = ValueNotifier<bool>(false);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    addTearDown(deepThink.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            deepThinkNotifier: deepThink,
            showVoiceInput: false,
            onSend: (_, _) async => true,
            onRealtimeVoice: () async {},
            onEditImage: (_) async => true,
            onGenerateImage: (_) async => true,
            onGenerateVideo: (_, _) async => true,
            onSynthesizeSpeech: (_) async => true,
            onCloneVoice: (_, _) async => true,
            onDesignVoice: (_) async => true,
            onGenerateMusic: (_) async => true,
            onPersonaReply: () async => true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();

    expect(find.text('添加内容'), findsOneWidget);
    expect(find.text('语音与编辑'), findsOneWidget);
    expect(find.text('生成与工具'), findsOneWidget);
    expect(find.text('个性化'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-attachment-menu-scroll')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('composer-attachment-menu-scroll')),
          )
          .scrollDirection,
      Axis.vertical,
    );
    expect(tester.takeException(), isNull);
  });
}
