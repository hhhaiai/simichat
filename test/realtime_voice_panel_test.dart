import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:ai_chat_app/shared/providers/realtime_voice_provider.dart';
import 'package:ai_chat_app/shared/widgets/realtime_voice_panel.dart';
import 'package:ai_chat_app/core/media/realtime_voice_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestRealtimeVoiceController extends RealtimeVoiceController {
  _TestRealtimeVoiceController(RealtimeVoiceState initialState) : super() {
    state = initialState;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('panel exposes connection setup and PCM capture boundary', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: RealtimeVoicePanel())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('实时语音对话'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('realtime-voice-capture-boundary')),
      findsOneWidget,
    );
    expect(find.textContaining('当前未连接 Realtime WebSocket'), findsOneWidget);
    expect(find.textContaining('非 Android 取决于对应平台支持'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('realtime-voice-configuration')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('realtime-voice-endpoint-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('realtime-voice-save-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('realtime-voice-connect-button')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('realtime-voice-connect-button')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      find.byKey(const ValueKey('realtime-voice-connect-disabled-reason')),
      findsOneWidget,
    );
  });

  testWidgets('panel remains scrollable and safe on a narrow display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: RealtimeVoicePanel())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('audio frame status follows the native PCM runtime state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = _TestRealtimeVoiceController(
      const RealtimeVoiceState(
        snapshot: RealtimeVoiceSessionSnapshot(
          state: RealtimeVoiceSessionState.connected,
          sessionId: 'ui-test-session',
        ),
        receivedAudioBytes: 320,
        nativeAudioActive: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [realtimeVoiceProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: Scaffold(body: RealtimeVoicePanel())),
      ),
    );
    await tester.pumpAndSettle();

    final activeStatus = tester.widget<Text>(
      find.textContaining('已收到 320 bytes 音频帧'),
    );
    expect(activeStatus.data, contains('已交给原生播放队列'));
    expect(activeStatus.data, isNot(contains('仍需原生音频适配')));

    controller.state = controller.state.copyWith(nativeAudioActive: false);
    await tester.pump();

    final inactiveStatus = tester.widget<Text>(
      find.textContaining('已收到 320 bytes 音频帧'),
    );
    expect(inactiveStatus.data, contains('需要开启后才能播放'));
    expect(inactiveStatus.data, isNot(contains('已交给原生播放队列')));
  });

  testWidgets('ChatGPT composer exposes realtime voice in the plus menu', (
    tester,
  ) async {
    var opened = false;
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final hasText = ValueNotifier<bool>(false);
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
      hasText.dispose();
    });

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
            onRealtimeVoice: () async => opened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('realtime-voice-menu-item')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('realtime-voice-menu-item')));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });
}
