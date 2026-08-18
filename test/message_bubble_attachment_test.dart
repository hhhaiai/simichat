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

  testWidgets('message bubble renders video attachments as media cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '视频已经生成',
            isUser: false,
            attachments: [
              MessageAttachmentView(
                fileName: 'generated.mp4',
                fileType: 'video',
                fileSize: 4096,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('generated.mp4'), findsOneWidget);
    expect(find.text('4.0 KB'), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local video card stays within a narrow mobile message bubble', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final videoFile = (await tester.runAsync(_createLocalVideoAttachmentFile))!;
    addTearDown(() {
      if (videoFile.existsSync()) videoFile.deleteSync();
      if (videoFile.parent.existsSync()) videoFile.parent.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '窄屏视频',
            isUser: false,
            attachments: [
              MessageAttachmentView(
                fileName: 'small-screen.mp4',
                fileType: 'video',
                fileSize: videoFile.lengthSync(),
                localPath: videoFile.path,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final card = find.byKey(
      const ValueKey('video-attachment-small-screen.mp4'),
    );
    expect(card, findsOneWidget);
    expect(tester.getSize(card).width, lessThanOrEqualTo(280));
    expect(tester.takeException(), isNull);
  });

  testWidgets('local image card stays within an extra narrow message bubble', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final imageFile = (await tester.runAsync(_createLocalAttachmentFile))!;
    addTearDown(() {
      if (imageFile.existsSync()) imageFile.deleteSync();
      if (imageFile.parent.existsSync()) imageFile.parent.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '窄屏图片',
            isUser: false,
            attachments: [
              MessageAttachmentView(
                fileName: 'narrow-photo.png',
                fileType: 'image',
                fileSize: imageFile.lengthSync(),
                localPath: imageFile.path,
              ),
            ],
            attachmentImageBuilder: (_, _) =>
                const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();

    final card = find.byKey(
      const ValueKey('attachment-thumbnail-narrow-photo.png'),
    );
    expect(card, findsOneWidget);
    expect(tester.getSize(card).width, lessThanOrEqualTo(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('local audio card stays within an extra narrow message bubble', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audioFile = (await tester.runAsync(_createLocalAttachmentFile))!;
    addTearDown(() {
      if (audioFile.existsSync()) audioFile.deleteSync();
      if (audioFile.parent.existsSync()) audioFile.parent.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '窄屏音频',
            isUser: false,
            attachments: [
              MessageAttachmentView(
                fileName: 'narrow-audio.m4a',
                fileType: 'audio',
                fileSize: audioFile.lengthSync(),
                localPath: audioFile.path,
                onPlayAudio: _noop,
                onDownload: _noop,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final card = find.byKey(
      const ValueKey('audio-attachment-narrow-audio.m4a'),
    );
    expect(card, findsOneWidget);
    expect(tester.getSize(card).width, lessThanOrEqualTo(200));
    expect(tester.takeException(), isNull);
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

  testWidgets(
    'PDF and ordinary file cards download when their card is tapped',
    (tester) async {
      var pdfDownloads = 0;
      var documentDownloads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              role: 'user',
              content: '文件附件',
              isUser: true,
              attachments: [
                MessageAttachmentView(
                  fileName: 'report.pdf',
                  fileType: 'pdf',
                  fileSize: 2048,
                  onDownload: () => pdfDownloads++,
                ),
                MessageAttachmentView(
                  fileName: 'notes.custom',
                  fileType: 'document',
                  fileSize: 4096,
                  onDownload: () => documentDownloads++,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('report.pdf'));
      await tester.tap(find.text('notes.custom'));
      await tester.pump();

      expect(pdfDownloads, 1);
      expect(documentDownloads, 1);
    },
  );

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

  testWidgets('image long press invokes edit image callback', (tester) async {
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

  testWidgets('image preview exposes open and download actions', (
    tester,
  ) async {
    final imageFile = (await tester.runAsync(_createLocalAttachmentFile))!;
    addTearDown(() {
      if (imageFile.existsSync()) imageFile.deleteSync();
      if (imageFile.parent.existsSync()) imageFile.parent.deleteSync();
    });
    var opened = 0;
    var downloaded = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '图片结果',
            isUser: false,
            attachments: [
              MessageAttachmentView(
                fileName: 'result.png',
                fileType: 'image',
                fileSize: imageFile.lengthSync(),
                localPath: imageFile.path,
                onOpenImage: () => opened++,
                onDownload: () => downloaded++,
              ),
            ],
            attachmentImageBuilder: (_, _) => const ColoredBox(
              key: ValueKey('result-thumbnail'),
              color: Colors.green,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('attachment-thumbnail-result.png')),
    );
    await tester.pump();
    expect(opened, 1);
    await tester.tap(
      find.byKey(const ValueKey('download-attachment-result.png')),
    );
    await tester.pump();
    expect(downloaded, 1);
  });

  testWidgets('audio and video cards expose playback and download actions', (
    tester,
  ) async {
    final audioFile = (await tester.runAsync(_createLocalAttachmentFile))!;
    addTearDown(() {
      if (audioFile.existsSync()) audioFile.deleteSync();
      if (audioFile.parent.existsSync()) audioFile.parent.deleteSync();
    });
    var played = 0;
    var audioDownloaded = 0;
    var videoDownloaded = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '媒体结果',
            isUser: false,
            attachments: [
              MessageAttachmentView(
                fileName: 'music.mp3',
                fileType: 'audio',
                fileSize: audioFile.lengthSync(),
                localPath: audioFile.path,
                onPlayAudio: () => played++,
                onDownload: () => audioDownloaded++,
              ),
              MessageAttachmentView(
                fileName: 'video.mp4',
                fileType: 'video',
                fileSize: 4096,
                onDownload: () => videoDownloaded++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('play-audio-music.mp3')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('play-audio-music.mp3'))).width,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.byKey(const ValueKey('play-audio-music.mp3')));
    await tester.pump();
    expect(played, 1);
    await tester.tap(
      find.byKey(const ValueKey('download-attachment-music.mp3')),
    );
    await tester.tap(
      find.byKey(const ValueKey('download-attachment-video.mp4')),
    );
    await tester.pump();
    expect(audioDownloaded, 1);
    expect(videoDownloaded, 1);
    expect(find.text('/Users/sanbo'), findsNothing);
  });

  testWidgets('attachment action keys prefer persisted attachment ids', (
    tester,
  ) async {
    final audioFile = (await tester.runAsync(_createLocalAttachmentFile))!;
    addTearDown(() {
      if (audioFile.existsSync()) audioFile.deleteSync();
      if (audioFile.parent.existsSync()) audioFile.parent.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            role: 'assistant',
            content: '稳定附件 key',
            isUser: false,
            attachments: [
              MessageAttachmentView(
                attachmentId: 'audio-attachment-1',
                fileName: 'same-name.bin',
                fileType: 'audio',
                fileSize: audioFile.lengthSync(),
                localPath: audioFile.path,
                onPlayAudio: () {},
                onDownload: () {},
              ),
              const MessageAttachmentView(
                attachmentId: 'video-attachment-1',
                fileName: 'same-name.bin',
                fileType: 'video',
                fileSize: 1,
                onDownload: _noop,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('play-audio-audio-attachment-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('download-attachment-audio-attachment-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('download-attachment-video-attachment-1')),
      findsOneWidget,
    );
  });
}

void _noop() {}

Future<File> _createLocalAttachmentFile() async {
  final dir = await Directory.systemTemp.createTemp('simichat_image_test_');
  final file = File('${dir.path}/local-photo.png');
  await file.writeAsBytes(const [0x89, 0x50, 0x4E, 0x47]);
  return file;
}

Future<File> _createLocalVideoAttachmentFile() async {
  final dir = await Directory.systemTemp.createTemp('simichat_video_test_');
  final file = File('${dir.path}/small-screen.mp4');
  await file.writeAsBytes(const [
    0x00,
    0x00,
    0x00,
    0x18,
    0x66,
    0x74,
    0x79,
    0x70,
  ]);
  return file;
}
