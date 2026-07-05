import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile device real send smoke uses local OpenAI mock', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final server = await _startOpenAiMockServer(
      requests: requests,
      reply: 'DEVICE integration reply 20260706',
    );
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'integration-channel',
      name: 'Integration Mock OpenAI',
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKeyEncrypted: KeyEncryptor.encrypt('test-api-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'integration-model',
      channelId: 'integration-channel',
      modelName: 'integration-mock-model',
    );
    await db.sessionDao.createSession(
      id: 'integration-session',
      defaultChannelModelId: 'integration-model',
    );
    await db.sessionDao.updateTitle('integration-session', '真机集成发送 smoke');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Integration Mock OpenAI / integration-mock-model'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byType(TextField).last,
      'device integration send',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));

    await _pumpUntil(tester, () async {
      final messages = await db.messageDao.getMessagesBySession(
        'integration-session',
      );
      return messages.any(
        (message) =>
            message.role == 'assistant' &&
            message.content == 'DEVICE integration reply 20260706',
      );
    });

    final messages = await db.messageDao.getMessagesBySession(
      'integration-session',
    );
    expect(
      messages.where((message) => message.role == 'user').single.content,
      'device integration send',
    );
    final assistant = messages
        .where((message) => message.role == 'assistant')
        .single;
    expect(assistant.content, 'DEVICE integration reply 20260706');
    expect(assistant.channelModelId, 'integration-model');
    expect(find.text('DEVICE integration reply 20260706'), findsOneWidget);
    expect(requests, hasLength(1));
    expect(requests.single['path'], '/v1/chat/completions');
    expect(requests.single['model'], 'integration-mock-model');
    expect(requests.single['stream'], isTrue);
    expect(requests.single['lastUser'], 'device integration send');
    expect(tester.takeException(), isNull);
  });
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
        'id': 'chatcmpl-integration-smoke',
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
