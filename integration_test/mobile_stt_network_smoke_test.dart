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

  testWidgets('mobile device uses OpenAI-compatible STT endpoint before chat', (
    tester,
  ) async {
    final chatRequests = <Map<String, dynamic>>[];
    final sttRequests = <Map<String, dynamic>>[];
    final server = await _startOpenAiCompatibleMockServer(
      chatRequests: chatRequests,
      sttRequests: sttRequests,
      sttTranscript: 'Pixel8 network STT transcript 20260706',
      chatReply: 'DEVICE STT network reply 20260706',
    );
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'stt-network-channel',
      name: 'STT Network Mock OpenAI',
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKeyEncrypted: KeyEncryptor.encrypt('network-api-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'stt-network-model',
      channelId: 'stt-network-channel',
      modelName: 'stt-network-mock-model',
    );
    await db.sessionDao.createSession(
      id: 'stt-network-session',
      defaultChannelModelId: 'stt-network-model',
    );
    await db.sessionDao.updateTitle('stt-network-session', 'STT 网络 smoke');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('STT Network Mock OpenAI / stt-network-mock-model'),
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
    final prompt = '请走 STT 网络识别：data:audio/wav;base64,$base64Audio';

    await tester.enterText(find.byType(TextField).last, prompt);
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));

    await _pumpUntil(tester, () async {
      final messages = await db.messageDao.getMessagesBySession(
        'stt-network-session',
      );
      return messages.any(
        (message) =>
            message.role == 'assistant' &&
            message.content == 'DEVICE STT network reply 20260706',
      );
    });
    await _pumpUntil(
      tester,
      () async =>
          find.text('DEVICE STT network reply 20260706').evaluate().isNotEmpty,
    );

    final messages = await db.messageDao.getMessagesBySession(
      'stt-network-session',
    );
    final user = messages.where((message) => message.role == 'user').single;
    expect(user.content, contains('已接收 base64 语音'));
    expect(user.content, isNot(contains(base64Audio)));
    expect(user.content, isNot(contains('data:audio')));
    expect(user.content, isNot(contains('Pixel8 network STT transcript')));

    final attachments = await db.attachmentDao.getAttachmentsByMessage(user.id);
    expect(attachments, hasLength(1));
    expect(attachments.single.fileType, 'audio');
    expect(attachments.single.fileName, 'inline-base64-audio.wav');

    final root = await getApplicationDocumentsDirectory();
    final transcriptDetails = await AudioTranscriptArchive(
      rootDirectory: root,
    ).readDetails(messageId: user.id, attachmentId: attachments.single.id);
    expect(transcriptDetails?.status, AudioTranscriptStatus.ready);
    expect(
      transcriptDetails?.transcriptText,
      'Pixel8 network STT transcript 20260706',
    );

    expect(sttRequests, hasLength(1));
    expect(sttRequests.single['path'], '/v1/audio/transcriptions');
    expect(sttRequests.single['authorization'], 'Bearer network-api-key');
    expect(sttRequests.single['contentType'], contains('multipart/form-data'));
    expect(sttRequests.single['hasWhisperModel'], isTrue);
    expect(sttRequests.single['hasAudioFilename'], isTrue);
    expect(sttRequests.single['bodyLength'], greaterThan(audioBytes.length));

    expect(chatRequests, hasLength(1));
    expect(chatRequests.single['path'], '/v1/chat/completions');
    expect(chatRequests.single['model'], 'stt-network-mock-model');
    expect(chatRequests.single['stream'], isTrue);
    final lastUser = chatRequests.single['lastUser'] as String;
    expect(lastUser, contains('以下是语音转文字结果'));
    expect(lastUser, contains('Pixel8 network STT transcript 20260706'));
    expect(lastUser, isNot(contains(base64Audio)));
    expect(lastUser, isNot(contains('data:audio')));

    final assistant = messages
        .where((message) => message.role == 'assistant')
        .single;
    expect(assistant.content, 'DEVICE STT network reply 20260706');
    expect(assistant.channelModelId, 'stt-network-model');
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
    'hasAudioFilename': bodyText.contains('filename="inline-base64-audio.wav"'),
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
    'id': 'chatcmpl-stt-network-smoke',
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
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('Timed out waiting for condition');
}
