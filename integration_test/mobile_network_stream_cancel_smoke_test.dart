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

  testWidgets('mobile network loss cancels in-flight stream on device', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final clientDisconnected = Completer<void>();
    final server = await _startSlowOpenAiMockServer(
      requests: requests,
      clientDisconnected: clientDisconnected,
      firstChunk: 'partial network stream reply 20260707',
    );
    addTearDown(() => server.close(force: true));

    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const sessionId = 'network-stream-cancel-session';
    await db.channelDao.createChannel(
      id: 'network-stream-cancel-channel',
      name: 'Network Stream Cancel Mock',
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKeyEncrypted: KeyEncryptor.encrypt('network-stream-cancel-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'network-stream-cancel-model',
      channelId: 'network-stream-cancel-channel',
      modelName: 'network-stream-cancel-model',
    );
    await db.sessionDao.createSession(
      id: sessionId,
      defaultChannelModelId: 'network-stream-cancel-model',
    );
    await db.sessionDao.updateTitle(sessionId, '网络流式取消 smoke');

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
      'network stream cancel smoke 20260707',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));

    await _pumpUntil(
      tester,
      () async {
        final state = container.read(streamStateProvider(sessionId));
        return requests.isNotEmpty && state.isStreaming;
      },
      timeout: const Duration(seconds: 20),
      describe: () async => _describeStreamState(
        container: container,
        db: db,
        sessionId: sessionId,
        requestCount: requests.length,
      ),
    );

    // scripts/smoke_android_network_stream_cancel.sh watches this marker and
    // only disables network after a real in-flight stream is present.
    // ignore: avoid_print
    print('SIMICHAT_NETWORK_STREAM_CANCEL_READY');

    await _pumpUntil(
      tester,
      () async {
        final state = container.read(streamStateProvider(sessionId));
        return !state.isStreaming &&
            state.error == networkStreamingInterruptedMessage;
      },
      timeout: const Duration(seconds: 40),
      describe: () async => _describeStreamState(
        container: container,
        db: db,
        sessionId: sessionId,
        requestCount: requests.length,
      ),
    );

    final state = container.read(streamStateProvider(sessionId));
    expect(state.isStreaming, isFalse);
    expect(state.currentContent, isEmpty);
    expect(state.error, networkStreamingInterruptedMessage);
    expect(find.text(networkStreamingInterruptedMessage), findsOneWidget);
    expect(find.text('网络连接断开，已停止生成，联网后可重试'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBackgroundInterruptedSessionStorageKey), isNull);
    expect(
      prefs.getStringList(kBackgroundInterruptedSessionsStorageKey),
      isNull,
    );

    final messages = await db.messageDao.getMessagesBySession(sessionId);
    expect(messages.where((message) => message.role == 'user'), hasLength(1));
    expect(messages.where((message) => message.role == 'assistant'), isEmpty);
    expect(requests, hasLength(1));
    expect(requests.single['path'], '/v1/chat/completions');
    expect(requests.single['model'], 'network-stream-cancel-model');
    expect(requests.single['stream'], isTrue);

    // scripts/smoke_android_network_stream_cancel.sh restores Wi-Fi/data only
    // after this marker, so the following assertion proves the user-visible
    // retry affordance after a physical network recovery.
    // ignore: avoid_print
    print('SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED');

    await _pumpUntil(
      tester,
      () async => find.text('网络已恢复，可点“重试”继续').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
    );
    expect(find.text('重试'), findsWidgets);
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
        'id': 'chatcmpl-network-stream-cancel-smoke',
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
