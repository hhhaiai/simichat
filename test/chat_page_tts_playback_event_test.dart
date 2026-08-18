import 'dart:async';
import 'dart:io';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/media/audio_player.dart';
import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:ai_chat_app/features/chat/chat_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'chat page serializes TTS preparation and clears stop after completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kTextToSpeechEnabledStorageKey: true,
        kTextToSpeechProviderStorageKey: kTextToSpeechProviderOpenAiCompatible,
        kTextToSpeechBaseUrlStorageKey: 'https://example.invalid',
        kTextToSpeechModelStorageKey: 'tts-test',
        kTextToSpeechVoiceStorageKey: 'alloy',
        kTextToSpeechApiKeyStorageKey: 'encrypted-test-key',
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.sessionDao.createSession(id: 'session-tts');
      await db.messageDao.insertMessage(
        id: 'message-tts',
        sessionId: 'session-tts',
        role: 'assistant',
        content: '这是一条可以播报的回复。',
      );
      await db.messageDao.insertMessage(
        id: 'message-tts-2',
        sessionId: 'session-tts',
        role: 'assistant',
        content: '这是第二条可以播报的回复。',
      );
      final tempDir = Directory(
        '${Directory.systemTemp.path}/simichat_chat_tts_event_${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final player = _CompletingAudioPlayer();
      final synthesisGate = Completer<void>();
      final service = _FakeTextToSpeechService(
        fakePlayer: player,
        audioFile: File('${tempDir.path}/simichat-tts-4242.mp3'),
        synthesisGate: synthesisGate,
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          isOnlineProvider.overrideWithValue(true),
          activeSessionIdProvider.overrideWith((ref) => 'session-tts'),
          audioPlayerProvider.overrideWithValue(player),
          textToSpeechServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      await container.read(textToSpeechConfigProvider.notifier).ready;
      expect(container.read(textToSpeechConfigProvider).isConfigured, true);
      expect(container.read(textToSpeechServiceProvider), same(service));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ChatPage())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.volume_up_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);

      final speakButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.volume_up_outlined).first,
      );
      speakButton.onPressed!();
      await tester.pump();

      // 第一条仍在网络合成时点击另一条，不应启动第二个并发请求；否则较旧
      // 请求晚返回会反向打断用户刚选择的新播报。
      final secondSpeakButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.volume_up_outlined),
      );
      secondSpeakButton.onPressed!();
      await tester.pump();
      expect(service.speakCalls, 1);
      expect(find.text('正在生成语音，请稍候'), findsOneWidget);

      synthesisGate.complete();
      await tester.pump(const Duration(milliseconds: 100));

      expect(player.playedPath, isNotNull);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);

      player.completeCurrentPlayback();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
      expect(find.byIcon(Icons.volume_up_outlined), findsNWidgets(2));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pathless terminal playback event clears a pending TTS request', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kTextToSpeechEnabledStorageKey: true,
      kTextToSpeechProviderStorageKey: kTextToSpeechProviderOpenAiCompatible,
      kTextToSpeechBaseUrlStorageKey: 'https://example.invalid',
      kTextToSpeechModelStorageKey: 'tts-test',
      kTextToSpeechVoiceStorageKey: 'alloy',
      kTextToSpeechApiKeyStorageKey: 'encrypted-test-key',
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.sessionDao.createSession(id: 'session-tts-pathless');
    await db.messageDao.insertMessage(
      id: 'message-tts-pathless',
      sessionId: 'session-tts-pathless',
      role: 'assistant',
      content: '这是一条需要等待合成的回复。',
    );
    final tempDir = Directory(
      '${Directory.systemTemp.path}/simichat_chat_tts_pathless_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final player = _CompletingAudioPlayer();
    final synthesisGate = Completer<void>();
    final service = _FakeTextToSpeechService(
      fakePlayer: player,
      audioFile: File('${tempDir.path}/simichat-tts-pathless.mp3'),
      synthesisGate: synthesisGate,
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        activeSessionIdProvider.overrideWith((ref) => 'session-tts-pathless'),
        audioPlayerProvider.overrideWithValue(player),
        textToSpeechServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    await container.read(textToSpeechConfigProvider.notifier).ready;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChatPage())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final speakButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.volume_up_outlined),
    );
    speakButton.onPressed!();
    await tester.pump();
    expect(find.byIcon(Icons.hourglass_top_outlined), findsOneWidget);

    // Native error callbacks may omit the path. That event still has to
    // invalidate the pending synthesis and restore a playable button.
    player.emit(const AudioPlaybackEvent(type: AudioPlaybackEventType.error));
    await tester.pump();
    expect(find.byIcon(Icons.hourglass_top_outlined), findsNothing);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);

    // The stale synthesis future may complete later, but must not revive the
    // stopped state or start playback after the terminal event.
    synthesisGate.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'attachment playback completion emitted before playFile returns does not leave stop state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.sessionDao.createSession(id: 'session-audio');
      await db.messageDao.insertMessage(
        id: 'message-audio',
        sessionId: 'session-audio',
        role: 'user',
        content: '音频附件',
      );
      await db.attachmentDao.insertAttachment(
        id: 'attachment-audio',
        messageId: 'message-audio',
        fileType: 'audio',
        localPath: '/tmp/simichat-short.wav',
        fileName: 'short.wav',
        fileSize: 64,
      );

      final player = _ImmediateCompletionAudioPlayer();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          activeSessionIdProvider.overrideWith((ref) => 'session-audio'),
          isOnlineProvider.overrideWithValue(true),
          audioPlayerProvider.overrideWithValue(player),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ChatPage())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_circle_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(player.playedPath, '/tmp/simichat-short.wav');
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeTextToSpeechService extends TextToSpeechService {
  _FakeTextToSpeechService({
    required this.fakePlayer,
    required this.audioFile,
    this.synthesisGate,
  }) : super(engine: _StaticTextToSpeechEngine(), player: fakePlayer);

  final _CompletingAudioPlayer fakePlayer;

  final File audioFile;
  final Completer<void>? synthesisGate;
  int speakCalls = 0;

  @override
  Future<void> stop() => fakePlayer.stop();

  @override
  Future<TextToSpeechResult> speak({
    required String text,
    required String voice,
    CancelToken? cancelToken,
  }) async {
    speakCalls++;
    await synthesisGate?.future;
    await fakePlayer.playFile(audioFile.path);
    return TextToSpeechResult(audioFile: audioFile, fileSize: 3);
  }
}

