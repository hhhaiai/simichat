import 'dart:io';

import 'package:ai_chat_app/core/media/voice_recorder.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat input voice button records and sends audio attachment', (
    tester,
  ) async {
    final audioFile = _createAudioFile();
    addTearDown(() {
      if (audioFile.existsSync()) audioFile.deleteSync();
      final parent = audioFile.parent;
      if (parent.existsSync()) parent.deleteSync();
    });
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final hasText = ValueNotifier(false);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    final recorder = _FakeVoiceRecorder(
      VoiceRecordingResult(
        path: audioFile.path,
        fileName: 'voice.m4a',
        mimeType: 'audio/mp4',
        fileSize: audioFile.lengthSync(),
        durationMs: 1200,
      ),
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
            showVoiceInput: true,
            voiceRecorder: recorder,
            onSend: (text, attachments) async {
              sentAttachments = attachments;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('voice-record-button')));
    await tester.pump();
    expect(recorder.started, isTrue);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-record-button')));
    await tester.pump();
    expect(recorder.stopped, isTrue);
    expect(find.text('voice.m4a'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_outlined), findsOneWidget);

    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    expect(sentAttachments, hasLength(1));
    expect(sentAttachments!.single.type, 'audio');
    expect(sentAttachments!.single.path, audioFile.path);
    expect(sentAttachments!.single.name, 'voice.m4a');
    expect(find.text('voice.m4a'), findsNothing);
  });

  testWidgets('chat input blocks send while voice recording is active', (
    tester,
  ) async {
    final recorder = _FakeVoiceRecorder(null);
    var sendCount = 0;
    final controller = TextEditingController(text: '语音备注');
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
            showVoiceInput: true,
            voiceRecorder: recorder,
            onSend: (text, attachments) async {
              sendCount += 1;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('voice-record-button')));
    await tester.pump();

    final sendButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '发送',
      ),
    );
    expect(sendButton.onPressed, isNull);
    expect(sendCount, 0);
  });
}

File _createAudioFile() {
  final dir = Directory.systemTemp.createTempSync('simichat_voice_test_');
  final file = File('${dir.path}/voice.m4a');
  file.writeAsBytesSync(List<int>.filled(128, 1));
  return file;
}

class _FakeVoiceRecorder implements VoiceRecorderPlatform {
  _FakeVoiceRecorder(this.result);

  final VoiceRecordingResult? result;
  bool started = false;
  bool stopped = false;

  @override
  Future<void> startRecording() async {
    started = true;
  }

  @override
  Future<VoiceRecordingResult> stopRecording() async {
    stopped = true;
    final value = result;
    if (value == null) {
      throw const VoiceRecordingException('没有录音结果');
    }
    return value;
  }

  @override
  Future<void> cancelRecording() async {}
}
