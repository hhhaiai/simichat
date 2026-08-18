import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_chat_app/core/media/realtime_voice_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRealtimeVoiceSocket implements RealtimeVoiceSocket {
  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast(sync: true);
  final List<Object> sent = <Object>[];
  int? closeCode;
  String? closeReason;
  bool isClosed = false;

  @override
  Stream<Object?> get incoming => _incoming.stream;

  @override
  void add(Object message) {
    if (isClosed) throw StateError('socket closed');
    sent.add(message);
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    if (isClosed) return;
    isClosed = true;
    closeCode = code;
    closeReason = reason;
    await _incoming.close();
  }

  void push(Object message) {
    if (!isClosed) _incoming.add(message);
  }

  void fail(Object error) {
    if (!isClosed) _incoming.addError(error);
  }

  Future<void> dispose() => _incoming.close();
}

class _FakeSocketConnector {
  _FakeSocketConnector(this.socket);

  final _FakeRealtimeVoiceSocket socket;
  RealtimeVoiceSocketOptions? options;

  Future<RealtimeVoiceSocket> call(RealtimeVoiceSocketOptions next) async {
    options = next;
    return socket;
  }
}

Map<String, dynamic> _sentJson(_FakeRealtimeVoiceSocket socket, int index) {
  return (jsonDecode(socket.sent[index] as String) as Map)
      .cast<String, dynamic>();
}

RealtimeVoiceSessionConfig _config({
  RealtimeVoiceAuth? auth,
  RealtimeVoiceProvider provider = RealtimeVoiceProvider.openAi,
  RealtimeVoiceAudioTransport inputTransport = RealtimeVoiceAudioTransport.json,
}) {
  return RealtimeVoiceSessionConfig(
    endpoint: Uri.parse('wss://voice.example.test/v1/realtime'),
    provider: provider,
    model: provider == RealtimeVoiceProvider.xAi
        ? 'grok-voice-latest'
        : 'gpt-realtime',
    auth: auth ?? const RealtimeVoiceAuth.bearer('test-token'),
    instructions: 'Be concise.',
    voice: provider == RealtimeVoiceProvider.xAi ? 'eve' : 'alloy',
    inputAudio: const RealtimeVoiceAudioFormat.pcm16(sampleRate: 16000),
    outputAudio: const RealtimeVoiceAudioFormat.pcm16(sampleRate: 24000),
    inputAudioTransport: inputTransport,
    outputAudioTransport: RealtimeVoiceAudioTransport.json,
    transcriptionModel: 'transcribe-test',
    turnDetection: const RealtimeVoiceTurnDetection.serverVad(
      silenceDurationMs: 500,
    ),
  );
}

