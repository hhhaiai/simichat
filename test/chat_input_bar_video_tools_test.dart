import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first frame is not duplicated in ordinary references', () {
    const first = PendingAttachment(
      id: 'first-frame',
      path: '/tmp/first.png',
      name: 'first.png',
      type: 'image',
    );
    const second = PendingAttachment(
      id: 'reference',
      path: '/tmp/reference.png',
      name: 'reference.png',
      type: 'image',
    );

    final config = VideoGenerationConfig(
      referenceAttachments: const [first, second],
      firstFrameAttachment: first,
    );

    expect(config.referenceAttachments, const [second]);
    expect(config.firstFrameAttachment, first);
    expect(config.allAttachments, const [second, first]);
  });

  testWidgets('video task panel preserves multi-reference roles', (
    tester,
  ) async {
    final controller = TextEditingController(text: '海边日落，镜头缓慢推进');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);

    const first = PendingAttachment(
      id: 'video-image-1',
      path: '/tmp/video-image-1.png',
      name: 'first.png',
      type: 'image',
      fileSize: 10,
    );
    const second = PendingAttachment(
      id: 'video-image-2',
      path: '/tmp/video-image-2.png',
      name: 'second.png',
      type: 'image',
      fileSize: 20,
    );
    const audio = PendingAttachment(
      id: 'video-audio',
      path: '/tmp/video-audio.wav',
      name: 'reference.wav',
      type: 'audio',
      fileSize: 30,
    );
    VideoGenerationConfig? received;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            showVoiceInput: false,
            initialAttachments: const [first, second, audio],
            onSend: (_, _) async => true,
            onOpenVideoGenerationTask: (text, config) async {
              expect(text, '海边日落，镜头缓慢推进');
              received = config;
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
    expect(find.text('参考图（可多选）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('video-first-frame-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('video-reference-audio-field')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('confirm-video-generation')));
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.referenceAttachments, hasLength(2));
    expect(received!.referenceAttachments.map((item) => item.name), [
      'first.png',
      'second.png',
    ]);
    expect(received!.firstFrameAttachment, isNull);
    expect(received!.referenceAudioAttachment, isNull);
    expect(received!.aspectRatio, '16:9');
    expect(received!.allAttachments, hasLength(2));
    expect(controller.text, isEmpty);
  });

  testWidgets('plus video action uses the shared production task sheet', (
    tester,
  ) async {
    final controller = TextEditingController(text: '共享视频参数');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    const image = PendingAttachment(
      id: 'shared-video-image',
      path: '/tmp/shared-video-image.png',
      name: 'shared.png',
      type: 'image',
    );
    var configureCalls = 0;
    VideoGenerationConfig? received;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isStreaming: false,
            hasTextNotifier: hasText,
            showVoiceInput: false,
            initialAttachments: const [image],
            onSend: (_, _) async => true,
            onConfigureVideoGenerationTask: (text, attachments) async {
              configureCalls++;
              expect(text, '共享视频参数');
              expect(attachments, const [image]);
              return VideoGenerationConfig(
                referenceAttachments: const [image],
                duration: 8,
                aspectRatio: '9:16',
                resolution: '720p',
              );
            },
            onOpenVideoGenerationTask: (text, config) async {
              received = config;
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

    expect(configureCalls, 1);
    expect(
      find.byKey(const ValueKey('confirm-video-generation')),
      findsNothing,
    );
    expect(received?.duration, 8);
    expect(received?.aspectRatio, '9:16');
    expect(received?.resolution, '720p');
  });
}
