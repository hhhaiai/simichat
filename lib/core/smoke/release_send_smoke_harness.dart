import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../crypto/key_encryptor.dart';
import '../database/app_database.dart';
import '../ai/model_switch_record.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/session_provider.dart';

const releaseSendSmokeEnabled = bool.fromEnvironment(
  'SIMICHAT_RELEASE_SEND_SMOKE',
);
const _releaseSmokeRunId = String.fromEnvironment(
  'SIMICHAT_RELEASE_SMOKE_RUN_ID',
  defaultValue: 'manual',
);

const _smokeChannelId = 'ios-release-smoke-channel';
const _smokeModelId = 'ios-release-smoke-model';
const _smokeModelBId = 'ios-release-smoke-model-b';
const _smokeSessionId = 'ios-release-smoke-session';
const _smokeModelName = 'ios-release-smoke-model';
const _smokeModelBName = 'ios-release-smoke-model-b';
const _smokeModelLabel = 'iOS Release Smoke OpenAI / ios-release-smoke-model';
const _smokeModelBLabel =
    'iOS Release Smoke OpenAI / ios-release-smoke-model-b';
const _smokePrompt = 'ios release send smoke';
const _smokeSwitchPrompt = 'ios release model switch smoke';
const _smokeStopPrompt = 'ios release stop smoke';
const _smokeReply = 'IOS release smoke reply 20260706';
const _smokeSwitchReply = 'IOS release switched reply 20260706';
const _smokeSlowPrefix = 'IOS slow chunk';

Future<void> runReleaseSendSmokeApp({required Widget child}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await _deleteStaleSmokeArchive();
  await _writeSmokeResult({'status': 'starting'});
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: _ReleaseSendSmokeBootstrap(db: db, child: child),
    ),
  );
}

class _ReleaseSendSmokeBootstrap extends ConsumerStatefulWidget {
  const _ReleaseSendSmokeBootstrap({required this.db, required this.child});

  final AppDatabase db;
  final Widget child;

  @override
  ConsumerState<_ReleaseSendSmokeBootstrap> createState() =>
      _ReleaseSendSmokeBootstrapState();
}

