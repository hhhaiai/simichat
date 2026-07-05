import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/media/audio_player.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile device generates assistant speech through TTS endpoint', (
    tester,
  ) async {
    final ttsRequests = <Map<String, dynamic>>[];
    final server = await _startTtsMockServer(ttsRequests: ttsRequests);
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues({
      kTextToSpeechEnabledStorageKey: true,
      kTextToSpeechProviderStorageKey: kTextToSpeechProviderOpenAiCompatible,
      kTextToSpeechBaseUrlStorageKey: 'http://127.0.0.1:${server.port}',
      kTextToSpeechModelStorageKey: 'tts-network-mock-model',
      kTextToSpeechVoiceStorageKey: 'alloy',
      kTextToSpeechApiKeyStorageKey: KeyEncryptor.encrypt('tts-network-key'),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 'tts-network-session');
    await db.sessionDao.updateTitle('tts-network-session', 'TTS 网络 smoke');
    await db.messageDao.insertMessage(
      id: 'tts-assistant-message',
      sessionId: 'tts-network-session',
      role: 'assistant',
      content: 'DEVICE TTS assistant message 20260706',
    );

    final audioPlayer = _RecordingAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioPlayerProvider.overrideWithValue(audioPlayer),
      ],
    );
    addTearDown(container.dispose);
    await container.read(textToSpeechConfigProvider.notifier).ready;
    expect(container.read(textToSpeechConfigProvider).isConfigured, true);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('DEVICE TTS assistant message 20260706'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await _pumpUntil(tester, () async => audioPlayer.playedPath != null);
    await tester.pumpAndSettle();

    expect(ttsRequests, hasLength(1));
    expect(ttsRequests.single['path'], '/v1/audio/speech');
    expect(ttsRequests.single['authorization'], 'Bearer tts-network-key');
    expect(ttsRequests.single['contentType'], contains('application/json'));
    expect(ttsRequests.single['model'], 'tts-network-mock-model');
    expect(ttsRequests.single['voice'], 'alloy');
    expect(
      ttsRequests.single['input'],
      'DEVICE TTS assistant message 20260706',
    );
    expect(ttsRequests.single['responseFormat'], 'mp3');
    expect(audioPlayer.stopCount, 1);
    expect(audioPlayer.playedPath, isNotNull);
    final ttsFile = File(audioPlayer.playedPath!);
    expect(await ttsFile.exists(), isTrue);
    expect(ttsFile.path, contains('tts_audio'));
    expect(await ttsFile.length(), greaterThan(0));
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pumpAndSettle();
    expect(audioPlayer.stopCount, 2);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RecordingAudioPlayer implements AudioPlayerPlatform {
  final _events = StreamController<AudioPlaybackEvent>.broadcast();
  String? playedPath;
  var stopCount = 0;

  @override
  Stream<AudioPlaybackEvent> get events => _events.stream;

  @override
  Future<void> playFile(String audioPath) async {
    playedPath = audioPath;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

Future<HttpServer> _startTtsMockServer({
  required List<Map<String, dynamic>> ttsRequests,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
      if (request.method != 'POST' || request.uri.path != '/v1/audio/speech') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      ttsRequests.add({
        'path': request.uri.path,
        'authorization': request.headers.value(HttpHeaders.authorizationHeader),
        'contentType': request.headers.contentType?.toString(),
        'model': decoded['model'],
        'voice': decoded['voice'],
        'input': decoded['input'],
        'responseFormat': decoded['response_format'],
      });

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.add(<int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00]);
      await request.response.close();
    }),
  );
  return server;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('Timed out waiting for condition');
}
