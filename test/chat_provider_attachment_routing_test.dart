import 'dart:io';

import 'package:ai_chat_app/core/ai/attachment_helper.dart';
import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  const sessionId = 'attachment-routing-session';
  await db.channelDao.createChannel(
    id: 'attachment-routing-channel',
    name: 'Attachment Routing',
    baseUrl: 'https://example.invalid/v1',
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

  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
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
  return _AttachmentFixture(
    db: db,
    container: container,
    ref: ref,
    sessionId: sessionId,
  );
}

class _AttachmentFixture {
  const _AttachmentFixture({
    required this.db,
    required this.container,
    required this.ref,
    required this.sessionId,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final WidgetRef ref;
  final String sessionId;

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}
