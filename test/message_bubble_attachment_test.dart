import 'dart:io';

import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:ai_chat_app/shared/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('message bubble renders attachment chips with size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'user',
            content: '请看这张图',
            isUser: true,
            attachments: [
              MessageAttachmentView(
                fileName: 'photo.png',
                fileType: 'image',
                fileSize: 1536,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('请看这张图'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('message bubble renders local image attachments as thumbnails', (
    tester,
  ) async {
    final imageFile = (await tester.runAsync(_createLocalAttachmentFile))!;
    addTearDown(() {
      if (imageFile.existsSync()) {
        imageFile.deleteSync();
      }
      if (imageFile.parent.existsSync()) {
        imageFile.parent.deleteSync();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'user',
            content: '图片预览',
            isUser: true,
            attachments: [
              MessageAttachmentView(
                fileName: 'local-photo.png',
                fileType: 'image',
                fileSize: imageFile.lengthSync(),
                localPath: imageFile.path,
              ),
            ],
            attachmentImageBuilder: (_, _) => const ColoredBox(
              key: ValueKey('fake-thumbnail-image'),
              color: Colors.blue,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('图片预览'), findsOneWidget);
    expect(find.text('local-photo.png'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('attachment-thumbnail-local-photo.png')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fake-thumbnail-image')), findsOneWidget);
    expect(find.text(imageFile.path), findsNothing);
  });

  testWidgets('message bubble renders audio attachments with waveform icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'user',
            content: '这是一段语音',
            isUser: true,
            attachments: [
              MessageAttachmentView(
                fileName: 'voice.m4a',
                fileType: 'audio',
                fileSize: 2048,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('这是一段语音'), findsOneWidget);
    expect(find.text('voice.m4a'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_outlined), findsOneWidget);
  });

  testWidgets('message bubble renders audio transcript status', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'user',
            content: '这是一段转写失败的语音',
            isUser: true,
            attachments: [
              MessageAttachmentView(
                fileName: 'voice.m4a',
                fileType: 'audio',
                fileSize: 2048,
                audioTranscriptStatus: AudioTranscriptStatus.failed,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('转写：转写失败'), findsOneWidget);
    expect(find.text('voice.m4a'), findsOneWidget);
    expect(find.textContaining('/'), findsNothing);
  });

  testWidgets('audio attachment exposes transcript details action', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'user',
            content: '查看转写',
            isUser: true,
            attachments: [
              MessageAttachmentView(
                fileName: 'voice.m4a',
                fileType: 'audio',
                fileSize: 2048,
                audioTranscriptStatus: AudioTranscriptStatus.ready,
                onOpenAudioTranscript: () => opened++,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('查看 / 复制转写稿'), findsOneWidget);
    expect(find.textContaining('/Users/sanbo'), findsNothing);

    await tester.tap(find.text('查看 / 复制转写稿'));
    await tester.pump();

    expect(opened, 1);
  });


  testWidgets('image long press invokes edit image callback', (
    tester,
  ) async {
    final imageFile = (await tester.runAsync(_createLocalAttachmentFile))!;
    addTearDown(() {
      if (imageFile.existsSync()) imageFile.deleteSync();
      if (imageFile.parent.existsSync()) imageFile.parent.deleteSync();
    });
    var longPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'user',
            content: '图片预览',
            isUser: true,
            attachments: [
              MessageAttachmentView(
                fileName: 'editable-photo.png',
                fileType: 'image',
                fileSize: imageFile.lengthSync(),
                localPath: imageFile.path,
                onEditImage: () => longPressed = true,
              ),
            ],
            attachmentImageBuilder: (_, _) => const ColoredBox(
              key: ValueKey('fake-thumbnail-image'),
              color: Colors.blue,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('edit-image-longpress')), findsOneWidget);
    await tester.longPress(
      find.byKey(const ValueKey('attachment-thumbnail-editable-photo.png')),
    );
    await tester.pumpAndSettle();
    expect(longPressed, isTrue);
  });
}


Future<File> _createLocalAttachmentFile() async {
  final dir = await Directory.systemTemp.createTemp('simichat_image_test_');
  final file = File('${dir.path}/local-photo.png');
  await file.writeAsBytes(const [0x89, 0x50, 0x4E, 0x47]);
  return file;
}
