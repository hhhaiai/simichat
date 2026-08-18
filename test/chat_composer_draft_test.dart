import 'package:ai_chat_app/core/media/voice_recorder.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'composer restores text, attachments, and deep think per session',
    (tester) async {
      tester.view.physicalSize = const Size(800, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final hostKey = GlobalKey<_ComposerHarnessState>();
      final attachmentA = const PendingAttachment(
        id: 'draft-a',
        path: '/drafts/a/photo.png',
        name: 'photo-a.png',
        type: 'image',
        fileSize: 10,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _ComposerHarness(
              key: hostKey,
              initialSessionId: 'session-a',
              initialDraft: ChatComposerDraft(attachments: [attachmentA]),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('pending-attachment-draft-a')),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'A 的草稿');
      await tester.tap(find.byKey(const ValueKey('deep-think-button')));
      await tester.pump();
      expect(find.byTooltip('深度思考已开启'), findsOneWidget);

      final attachmentB = const PendingAttachment(
        id: 'draft-b',
        path: '/drafts/b/report.pdf',
        name: 'report.pdf',
        type: 'pdf',
        fileSize: 20,
      );
      hostKey.currentState!.setDraft(
        'session-b',
        ChatComposerDraft(
          text: 'B 的草稿',
          attachments: [attachmentB],
          deepThink: false,
        ),
      );
      hostKey.currentState!.switchSession('session-b');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('pending-attachment-draft-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pending-attachment-draft-a')),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'B 的草稿',
      );
      expect(find.byTooltip('深度思考'), findsOneWidget);

      hostKey.currentState!.switchSession('session-a');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('pending-attachment-draft-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pending-attachment-draft-b')),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'A 的草稿',
      );
      expect(find.byTooltip('深度思考已开启'), findsOneWidget);
    },
  );

  testWidgets('stop remains actionable while submitting and streaming', (
    tester,
  ) async {
    var stopCount = 0;
    var sendCount = 0;
    final controller = TextEditingController(text: '正在发送');
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
            isStreaming: true,
            isSubmitting: true,
            hasTextNotifier: hasText,
            onSend: (text, attachments) async {
              sendCount++;
              return true;
            },
            onStop: () async => stopCount++,
          ),
        ),
      ),
    );

    expect(find.byTooltip('停止'), findsOneWidget);
    await tester.tap(find.byTooltip('停止'));
    await tester.pump();

    expect(stopCount, 1);
    expect(sendCount, 0);
  });

  testWidgets(
    'voice recording is cancelled when lifecycle pauses and widget disposes',
    (tester) async {
      final recorder = _LifecycleRecorder();
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final hasText = ValueNotifier(false);
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
              onSend: (text, attachments) async => true,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('voice-record-button')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(recorder.cancelCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-record-button')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(recorder.cancelCount, 2);
    },
  );
}

class _ComposerHarness extends StatefulWidget {
  final String initialSessionId;
  final ChatComposerDraft initialDraft;

  const _ComposerHarness({
    super.key,
    required this.initialSessionId,
    required this.initialDraft,
  });

  @override
  State<_ComposerHarness> createState() => _ComposerHarnessState();
}

class _ComposerHarnessState extends State<_ComposerHarness> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final ValueNotifier<bool> _hasText;
  late final ValueNotifier<bool> _deepThink;
  late String _sessionId;
  late List<PendingAttachment> _initialAttachments;
  late final Map<String, ChatComposerDraft> _drafts;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.initialSessionId;
    _controller = TextEditingController(text: widget.initialDraft.text);
    _focusNode = FocusNode();
    _hasText = ValueNotifier(_controller.text.trim().isNotEmpty);
    _deepThink = ValueNotifier(widget.initialDraft.deepThink);
    _initialAttachments = List.of(widget.initialDraft.attachments);
    _drafts = {_sessionId: widget.initialDraft};
    _controller.addListener(_captureText);
  }

  @override
  void dispose() {
    _controller.removeListener(_captureText);
    _controller.dispose();
    _focusNode.dispose();
    _hasText.dispose();
    _deepThink.dispose();
    super.dispose();
  }

  void _captureText() {
    _hasText.value = _controller.text.trim().isNotEmpty;
    final previous = _drafts[_sessionId] ?? const ChatComposerDraft();
    _drafts[_sessionId] = previous.copyWith(
      text: _controller.text,
      deepThink: _deepThink.value,
    );
  }

  void _captureDraft(ChatComposerDraft draft) {
    _drafts[_sessionId] = ChatComposerDraft(
      text: draft.text,
      attachments: List.of(draft.attachments),
      deepThink: draft.deepThink,
    );
  }

  void setDraft(String sessionId, ChatComposerDraft draft) {
    _drafts[sessionId] = draft;
    if (_sessionId != sessionId) return;
    setState(() {
      _initialAttachments = List.of(draft.attachments);
      _controller.value = TextEditingValue(
        text: draft.text,
        selection: TextSelection.collapsed(offset: draft.text.length),
      );
      _deepThink.value = draft.deepThink;
    });
  }

  void switchSession(String sessionId) {
    _captureText();
    final draft = _drafts[sessionId] ?? const ChatComposerDraft();
    setState(() {
      _sessionId = sessionId;
      _initialAttachments = List.of(draft.attachments);
      _controller.value = TextEditingValue(
        text: draft.text,
        selection: TextSelection.collapsed(offset: draft.text.length),
      );
      _deepThink.value = draft.deepThink;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChatInputBar(
      sessionId: _sessionId,
      controller: _controller,
      focusNode: _focusNode,
      isStreaming: false,
      hasTextNotifier: _hasText,
      deepThinkNotifier: _deepThink,
      initialAttachments: _initialAttachments,
      onDraftChanged: _captureDraft,
      onSend: (text, attachments) async => true,
    );
  }
}

class _LifecycleRecorder implements VoiceRecorderPlatform {
  int cancelCount = 0;

  @override
  Future<void> startRecording() async {}

  @override
  Future<VoiceRecordingResult> stopRecording() async {
    throw const VoiceRecordingException('未提供录音结果');
  }

  @override
  Future<void> cancelRecording() async {
    cancelCount++;
  }
}
