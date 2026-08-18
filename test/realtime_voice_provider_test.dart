import 'dart:async';
import 'dart:convert';

import 'package:ai_chat_app/core/media/realtime_voice_session.dart';
import 'package:ai_chat_app/shared/providers/realtime_voice_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRealtimeVoiceSocket implements RealtimeVoiceSocket {
  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast(sync: true);
  final List<Object> sent = <Object>[];
  bool isClosed = false;

  @override
  Stream<Object?> get incoming => _incoming.stream;

  @override
  void add(Object message) => sent.add(message);

  void emit(Object message) {
    if (!isClosed) _incoming.add(message);
  }

  void fail(Object error) {
    if (!isClosed) _incoming.addError(error);
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    if (isClosed) return;
    isClosed = true;
    await _incoming.close();
  }

  Future<void> dispose() => _incoming.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('xAI session configuration enables the documented transcript model', () {
    final config = const RealtimeVoiceConfig(
      provider: RealtimeVoiceProvider.xAi,
      endpoint: 'wss://api.x.ai/v1/realtime',
      model: 'grok-voice-latest',
      voice: 'eve',
      token: 'xai-realtime-token',
    );

    final session = config.toSessionConfig();
    final event = RealtimeVoiceProtocol.sessionUpdate(session);
    final sessionFields = (event['session'] as Map).cast<String, dynamic>();
    final audio = (sessionFields['audio'] as Map).cast<String, dynamic>();
    final input = (audio['input'] as Map).cast<String, dynamic>();

    expect(input['transcription'], {
      'model': 'grok-transcribe',
      'language_hint': 'auto',
    });
  });

  test('does not expose a credential embedded in a realtime endpoint', () {
    const config = RealtimeVoiceConfig(
      endpoint: 'wss://example.test/v1/realtime?token=raw-secret',
      model: 'realtime-test-model',
      token: 'header-secret',
    );

    expect(config.toString(), isNot(contains('raw-secret')));
    expect(config.toString(), isNot(contains('header-secret')));
  });

  test(
    'reconnect closes a failed transport before creating the next session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final sockets = <_FakeRealtimeVoiceSocket>[];
      final controller = RealtimeVoiceController(
        connector: (_) async {
          final socket = _FakeRealtimeVoiceSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.saveConfig(
        const RealtimeVoiceConfig(
          endpoint: 'wss://example.test/v1/realtime',
          model: 'realtime-test-model',
          voice: 'alloy',
          token: 'realtime-token',
        ),
      );

      await controller.connect();
      sockets.single.fail(StateError('loopback transport failed'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.sessionState, RealtimeVoiceSessionState.failed);
      expect(sockets.single.isClosed, isTrue);

      await controller.connect();
      expect(sockets, hasLength(2));
      expect(controller.state.isConnected, isTrue);

      await controller.disconnect();
      await Future.wait(sockets.map((socket) => socket.dispose()));
    },
  );

  test(
    'persists realtime configuration encrypted and mirrors session events',
    () async {
      SharedPreferences.setMockInitialValues({});
      final socket = _FakeRealtimeVoiceSocket();
      final controller = RealtimeVoiceController(
        connector: (_) async => socket,
      );
      addTearDown(controller.dispose);
      await controller.ready;

      expect(controller.state.config.isConfigured, isFalse);
      final configured = controller.state.config.copyWith(
        endpoint: 'wss://example.test/v1/realtime',
        model: 'realtime-test-model',
        voice: 'alloy',
        token: 'realtime-secret-token',
      );
      await controller.saveConfig(configured);

      final prefs = await SharedPreferences.getInstance();
      final encrypted = prefs.getString(kRealtimeVoiceTokenStorageKey);
      expect(encrypted, isNotNull);
      expect(encrypted, isNot(contains('realtime-secret-token')));
      expect(controller.state.config.hasToken, isTrue);

      await controller.connect();
      expect(controller.state.isConnected, isTrue);
      expect(socket.sent, isNotEmpty);
      expect(jsonDecode(socket.sent.first as String)['type'], 'session.update');

      socket.emit(
        jsonEncode({
          'type': 'session.created',
          'session': {'id': 'session_1'},
        }),
      );
      socket.emit(
        jsonEncode({'type': 'response.output_text.delta', 'delta': '你好'}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.snapshot.sessionId, 'session_1');
      expect(controller.state.outputText, '你好');

      await controller.sendText('继续');
      expect(
        socket.sent
            .whereType<String>()
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .any((event) => event['type'] == 'conversation.item.create'),
        isTrue,
      );

      await controller.disconnect();
      expect(controller.state.sessionState, RealtimeVoiceSessionState.closed);

      final restored = RealtimeVoiceController();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.state.config.hasToken, isTrue);
      expect(restored.state.config.endpoint, 'wss://example.test/v1/realtime');
    },
  );
}
