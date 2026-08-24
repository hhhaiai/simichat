import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/image_generation_service.dart';
import 'package:ai_chat_app/core/ai/image_generation_task.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/image_generation_tasks_provider.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RefCapture extends ConsumerWidget {
  const _RefCapture(this.onCapture);

  final void Function(WidgetRef ref) onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onCapture(ref);
    return const SizedBox();
  }
}

/// 绕过 dio 网络管线的 fake service：只验证占位 / 失败 / 取消流转。
class _FakeImageService extends ImageGenerationService {
  _FakeImageService({required this.behaviour, this.gate})
    : super(baseUrl: 'https://img.example.com/v1', apiKey: 'k', model: 'm');

  final String behaviour;

  /// 成功路径的可控放行门：放行前任务保持 running。
  final Completer<void>? gate;

  @override
  Future<GeneratedImage> generate(
    String prompt, {
    String? referenceImagePath,
    List<String> referenceImagePaths = const <String>[],
    int count = 1,
    Map<String, dynamic> extra = const <String, dynamic>{},
    CancelToken? cancelToken,
    String size = kImageGenerationSize,
  }) async {
    switch (behaviour) {
      case 'success':
        if (gate != null) await gate!.future;
        // 1x1 PNG 头 + 最小 IDAT/IEND，能通过 MIME 嗅探。
        return GeneratedImage(
          bytes: Uint8List.fromList([
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
            0x00,
            0x00,
            0x00,
            0x0D,
            0x49,
            0x48,
            0x44,
            0x52,
            0x00,
            0x00,
            0x00,
            0x01,
            0x00,
            0x00,
            0x00,
            0x01,
            0x08,
            0x06,
            0x00,
            0x00,
            0x00,
            0x1F,
            0x15,
            0xC4,
            0x89,
            0x00,
            0x00,
            0x00,
            0x0D,
            0x49,
            0x44,
            0x41,
            0x54,
            0x78,
            0xDA,
            0x63,
            0xFC,
            0xCF,
            0xC0,
            0x50,
            0x0F,
            0x00,
            0x04,
            0x85,
            0x01,
            0x80,
            0x84,
            0xA9,
            0x8C,
            0x21,
            0x00,
            0x00,
            0x00,
            0x00,
            0x49,
            0x45,
            0x4E,
            0x44,
            0x42,
            0x60,
            0x82,
          ]),
        );
      case 'fail':
        throw const ImageGenerationException('HTTP 401 invalid api key');
      case 'hang':
        final pending = Completer<GeneratedImage>();
        cancelToken?.whenCancel.then((_) {
          if (!pending.isCompleted) {
            pending.completeError(const ImageGenerationException('请求已取消'));
          }
        });
        return pending.future;
      default:
        throw const ImageGenerationException('unexpected behaviour');
    }
  }
}

Future<WidgetRef> _pumpBase(
  WidgetTester tester,
  AppDatabase db, {
  required String channelId,
  required String sessionId,
}) async {
  final appDirectory = Directory.systemTemp.createTempSync('img-flow-');
  addTearDown(() => appDirectory.deleteSync(recursive: true));
  final pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
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
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      null,
    );
  });

  await db.channelDao.createChannel(
    id: channelId,
    name: 'Img Channel',
    baseUrl: 'https://img.example.com/v1',
    apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: '$channelId-model',
    channelId: channelId,
    modelName: 'gpt-image-1',
    capability: 'image',
  );
  await db.sessionDao.createSession(
    id: sessionId,
    defaultChannelModelId: '$channelId-model',
  );

  WidgetRef? capturedRef;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: _RefCapture((ref) => capturedRef = ref)),
    ),
  );
  await tester.pumpAndSettle();
  return capturedRef!;
}