class _ReleaseSendSmokeBootstrapState
    extends ConsumerState<_ReleaseSendSmokeBootstrap> {
  bool _started = false;
  HttpServer? _server;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_started) {
        _started = true;
        unawaited(_runSmoke());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_server?.close(force: true));
    unawaited(widget.db.close());
    super.dispose();
  }

  Future<void> _runSmoke() async {
    final requests = <Map<String, Object?>>[];
    try {
      await _writeSmokeStage('start');
      _server = await _startOpenAiMockServer(requests: requests);
      await _writeSmokeStage('server_started');
      await _seedSmokeDatabase(widget.db, _server!.port);
      await _writeSmokeStage('database_seeded');
      ref.read(activeSessionIdProvider.notifier).state = _smokeSessionId;

      final accepted = await sendMessage(
        ref: ref,
        sessionId: _smokeSessionId,
        content: _smokePrompt,
      );
      if (!accepted) {
        throw StateError('sendMessage returned false');
      }
      await _writeSmokeStage('initial_send_accepted', requests: requests);

      final firstAssistants = await _waitForAssistantMessages(
        widget.db,
        count: 1,
      );
      await _writeSmokeStage('initial_reply_received', requests: requests);
      final assistant = firstAssistants.single;
      final userMessages = (await widget.db.messageDao.getMessagesBySession(
        _smokeSessionId,
      )).where((message) => message.role == 'user').toList();

      if (assistant.content != _smokeReply) {
        throw StateError('unexpected assistant content: ${assistant.content}');
      }
      if (userMessages.length != 1 ||
          userMessages.single.content != _smokePrompt) {
        throw StateError('unexpected user message count or content');
      }
      if (requests.length != 1) {
        throw StateError('unexpected mock request count: ${requests.length}');
      }
      final request = requests.single;
      if (request['path'] != '/v1/chat/completions' ||
          request['model'] != _smokeModelName ||
          request['stream'] != true ||
          request['lastUser'] != _smokePrompt) {
        throw StateError('unexpected mock request: ${jsonEncode(request)}');
      }

      await ref.read(messagesProvider(_smokeSessionId).future);
      retryLastUserMessage(ref, sessionId: _smokeSessionId);
      await _writeSmokeStage('retry_started', requests: requests);
      final retryAssistants = await _waitForAssistantMessages(
        widget.db,
        count: 2,
      );
      await _writeSmokeStage('retry_reply_received', requests: requests);
      final retryRequests = requests
          .where((request) => request['lastUser'] == _smokePrompt)
          .toList(growable: false);
      if (retryRequests.length != 2 ||
          retryAssistants.last.content != _smokeReply ||
          retryAssistants.last.channelModelId != _smokeModelId) {
        throw StateError('retry smoke did not repeat the last user message');
      }

      final switchResult = await switchConversationModel(
        ref: ref,
        modelId: _smokeModelBId,
        modelLabel: _smokeModelBLabel,
        previousModelId: _smokeModelId,
        previousModelLabel: _smokeModelLabel,
      );
      final switchedSession = await widget.db.sessionDao.getSession(
        _smokeSessionId,
      );
      final modelSwitchRecords =
          (await widget.db.messageDao.getMessagesBySession(_smokeSessionId))
              .where(
                (message) => message.messageType == kModelSwitchMessageType,
              )
              .toList(growable: false);
      if (!switchResult.changed ||
          !switchResult.recorded ||
          switchedSession?.defaultChannelModelId != _smokeModelBId ||
          modelSwitchRecords.length != 1) {
        throw StateError('model switch smoke failed');
      }
      await _writeSmokeStage('model_switched', requests: requests);

      final switchAccepted = await sendMessage(
        ref: ref,
        sessionId: _smokeSessionId,
        content: _smokeSwitchPrompt,
      );
      if (!switchAccepted) {
        throw StateError('model switch sendMessage returned false');
      }
      await _writeSmokeStage('switch_send_accepted', requests: requests);
      final switchAssistants = await _waitForAssistantMessages(
        widget.db,
        count: 3,
      );
      await _writeSmokeStage('switch_reply_received', requests: requests);
      final switchRequest = requests.lastWhere(
        (request) => request['lastUser'] == _smokeSwitchPrompt,
      );
      if (switchAssistants.last.content != _smokeSwitchReply ||
          switchAssistants.last.channelModelId != _smokeModelBId ||
          switchRequest['model'] != _smokeModelBName) {
        throw StateError('switched model send smoke failed');
      }

      final stopAccepted = await sendMessage(
        ref: ref,
        sessionId: _smokeSessionId,
        content: _smokeStopPrompt,
      );
      if (!stopAccepted) {
        throw StateError('stop sendMessage returned false');
      }
      await _writeSmokeStage('stop_send_accepted', requests: requests);
      final stopRequest = await _waitForRequest(
        requests,
        lastUser: _smokeStopPrompt,
      );
      await _writeSmokeStage('stop_request_seen', requests: requests);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      cancelStreaming(ref, _smokeSessionId);
      await _writeSmokeStage('stop_cancel_called', requests: requests);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final afterStopMessages = await widget.db.messageDao.getMessagesBySession(
        _smokeSessionId,
      );
      final stopAssistantMessages = afterStopMessages
          .where(
            (message) =>
                message.role == 'assistant' &&
                message.content.contains(_smokeSlowPrefix),
          )
          .toList(growable: false);
      if (stopRequest['completed'] == true ||
          stopAssistantMessages.any(
            (message) => message.content.contains('$_smokeSlowPrefix 6'),
          ) ||
          ref.read(streamStateProvider(_smokeSessionId)).isStreaming) {
        throw StateError(
          'stop smoke did not cancel the slow upstream request: '
          '${jsonEncode(stopRequest)}',
        );
      }
      await _writeSmokeStage('stop_verified', requests: requests);

      await _writeSmokeResult({
        'status': 'passed',
        'reply': assistant.content,
        'assistantChannelModelId': assistant.channelModelId,
        'request': request,
        'userMessageCount': userMessages.length,
        'checks': {
          'initialSend': {
            'reply': assistant.content,
            'model': request['model'],
          },
          'retry': {
            'requestCountForInitialPrompt': retryRequests.length,
            'assistantCountAfterRetry': retryAssistants.length,
            'lastReply': retryAssistants.last.content,
          },
          'modelSwitch': {
            'changed': switchResult.changed,
            'recorded': switchResult.recorded,
            'sessionDefaultModelId': switchedSession?.defaultChannelModelId,
            'timelineRecordCount': modelSwitchRecords.length,
            'requestModel': switchRequest['model'],
            'reply': switchAssistants.last.content,
          },
          'stop': {
            'assistantMessageCount': stopAssistantMessages.length,
            'partialReply': stopAssistantMessages.isEmpty
                ? ''
                : stopAssistantMessages.last.content,
            'requestModel': stopRequest['model'],
            'requestCompleted': stopRequest['completed'],
            'requestBrokenPipe': stopRequest['brokenPipe'],
          },
        },
      });
    } catch (error, stackTrace) {
      await _writeSmokeResult({
        'status': 'failed',
        'error': error.toString(),
        'stack': stackTrace.toString().split('\n').take(12).join('\n'),
        'requests': requests,
      });
    } finally {
      await _server?.close(force: true);
      _server = null;
      await _deleteStaleSmokeArchive();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _seedSmokeDatabase(AppDatabase db, int port) async {
  await db.channelDao.createChannel(
    id: _smokeChannelId,
    name: 'iOS Release Smoke OpenAI',
    baseUrl: 'http://127.0.0.1:$port',
    apiKeyEncrypted: KeyEncryptor.encrypt('test-api-key'),
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: _smokeModelId,
    channelId: _smokeChannelId,
    modelName: _smokeModelName,
  );
  await db.channelDao.addModel(
    id: _smokeModelBId,
    channelId: _smokeChannelId,
    modelName: _smokeModelBName,
  );
  await db.sessionDao.createSession(
    id: _smokeSessionId,
    defaultChannelModelId: _smokeModelId,
  );
  await db.sessionDao.updateTitle(_smokeSessionId, 'iOS release 发送 smoke');
}

Future<HttpServer> _startOpenAiMockServer({
  required List<Map<String, Object?>> requests,
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
      final lastUser = messages.reversed.firstWhere(
        (message) => message['role'] == 'user',
      )['content'];
      final requestRecord = <String, Object?>{
        'path': request.uri.path,
        'model': decoded['model'],
        'stream': decoded['stream'],
        'lastUser': lastUser,
        'completed': false,
        'brokenPipe': false,
      };
      requests.add(requestRecord);

      request.response.statusCode = HttpStatus.ok;
      request.response.bufferOutput = false;
      request.response.headers
        ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      if (lastUser == _smokeStopPrompt) {
        await _writeSlowSmokeResponse(
          response: request.response,
          model: decoded['model'].toString(),
          requestRecord: requestRecord,
        );
        return;
      }

      final reply = lastUser == _smokeSwitchPrompt
          ? _smokeSwitchReply
          : _smokeReply;
      await _writeSmokeResponseChunk(
        response: request.response,
        model: decoded['model'].toString(),
        content: reply,
      );
      request.response.write('data: [DONE]\n\n');
      requestRecord['completed'] = true;
      await request.response.close();
    }),
  );
  return server;
}

