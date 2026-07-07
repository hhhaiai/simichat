import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile background stream cancel smoke keeps retry affordance', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final clientDisconnected = Completer<void>();
    final server = await _startSlowOpenAiMockServer(
      requests: requests,
      clientDisconnected: clientDisconnected,
      firstChunk: 'partial background stream reply 20260707',
    );
    addTearDown(() => server.close(force: true));

    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const sessionId = 'background-stream-cancel-session';
    await db.channelDao.createChannel(
      id: 'background-stream-cancel-channel',
      name: 'Background Stream Cancel Mock',
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKeyEncrypted: KeyEncryptor.encrypt('background-stream-cancel-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'background-stream-cancel-model',
      channelId: 'background-stream-cancel-channel',
      modelName: 'background-stream-cancel-model',
    );
    await db.sessionDao.createSession(
      id: sessionId,
      defaultChannelModelId: 'background-stream-cancel-model',
    );
    await db.sessionDao.updateTitle(sessionId, '后台流式取消 smoke');

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AiChatApp()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).last,
      'background stream cancel smoke 20260707',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));

    await _pumpUntil(
      tester,
      () async {
        final state = container.read(streamStateProvider(sessionId));
        return requests.isNotEmpty &&
            state.isStreaming &&
            state.isWaitingForFirstToken;
      },
      timeout: const Duration(seconds: 20),
      describe: () async => _describeStreamState(
        container: container,
        db: db,
        sessionId: sessionId,
        requestCount: requests.length,
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final state = container.read(streamStateProvider(sessionId));
    expect(state.isStreaming, isFalse);
    expect(state.error, backgroundStreamingInterruptedMessage);
    expect(find.text(backgroundStreamingInterruptedMessage), findsOneWidget);
    expect(find.text('已停止后台生成，可点“重试”继续'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), isNull);

    final messages = await db.messageDao.getMessagesBySession(sessionId);
    expect(messages.where((message) => message.role == 'user'), hasLength(1));
    expect(messages.where((message) => message.role == 'assistant'), isEmpty);
    expect(requests, hasLength(1));
    expect(requests.single['path'], '/v1/chat/completions');
    expect(requests.single['model'], 'background-stream-cancel-model');
    expect(requests.single['stream'], isTrue);
    expect(tester.takeException(), isNull);
  });
}

Future<String> _describeStreamState({
  required ProviderContainer container,
  required AppDatabase db,
  required String sessionId,
  required int requestCount,
}) async {
  final state = container.read(streamStateProvider(sessionId));
  final messages = await db.messageDao.getMessagesBySession(sessionId);
  return 'state(isStreaming=${state.isStreaming}, '
      'waiting=${state.isWaitingForFirstToken}, '
      'content=${state.currentContent}, error=${state.error}), '
      'requests=$requestCount, messages=${messages.length}';
}

Future<HttpServer> _startSlowOpenAiMockServer({
  required List<Map<String, dynamic>> requests,
  required Completer<void> clientDisconnected,
  required String firstChunk,
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
      requests.add({
        'path': request.uri.path,
        'model': decoded['model'],
        'stream': decoded['stream'],
      });

      request.response.statusCode = HttpStatus.ok;
      request.response.headers
        ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      final payload = {
        'id': 'chatcmpl-background-stream-cancel-smoke',
        'object': 'chat.completion.chunk',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': decoded['model'],
        'choices': [
          {
            'index': 0,
            'delta': {'content': firstChunk},
            'finish_reason': null,
          },
        ],
      };
      try {
        request.response.write(': ${' ' * 4096}\n\n');
        request.response.write('data: ${jsonEncode(payload)}\n\n');
        await request.response.flush();
        while (true) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          request.response.write(': keepalive\n\n');
          await request.response.flush();
        }
      } catch (_) {
        if (!clientDisconnected.isCompleted) clientDisconnected.complete();
      } finally {
        try {
          await request.response.close();
        } catch (_) {}
      }
    }),
  );
  return server;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  FutureOr<String> Function()? describe,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  final details = describe == null ? '' : ': ${await describe()}';
  fail('Timed out waiting for condition$details');
}