void main() {
  group('RealtimeVoiceEventParser', () {
    test('parses input transcript, output text, and base64 audio deltas', () {
      final input = RealtimeVoiceEventParser.parse(
        jsonEncode({
          'type': 'conversation.item.input_audio_transcription.delta',
          'item_id': 'item_1',
          'delta': '你好',
        }),
      );
      final output = RealtimeVoiceEventParser.parse(
        jsonEncode({
          'type': 'response.output_text.delta',
          'response_id': 'response_1',
          'delta': 'hello',
        }),
      );
      final audio = RealtimeVoiceEventParser.parse(
        jsonEncode({
          'type': 'response.output_audio.delta',
          'response_id': 'response_1',
          'delta': base64Encode(<int>[0, 1, 255]),
        }),
      );

      expect(input, isA<RealtimeVoiceTextEvent>());
      expect(
        (input! as RealtimeVoiceTextEvent).source,
        RealtimeVoiceTextSource.inputTranscript,
      );
      expect((input as RealtimeVoiceTextEvent).delta, '你好');
      expect(
        (output! as RealtimeVoiceTextEvent).source,
        RealtimeVoiceTextSource.outputText,
      );
      expect((output as RealtimeVoiceTextEvent).delta, 'hello');
      expect(audio, isA<RealtimeVoiceAudioEvent>());
      expect((audio! as RealtimeVoiceAudioEvent).bytes, <int>[0, 1, 255]);
    });

    test('marks xAI cumulative transcript updates without throwing', () {
      final event = RealtimeVoiceEventParser.parse(
        jsonEncode({
          'type': 'conversation.item.input_audio_transcription.updated',
          'item_id': 'item_xai',
          'text': 'hello world',
        }),
      );

      expect(event, isA<RealtimeVoiceTextEvent>());
      final textEvent = event! as RealtimeVoiceTextEvent;
      expect(textEvent.isCumulative, isTrue);
      expect(textEvent.text, 'hello world');
      expect(textEvent.delta, isEmpty);
    });

    test('ignores unknown and malformed events safely', () {
      expect(
        RealtimeVoiceEventParser.parse(
          jsonEncode({'type': 'future.vendor.event', 'secret': 'sk-live-key'}),
        ),
        isNull,
      );
      expect(RealtimeVoiceEventParser.parse('{not-json'), isNull);
      expect(RealtimeVoiceEventParser.parse(42), isNull);
    });

    test('redacts remote error text before exposing it as an event', () {
      final event = RealtimeVoiceEventParser.parse(
        jsonEncode({
          'type': 'error',
          'error': {
            'type': 'invalid_request_error',
            'code': 'invalid_api_key',
            'message': 'Authorization: Bearer sk-live-secret token=raw-secret',
            'param': 'api_key',
          },
        }),
      );

      expect(event, isA<RealtimeVoiceErrorEvent>());
      final error = event! as RealtimeVoiceErrorEvent;
      expect(error.message, isNot(contains('sk-live-secret')));
      expect(error.message, isNot(contains('raw-secret')));
      expect(error.message, contains('***'));
    });
  });

  group('RealtimeVoiceProtocol', () {
    test('builds xAI session fields using nested audio configuration', () {
      final config = _config(provider: RealtimeVoiceProvider.xAi);
      final event = RealtimeVoiceProtocol.sessionUpdate(config);
      final session = (event['session'] as Map).cast<String, dynamic>();
      final audio = (session['audio'] as Map).cast<String, dynamic>();
      final input = (audio['input'] as Map).cast<String, dynamic>();
      final output = (audio['output'] as Map).cast<String, dynamic>();

      expect(event['type'], 'session.update');
      expect(session['instructions'], 'Be concise.');
      expect(session['voice'], 'eve');
      expect(session['turn_detection'], {
        'type': 'server_vad',
        'silence_duration_ms': 500,
      });
      expect(input['format'], {'type': 'audio/pcm', 'rate': 16000});
      expect(input['transcription'], {'model': 'transcribe-test'});
      expect(output['format'], {'type': 'audio/pcm', 'rate': 24000});
    });

    test(
      'builds OpenAI-compatible append, commit, response, and cancel fields',
      () {
        expect(RealtimeVoiceProtocol.inputAudioAppend('AQI='), {
          'type': 'input_audio_buffer.append',
          'audio': 'AQI=',
        });
        expect(RealtimeVoiceProtocol.inputAudioCommit(), {
          'type': 'input_audio_buffer.commit',
        });
        expect(
          RealtimeVoiceProtocol.responseCreate(
            response: {
              'output_modalities': ['audio'],
            },
          ),
          {
            'type': 'response.create',
            'response': {
              'output_modalities': ['audio'],
            },
          },
        );
        expect(RealtimeVoiceProtocol.responseCancel(responseId: 'resp_1'), {
          'type': 'response.cancel',
          'response_id': 'resp_1',
        });
      },
    );

    test(
      'does not put credentials in connection option toString or config toString',
      () {
        final secret = 'sk-live-super-secret';
        final config = _config(auth: RealtimeVoiceAuth.bearer(secret));
        final connector = _FakeSocketConnector(_FakeRealtimeVoiceSocket());
        final session = RealtimeVoiceSession(config, connector: connector.call);

        addTearDown(() async {
          await session.close();
          await connector.socket.dispose();
        });

        expect(config.toString(), isNot(contains(secret)));
        expect(session.snapshot.toString(), isNot(contains(secret)));
      },
    );

    test(
      'keeps custom WebSocket fields while preserving provider defaults',
      () {
        final config = RealtimeVoiceSessionConfig(
          endpoint: Uri.parse('wss://custom.example.test/realtime'),
          provider: RealtimeVoiceProvider.custom,
          model: 'custom-model',
          auth: const RealtimeVoiceAuth.bearer('custom-token'),
          inputAudio: const RealtimeVoiceAudioFormat.pcm16(sampleRate: 16000),
          additionalSessionFields: {
            'vendor_options': {'barge_in': true},
            'audio': {
              'input': {'vendor_codec': 'pcm16-custom'},
            },
          },
        );

        final event = RealtimeVoiceProtocol.sessionUpdate(config);
        final session = (event['session'] as Map).cast<String, dynamic>();
        final audio = (session['audio'] as Map).cast<String, dynamic>();
        final input = (audio['input'] as Map).cast<String, dynamic>();

        expect(session['vendor_options'], {'barge_in': true});
        expect(input['format'], {'type': 'audio/pcm', 'rate': 16000});
        expect(input['vendor_codec'], 'pcm16-custom');
      },
    );
  });

  group('RealtimeVoiceSession', () {
    test(
      'connects, sends session update and streams parsed response events',
      () async {
        final socket = _FakeRealtimeVoiceSocket();
        final connector = _FakeSocketConnector(socket);
        final session = RealtimeVoiceSession(
          _config(),
          connector: connector.call,
        );
        addTearDown(() async {
          await session.close();
          await socket.dispose();
        });

        final events = <RealtimeVoiceEvent>[];
        final subscription = session.events.listen(events.add);
        addTearDown(subscription.cancel);

        await session.connect();
        expect(session.snapshot.state, RealtimeVoiceSessionState.connected);
        expect(_sentJson(socket, 0)['type'], 'session.update');
        expect(
          connector.options!.headers['Authorization'],
          'Bearer test-token',
        );

        socket.push(
          jsonEncode({
            'type': 'session.created',
            'session': {'id': 'sess_1'},
          }),
        );
        socket.push(
          jsonEncode({
            'type': 'response.created',
            'response': {'id': 'resp_1'},
          }),
        );
        socket.push(
          jsonEncode({
            'type': 'conversation.item.input_audio_transcription.delta',
            'item_id': 'item_1',
            'delta': 'hi',
          }),
        );
        socket.push(
          jsonEncode({
            'type': 'response.output_text.delta',
            'response_id': 'resp_1',
            'delta': 'hello',
          }),
        );
        socket.push(
          jsonEncode({
            'type': 'response.output_audio.delta',
            'response_id': 'resp_1',
            'delta': base64Encode(<int>[1, 2]),
          }),
        );
        socket.push(
          jsonEncode({
            'type': 'response.done',
            'response': {'id': 'resp_1', 'status': 'completed'},
          }),
        );
        await Future<void>.delayed(Duration.zero);

        expect(session.snapshot.sessionId, 'sess_1');
        expect(session.snapshot.activeResponseId, isNull);
        expect(events.whereType<RealtimeVoiceTextEvent>(), hasLength(2));
        expect(events.whereType<RealtimeVoiceAudioEvent>(), hasLength(1));
        expect(
          events.whereType<RealtimeVoiceResponseEvent>().map(
            (event) => event.phase,
          ),
          [RealtimeVoiceResponsePhase.started, RealtimeVoiceResponsePhase.done],
        );
      },
    );

    test(
      'normalizes cumulative xAI transcript updates to appendable deltas',
      () async {
        final socket = _FakeRealtimeVoiceSocket();
        final session = RealtimeVoiceSession(
          _config(provider: RealtimeVoiceProvider.xAi),
          connector: _FakeSocketConnector(socket).call,
        );
        addTearDown(() async {
          await session.close();
          await socket.dispose();
        });

        final textEvents = <RealtimeVoiceTextEvent>[];
        final subscription = session.events
            .where((event) => event is RealtimeVoiceTextEvent)
            .cast<RealtimeVoiceTextEvent>()
            .listen(textEvents.add);
        addTearDown(subscription.cancel);

        await session.connect();
        socket.push(
          jsonEncode({
            'type': 'conversation.item.input_audio_transcription.updated',
            'item_id': 'item_xai',
            'text': 'hello',
          }),
        );
        socket.push(
          jsonEncode({
            'type': 'conversation.item.input_audio_transcription.updated',
            'item_id': 'item_xai',
            'text': 'hello world',
          }),
        );
        await Future<void>.delayed(Duration.zero);

        expect(textEvents.map((event) => event.delta), ['hello', ' world']);
        expect(textEvents.last.text, 'hello world');
      },
    );

    test(
      'sends PCM/base64, commit, response.create, and response.cancel',
      () async {
        final socket = _FakeRealtimeVoiceSocket();
        final session = RealtimeVoiceSession(
          _config(),
          connector: _FakeSocketConnector(socket).call,
        );
        addTearDown(() async {
          await session.close();
          await socket.dispose();
        });

        await session.connect();
        await session.sendPcm(Uint8List.fromList(<int>[0, 1, 2]));
        await session.commitInputAudio();
        await session.createResponse();
        await session.cancelResponse(responseId: 'resp_1');

        expect(_sentJson(socket, 1), {
          'type': 'input_audio_buffer.append',
          'audio': 'AAEC',
        });
        expect(_sentJson(socket, 2), {'type': 'input_audio_buffer.commit'});
        expect(_sentJson(socket, 3), {'type': 'response.create'});
        expect(_sentJson(socket, 4), {
          'type': 'response.cancel',
          'response_id': 'resp_1',
        });
      },
    );

    test(
      'uses binary frames only when the input transport requests it',
      () async {
        final socket = _FakeRealtimeVoiceSocket();
        final session = RealtimeVoiceSession(
          _config(inputTransport: RealtimeVoiceAudioTransport.binary),
          connector: _FakeSocketConnector(socket).call,
        );
        addTearDown(() async {
          await session.close();
          await socket.dispose();
        });

        await session.connect();
        await session.sendPcm(<int>[0, 1, 2]);

        expect(socket.sent[1], <int>[0, 1, 2]);
        expect(socket.sent[1], isA<Uint8List>());
      },
    );

    test(
      'uses the xAI ephemeral subprotocol without retaining it in state',
      () async {
        final socket = _FakeRealtimeVoiceSocket();
        final connector = _FakeSocketConnector(socket);
        final session = RealtimeVoiceSession(
          _config(
            provider: RealtimeVoiceProvider.xAi,
            auth: const RealtimeVoiceAuth.ephemeral('ephemeral-secret'),
          ),
          connector: connector.call,
        );
        addTearDown(() async {
          await session.close();
          await socket.dispose();
        });

        await session.connect();
        expect(connector.options!.headers, isNot(contains('Authorization')));
        expect(
          connector.options!.protocols,
          contains('xai-client-secret.ephemeral-secret'),
        );
        expect(
          session.snapshot.toString(),
          isNot(contains('ephemeral-secret')),
        );
      },
    );

    test('closes the socket when the transport reports an error', () async {
      final socket = _FakeRealtimeVoiceSocket();
      final session = RealtimeVoiceSession(
        _config(),
        connector: _FakeSocketConnector(socket).call,
      );
      addTearDown(() async {
        await session.close();
        await socket.dispose();
      });

      await session.connect();
      socket.fail(StateError('loopback transport failed'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(session.snapshot.state, RealtimeVoiceSessionState.failed);
      expect(socket.isClosed, isTrue);
    });

    test(
      'CancelToken cancellation cancels an active response and closes session',
      () async {
        final socket = _FakeRealtimeVoiceSocket();
        final session = RealtimeVoiceSession(
          _config(),
          connector: _FakeSocketConnector(socket).call,
        );
        addTearDown(() async {
          await session.close();
          await socket.dispose();
        });

        await session.connect();
        socket.push(
          jsonEncode({
            'type': 'response.created',
            'response': {'id': 'resp_1'},
          }),
        );
        await Future<void>.delayed(Duration.zero);

        final token = CancelToken();
        // Bind the cancellation observer on an already connected session.
        await session.bindCancelToken(token);
        token.cancel('Bearer sk-secret');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(session.snapshot.state, RealtimeVoiceSessionState.cancelled);
        expect(socket.isClosed, isTrue);
        expect(
          socket.sent.map((item) => item is String ? item : '').join(),
          isNot(contains('sk-secret')),
        );
      },
    );

    test(
      'close is idempotent and rejects sends after terminal state',
      () async {
        final socket = _FakeRealtimeVoiceSocket();
        final session = RealtimeVoiceSession(
          _config(),
          connector: _FakeSocketConnector(socket).call,
        );
        await session.connect();

        await session.close(code: 1000, reason: 'ui close');
        await session.close(code: 1000, reason: 'second close');

        expect(session.snapshot.state, RealtimeVoiceSessionState.closed);
        expect(socket.closeCode, 1000);
        expect(socket.closeReason, 'ui close');
        await expectLater(
          session.sendAudioBase64('AQI='),
          throwsA(isA<RealtimeVoiceSessionException>()),
        );
        await socket.dispose();
      },
    );
  });
}
