import 'dart:io';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:ai_chat_app/features/chat/chat_page.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'audio transcript details expose metadata and reusable composer actions',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final root = Directory.systemTemp.createTempSync(
        'simichat-transcript-actions-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider,
        (call) async => root.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pathProvider,
          null,
        ),
      );

      final audio = File('${root.path}/archived-source.wav')
        ..writeAsBytesSync(List<int>.filled(80, 0x53));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.sessionDao.createSession(id: 'transcript-session');
      await db.messageDao.insertMessage(
        id: 'transcript-user-message',
        sessionId: 'transcript-session',
        role: 'user',
        content: '识别语音：archived-source.wav',
      );
      await db.attachmentDao.insertAttachment(
        id: 'transcript-audio-attachment',
        messageId: 'transcript-user-message',
        fileType: 'audio',
        localPath: audio.path,
        fileName: 'archived-source.wav',
        fileSize: audio.lengthSync(),
      );
      await db.messageDao.insertMessage(
        id: 'transcript-result-message',
        sessionId: 'transcript-session',
        role: 'assistant',
        content: '这是一段可以继续使用的语音转写。',
        channelModelId: null,
      );
      await tester.runAsync(
        () => AudioTranscriptArchive(rootDirectory: root).writeDraft(
          messageId: 'transcript-user-message',
          attachmentId: 'transcript-audio-attachment',
          fileName: 'archived-source.wav',
          fileSize: audio.lengthSync(),
          transcript: '这是一段可以继续使用的语音转写。',
          modelId: 'mimo-v2.5-asr',
          language: 'zh',
          resultMessageId: 'transcript-result-message',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          isOnlineProvider.overrideWithValue(true),
          activeSessionIdProvider.overrideWith((ref) => 'transcript-session'),
        ],
      );
      addTearDown(container.dispose);
      await container.read(mcpManagerProvider.notifier).ready;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ChatPage())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final audioCard = find.byKey(
        const ValueKey('audio-attachment-transcript-audio-attachment'),
      );
      expect(audioCard, findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(audioCard);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.text('语音转写详情'), findsOneWidget);
      expect(find.text('模型：mimo-v2.5-asr'), findsOneWidget);
      expect(find.text('语言：中文'), findsOneWidget);
      expect(find.text('这是一段可以继续使用的语音转写。'), findsWidgets);
      expect(
        find.byKey(const ValueKey('edit-audio-transcript')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('download-audio-transcript')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('retry-audio-transcript')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('use-audio-transcript-in-composer')),
      );
      await tester.pumpAndSettle();
      final composer = find.byType(TextField).last;
      expect(
        tester.widget<TextField>(composer).controller?.text,
        '这是一段可以继续使用的语音转写。',
      );

      await tester.runAsync(() async {
        await tester.tap(audioCard);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ask-about-audio-transcript')),
      );
      await tester.pumpAndSettle();
      final followUp = tester.widget<TextField>(composer).controller!.text;
      expect(followUp, startsWith('请基于以下语音转写回答我的问题：'));
      expect(followUp, contains('这是一段可以继续使用的语音转写。'));
      expect(followUp, endsWith('问题：'));
      expect(tester.takeException(), isNull);
    },
  );
}
