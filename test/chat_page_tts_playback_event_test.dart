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
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat page clears TTS stop action after native completion event', (
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
    await db.sessionDao.createSession(id: 'session-tts');
    await db.messageDao.insertMessage(
      id: 'message-tts',
      sessionId: 'session-tts',
      role: 'assistant',
      content: '这是一条可以播报的回复。',
    );
    final tempDir = Directory(
      '${Directory.systemTemp.path}/simichat_chat_tts_event_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final player = _CompletingAudioPlayer();
    final service = _FakeTextToSpeechService(
      fakePlayer: player,
      audioFile: File('${tempDir.path}/simichat-tts-4242.mp3'),
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

    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);

    final speakButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.volume_up_outlined),
    );
    speakButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.playedPath, isNotNull);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);

    player.completeCurrentPlayback();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeTextToSpeechService extends TextToSpeechService {
  _FakeTextToSpeechService({required this.fakePlayer, required this.audioFile})
    : super(engine: _StaticTextToSpeechEngine(), player: fakePlayer);

  final _CompletingAudioPlayer fakePlayer;

  final File audioFile;

  @override
  Future<void> stop() => fakePlayer.stop();

  @override
  Future<TextToSpeechResult> speak({
    required String text,
    required String voice,
  }) async {
    await fakePlayer.playFile(audioFile.path);
    return TextToSpeechResult(audioFile: audioFile, fileSize: 3);
  }
}

class _StaticTextToSpeechEngine implements TextToSpeechEngine {
  @override
  Future<List<int>> synthesize(TextToSpeechInput input) async => [1, 2, 3];
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
}
