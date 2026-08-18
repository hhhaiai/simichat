import 'dart:io';
import 'dart:async';

import 'package:ai_chat_app/core/media/audio_player.dart';
import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextToSpeechService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_tts_service_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes synthesized mp3 into temp directory and plays it', () async {
      final engine = _FakeTextToSpeechEngine([0x49, 0x44, 0x33]);
      final player = _FakeAudioPlayer();
      final service = TextToSpeechService(
        engine: engine,
        player: player,
        outputDirectory: () async => tempDir,
        now: () => DateTime.fromMillisecondsSinceEpoch(1234),
      );

      final result = await service.speak(
        text: '  hello   SimiChat ',
        voice: 'alloy',
      );

      expect(engine.lastInput?.text, 'hello SimiChat');
      expect(engine.lastInput?.voice, 'alloy');
      expect(result.fileSize, 3);
      expect(result.audioFile.path, contains('tts_audio'));
      expect(result.audioFile.path, contains('simichat-tts-1234.mp3'));
      expect(await result.audioFile.readAsBytes(), [0x49, 0x44, 0x33]);
      expect(player.playedPath, result.audioFile.path);
    });

    test('uses configured audio extension for non-mp3 output', () async {
      final player = _FakeAudioPlayer();
      final service = TextToSpeechService(
        engine: _FakeTextToSpeechEngine([0x52, 0x49, 0x46, 0x46]),
        player: player,
        outputDirectory: () async => tempDir,
        now: () => DateTime.fromMillisecondsSinceEpoch(5678),
        audioFileExtension: 'wav',
      );

      final result = await service.speak(text: '你好', voice: 'alloy');

      expect(result.audioFile.path, endsWith('simichat-tts-5678.wav'));
      expect(player.playedPath, result.audioFile.path);
    });

    test('rejects empty text before calling engine', () async {
      final engine = _FakeTextToSpeechEngine([1]);
      final service = TextToSpeechService(
        engine: engine,
        player: _FakeAudioPlayer(),
        outputDirectory: () async => tempDir,
      );

      await expectLater(
        service.speak(text: '   ', voice: 'alloy'),
        throwsA(isA<TextToSpeechException>()),
      );
      expect(engine.lastInput, isNull);
    });

    test('truncates long text to max input characters', () async {
      final engine = _FakeTextToSpeechEngine([1, 2, 3]);
      final service = TextToSpeechService(
        engine: engine,
        player: _FakeAudioPlayer(),
        outputDirectory: () async => tempDir,
      );

      await service.speak(
        text: List.filled(kTextToSpeechMaxInputCharacters + 50, 'a').join(),
        voice: 'alloy',
      );

      expect(engine.lastInput?.text.length, kTextToSpeechMaxInputCharacters);
    });

    test('validates voice format before calling engine', () async {
      final engine = _FakeTextToSpeechEngine([1]);
      final service = TextToSpeechService(
        engine: engine,
        player: _FakeAudioPlayer(),
        outputDirectory: () async => tempDir,
      );

      await expectLater(
        service.speak(text: 'hello', voice: '../bad'),
        throwsA(
          isA<TextToSpeechException>().having(
            (e) => e.message,
            'message',
            contains('音色格式'),
          ),
        ),
      );
      expect(engine.lastInput, isNull);
    });

    test('stop delegates to audio player', () async {
      final player = _FakeAudioPlayer();
      final service = TextToSpeechService(
        engine: _FakeTextToSpeechEngine([1]),
        player: player,
        outputDirectory: () async => tempDir,
      );

      await service.stop();

      expect(player.stopped, true);
    });

    test('playbackEvents exposes audio player terminal events', () async {
      final player = _FakeAudioPlayer();
      final service = TextToSpeechService(
        engine: _FakeTextToSpeechEngine([1]),
        player: player,
        outputDirectory: () async => tempDir,
      );

      final expected = const AudioPlaybackEvent(
        type: AudioPlaybackEventType.completed,
        path: '/app/cache/tts.mp3',
      );
      expectLater(
        service.playbackEvents,
        emits(
          isA<AudioPlaybackEvent>()
              .having((event) => event.type, 'type', expected.type)
              .having((event) => event.path, 'path', expected.path),
        ),
      );

      player.emit(expected);
    });

    test(
      'tracks synthesis, playback, completion, stop, and error states',
      () async {
        final player = _FakeAudioPlayer();
        final service = TextToSpeechService(
          engine: _FakeTextToSpeechEngine([1]),
          player: player,
          outputDirectory: () async => tempDir,
          now: () => DateTime.fromMillisecondsSinceEpoch(1234),
        );
        final states = <TextToSpeechPlaybackState>[];
        final subscription = service.playbackStates.listen(
          (snapshot) => states.add(snapshot.state),
        );
        addTearDown(subscription.cancel);

        final result = await service.speak(text: 'hello', voice: 'alloy');
        expect(service.playbackState, TextToSpeechPlaybackState.playing);

        player.emit(
          AudioPlaybackEvent(
            type: AudioPlaybackEventType.completed,
            path: result.audioFile.path,
          ),
        );
        player.emit(
          AudioPlaybackEvent(
            type: AudioPlaybackEventType.stopped,
            path: result.audioFile.path,
          ),
        );
        player.emit(
          AudioPlaybackEvent(
            type: AudioPlaybackEventType.error,
            path: result.audioFile.path,
            message: 'focus lost',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          states,
          containsAll(<TextToSpeechPlaybackState>[
            TextToSpeechPlaybackState.synthesizing,
            TextToSpeechPlaybackState.playing,
            TextToSpeechPlaybackState.completed,
            TextToSpeechPlaybackState.stopped,
            TextToSpeechPlaybackState.error,
          ]),
        );
        expect(service.playbackState, TextToSpeechPlaybackState.error);
        expect(service.playbackSnapshot.message, 'focus lost');
      },
    );

    test(
      'cancelling while player is pending stops playback and deletes file',
      () async {
        final player = _BlockingAudioPlayer();
        final service = TextToSpeechService(
          engine: _FakeTextToSpeechEngine([1, 2, 3]),
          player: player,
          outputDirectory: () async => tempDir,
          now: () => DateTime.fromMillisecondsSinceEpoch(5678),
        );
        final cancelToken = CancelToken();
        final operation = service.speak(
          text: 'hello',
          voice: 'alloy',
          cancelToken: cancelToken,
        );

        final path = await player.playStarted.future;
        cancelToken.cancel('stop playback');
        player.release();

        await expectLater(
          operation,
          throwsA(
            isA<TextToSpeechException>().having(
              (error) => error.message,
              'message',
              contains('取消'),
            ),
          ),
        );
        expect(player.stopped, isTrue);
        expect(await File(path).exists(), isFalse);
        expect(service.playbackState, TextToSpeechPlaybackState.stopped);
      },
    );

    test('parses native audio playback method call events safely', () {
      final completed = AudioPlaybackEvent.fromMethodCall(
        const MethodCall('playbackCompleted', {'path': ' /app/audio.mp3 '}),
      );
      expect(completed?.type, AudioPlaybackEventType.completed);
      expect(completed?.path, '/app/audio.mp3');

      final stopped = AudioPlaybackEvent.fromMethodCall(
        const MethodCall('playbackStopped', {'path': '/app/audio.mp3'}),
      );
      expect(stopped?.type, AudioPlaybackEventType.stopped);

      final error = AudioPlaybackEvent.fromMethodCall(
        const MethodCall('playbackError', {'message': ' interrupted '}),
      );
      expect(error?.type, AudioPlaybackEventType.error);
      expect(error?.message, 'interrupted');

      expect(
        AudioPlaybackEvent.fromMethodCall(const MethodCall('unknown')),
        isNull,
      );
    });

    test(
      'method channel audio player keeps audio focus skip test-only',
      () async {
        final audioFile = File('${tempDir.path}/tts.mp3')
          ..writeAsBytesSync([0x49, 0x44, 0x33]);
        const channel = MethodChannel('simichat/audio_player');
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return true;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        const player = MethodChannelAudioPlayer();

        await player.playFile(audioFile.path);
        await player.playFileForTesting(
          audioFile.path,
          skipAudioFocusRequest: true,
        );

        expect(calls, hasLength(2));
        expect(calls.first.method, 'playFile');
        expect(calls.first.arguments, isA<Map>());
        expect(
          (calls.first.arguments as Map).containsKey('skipAudioFocusRequest'),
          isFalse,
        );
        expect(
          calls.last.arguments,
          containsPair('skipAudioFocusRequest', true),
        );
      },
    );

    test('method channel audio player maps audio focus denial', () async {
      final audioFile = File('${tempDir.path}/tts.mp3')
        ..writeAsBytesSync([0x49, 0x44, 0x33]);
      const channel = MethodChannel('simichat/audio_player');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'AUDIO_FOCUS_DENIED');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      const player = MethodChannelAudioPlayer();

      await expectLater(
        player.playFile(audioFile.path),
        throwsA(
          isA<AudioPlaybackException>().having(
            (error) => error.message,
            'message',
            '无法获取音频播放焦点',
          ),
        ),
      );
    });
  });
}

