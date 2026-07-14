import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/relay/channel_model_relay_bridge.dart';
import 'package:ai_chat_app/core/relay/openai_compatible_relay_server.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bridge lists and resolves only enabled chat models', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    await db.channelDao.addModel(
      id: 'embedding-model',
      channelId: 'channel-1',
      modelName: 'text-embedding-3-small',
      capability: 'embedding',
    );
    await db.channelDao.addModel(
      id: 'vision-model',
      channelId: 'channel-1',
      modelName: 'gpt-4o',
      capability: ModelCapability.vision,
    );
    await db.channelDao.createChannel(
      id: 'disabled-channel',
      name: 'Disabled',
      baseUrl: 'https://disabled.example/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('sk-disabled'),
      protocol: 'openai_chat',
    );
    await db.channelDao.updateChannel('disabled-channel', isEnabled: false);
    await db.channelDao.addModel(
      id: 'disabled-model',
      channelId: 'disabled-channel',
      modelName: 'gpt-disabled',
    );

    final bridge = ChannelModelRelayBridge(channelDao: db.channelDao);

    final models = await bridge.listModels();
    expect(models.map((item) => item.id), contains('chat-model'));
    expect(models.map((item) => item.id), contains('vision-model'));
    expect(
      models.map((item) => item.id),
      contains(kOpenAiRelayRouteAliasDefault),
    );
    expect(models.map((item) => item.id), contains(kOpenAiRelayRouteAliasFree));
    expect(models.map((item) => item.id), contains(kOpenAiRelayRouteAliasFast));
    expect(
      models
          .firstWhere((item) => item.id == kOpenAiRelayRouteAliasDefault)
          .supportsVision,
      isTrue,
    );
    expect(models.map((item) => item.id), isNot(contains('embedding-model')));
    expect(models.map((item) => item.id), isNot(contains('disabled-model')));
    expect(await bridge.resolveModel('chat-model'), isNotNull);
    final visionModel = await bridge.resolveModel('vision-model');
    expect(visionModel, isNotNull);
    expect(visionModel!.supportsVision, isTrue);
    expect(await bridge.resolveModel('embedding-model'), isNull);
    expect(await bridge.resolveModel('disabled-model'), isNull);
  });

  test(
    'bridge decrypts API key and forwards through configured protocol',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);

      String? seenProtocol;
      String? seenBaseUrl;
      String? seenApiKey;
      String? seenModel;
      String? seenSystemPrompt;
      List<AiMessage>? seenMessages;
      CancelToken? seenCancelToken;
      bool? seenJsonResponse;
      final bridge = ChannelModelRelayBridge(
        channelDao: db.channelDao,
        sendMessage:
            ({
              required protocol,
              required baseUrl,
              required apiKey,
              required model,
              required messages,
              systemPrompt,
              cancelToken,
              required jsonResponse,
            }) {
              seenProtocol = protocol;
              seenBaseUrl = baseUrl;
              seenApiKey = apiKey;
              seenModel = model;
              seenSystemPrompt = systemPrompt;
              seenMessages = messages;
              seenCancelToken = cancelToken;
              seenJsonResponse = jsonResponse;
              return Stream.fromIterable(const [AiChunk(content: 'ok')]);
            },
      );

      final relayModel = (await bridge.resolveModel('chat-model'))!;
      final cancelToken = CancelToken();
      final chunks = await bridge
          .forward(
            model: relayModel,
            messages: const [AiMessage(role: 'user', content: 'hello')],
            systemPrompt: 'system',
            cancelToken: cancelToken,
            jsonResponse: true,
          )
          .toList();

      expect(chunks.single.content, 'ok');
      expect(seenProtocol, 'openai_chat');
      expect(seenBaseUrl, 'https://api.example.com/v1');
      expect(seenApiKey, 'test-key-local-relay');
      expect(seenModel, 'gpt-test');
      expect(seenSystemPrompt, 'system');
      expect(seenMessages!.single.content, 'hello');
      expect(seenCancelToken, same(cancelToken));
      expect(seenJsonResponse, isTrue);
    },
  );

  test('bridge fetches OpenAI chat messages without streaming', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);

    String? seenBaseUrl;
    String? seenApiKey;
    String? seenModel;
    String? seenSystemPrompt;
    List<AiMessage>? seenMessages;
    CancelToken? seenCancelToken;
    final bridge = ChannelModelRelayBridge(
      channelDao: db.channelDao,
      fetchOpenAiMessage:
          ({
            required baseUrl,
            required apiKey,
            required model,
            required messages,
            systemPrompt,
            cancelToken,
          }) async {
            seenBaseUrl = baseUrl;
            seenApiKey = apiKey;
            seenModel = model;
            seenSystemPrompt = systemPrompt;
            seenMessages = messages;
            seenCancelToken = cancelToken;
            return (content: 'one-shot-json', thinking: 'reasoning');
          },
    );

    final relayModel = (await bridge.resolveModel('chat-model'))!;
    final cancelToken = CancelToken();
    final chunk = await bridge.forwardOnce(
      model: relayModel,
      messages: const [AiMessage(role: 'user', content: 'hello once')],
      systemPrompt: 'system once',
      cancelToken: cancelToken,
    );

    expect(chunk?.content, 'one-shot-json');
    expect(chunk?.thinking, 'reasoning');
    expect(seenBaseUrl, 'https://api.example.com/v1');
    expect(seenApiKey, 'test-key-local-relay');
    expect(seenModel, 'gpt-test');
    expect(seenSystemPrompt, 'system once');
    expect(seenMessages!.single.content, 'hello once');
    expect(seenCancelToken, same(cancelToken));
  });

  test(
    'bridge routes default, free and fast aliases with fallback candidates',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      await db.channelDao.setDefaultModel('channel-1', 'chat-model');
      await db.channelDao.createChannel(
        id: 'channel-free',
        name: 'OpenRouter Free',
        baseUrl: 'https://openrouter.ai/api/v1',
        apiKeyEncrypted: KeyEncryptor.encrypt('test-free-key'),
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'free-model',
        channelId: 'channel-free',
        modelName: 'meta-llama/free',
      );
      await db.channelDao.createChannel(
        id: 'channel-local',
        name: 'zz Ollama Local',
        baseUrl: 'http://127.0.0.1:11434',
        apiKeyEncrypted: '',
        protocol: 'ollama',
      );
      await db.channelDao.addModel(
        id: 'local-model',
        channelId: 'channel-local',
        modelName: 'llama3',
      );

      final defaultBridge = ChannelModelRelayBridge(
        channelDao: db.channelDao,
        routeStrategy: OpenAiRelayRouteStrategy.defaultModel,
      );
      final freeBridge = ChannelModelRelayBridge(
        channelDao: db.channelDao,
        routeStrategy: OpenAiRelayRouteStrategy.freeFirst,
      );

      final defaultRoute = await defaultBridge.routeModel(null);
      expect(defaultRoute!.primary.id, 'chat-model');
      expect(
        defaultRoute.fallbacks.map((item) => item.id),
        contains('free-model'),
      );

      final freeRoute = await freeBridge.routeModel(kOpenAiRelayRouteAliasFree);
      expect(freeRoute!.primary.id, 'free-model');
      expect(
        freeRoute.fallbacks.map((item) => item.id),
        contains('local-model'),
      );

      final fastRoute = await freeBridge.routeModel(kOpenAiRelayRouteAliasFast);
      expect(fastRoute!.primary.id, 'local-model');

      final exact = await freeBridge.routeModel('chat-model');
      expect(exact!.primary.id, 'chat-model');
      expect(exact.fallbacks, isEmpty);

      final missingDirect = await ChannelModelRelayBridge(
        channelDao: db.channelDao,
      ).routeModel('missing-model');
      expect(missingDirect, isNull);
    },
  );
}

Future<void> _seed(AppDatabase db) async {
  await db.channelDao.createChannel(
    id: 'channel-1',
    name: 'OpenAI Local',
    baseUrl: 'https://api.example.com/v1',
    apiKeyEncrypted: KeyEncryptor.encrypt('test-key-local-relay'),
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'chat-model',
    channelId: 'channel-1',
    modelName: 'gpt-test',
  );
}
