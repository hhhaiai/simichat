import 'package:ai_chat_app/core/context/chunked_content_task.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/database/dao/chunked_content_task_dao.dart';
import 'package:ai_chat_app/features/chat/chat_page.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('active long-content card stops the persisted task', (
    tester,
  ) async {
    final fixture = await _ChatTaskFixture.create();
    addTearDown(fixture.dispose);
    final task = await fixture.createTask(id: 'active-task');

    await fixture.pump(tester);

    expect(
      find.byKey(ValueKey('chunked-content-task-${task.id}')),
      findsOneWidget,
    );
    expect(find.text('长内容 · 分析整合'), findsOneWidget);
    expect(
      find.byKey(ValueKey('chunked-content-stop-${task.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('chunked-content-continue-${task.id}')),
      findsNothing,
    );

    await tester.tap(find.byKey(ValueKey('chunked-content-stop-${task.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final saved = await fixture.db.chunkedContentTaskDao.getTask(task.id);
    expect(saved!.status, chunkedContentCancelledStatus);
    expect(
      find.byKey(ValueKey('chunked-content-continue-${task.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('chunked-content-restart-${task.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed long-content card keeps retry actions visible', (
    tester,
  ) async {
    final fixture = await _ChatTaskFixture.create();
    addTearDown(fixture.dispose);
    final task = await fixture.createTask(id: 'failed-task');
    await fixture.db.chunkedContentTaskDao.markInterrupted(task.id);

    await fixture.pump(tester);

    expect(
      find.byKey(ValueKey('chunked-content-task-${task.id}')),
      findsOneWidget,
    );
    expect(find.text('应用已中断任务，可继续未完成部分或从头重试'), findsOneWidget);
    expect(
      find.byKey(ValueKey('chunked-content-continue-${task.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('chunked-content-restart-${task.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('chunked-content-stop-${task.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unavailable retry prerequisites never turn failed task into orphaned running card',
    (tester) async {
      final fixture = await _ChatTaskFixture.create();
      addTearDown(fixture.dispose);
      final task = await fixture.createTask(
        id: 'missing-model-task',
        channelModelId: 'removed-model',
      );
      await fixture.db.chunkedContentTaskDao.markInterrupted(task.id);

      await fixture.pump(tester);
      await tester.tap(
        find.byKey(ValueKey('chunked-content-continue-${task.id}')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      final saved = await fixture.db.chunkedContentTaskDao.getTask(task.id);
      expect(saved!.status, chunkedContentFailedStatus);
      expect(
        find.byKey(ValueKey('chunked-content-continue-${task.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('chunked-content-stop-${task.id}')),
        findsNothing,
      );
      expect(find.text('无法继续该长内容任务；请确认原始附件和提交时模型仍可用。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ChatTaskFixture {
  _ChatTaskFixture._(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;

  static const sessionId = 'chunked-card-session';
  static const channelId = 'chunked-card-channel';
  static const modelId = 'chunked-card-model';

  static Future<_ChatTaskFixture> create() async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.channelDao.createChannel(
      id: channelId,
      name: 'Chunked task card channel',
      baseUrl: 'https://example.test/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('chunked-card-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: modelId,
      channelId: channelId,
      modelName: 'chunked-card-model-name',
    );
    await db.sessionDao.createSession(
      id: sessionId,
      defaultChannelModelId: modelId,
    );
    await db.messageDao.insertMessage(
      id: 'chunked-card-source-message',
      sessionId: sessionId,
      role: 'user',
      content: '请分析附件',
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        activeSessionIdProvider.overrideWith((ref) => sessionId),
        selectedModelIdProvider.overrideWith((ref) => modelId),
      ],
    );
    await container.read(mcpManagerProvider.notifier).ready;
    return _ChatTaskFixture._(db, container);
  }

  Future<ChunkedContentTask> createTask({
    required String id,
    String channelModelId = modelId,
  }) {
    return db.chunkedContentTaskDao.createTask(
      id: id,
      sessionId: sessionId,
      sourceMessageId: 'chunked-card-source-message',
      sourceAttachmentId: '$id-source',
      originalPrompt: '请分析附件',
      channelModelId: channelModelId,
      providerId: 'openai_chat',
      strategy: ChunkedContentStrategy.mapReduce,
      requestSnapshot: ChunkedContentRequestSnapshot(
        protocol: 'openai_chat',
        modelName: 'chunked-card-model-name',
        maxInputTokens: 8000,
        targetChunkTokens: 3600,
        overlapTokens: 360,
        sourceAttachmentIds: ['$id-source'],
      ),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChatPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}