class _FakeTextToSpeechEngine implements TextToSpeechEngine {
  _FakeTextToSpeechEngine(this.bytes);

  final List<int> bytes;
  TextToSpeechInput? lastInput;

  @override
  Future<List<int>> synthesize(
    TextToSpeechInput input, {
    CancelToken? cancelToken,
  }) async {
    lastInput = input;
    return bytes;
  }
}

class _FakeAudioPlayer implements AudioPlayerPlatform {
  final _events = StreamController<AudioPlaybackEvent>.broadcast();
  String? playedPath;
  var stopped = false;

  @override
  Stream<AudioPlaybackEvent> get events => _events.stream;

  @override
  Future<void> playFile(String audioPath) async {
    playedPath = audioPath;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void emit(AudioPlaybackEvent event) {
    _events.add(event);
  }
}

class _BlockingAudioPlayer implements AudioPlayerPlatform {
  final playStarted = Completer<String>();
  final playGate = Completer<void>();
  var stopped = false;

  @override
  Stream<AudioPlaybackEvent> get events =>
      const Stream<AudioPlaybackEvent>.empty();

  @override
  Future<void> playFile(String audioPath) async {
    if (!playStarted.isCompleted) playStarted.complete(audioPath);
    await playGate.future;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void release() {
    if (!playGate.isCompleted) playGate.complete();
  }
}