class _StaticTextToSpeechEngine implements TextToSpeechEngine {
  @override
  Future<List<int>> synthesize(
    TextToSpeechInput input, {
    CancelToken? cancelToken,
  }) async => [1, 2, 3];
}

class _CompletingAudioPlayer implements AudioPlayerPlatform {
  final _events = StreamController<AudioPlaybackEvent>.broadcast();
  String? playedPath;

  @override
  Stream<AudioPlaybackEvent> get events => _events.stream;

  @override
  Future<void> playFile(String audioPath) async {
    playedPath = audioPath;
  }

  @override
  Future<void> stop() async {}

  void completeCurrentPlayback() {
    final path = playedPath;
    if (path == null) return;
    _events.add(
      AudioPlaybackEvent(type: AudioPlaybackEventType.completed, path: path),
    );
  }

  void emit(AudioPlaybackEvent event) => _events.add(event);
}

class _ImmediateCompletionAudioPlayer implements AudioPlayerPlatform {
  final _events = StreamController<AudioPlaybackEvent>.broadcast();
  String? playedPath;

  @override
  Stream<AudioPlaybackEvent> get events => _events.stream;

  @override
  Future<void> playFile(String audioPath) async {
    playedPath = audioPath;
    _events.add(
      AudioPlaybackEvent(
        type: AudioPlaybackEventType.completed,
        path: audioPath,
      ),
    );
  }

  @override
  Future<void> stop() async {}
}
