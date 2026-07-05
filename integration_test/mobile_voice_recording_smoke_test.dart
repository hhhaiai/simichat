import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile device records voice and sends it through STT', (
    tester,
  ) async {
    final chatRequests = <Map<String, dynamic>>[];
    final sttRequests = <Map<String, dynamic>>[];
    final server = await _startOpenAiCompatibleMockServer(
      chatRequests: chatRequests,
      sttRequests: sttRequests,
      sttTranscript: 'Pixel8 real recorder transcript 20260706',
      chatReply: 'DEVICE voice recorder reply 20260706',
    );
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'voice-recorder-channel',
      name: 'Voice Recorder Mock OpenAI',
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKeyEncrypted: KeyEncryptor.encrypt('voice-recorder-api-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'voice-recorder-model',
      channelId: 'voice-recorder-channel',
      modelName: 'voice-recorder-mock-model',
    );
    await db.sessionDao.createSession(
      id: 'voice-recorder-session',
      defaultChannelModelId: 'voice-recorder-model',
    );
    await db.sessionDao.updateTitle('voice-recorder-session', '真机录音 smoke');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Voice Recorder Mock OpenAI / voice-recorder-mock-model'),
      findsOneWidget,
    );

    final voiceButton = find.byKey(const ValueKey('voice-record-button'));
    expect(voiceButton, findsOneWidget);

    await tester.tap(voiceButton);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.tap(voiceButton);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.graphic_eq_outlined), findsOneWidget);

    await tester.tap(find.byTooltip('发送'));

    await _pumpUntil(tester, () async {
      final messages = await db.messageDao.getMessagesBySession(
        'voice-recorder-session',
      );
      return messages.any(
        (message) =>
            message.role == 'assistant' &&
            message.content == 'DEVICE voice recorder reply 20260706',
      );
    });
    await _pumpUntil(
      tester,
      () async => find
          .text('DEVICE voice recorder reply 20260706')
          .evaluate()
          .isNotEmpty,
    );

    final messages = await db.messageDao.getMessagesBySession(
      'voice-recorder-session',
    );
    final user = messages.where((message) => message.role == 'user').single;
    expect(user.content, '');

    final attachments = await db.attachmentDao.getAttachmentsByMessage(user.id);
    expect(attachments, hasLength(1));
    expect(attachments.single.fileType, 'audio');
    expect(attachments.single.fileName, startsWith('simichat-recording-'));
    expect(attachments.single.fileName, endsWith('.m4a'));
    expect(attachments.single.fileSize, greaterThan(0));
    expect(await File(attachments.single.localPath).exists(), isTrue);

    final root = await getApplicationDocumentsDirectory();
    final transcriptDetails = await AudioTranscriptArchive(
      rootDirectory: root,
    ).readDetails(messageId: user.id, attachmentId: attachments.single.id);
    expect(transcriptDetails?.status, AudioTranscriptStatus.ready);
    expect(
      transcriptDetails?.transcriptText,
      'Pixel8 real recorder transcript 20260706',
    );

    expect(sttRequests, hasLength(1));
    expect(sttRequests.single['path'], '/v1/audio/transcriptions');
    expect(
      sttRequests.single['authorization'],
      'Bearer voice-recorder-api-key',
    );
    expect(sttRequests.single['contentType'], contains('multipart/form-data'));
    expect(sttRequests.single['hasWhisperModel'], isTrue);
    expect(sttRequests.single['hasRecordingFilename'], isTrue);
    expect(
      sttRequests.single['bodyLength'],
      greaterThan(attachments.single.fileSize),
    );

    expect(chatRequests, hasLength(1));
    expect(chatRequests.single['path'], '/v1/chat/completions');
    expect(chatRequests.single['model'], 'voice-recorder-mock-model');
    expect(chatRequests.single['stream'], isTrue);
    final lastUser = chatRequests.single['lastUser'] as String;
    expect(lastUser, contains('以下是语音转文字结果'));
    expect(lastUser, contains('Pixel8 real recorder transcript 20260706'));
    expect(lastUser, isNot(contains('base64')));
    expect(lastUser, isNot(contains(attachments.single.localPath)));

    final assistant = messages
        .where((message) => message.role == 'assistant')
        .single;
    expect(assistant.content, 'DEVICE voice recorder reply 20260706');
    expect(assistant.channelModelId, 'voice-recorder-model');
    expect(tester.takeException(), isNull);
  });
}

Future<HttpServer> _startOpenAiCompatibleMockServer({
  required List<Map<String, dynamic>> chatRequests,
  required List<Map<String, dynamic>> sttRequests,
  required String sttTranscript,
  required String chatReply,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
      if (request.method == 'POST' &&
          request.uri.path == '/v1/audio/transcriptions') {
        await _handleSttRequest(
          request,
          sttRequests: sttRequests,
          transcript: sttTranscript,
        );
        return;
      }
      if (request.method == 'POST' &&
          request.uri.path == '/v1/chat/completions') {
        await _handleChatRequest(
          request,
          chatRequests: chatRequests,
          reply: chatReply,
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }),
  );
  return server;
}

Future<void> _handleSttRequest(
  HttpRequest request, {
  required List<Map<String, dynamic>> sttRequests,
  required String transcript,
}) async {
  final bytes = await request.fold<List<int>>(
    <int>[],
    (buffer, chunk) => buffer..addAll(chunk),
  );
  final bodyText = latin1.decode(bytes);
  sttRequests.add({
    'path': request.uri.path,
    'authorization': request.headers.value(HttpHeaders.authorizationHeader),
    'contentType': request.headers.contentType?.toString(),
    'bodyLength': bytes.length,
    'hasWhisperModel':
        bodyText.contains('name="model"') && bodyText.contains('whisper-1'),
    'hasRecordingFilename':
        bodyText.contains('filename="simichat-recording-') &&
        bodyText.contains('.m4a"'),
  });

  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode({'text': transcript}));
  await request.response.close();
}

Future<void> _handleChatRequest(
  HttpRequest request, {
  required List<Map<String, dynamic>> chatRequests,
  required String reply,
}) async {
  final body = await utf8.decoder.bind(request).join();
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final messages = (decoded['messages'] as List<dynamic>? ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();
  chatRequests.add({
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
    'id': 'chatcmpl-voice-recorder-smoke',
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
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('Timed out waiting for condition');
}