void main() {
  test('image task snapshots restore interrupted work as retryable', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ImageGenerationTaskSnapshotStore();
    final first = ImageGenerationTasksNotifier(
      store: store,
      taskExists: (_) async => true,
    );
    await first.ready;
    first.start(
      ImageGenerationTask(
        messageId: 'persisted-image-placeholder',
        sessionId: 'persisted-image-session',
        prompt: '保留完整的多图重试参数',
        modelName: 'grok-imagine-image-quality',
        channelId: 'image-channel',
        routeModelId: 'image-model-id',
        providerProfileId: 'xai_grok_images',
        referenceImagePaths: const ['/private/composer_drafts/reference-a.png'],
        referenceImageNames: const ['reference-a.png'],
        count: 3,
        aspectRatio: '16:9',
        resolution: '2K',
        size: '1536x1024',
        quality: 'high',
        typedOptions: true,
      ),
    );
    await store.flush();

    final restoredStore = ImageGenerationTaskSnapshotStore();
    final restored = ImageGenerationTasksNotifier(
      store: restoredStore,
      taskExists: (_) async => true,
    );
    await restored.ready;
    final task = restored.state['persisted-image-placeholder'];
    expect(task, isNotNull);
    expect(task!.isFailed, isTrue);
    expect(task.error, contains('应用重启'));
    expect(task.routeModelId, 'image-model-id');
    expect(task.providerProfileId, 'xai_grok_images');
    expect(task.referenceImagePaths, [
      '/private/composer_drafts/reference-a.png',
    ]);
    expect(task.count, 3);
    expect(task.aspectRatio, '16:9');
    expect(task.resolution, '2K');
    expect(task.size, '1536x1024');
    expect(task.quality, 'high');

    restored.markFailed(
      task.messageId,
      'Bearer secret-token https://example.test /Users/private/key',
    );
    await restoredStore.flush();
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(
      kImageGenerationTaskSnapshotsStorageKey,
    );
    expect(encoded, isNotNull);
    expect(jsonDecode(encoded!), isA<Map>());
    expect(encoded, contains('"resolution":"2K"'));
    expect(encoded, contains('"size":"1536x1024"'));
    expect(encoded, isNot(contains('secret-token')));
    expect(encoded, isNot(contains('https://example.test')));
    expect(encoded, isNot(contains('/Users/private/key')));

    restored.finish(task.messageId);
    await restoredStore.flush();
    expect(
      preferences.getString(kImageGenerationTaskSnapshotsStorageKey),
      isNull,
    );
  });

  test(
    'image task recovery drops snapshots without a placeholder message',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = ImageGenerationTaskSnapshotStore();
      final first = ImageGenerationTasksNotifier(
        store: store,
        taskExists: (_) async => true,
      );
      await first.ready;
      first.start(
        ImageGenerationTask(
          messageId: 'deleted-placeholder',
          sessionId: 'deleted-session',
          prompt: '不应恢复为幽灵任务',
          modelName: 'gpt-image-2',
          channelId: 'deleted-channel',
          providerProfileId: 'openai_images',
        ),
      );
      await store.flush();

      final restoredStore = ImageGenerationTaskSnapshotStore();
      final restored = ImageGenerationTasksNotifier(
        store: restoredStore,
        taskExists: (_) async => false,
      );
      await restored.ready;
      await restoredStore.flush();

      expect(restored.state, isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(kImageGenerationTaskSnapshotsStorageKey),
        isNull,
      );
    },
  );

  testWidgets('image generation inserts placeholder then replaces on success', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // 门控 Completer 必须在 runAsync 真实 zone 内创建：
    // fake zone 的 Completer 完成事件不会被真实 zone 消费。
    Completer<void>? gateHolder;
    debugImageServiceFactory =
        ({required baseUrl, required apiKey, required model}) =>
            _FakeImageService(behaviour: 'success', gate: gateHolder);

    final ref = await _pumpBase(
      tester,
      db,
      channelId: 'img-channel',
      sessionId: 'img-session',
    );

    // 流程放单个 runAsync 窗口：文件 IO / drift 在真实 zone 自然完成。
    await tester.runAsync(() async {
      final gate = gateHolder = Completer<void>();
      final resultFuture = generateImage(
        ref: ref,
        sessionId: 'img-session',
        prompt: '一只猫',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 放行前：占位消息已写入且任务处于 running。
      final pending = await db.messageDao.getMessagesBySession('img-session');
      final placeholders = pending
          .where((m) => m.content == '正在生成图片…')
          .toList();
      expect(placeholders.length, 1);
      final task = ref.read(
        imageGenerationTasksProvider,
      )[placeholders.first.id];
      expect(task, isNotNull);
      expect(task!.isRunning, true);

      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final error = await resultFuture;
      expect(error, isNull);

      final messages = await db.messageDao.getMessagesBySession('img-session');
      expect(messages.any((m) => m.content == '正在生成图片…'), false);
      expect(messages.any((m) => m.content == '一只猫'), true);
      expect(messages.any((m) => m.content == '已生成图片'), true);
      expect(ref.read(imageGenerationTasksProvider), isEmpty);
    });
    debugImageServiceFactory = null;
  });

  testWidgets('image result save failure keeps placeholder and retry snapshot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    debugImageServiceFactory =
        ({required baseUrl, required apiKey, required model}) =>
            _FakeImageService(behaviour: 'success');
    addTearDown(() => debugImageServiceFactory = null);

    final ref = await _pumpBase(
      tester,
      db,
      channelId: 'img-save-failure-channel',
      sessionId: 'img-save-failure-session',
    );
    final blockedRoot = File(
      '${Directory.systemTemp.path}/simichat-image-blocked-root-${DateTime.now().microsecondsSinceEpoch}',
    )..writeAsStringSync('not a directory');
    addTearDown(() {
      if (blockedRoot.existsSync()) blockedRoot.deleteSync();
    });
    const pathProviderChannel = MethodChannel(
      'plugins.flutter.io/path_provider',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => blockedRoot.path,
    );

    final error = await tester.runAsync(
      () => generateImage(
        ref: ref,
        sessionId: 'img-save-failure-session',
        prompt: '保存失败后仍可重试',
      ),
    );

    expect(error, contains('图片结果保存失败'));
    final messages = (await tester.runAsync(
      () => db.messageDao.getMessagesBySession('img-save-failure-session'),
    ))!;
    expect(messages, hasLength(1));
    final placeholder = messages.single;
    expect(placeholder.role, 'assistant');
    expect(placeholder.content, contains('图片结果保存失败'));
    final task = ref.read(imageGenerationTasksProvider)[placeholder.id];
    expect(task, isNotNull);
    expect(task!.isFailed, isTrue);
    expect(task.prompt, '保存失败后仍可重试');
    expect(task.routeModelId, 'img-save-failure-channel-model');
  });

  testWidgets('image generation failure keeps placeholder with retry task', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    debugImageServiceFactory =
        ({required baseUrl, required apiKey, required model}) =>
            _FakeImageService(behaviour: 'fail');

    final ref = await _pumpBase(
      tester,
      db,
      channelId: 'img-fail-channel',
      sessionId: 'img-fail-session',
    );

    await tester.runAsync(() async {
      final error = await generateImage(
        ref: ref,
        sessionId: 'img-fail-session',
        prompt: '一只猫',
      );
      expect(error, contains('图片生成失败'));

      final messages = await db.messageDao.getMessagesBySession(
        'img-fail-session',
      );
      final placeholder = messages.firstWhere(
        (m) => m.content.startsWith('图片生成失败'),
        orElse: () => throw StateError('缺少失败占位消息'),
      );
      expect(placeholder.content, contains('401'));
      final task = ref.read(imageGenerationTasksProvider)[placeholder.id];
      expect(task, isNotNull);
      expect(task!.isFailed, true);
      expect(task.prompt, '一只猫');
      expect(task.routeModelId, 'img-fail-channel-model');
      expect(task.compactError, isNot(contains('test-key')));
    });
    debugImageServiceFactory = null;
  });

  testWidgets('cancelling image generation updates placeholder to cancelled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    debugImageServiceFactory =
        ({required baseUrl, required apiKey, required model}) =>
            _FakeImageService(behaviour: 'hang');

    final ref = await _pumpBase(
      tester,
      db,
      channelId: 'img-cancel-channel',
      sessionId: 'img-cancel-session',
    );

    await tester.runAsync(() async {
      final resultFuture = generateImage(
        ref: ref,
        sessionId: 'img-cancel-session',
        prompt: '一只猫',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await cancelImageGeneration(ref: ref, sessionId: 'img-cancel-session');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final error = await resultFuture;
      expect(error, '已取消');

      final messages = await db.messageDao.getMessagesBySession(
        'img-cancel-session',
      );
      expect(messages.any((m) => m.content == '图片生成已取消'), true);
      expect(messages.any((m) => m.content == '已生成图片'), false);
      expect(ref.read(imageGenerationTasksProvider), isEmpty);
    });
    debugImageServiceFactory = null;
  });
}
