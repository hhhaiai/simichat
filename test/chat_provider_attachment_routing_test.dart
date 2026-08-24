import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ai_chat_app/core/ai/attachment_helper.dart';
import 'package:ai_chat_app/core/ai/http_helper.dart';
import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:ai_chat_app/core/media/audio_transcription_service.dart';
import 'package:ai_chat_app/core/media/media_request_options.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/audio_transcription_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'chat transport preflight allows text fallback and rejects unsupported files',
    () {
      expect(
        preflightChatAttachmentTransport(
          protocol: 'openai_chat',
          attachmentTypes: const ['document'],
        ),
        isNull,
      );

      for (final type in ['pdf', 'video']) {
        final error = preflightChatAttachmentTransport(
          protocol: 'openai_chat',
          attachmentTypes: [type],
        );

        expect(error, isNotNull);
        expect(error!.attachmentType, type);
        expect(error.message, contains('消息未发送'));
        expect(error.message, anyOf(contains('真实'), contains('File API')));
      }

      expect(
        preflightChatAttachmentTransport(
          protocol: 'openai_chat',
          attachmentTypes: const ['image', 'audio'],
        ),
        isNull,
      );

      expect(
        preflightChatAttachmentTransport(
          protocol: 'openai_response',
          attachmentTypes: const ['pdf'],
          nativeAttachmentTypes: const {'image', 'pdf'},
        ),
        isNull,
      );
      expect(
        preflightChatAttachmentTransport(
          protocol: 'openai_response',
          attachmentTypes: const ['document'],
          nativeAttachmentTypes: const {'image', 'pdf', 'document'},
        ),
        isNull,
      );
      expect(
        preflightChatAttachmentTransport(
          protocol: 'openai_chat',
          attachmentTypes: const ['pdf'],
          nativeAttachmentTypes: const {'image', 'audio'},
        )?.attachmentType,
        'pdf',
      );
    },
  );

  test(
    'binds extracted text once without turning the filename into content',
    () {
      const extracted = '唯一校验文本：document-entered-context-4c9e';
      final result = fileAwareMessageContent(
        content: '请读取文件',
        extractedContents: const [extracted, extracted],
      );

      expect(result, contains('请读取文件'));
      expect(result, contains(extracted));
      expect(result, isNot(contains('report.md')));
      expect(RegExp(RegExp.escape(extracted)).allMatches(result), hasLength(1));
    },
  );

  test(
    'text fallback reserves half the input window for system and history',
    () {
      expect(singleTextFallbackTokenBudget(8192), 4096);
      expect(
        isSingleTextFallbackWithinBudget(
          content: 'x' * 3000,
          maxInputTokens: 8192,
        ),
        isTrue,
      );
      expect(
        isSingleTextFallbackWithinBudget(
          content: 'x' * 4000,
          maxInputTokens: 8192,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'document extraction failure leaves the attachment unpersisted and retryable',
    (tester) async {
      final fixture = await _createFixture(tester);
      addTearDown(fixture.dispose);
      final source = File(
        '${Directory.systemTemp.path}/simichat-binary-document-${DateTime.now().microsecondsSinceEpoch}.dat',
      );
      source.writeAsBytesSync([0x41, 0x00, 0x42]);
      addTearDown(() {
        if (source.existsSync()) source.deleteSync();
      });
      final pending = PendingAttachment(
        path: source.path,
        name: 'binary-document.dat',
        type: 'document',
      );

      final sent = await tester.runAsync(
        () => sendMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          content: '请读取文件',
          attachments: [pending],
        ),
      );

      expect(sent, isFalse);
      expect(
        fixture.container.read(streamStateProvider(fixture.sessionId)).error,
        contains('UTF-8'),
      );
      expect(
        await fixture.db.messageDao.getMessagesBySession(fixture.sessionId),
        isEmpty,
      );
      expect(await fixture.db.attachmentDao.getAllAttachments(), isEmpty);
      expect(pending.path, source.path);
      expect(pending.name, 'binary-document.dat');
    },
  );

  testWidgets(
    'oversized text attachment creates a persistent task and only one final reply',
    (tester) async {
      final fixture = await _createFixture(tester);
      addTearDown(fixture.dispose);
      debugChunkedContentRequestSender = (request, _) async {
        return request.kind == 'reduce'
            ? '长文档最终回答'
            : '分段 ${request.chunkIndex} 的事实';
      };
      addTearDown(() => debugChunkedContentRequestSender = null);
      final source = File(
        '${Directory.systemTemp.path}/simichat-large-text-document-${DateTime.now().microsecondsSinceEpoch}.md',
      );
      source.writeAsStringSync('x' * 60000);
      addTearDown(() {
        if (source.existsSync()) source.deleteSync();
      });

      final sent = await tester.runAsync(
        () => sendMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          content: '请总结这个长文档',
          attachments: [
            PendingAttachment(
              path: source.path,
              name: 'large-document.md',
              type: 'document',
            ),
          ],
        ),
      );

      expect(sent, isTrue);
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 80; attempt++) {
          final tasks = await fixture.db.chunkedContentTaskDao
              .listTasksBySession(fixture.sessionId);
          if (tasks.length == 1 && tasks.single.status == 'completed') return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('分批任务没有完成');
      });
      final tasks = await fixture.db.chunkedContentTaskDao.listTasksBySession(
        fixture.sessionId,
      );
      expect(tasks, hasLength(1));
      expect(tasks.single.status, 'completed');
      expect(tasks.single.totalChunks, greaterThan(1));
      final messages = (await tester.runAsync(
        () => fixture.db.messageDao.getMessagesBySession(fixture.sessionId),
      ))!;
      expect(messages.where((message) => message.role == 'user'), hasLength(1));
      expect(
        messages.where((message) => message.role == 'assistant'),
        hasLength(1),
      );
      expect(
        messages.singleWhere((message) => message.role == 'assistant').content,
        '长文档最终回答',
      );
      expect(await fixture.db.attachmentDao.getAllAttachments(), hasLength(1));
    },
  );

  testWidgets(
    'audio and typed text are transcribed once and sent as one chat turn',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final source = File(
        '${Directory.systemTemp.path}/simichat-joint-audio-${DateTime.now().microsecondsSinceEpoch}.m4a',
      )..writeAsBytesSync(List<int>.filled(64, 0x41));
      addTearDown(() {
        if (source.existsSync()) source.deleteSync();
      });
      final stt = _FakeSpeechToTextEngine('语音里说的内容');
      final adapter = _CapturingChatSseAdapter();
      debugDioFactory = (_) {
        final dio = Dio();
        dio.httpClientAdapter = adapter;
        return dio;
      };
      addTearDown(() {
        debugDioFactory = null;
        adapter.close(force: true);
      });
      final fixture = await _createFixture(tester, speechEngine: stt);
      addTearDown(fixture.dispose);

      final result = await tester.runAsync(() async {
        final sent = await sendMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          content: '请帮我总结',
          attachments: [
            PendingAttachment(
              path: source.path,
              name: 'recording.m4a',
              type: 'audio',
            ),
          ],
        );
        for (var attempt = 0; attempt < 80; attempt++) {
          if (adapter.payload != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        for (var attempt = 0; attempt < 80; attempt++) {
          final messages = await fixture.db.messageDao.getMessagesBySession(
            fixture.sessionId,
          );
          if (messages.any((message) => message.role == 'assistant')) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return sent;
      });

      expect(result, isTrue);
      expect(stt.calls, 1);
      expect(adapter.payload, isNotNull);
      final payloadText = jsonEncode(adapter.payload);
      expect(payloadText, contains('请帮我总结'));
      expect(payloadText, contains('语音里说的内容'));
      final messages = await fixture.db.messageDao.getMessagesBySession(
        fixture.sessionId,
      );
      final user = messages.singleWhere((message) => message.role == 'user');
      expect(user.content, contains('请帮我总结'));
      expect(user.content, contains('语音里说的内容'));
      expect(
        messages.where((message) => message.role == 'assistant'),
        hasLength(1),
      );
      expect(await fixture.db.attachmentDao.getAllAttachments(), hasLength(1));
    },
  );

  testWidgets(
    'standalone ASR archives audio and binds transcript metadata to result',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kSpeechToTextEnabledStorageKey: true,
        kSpeechToTextProviderStorageKey: kSpeechToTextProviderOpenAiCompatible,
        kSpeechToTextBaseUrlStorageKey: 'https://stt.example.test/v1',
        kSpeechToTextModelStorageKey: 'mimo-v2.5-asr',
        kSpeechToTextApiKeyStorageKey: KeyEncryptor.encrypt('asr-test-key'),
        kSpeechToTextLanguageStorageKey: 'auto',
        kSpeechToTextChannelModelIdStorageKey: 'attachment-routing-model',
      });
      final source = File(
        '${Directory.systemTemp.path}/simichat-standalone-asr-${DateTime.now().microsecondsSinceEpoch}.wav',
      )..writeAsBytesSync(List<int>.generate(96, (index) => index & 0xff));
      addTearDown(() {
        if (source.existsSync()) source.deleteSync();
      });
      final stt = _FakeSpeechToTextEngine('这是独立识别保存的正文');
      final fixture = await _createFixture(
        tester,
        modelName: 'mimo-v2.5-asr',
        capability: ModelCapability.audio,
        speechEngine: stt,
      );
      addTearDown(fixture.dispose);

      final error = await tester.runAsync(
        () => recognizeSpeechMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          audioPath: source.path,
          fileName: 'standalone.wav',
          language: SpeechRecognitionLanguage.chinese,
        ),
      );

      expect(error, isNull);
      expect(stt.calls, 1);
      final messages = await fixture.db.messageDao.getMessagesBySession(
        fixture.sessionId,
      );
      expect(messages, hasLength(2));
      final user = messages.singleWhere((message) => message.role == 'user');
      final assistant = messages.singleWhere(
        (message) => message.role == 'assistant',
      );
      expect(user.content, '识别语音：standalone.wav');
      expect(assistant.content, '这是独立识别保存的正文');
      expect(assistant.channelModelId, 'attachment-routing-model');

      final attachments = (await tester.runAsync(
        () => fixture.db.attachmentDao.getAllAttachments(),
      ))!;
      expect(attachments, hasLength(1));
      final audio = attachments.single;
      expect(audio.messageId, user.id);
      expect(audio.fileType, 'audio');
      expect(audio.fileName, 'standalone.wav');
      expect(audio.localPath, isNot(source.path));
      expect(File(audio.localPath).existsSync(), isTrue);
      expect(File(audio.localPath).readAsBytesSync(), source.readAsBytesSync());

      final details = await tester.runAsync(
        () => AudioTranscriptArchive(
          rootDirectory: fixture.root,
        ).readDetails(messageId: user.id, attachmentId: audio.id),
      );
      expect(details, isNotNull);
      expect(details!.status, AudioTranscriptStatus.ready);
      expect(details.transcriptText, '这是独立识别保存的正文');
      expect(details.modelId, 'mimo-v2.5-asr');
      expect(details.language, 'zh');
      expect(details.resultMessageId, assistant.id);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    },
  );

  testWidgets(
    'standalone ASR failure keeps no database row or archived media copy',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kSpeechToTextEnabledStorageKey: true,
        kSpeechToTextProviderStorageKey: kSpeechToTextProviderOpenAiCompatible,
        kSpeechToTextBaseUrlStorageKey: 'https://stt.example.test/v1',
        kSpeechToTextModelStorageKey: 'mimo-v2.5-asr',
        kSpeechToTextApiKeyStorageKey: KeyEncryptor.encrypt('asr-test-key'),
        kSpeechToTextLanguageStorageKey: 'auto',
        kSpeechToTextChannelModelIdStorageKey: 'attachment-routing-model',
      });
      final source = File(
        '${Directory.systemTemp.path}/simichat-failed-asr-${DateTime.now().microsecondsSinceEpoch}.wav',
      )..writeAsBytesSync(List<int>.filled(64, 0x52));
      addTearDown(() {
        if (source.existsSync()) source.deleteSync();
      });
      final fixture = await _createFixture(
        tester,
        modelName: 'mimo-v2.5-asr',
        capability: ModelCapability.audio,
        speechEngine: _ThrowingSpeechToTextEngine(),
      );
      addTearDown(fixture.dispose);

      final error = await tester.runAsync(
        () => recognizeSpeechMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          audioPath: source.path,
          fileName: 'failed.wav',
          language: SpeechRecognitionLanguage.english,
        ),
      );

      expect(error, startsWith('语音识别失败：'));
      expect(error, isNot(contains('secret.example.test')));
      expect(error, isNot(contains('sk-sensitive-token')));
      expect(error, isNot(contains('/Users/private/source.wav')));
      final databaseState = await tester.runAsync(() async {
        return (
          messages: await fixture.db.messageDao.getMessagesBySession(
            fixture.sessionId,
          ),
          attachments: await fixture.db.attachmentDao.getAllAttachments(),
        );
      });
      expect(databaseState, isNotNull);
      expect(databaseState!.messages, isEmpty);
      expect(databaseState.attachments, isEmpty);
      expect(source.existsSync(), isTrue, reason: 'Composer 原始草稿仍应可重试');

      final leftoverFiles = fixture.root.existsSync()
          ? fixture.root
                .listSync(recursive: true)
                .whereType<File>()
                .where(
                  (file) =>
                      file.path.contains('audio_files') ||
                      file.path.contains('audio_transcripts'),
                )
                .toList()
          : const <File>[];
      expect(leftoverFiles, isEmpty);
    },
  );

  testWidgets(
    'verified Responses document uses native file input without text duplication',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _CapturingResponsesSseAdapter();
      debugDioFactory = (_) {
        final dio = Dio();
        dio.httpClientAdapter = adapter;
        return dio;
      };
      addTearDown(() {
        debugDioFactory = null;
        adapter.close(force: true);
      });
      final fixture = await _createFixture(
        tester,
        protocol: 'openai_response',
        modelName: 'gpt-responses-file-test',
        baseUrl: 'https://responses-file.test/v1',
        sessionTitle: '原生文件传输测试',
      );
      addTearDown(fixture.dispose);
      final source = File(
        '${Directory.systemTemp.path}/simichat-native-document-${DateTime.now().microsecondsSinceEpoch}.md',
      );
      const documentText = '# 不应重复进入 input_text\n\n只作为原生文件发送。';
      source.writeAsStringSync(documentText);
      addTearDown(() {
        if (source.existsSync()) source.deleteSync();
      });

      final result = await tester
          .runAsync<
            ({bool sent, Map<String, dynamic> payload, bool assistantWritten})
          >(() async {
            final sent = await sendMessage(
              ref: fixture.ref,
              sessionId: fixture.sessionId,
              content: '请总结这份文档',
              attachments: [
                PendingAttachment(
                  path: source.path,
                  name: '报告.md',
                  type: 'document',
                ),
              ],
            );
            Map<String, dynamic>? payload;
            for (var attempt = 0; attempt < 80; attempt++) {
              payload = adapter.payload;
              if (payload != null) break;
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            if (payload == null) {
              throw StateError('Responses 原生文件请求没有到达协议 adapter');
            }
            var assistantWritten = false;
            for (var attempt = 0; attempt < 50; attempt++) {
              final messages = await fixture.db.messageDao.getMessagesBySession(
                fixture.sessionId,
              );
              if (messages.any((message) => message.role == 'assistant')) {
                assistantWritten = true;
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            return (
              sent: sent,
              payload: payload,
              assistantWritten: assistantWritten,
            );
          });

      expect(result, isNotNull);
      final completed = result!;
      expect(completed.sent, isTrue);
      final payload = completed.payload;
      final fileBearingInput = (payload['input'] as List)
          .whereType<Map>()
          .singleWhere(
            (input) =>
                input['role'] == 'user' &&
                (input['content'] as List?)?.any(
                      (part) => part is Map && part['type'] == 'input_file',
                    ) ==
                    true,
          );
      final content = fileBearingInput['content'] as List;
      expect(content.first, {'type': 'input_text', 'text': '请总结这份文档'});
      final filePart = content.last as Map;
      expect(filePart['type'], 'input_file');
      expect(filePart['filename'], '报告.md');
      expect(
        filePart['file_data'],
        'data:text/markdown;base64,${base64Encode(utf8.encode(documentText))}',
      );
      expect(jsonEncode(content), isNot(contains(documentText)));
      expect(await fixture.db.attachmentDao.getAllAttachments(), hasLength(1));
      expect(
        completed.assistantWritten,
        isTrue,
        reason: 'Responses 原生文件请求没有写入最终回复',
      );
    },
  );

  testWidgets(
    'direct send preflight rejects unsupported files before persistence',
    (tester) async {
      final fixture = await _createFixture(tester);
      addTearDown(fixture.dispose);

      for (final attachment in const [
        PendingAttachment(
          path: '/not-read/report.pdf',
          name: 'report.pdf',
          type: 'pdf',
        ),
        PendingAttachment(
          path: '/not-read/movie.mp4',
          name: 'movie.mp4',
          type: 'video',
        ),
      ]) {
        final sent = await tester.runAsync(
          () => sendMessage(
            ref: fixture.ref,
            sessionId: fixture.sessionId,
            content: '请读取这个附件',
            attachments: [attachment],
          ),
        );

        expect(sent, isFalse);
      }

      expect(
        await fixture.db.messageDao.getMessagesBySession(fixture.sessionId),
        isEmpty,
      );
      expect(await fixture.db.attachmentDao.getAllAttachments(), isEmpty);
      final error = fixture.container
          .read(streamStateProvider(fixture.sessionId))
          .error;
      expect(error, contains('消息未发送'));
    },
  );

  testWidgets('direct image send keeps Vision preflight inside sendMessage', (
    tester,
  ) async {
    final fixture = await _createFixture(tester);
    addTearDown(fixture.dispose);

    final sent = await tester.runAsync(
      () => sendMessage(
        ref: fixture.ref,
        sessionId: fixture.sessionId,
        content: '请描述图片',
        attachments: const [
          PendingAttachment(
            path: '/not-read/photo.png',
            name: 'photo.png',
            type: 'image',
          ),
        ],
      ),
    );

    expect(sent, isFalse);
    expect(
      fixture.container.read(streamStateProvider(fixture.sessionId)).error,
      contains('不支持图片输入'),
    );
    expect(
      await fixture.db.messageDao.getMessagesBySession(fixture.sessionId),
      isEmpty,
    );
    expect(await fixture.db.attachmentDao.getAllAttachments(), isEmpty);
  });

  testWidgets(
    'reuse/regenerate preflight rejects persisted unsupported attachments',
    (tester) async {
      final fixture = await _createFixture(tester);
      addTearDown(fixture.dispose);

      await fixture.db.messageDao.insertMessage(
        id: 'reuse-user',
        sessionId: fixture.sessionId,
        role: 'user',
        content: '旧消息',
      );
      await fixture.db.attachmentDao.insertAttachment(
        id: 'reuse-pdf',
        messageId: 'reuse-user',
        fileType: 'pdf',
        localPath: '/not-read/reuse.pdf',
        fileName: 'reuse.pdf',
        fileSize: 1,
      );

      final sent = await tester.runAsync(
        () => sendMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          content: 'ignored on reuse',
          reuseUserMessageId: 'reuse-user',
        ),
      );

      expect(sent, isFalse);
      final messages = await fixture.db.messageDao.getMessagesBySession(
        fixture.sessionId,
      );
      expect(messages.where((message) => message.role == 'user'), hasLength(1));
      expect(messages.where((message) => message.role == 'assistant'), isEmpty);
      expect(
        fixture.container.read(streamStateProvider(fixture.sessionId)).error,
        contains('PDF'),
      );
    },
  );

  testWidgets(
    'provider preflight rejects exact Mimo Responses PDF before persistence',
    (tester) async {
      final fixture = await _createFixture(
        tester,
        protocol: 'openai_response',
        modelName: 'mimo-v2.5-chat',
      );
      addTearDown(fixture.dispose);

      final sent = await tester.runAsync(
        () => sendMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          content: '请读取 PDF',
          attachments: const [
            PendingAttachment(
              path: '/not-read/mimo-report.pdf',
              name: 'mimo-report.pdf',
              type: 'pdf',
            ),
          ],
        ),
      );

      expect(sent, isFalse);
      expect(
        fixture.container.read(streamStateProvider(fixture.sessionId)).error,
        contains('未验证 PDF 原生 File 契约'),
      );
      expect(
        await fixture.db.messageDao.getMessagesBySession(fixture.sessionId),
        isEmpty,
      );
      expect(await fixture.db.attachmentDao.getAllAttachments(), isEmpty);
    },
  );

  testWidgets('composer keeps text and attachment when preflight rejects', (
    tester,
  ) async {
    final fixture = await _createFixture(tester);
    addTearDown(fixture.dispose);

    final controller = TextEditingController(text: '请读取这个文件');
    final focusNode = FocusNode();
    final hasText = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(hasText.dispose);
    const pending = PendingAttachment(
      id: 'draft-report',
      path: '/not-read/report.pdf',
      name: 'report.pdf',
      type: 'pdf',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, widgetRef, child) => ChatInputBar(
                sessionId: fixture.sessionId,
                controller: controller,
                focusNode: focusNode,
                isStreaming: false,
                hasTextNotifier: hasText,
                initialAttachments: const [pending],
                showImageAttachmentPreviews: false,
                onSend: (text, attachments) => sendMessage(
                  ref: widgetRef,
                  sessionId: fixture.sessionId,
                  content: text,
                  attachments: attachments,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(controller.text, '请读取这个文件');
    expect(
      find.byKey(const ValueKey('pending-attachment-draft-report')),
      findsOneWidget,
    );
    expect(
      await fixture.db.messageDao.getMessagesBySession(fixture.sessionId),
      isEmpty,
    );
    expect(
      fixture.container.read(streamStateProvider(fixture.sessionId)).error,
      contains('消息未发送'),
    );
  });
}

Future<_AttachmentFixture> _createFixture(
  WidgetTester tester, {
  String protocol = 'openai_chat',
  String modelName = 'plain-chat-model',
  String capability = ModelCapability.chat,
  String baseUrl = 'https://example.invalid/v1',
  String? sessionTitle,
  SpeechToTextEngine? speechEngine,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final appDirectory = Directory.systemTemp.createTempSync(
    'simichat_attachment_routing_app_data_',
  );
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    pathProviderChannel,
    (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getTemporaryDirectory':
          return appDirectory.path;
        default:
          return null;
      }
    },
  );
  const sessionId = 'attachment-routing-session';
  await db.channelDao.createChannel(
    id: 'attachment-routing-channel',
    name: 'Attachment Routing',
    baseUrl: baseUrl,
    apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
    protocol: protocol,
  );
  await db.channelDao.addModel(
    id: 'attachment-routing-model',
    channelId: 'attachment-routing-channel',
    modelName: modelName,
    capability: capability,
  );
  await db.sessionDao.createSession(
    id: sessionId,
    defaultChannelModelId: 'attachment-routing-model',
  );
  if (sessionTitle != null) {
    await db.sessionDao.updateTitle(sessionId, sessionTitle);
  }

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      if (speechEngine != null)
        speechToTextEngineProvider.overrideWithValue(speechEngine),
    ],
  );
  late WidgetRef ref;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, widgetRef, child) {
            ref = widgetRef;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await appDirectory.exists()) {
      await appDirectory.delete(recursive: true);
    }
  });
  return _AttachmentFixture(
    db: db,
    container: container,
    ref: ref,
    sessionId: sessionId,
    root: appDirectory,
  );
}

