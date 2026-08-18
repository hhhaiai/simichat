import 'package:ai_chat_app/shared/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('assistant message exposes text-to-speech action', (
    tester,
  ) async {
    var speaks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '你好，我是 SimiChat。',
            isUser: false,
            onSpeak: () => speaks++,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    final speakButton = find.ancestor(
      of: find.byIcon(Icons.volume_up_outlined),
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(speakButton).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(speakButton).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pump();

    expect(speaks, 1);
  });

  testWidgets('user message does not expose text-to-speech action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'user',
            content: '用户消息不显示播报按钮',
            isUser: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });

  testWidgets('empty assistant message hides text-to-speech action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '   ',
            isUser: false,
            onSpeak: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });

  testWidgets(
    'empty assistant content does not create a blank markdown block',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              role: 'assistant',
              content: '',
              isUser: false,
              attachments: [
                MessageAttachmentView(
                  fileName: 'answer.pdf',
                  fileType: 'pdf',
                  fileSize: 512,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('answer.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('speaking assistant message exposes stop action', (tester) async {
    var stops = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '正在播报的回复',
            isUser: false,
            onSpeak: () {},
            onStopSpeaking: () => stops++,
            isSpeaking: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pump();

    expect(stops, 1);
  });

  testWidgets('preparing assistant message shows disabled generating action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '正在生成播报',
            isUser: false,
            onSpeak: () {},
            onStopSpeaking: () {},
            isSpeaking: true,
            isPreparingSpeech: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.hourglass_top_outlined), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });
}