Future<void> _writeSlowSmokeResponse({
  required HttpResponse response,
  required String model,
  required Map<String, Object?> requestRecord,
}) async {
  try {
    for (var i = 1; i <= 6; i++) {
      await _writeSmokeResponseChunk(
        response: response,
        model: model,
        content: '$_smokeSlowPrefix $i ',
      );
      await response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    response.write('data: [DONE]\n\n');
    requestRecord['completed'] = true;
    await response.close();
  } catch (error) {
    requestRecord['brokenPipe'] = true;
    requestRecord['error'] = error.toString();
    try {
      await response.close();
    } catch (_) {
      // 客户端已取消时关闭响应可能再次失败，忽略即可。
    }
  }
}

Future<void> _writeSmokeResponseChunk({
  required HttpResponse response,
  required String model,
  required String content,
}) async {
  final payload = {
    'id': 'chatcmpl-ios-release-smoke',
    'object': 'chat.completion.chunk',
    'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'model': model,
    'choices': [
      {
        'index': 0,
        'delta': {'content': content},
        'finish_reason': null,
      },
    ],
  };
  response.write('data: ${jsonEncode(payload)}\n\n');
}

Future<List<Message>> _waitForAssistantMessages(
  AppDatabase db, {
  required int count,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final messages = await db.messageDao.getMessagesBySession(_smokeSessionId);
    final assistantMessages = messages
        .where((message) => message.role == 'assistant')
        .toList(growable: false);
    if (assistantMessages.length >= count) return assistantMessages;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException(
    'Timed out waiting for $count release smoke assistant replies',
  );
}

Future<Map<String, Object?>> _waitForRequest(
  List<Map<String, Object?>> requests, {
  required String lastUser,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    for (final request in requests.reversed) {
      if (request['lastUser'] == lastUser) {
        return request;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  throw TimeoutException('Timed out waiting for smoke request: $lastUser');
}

Future<File> _smokeResultFile() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(
    p.join(dir.path, 'ai_chat', 'release_smoke', 'ios-release-send-smoke.json'),
  );
  await file.parent.create(recursive: true);
  return file;
}

Future<void> _deleteStaleSmokeArchive() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(dir.path, 'conversations', 'ios-release-smoke-session.md'),
    );
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Smoke 清理失败不能覆盖主取证结果；下一次 smoke 会再次尝试清理。
  }
}

Future<void> _writeSmokeResult(Map<String, Object?> payload) async {
  final file = await _smokeResultFile();
  final enriched = <String, Object?>{
    'kind': 'ios_release_send_smoke',
    'runId': _releaseSmokeRunId,
    'timestamp': DateTime.now().toIso8601String(),
    'platform': Platform.operatingSystem,
    ...payload,
  };
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(enriched),
  );
}

Future<void> _writeSmokeStage(
  String stage, {
  List<Map<String, Object?>> requests = const [],
}) async {
  await _writeSmokeResult({
    'status': 'running',
    'stage': stage,
    if (requests.isNotEmpty) 'requests': requests,
  });
}