class _AttachmentFixture {
  const _AttachmentFixture({
    required this.db,
    required this.container,
    required this.ref,
    required this.sessionId,
    required this.root,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final WidgetRef ref;
  final String sessionId;
  final Directory root;

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

class _FakeSpeechToTextEngine implements SpeechToTextEngine {
  _FakeSpeechToTextEngine(this.transcript);

  final String transcript;
  int calls = 0;

  @override
  Future<String> transcribe(
    AudioTranscriptionInput input, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    return transcript;
  }
}

class _ThrowingSpeechToTextEngine implements SpeechToTextEngine {
  @override
  Future<String> transcribe(
    AudioTranscriptionInput input, {
    CancelToken? cancelToken,
  }) {
    throw StateError(
      'upstream https://secret.example.test/v1 '
      'Bearer sk-sensitive-token /Users/private/source.wav',
    );
  }
}

class _CapturingChatSseAdapter implements HttpClientAdapter {
  Map<String, dynamic>? payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final requestBody = options.data;
    if (payload == null && requestBody is String) {
      payload = jsonDecode(requestBody) as Map<String, dynamic>;
    }
    return ResponseBody.fromBytes(
      utf8.encode(
        'data: {"choices":[{"delta":{"content":"联合回复"}}]}\n\n'
        'data: [DONE]\n\n',
      ),
      200,
      headers: const {
        'content-type': ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CapturingResponsesSseAdapter implements HttpClientAdapter {
  Map<String, dynamic>? payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (payload == null) {
      final requestBody = options.data;
      payload = requestBody is String
          ? jsonDecode(requestBody) as Map<String, dynamic>
          : (requestBody as Map).cast<String, dynamic>();
    }
    return ResponseBody.fromBytes(
      utf8.encode(
        'data: {"type":"response.output_text.delta","delta":"read"}\n\n'
        'data: {"type":"response.completed","response":{"output":[]}}\n\n',
      ),
      200,
      headers: const {
        'content-type': ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
