import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/creation_mode_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'image quality aspect ratio clarity and pixel-size summaries are independently selectable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.channelDao.createChannel(
        id: 'image-parameter-channel',
        name: 'Image parameter channel',
        baseUrl: 'https://example.invalid/v1',
        apiKeyEncrypted: 'test-only',
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'image-parameter-chat',
        channelId: 'image-parameter-channel',
        modelName: 'gpt-5.3-codex-spark',
      );
      await db.channelDao.addModel(
        id: 'image-parameter-image',
        channelId: 'image-parameter-channel',
        modelName: 'gpt-image-2',
        capability: 'image',
      );
      await db.sessionDao.createSession(
        id: 'image-parameter-session',
        defaultChannelModelId: 'image-parameter-chat',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          isOnlineProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      container.read(activeSessionIdProvider.notifier).state =
          'image-parameter-session';
      container.read(selectedModelIdProvider.notifier).state =
          'image-parameter-chat';
      container.read(activeCreationModelIdProvider.notifier).state =
          'image-parameter-image';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AiChatApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '生成参数验收图片');
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成图片').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('image-quality-summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('image-aspect-ratio-summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('image-resolution-summary')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('image-size-summary')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('image-quality-summary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('image-option-quality-high')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('image-aspect-ratio-summary')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('image-option-aspect_ratio-16:9')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('image-resolution-summary')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('image-option-resolution-2K')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('image-size-summary')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('image-option-size-1536x1024')),
      );
      await tester.pumpAndSettle();

      expect(find.text('质量 · 高'), findsOneWidget);
      expect(find.text('宽高比 · 16:9'), findsOneWidget);
      expect(find.text('清晰度 · 2K'), findsOneWidget);
      expect(find.text('分辨率 · 1536x1024'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
