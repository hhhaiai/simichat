import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:ai_chat_app/core/media/audio_transcription_service.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/audio_transcription_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile device sends pasted base64 audio through fake STT', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final server = await _startOpenAiMockServer(
      requests: requests,
      reply: 'DEVICE base64 audio reply 20260706',
    );
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'base64-audio-channel',
      name: 'Base64 Audio Mock OpenAI',
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKeyEncrypted: KeyEncryptor.encrypt('test-api-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'base64-audio-model',
      channelId: 'base64-audio-channel',
      modelName: 'base64-audio-mock-model',
    );
    await db.sessionDao.createSession(
      id: 'base64-audio-session',
      defaultChannelModelId: 'base64-audio-model',
    );
    await db.sessionDao.updateTitle('base64-audio-session', 'base64 语音 smoke');

    const transcript = 'Pixel8 voice transcript 20260706';
    final fakeStt = _FakeSpeechToTextEngine(transcript);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          speechToTextEngineProvider.overrideWithValue(fakeStt),
        ],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Base64 Audio Mock OpenAI / base64-audio-mock-model'),
      findsOneWidget,
    );

    final audioBytes = <int>[
      0x52,
      0x49,
      0x46,
      0x46,
      0x24,
      0x00,
      0x00,
      0x00,
      0x57,
      0x41,
      0x56,
      0x45,
    ];
    final base64Audio = base64Encode(audioBytes);
    final prompt = '请识别这段语音：data:audio/wav;base64,$base64Audio';

    await tester.enterText(find.byType(TextField).last, prompt);
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));

    await _pumpUntil(tester, () async {
      final messages = await db.messageDao.getMessagesBySession(
        'base64-audio-session',
      );
      return messages.any(
        (message) =>
            message.role == 'assistant' &&
            message.content == 'DEVICE base64 audio reply 20260706',
      );
    });
    await _pumpUntil(
      tester,
      () async =>
          find.text('DEVICE base64 audio reply 20260706').evaluate().isNotEmpty,
    );

    final messages = await db.messageDao.getMessagesBySession(
      'base64-audio-session',
    );
    final user = messages.where((message) => message.role == 'user').single;
    expect(user.content, contains('已接收 base64 语音'));
    expect(user.content, isNot(contains(base64Audio)));
    expect(user.content, isNot(contains('data:audio')));
    expect(user.content, isNot(contains(transcript)));

    final attachments = await db.attachmentDao.getAttachmentsByMessage(user.id);
    expect(attachments, hasLength(1));
    expect(attachments.single.fileType, 'audio');
    expect(attachments.single.fileName, 'inline-base64-audio.wav');
    expect(fakeStt.inputs, hasLength(1));
    expect(fakeStt.inputs.single.fileName, 'inline-base64-audio.wav');
    expect(await File(fakeStt.inputs.single.audioPath).exists(), isTrue);

    final root = await getApplicationDocumentsDirectory();
    final transcriptDetails = await AudioTranscriptArchive(
      rootDirectory: root,
    ).readDetails(messageId: user.id, attachmentId: attachments.single.id);
    expect(transcriptDetails?.status, AudioTranscriptStatus.ready);
    expect(transcriptDetails?.transcriptText, transcript);

    final assistant = messages
        .where((message) => message.role == 'assistant')
        .single;
    expect(assistant.content, 'DEVICE base64 audio reply 20260706');
    expect(assistant.channelModelId, 'base64-audio-model');
    expect(requests, hasLength(1));
    expect(requests.single['path'], '/v1/chat/completions');
    expect(requests.single['model'], 'base64-audio-mock-model');
    expect(requests.single['stream'], isTrue);
    final lastUser = requests.single['lastUser'] as String;
    expect(lastUser, contains('以下是语音转文字结果'));
    expect(lastUser, contains(transcript));
    expect(lastUser, isNot(contains(base64Audio)));
    expect(lastUser, isNot(contains('data:audio')));
    expect(tester.takeException(), isNull);
  });
}

class _FakeSpeechToTextEngine implements SpeechToTextEngine {
  _FakeSpeechToTextEngine(this.transcript);

  final String transcript;
  final inputs = <AudioTranscriptionInput>[];

  @override
  Future<String> transcribe(
    AudioTranscriptionInput input, {
    CancelToken? cancelToken,
  }) async {
    inputs.add(input);
    return transcript;
  }
}

Future<HttpServer> _startOpenAiMockServer({
  required List<Map<String, dynamic>> requests,
  required String reply,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
      if (request.method != 'POST' ||
          request.uri.path != '/v1/chat/completions') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final messages = (decoded['messages'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      requests.add({
        'path': request.uri.path,
        'model': decoded['model'],
        'stream': decoded['stream'],
        'lastUser': messages.reversed.firstWhere(
          (message) => message['role'] == 'user',
        )['content'],
      });

      request.response.statusCode = HttpStatus.ok;
      request.response.headers
        ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      final payload = {
        'id': 'chatcmpl-base64-audio-smoke',
        'object': 'chat.completion.chunk',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': decoded['model'],
        'choices': [
          {
            'index': 0,
            'delta': {'content': reply},
            'finish_reason': null,
          },
        ],
      };
      request.response.write('data: ${jsonEncode(payload)}\n\n');
      request.response.write('data: [DONE]\n\n');
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
