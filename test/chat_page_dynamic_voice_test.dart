import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/http_helper.dart';
import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/media/openai_text_to_speech_engine.dart';
import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:ai_chat_app/features/chat/chat_page.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'standalone Dio test hook preserves TTS bytes and request JSON',
    () async {
      final adapter = _CapturingSpeechAdapter();
      debugDioFactory = (_) {
        final dio = Dio();
        dio.httpClientAdapter = adapter;
        return dio;
      };
      addTearDown(() {
        debugDioFactory = null;
        adapter.close(force: true);
      });

      final bytes =
          await OpenAiCompatibleTextToSpeechEngine(
            baseUrl: 'https://voice.example.test/v1',
            apiKey: 'test-key',
            model: 'mimo-v2.5-tts',
          ).synthesize(
            const TextToSpeechInput(
              text: 'adapter check',
              voice: 'provider-voice',
            ),
          );

      expect(bytes, const [0x49, 0x44, 0x33]);
      expect(adapter.payload?['voice'], 'provider-voice');
    },
  );

  testWidgets(
    'TTS task sheet loads provider voices and sends the selected raw voice id',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kTextToSpeechEnabledStorageKey: true,
        kTextToSpeechProviderStorageKey: kTextToSpeechProviderOpenAiCompatible,
        kTextToSpeechBaseUrlStorageKey: 'https://voice.example.test/v1',
        kTextToSpeechModelStorageKey: 'mimo-v2.5-tts',
        kTextToSpeechVoiceStorageKey: 'alloy',
        kTextToSpeechApiKeyStorageKey: KeyEncryptor.encrypt('voice-test-key'),
        kTextToSpeechSpeedStorageKey: '1.0',
        kTextToSpeechResponseFormatStorageKey: 'mp3',
        kTextToSpeechChannelModelIdStorageKey: 'dynamic-voice-model',
      });
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final root = Directory.systemTemp.createTempSync(
        'simichat-dynamic-voice-',
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

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.channelDao.createChannel(
        id: 'dynamic-voice-channel',
        name: 'Dynamic voice channel',
        baseUrl: 'https://voice.example.test/v1',
        apiKeyEncrypted: KeyEncryptor.encrypt('voice-test-key'),
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'dynamic-voice-model',
        channelId: 'dynamic-voice-channel',
        modelName: 'mimo-v2.5-tts',
        capability: ModelCapability.tts,
      );
      await db.sessionDao.createSession(
        id: 'dynamic-voice-session',
        defaultChannelModelId: 'dynamic-voice-model',
      );

      final voiceGate = Completer<List<TextToSpeechVoiceOption>>();
      var voiceLoads = 0;
      final adapter = _CapturingSpeechAdapter();
      debugDioFactory = (_) {
        final dio = Dio();
        dio.httpClientAdapter = adapter;
        return dio;
      };
      addTearDown(() {
        debugDioFactory = null;
        adapter.close(force: true);
      });
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          isOnlineProvider.overrideWithValue(true),
          activeSessionIdProvider.overrideWith(
            (ref) => 'dynamic-voice-session',
          ),
          selectedModelIdProvider.overrideWith((ref) => 'dynamic-voice-model'),
          textToSpeechVoiceLoaderProvider.overrideWithValue((config) {
            voiceLoads++;
            expect(config.model, 'mimo-v2.5-tts');
            expect(config.channelModelId, 'dynamic-voice-model');
            return voiceGate.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(mcpManagerProvider.notifier).ready;
      await container.read(textToSpeechConfigProvider.notifier).ready;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ChatPage())),
        ),
      );
      await tester.pumpAndSettle();

      final composer = find.byType(TextField).last;
      await tester.enterText(composer, '动态音色合成测试');
      await tester.pump();
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      final speechAction = find.byKey(
        const ValueKey('synthesize-speech-menu-item'),
      );
      await tester.ensureVisible(speechAction);
      await tester.tap(speechAction);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(voiceLoads, 1);
      expect(
        find.byKey(const ValueKey('speech-voices-loading')),
        findsOneWidget,
      );
      voiceGate.complete(const [
        TextToSpeechVoiceOption(id: 'provider-voice-42', label: '渠道音色'),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('speech-voices-loaded')),
        findsOneWidget,
      );
      expect(find.text('已同步 1 个渠道音色'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('speech-synthesis-voice-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('渠道音色 (provider-voice-42)').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('submit-speech-synthesis-task')),
      );
      for (
        var attempt = 0;
        attempt < 40 && adapter.payload == null;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | ');
      expect(adapter.payload, isNotNull, reason: visibleText);
      expect(adapter.payload!['model'], 'mimo-v2.5-tts');
      expect(adapter.payload!['input'], '动态音色合成测试');
      expect(adapter.payload!['voice'], 'provider-voice-42');
      expect(adapter.payload!['speed'], 1);
      expect(adapter.payload!['response_format'], 'mp3');
      // 任务面板到 provider wire 的 raw ID 已在上方断言；媒体落盘事务需要
      // dart:io 的真实异步事件循环，独立覆盖在 chat_page_voice_tools_test。
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('TTS task sheet falls back and can retry voice loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kTextToSpeechEnabledStorageKey: true,
      kTextToSpeechProviderStorageKey: kTextToSpeechProviderOpenAiCompatible,
      kTextToSpeechBaseUrlStorageKey: 'https://voice.example.test/v1',
      kTextToSpeechModelStorageKey: 'tts-1',
      kTextToSpeechVoiceStorageKey: 'alloy',
      kTextToSpeechApiKeyStorageKey: KeyEncryptor.encrypt('voice-test-key'),
    });
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.sessionDao.createSession(id: 'voice-fallback-session');
    var loads = 0;
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        activeSessionIdProvider.overrideWith((ref) => 'voice-fallback-session'),
        textToSpeechVoiceLoaderProvider.overrideWithValue((config) async {
          loads++;
          if (loads == 1) {
            throw const TextToSpeechException('voice catalog down');
          }
          return const [
            TextToSpeechVoiceOption(id: 'recovered-voice', label: '恢复音色'),
          ];
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(mcpManagerProvider.notifier).ready;
    await container.read(textToSpeechConfigProvider.notifier).ready;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChatPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '重试渠道音色');
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('synthesize-speech-menu-item'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('speech-voices-fallback')),
      findsOneWidget,
    );
    expect(find.text('渠道音色获取失败，已使用本地预设'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry-speech-voices')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(loads, 2);
    expect(find.byKey(const ValueKey('speech-voices-loaded')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('speech-synthesis-voice-field')),
    );
    await tester.pumpAndSettle();
    expect(find.text('恢复音色 (recovered-voice)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _CapturingSpeechAdapter implements HttpClientAdapter {
  Map<String, dynamic>? payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data;
    payload = data is String
        ? jsonDecode(data) as Map<String, dynamic>
        : (data as Map).cast<String, dynamic>();
    return ResponseBody.fromBytes(
      const [0x49, 0x44, 0x33],
      200,
      headers: const {
        'content-type': ['audio/mpeg'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
