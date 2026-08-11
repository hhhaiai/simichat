import 'dart:io';

import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/chat/chat_page.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'image send is blocked with preserved input when channel has no vision model',
    (tester) async {
      final fixture = await _pumpChat(tester, includeVisionModel: false);
      addTearDown(fixture.dispose);

      final input = tester.widget<TextField>(find.byType(TextField));
      input.controller!.text = '请描述这张图';
      final inputBar = tester.widget<ChatInputBar>(find.byType(ChatInputBar));
      final sent = await tester.runAsync(
        () => inputBar.onSend('请描述这张图', const [
          PendingAttachment(
            path: '/not-read-without-vision.png',
            name: 'photo.png',
            type: 'image',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(sent, isFalse);
      expect(find.text('当前渠道没有支持识图的 Vision 模型，已保留图片和输入'), findsOneWidget);
      expect(input.controller!.text, '请描述这张图');
      expect(
        await fixture.db.messageDao.getMessagesBySession('vision-session'),
        isEmpty,
      );
      expect(
        (await fixture.db.sessionDao.getSession(
          'vision-session',
        ))!.defaultChannelModelId,
        'text-model',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deep think send is blocked with preserved input when channel has no reasoner',
    (tester) async {
      final fixture = await _pumpChat(tester, includeVisionModel: false);
      addTearDown(fixture.dispose);

      final input = tester.widget<TextField>(find.byType(TextField));
      input.controller!.text = '请深入分析';
      final inputBar = tester.widget<ChatInputBar>(find.byType(ChatInputBar));
      inputBar.deepThinkNotifier!.value = true;
      await tester.pump();

      final sent = await tester.runAsync(
        () => inputBar.onSend('请深入分析', const []),
      );
      await tester.pumpAndSettle();

      expect(sent, isFalse);
      expect(find.text('当前渠道没有深度思考（reasoner）模型，已保留输入'), findsOneWidget);
      expect(input.controller!.text, '请深入分析');
      expect(
        await fixture.db.messageDao.getMessagesBySession('vision-session'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deep think send automatically uses reasoner in current channel',
    (tester) async {
      final fixture = await _pumpChat(
        tester,
        includeVisionModel: false,
        includeReasonerModel: true,
      );
      addTearDown(fixture.dispose);

      final inputBar = tester.widget<ChatInputBar>(find.byType(ChatInputBar));
      inputBar.deepThinkNotifier!.value = true;
      await tester.pump();
      final sent = await tester.runAsync(
        () => inputBar.onSend('请深入分析', const []),
      );
      expect(sent, isTrue);
      expect(
        fixture.container.read(streamStateProvider('vision-session')).modelId,
        'reasoner-model',
      );
      // 走用户的“停止生成”路径收口未等待的流，避免销毁
      // WidgetRef 后仍有异步请求回调。
      expect(
        await tester.runAsync(() => inputBar.onSend('', const [])),
        isTrue,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(
        (await fixture.db.sessionDao.getSession(
          'vision-session',
        ))!.defaultChannelModelId,
        'text-model',
      );
      expect(fixture.container.read(selectedModelIdProvider), 'text-model');
      final messages = await fixture.db.messageDao.getMessagesBySession(
        'vision-session',
      );
      expect(messages.where((message) => message.role == 'user'), hasLength(1));
      expect(find.text('当前渠道没有深度思考（reasoner）模型，已保留输入'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('image send automatically uses vision model in current channel', (
    tester,
  ) async {
    final fixture = await _pumpChat(tester, includeVisionModel: true);
    addTearDown(fixture.dispose);
    final image = File('${fixture.tempDir.path}/photo.png');
    const imageBytes = [0x89, 0x50, 0x4e, 0x47];
    image.writeAsBytesSync(imageBytes);

    final inputBar = tester.widget<ChatInputBar>(find.byType(ChatInputBar));
    final sent = await tester.runAsync(
      () => inputBar.onSend('请描述这张图', [
        PendingAttachment(path: image.path, name: 'photo.png', type: 'image'),
      ]),
    );
    expect(sent, isTrue);
    expect(
      fixture.container.read(streamStateProvider('vision-session')).modelId,
      'vision-model',
    );
    expect(await tester.runAsync(() => inputBar.onSend('', const [])), isTrue);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(
      (await fixture.db.sessionDao.getSession(
        'vision-session',
      ))!.defaultChannelModelId,
      'text-model',
    );
    expect(fixture.container.read(selectedModelIdProvider), 'text-model');
    final messages = await fixture.db.messageDao.getMessagesBySession(
      'vision-session',
    );
    expect(messages.where((message) => message.role == 'user'), hasLength(1));
    expect(
      messages.singleWhere((message) => message.role == 'user').content,
      '请描述这张图',
    );
    expect(find.text('当前渠道没有支持识图的 Vision 模型，已保留图片和输入'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<_ChatFixture> _pumpChat(
  WidgetTester tester, {
  required bool includeVisionModel,
  bool includeReasonerModel = false,
  String baseUrl = 'https://example.invalid/v1',
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final tempDir = Directory.systemTemp.createTempSync('simichat_vision_guard_');
  await db.channelDao.createChannel(
    id: 'vision-channel',
    name: 'Vision Test',
    baseUrl: baseUrl,
    apiKeyEncrypted: KeyEncryptor.encrypt('vision-test-key'),
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'text-model',
    channelId: 'vision-channel',
    modelName: 'text-model-name',
    capability: ModelCapability.chat,
  );
  if (includeVisionModel) {
    await db.channelDao.addModel(
      id: 'vision-model',
      channelId: 'vision-channel',
      modelName: 'vision-model-name',
      capability: ModelCapability.vision,
    );
  }
  if (includeReasonerModel) {
    await db.channelDao.addModel(
      id: 'reasoner-model',
      channelId: 'vision-channel',
      modelName: 'reasoner-model-name',
      capability: ModelCapability.reasoner,
    );
  }
  await db.sessionDao.createSession(
    id: 'vision-session',
    defaultChannelModelId: 'text-model',
  );

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      isOnlineProvider.overrideWithValue(true),
      activeSessionIdProvider.overrideWith((ref) => 'vision-session'),
      selectedModelIdProvider.overrideWith((ref) => 'text-model'),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ChatPage())),
    ),
  );
  await tester.pumpAndSettle();
  return _ChatFixture(db: db, container: container, tempDir: tempDir);
}

class _ChatFixture {
  const _ChatFixture({
    required this.db,
    required this.container,
    required this.tempDir,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final Directory tempDir;

  Future<void> dispose() async {
    container.dispose();
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}
