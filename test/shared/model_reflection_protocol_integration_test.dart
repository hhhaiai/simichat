import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/http_helper.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/provider_access.dart';
import 'package:ai_chat_app/shared/providers/reflection_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'model reflection uses the configured chat protocol end to end',
    () async {
      final now = DateTime.utc(2026, 7, 14, 22);
      final digest = _digest(now);
      SharedPreferences.setMockInitialValues({
        kAssistantReflectionModelEnabledStorageKey: true,
      });

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requestCount = 0;
      final serverSubscription = server.listen((request) async {
        requestCount += 1;
        final payload = jsonDecode(await utf8.decoder.bind(request).join());
        expect(payload['model'], 'reflection-model');
        expect(payload['stream'], isFalse);
        request.response.bufferOutput = false;
        request.response.persistentConnection = false;
        request.response.headers.contentType = ContentType.json;
        final modelJson = jsonEncode({
          'insights': [
            {
              'category': '模型增强',
              'text': '先验证用户仍在等待的移动端后台能力。',
              'priority': 'high',
            },
          ],
          'actionItems': ['继续完成移动端真机验证。'],
        });
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': modelJson},
              },
            ],
          }),
        );
        await request.response.close();
      });

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.channelDao.createChannel(
        id: 'reflection-channel',
        name: 'Reflection Local Mock',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKeyEncrypted: KeyEncryptor.encrypt('test-reflection-key'),
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'reflection-model-id',
        channelId: 'reflection-channel',
        modelName: 'reflection-model',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          reflectionServiceProvider.overrideWithValue(
            ReflectionService(now: () => now),
          ),
        ],
      );

      try {
        final report = await runAssistantReflectionWithAccess(
          ContainerProviderAccess(container),
          digest: digest,
        );

        expect(requestCount, 1);
        expect(report?.generationMode, kReflectionGenerationModeModel);
        expect(report?.insights.any((item) => item.category == '模型增强'), isTrue);
        expect(container.read(assistantReflectionPendingProvider), isNull);
      } finally {
        container.dispose();
        disposeAllDio();
        await serverSubscription.cancel();
        await server.close(force: true);
        await db.close();
      }
    },
  );
}

DreamingDigest _digest(DateTime now) {
  return DreamingDigest(
    day: now,
    generatedAt: now,
    sessionCount: 1,
    originalMessageCount: 2,
    userMessageCount: 1,
    assistantMessageCount: 1,
    sessions: [
      DreamingSessionDigest(
        sessionId: 's1',
        title: '模型反思协议测试',
        messageCount: 2,
        userMessageCount: 1,
        assistantMessageCount: 1,
        highlights: const ['继续推进模型反思'],
        firstMessageAt: now.subtract(const Duration(minutes: 1)),
        lastMessageAt: now,
      ),
    ],
    memoryCandidates: const [],
    keywords: const ['模型反思'],
    elapsedMs: 1,
  );
}
