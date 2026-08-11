import 'dart:io';

import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('image endpoints are limited to OpenAI-compatible protocols', () {
    expect(canUseChannelImageGeneration('openai_chat'), isTrue);
    expect(canUseChannelImageGeneration('openai_response'), isTrue);
    expect(canUseChannelImageGeneration('claude'), isFalse);
    expect(canUseChannelImageGeneration('gemini'), isFalse);
    expect(canUseChannelImageGeneration('ollama'), isFalse);
  });

  testWidgets(
    'unsupported image generation and edit leave conversation untouched',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.channelDao.createChannel(
        id: 'claude-channel',
        name: 'Claude only',
        baseUrl: 'https://api.anthropic.com',
        apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
        protocol: 'claude',
      );
      await db.channelDao.addModel(
        id: 'claude-model',
        channelId: 'claude-channel',
        modelName: 'claude-test',
      );
      await db.sessionDao.createSession(
        id: 'image-session',
        defaultChannelModelId: 'claude-model',
      );
      final temp = Directory.systemTemp.createTempSync(
        'simichat_image_provider_',
      );
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final sourceImage = File('${temp.path}/source.png');
      sourceImage.writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const MaterialApp(home: SizedBox());
            },
          ),
        ),
      );
      final generationError = await generateImage(
        ref: capturedRef,
        sessionId: 'image-session',
        prompt: '一只在月球上的猫',
      );
      final editError = await editImage(
        ref: capturedRef,
        sessionId: 'image-session',
        imagePath: sourceImage.path,
        prompt: '改成赛博朋克夜景',
      );

      expect(generationError, contains('当前渠道不支持'));
      expect(generationError, contains('/v1/images/generations'));
      expect(editError, contains('当前渠道不支持'));
      expect(editError, contains('/v1/images/edits'));
      expect(
        await db.messageDao.getMessagesBySession('image-session'),
        isEmpty,
      );
      expect((await db.sessionDao.getSession('image-session'))!.totalTokens, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
