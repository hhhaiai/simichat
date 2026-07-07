import 'dart:async';

import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'offline send keeps composer draft and does not write a user message',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.channelDao.createChannel(
        id: 'offline-channel',
        name: 'Offline OpenAI',
        baseUrl: 'https://example.invalid/v1',
        apiKeyEncrypted: KeyEncryptor.encrypt('offline-test-key'),
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'offline-model',
        channelId: 'offline-channel',
        modelName: 'offline-model',
      );
      await db.sessionDao.createSession(
        id: 'offline-session',
        defaultChannelModelId: 'offline-model',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            isOnlineProvider.overrideWithValue(false),
          ],
          child: const AiChatApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(EditableText).last,
        'offline draft 20260706',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(find.text('offline draft 20260706'), findsOneWidget);
      expect(find.text('当前网络不可用，已保留输入，联网后可重试'), findsOneWidget);
      expect(
        await db.messageDao.getMessagesBySession('offline-session'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'network restore after blocked offline send keeps draft and prompts retry',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final connectivity = StreamController<List<ConnectivityResult>>();
      addTearDown(connectivity.close);

      await db.channelDao.createChannel(
        id: 'restore-channel',
        name: 'Restore OpenAI',
        baseUrl: 'https://example.invalid/v1',
        apiKeyEncrypted: KeyEncryptor.encrypt('restore-test-key'),
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'restore-model',
        channelId: 'restore-channel',
        modelName: 'restore-model',
      );
      await db.sessionDao.createSession(
        id: 'restore-session',
        defaultChannelModelId: 'restore-model',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWith((ref) => connectivity.stream),
          ],
          child: const AiChatApp(),
        ),
      );
      connectivity.add([ConnectivityResult.none]);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(EditableText).last,
        'restore draft 20260706',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.text('restore draft 20260706'), findsOneWidget);
      expect(
        await db.messageDao.getMessagesBySession('restore-session'),
        isEmpty,
      );

      connectivity.add([ConnectivityResult.wifi]);
      await tester.pumpAndSettle();

      expect(find.text('restore draft 20260706'), findsOneWidget);
      expect(find.text('网络已恢复，可发送保留的输入'), findsOneWidget);
      expect(
        await db.messageDao.getMessagesBySession('restore-session'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'network restore prompt does not leak from blocked session to another draft',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final connectivity = StreamController<List<ConnectivityResult>>();
      addTearDown(connectivity.close);

      await db.channelDao.createChannel(
        id: 'session-scope-channel',
        name: 'Session Scope OpenAI',
        baseUrl: 'https://example.invalid/v1',
        apiKeyEncrypted: KeyEncryptor.encrypt('session-scope-test-key'),
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'session-scope-model',
        channelId: 'session-scope-channel',
        modelName: 'session-scope-model',
      );
      await db.sessionDao.createSession(
        id: 'offline-session-a',
        defaultChannelModelId: 'session-scope-model',
      );
      await db.sessionDao.createSession(
        id: 'offline-session-b',
        defaultChannelModelId: 'session-scope-model',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWith((ref) => connectivity.stream),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AiChatApp(),
        ),
      );
      connectivity.add([ConnectivityResult.none]);
      container.read(activeSessionIdProvider.notifier).state =
          'offline-session-a';
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(EditableText).last,
        'session A offline draft 20260706',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.text('当前网络不可用，已保留输入，联网后可重试'), findsOneWidget);
      expect(
        await db.messageDao.getMessagesBySession('offline-session-a'),
        isEmpty,
      );

      container.read(activeSessionIdProvider.notifier).state =
          'offline-session-b';
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(EditableText).last,
        'session B own draft 20260706',
      );
      await tester.pump();

      connectivity.add([ConnectivityResult.wifi]);
      await tester.pumpAndSettle();

      expect(find.text('session B own draft 20260706'), findsOneWidget);
      expect(find.text('网络已恢复，可发送保留的输入'), findsNothing);
      expect(
        await db.messageDao.getMessagesBySession('offline-session-a'),
        isEmpty,
      );
      expect(
        await db.messageDao.getMessagesBySession('offline-session-b'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline and restore snackbars stay on screen with mobile keyboard inset',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final connectivity = StreamController<List<ConnectivityResult>>();
      addTearDown(connectivity.close);

      await db.channelDao.createChannel(
        id: 'keyboard-inset-channel',
        name: 'Keyboard Inset OpenAI',
        baseUrl: 'https://example.invalid/v1',
        apiKeyEncrypted: KeyEncryptor.encrypt('keyboard-inset-test-key'),
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'keyboard-inset-model',
        channelId: 'keyboard-inset-channel',
        modelName: 'keyboard-inset-model',
      );
      await db.sessionDao.createSession(
        id: 'keyboard-inset-session',
        defaultChannelModelId: 'keyboard-inset-model',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWith((ref) => connectivity.stream),
          ],
          child: const AiChatApp(),
        ),
      );
      connectivity.add([ConnectivityResult.none]);
      await tester.pumpAndSettle();

      await tester.showKeyboard(find.byType(EditableText).last);
      await tester.enterText(
        find.byType(EditableText).last,
        'keyboard inset offline draft',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      var snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.fixed);

      connectivity.add([ConnectivityResult.wifi]);
      await tester.pumpAndSettle();

      expect(find.text('keyboard inset offline draft'), findsOneWidget);
      expect(find.text('网络已恢复，可发送保留的输入'), findsOneWidget);
      snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.fixed);
      expect(tester.takeException(), isNull);
    },
  );
}
