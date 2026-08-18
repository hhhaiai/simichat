import 'package:ai_chat_app/core/ai/universal_media_service.dart';
import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/universal_media_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UniversalMediaCapability resolve({
    UniversalMediaKind kind = UniversalMediaKind.video,
    String protocol = 'openai_chat',
    String baseUrl = 'https://relay.test/v1',
    bool? apiKeyConfigured = true,
    String modelName = 'chat-model',
    String modelCapability = 'chat',
    String? mediaModel = 'sora-test',
    String? mediaEndpoint = '/v1/videos/generations',
    bool checking = false,
  }) {
    return resolveUniversalMediaCapability(
      kind: kind,
      protocol: protocol,
      baseUrl: baseUrl,
      apiKeyConfigured: apiKeyConfigured,
      modelName: modelName,
      modelCapability: modelCapability,
      mediaModel: mediaModel,
      mediaEndpoint: mediaEndpoint,
      checking: checking,
    );
  }

  test('capability remains checking while model or config is loading', () {
    final result = resolve(checking: true);

    expect(result.status, UniversalMediaCapabilityStatus.checking);
    expect(result.message, contains('检测'));
  });

  test(
    'missing channel or media configuration is not advertised as available',
    () {
      expect(
        resolve(apiKeyConfigured: false).status,
        UniversalMediaCapabilityStatus.notConfigured,
      );
      expect(resolve(apiKeyConfigured: false).message, contains('API Key'));

      final missingMediaModel = resolve(mediaModel: '');
      expect(
        missingMediaModel.status,
        UniversalMediaCapabilityStatus.notConfigured,
      );
      expect(missingMediaModel.message, contains('模型和接口路径'));

      final missingBaseUrl = resolve(baseUrl: '');
      expect(
        missingBaseUrl.status,
        UniversalMediaCapabilityStatus.notConfigured,
      );
      expect(missingBaseUrl.message, contains('Base URL'));
    },
  );

  test(
    'unsupported protocol is rejected even when generic media fields exist',
    () {
      final result = resolve(protocol: 'claude');

      expect(result.status, UniversalMediaCapabilityStatus.unavailable);
      expect(result.message, contains('渠道协议'));
    },
  );

  test('chat-compatible model can use explicitly configured media route', () {
    final result = resolve();

    expect(result.status, UniversalMediaCapabilityStatus.available);
    expect(result.isAvailable, isTrue);
  });

  test('embedding model cannot be promoted to a media model', () {
    final result = resolve(
      modelName: 'text-embedding-3-small',
      modelCapability: 'embedding',
    );

    expect(result.status, UniversalMediaCapabilityStatus.unavailable);
    expect(result.message, contains('Embedding'));
  });

  test(
    'video and music require explicit media capability when model is media-only',
    () {
      final video = resolve(
        modelName: 'provider-video',
        modelCapability: 'video',
      );
      final music = resolve(
        kind: UniversalMediaKind.music,
        modelName: 'provider-music',
        modelCapability: 'music',
        mediaModel: 'music-test',
        mediaEndpoint: '/v1/audio/music',
      );

      expect(video.status, UniversalMediaCapabilityStatus.available);
      expect(music.status, UniversalMediaCapabilityStatus.available);
    },
  );

  test('model name alone does not fabricate video or music capability', () {
    final video = resolve(
      modelName: 'video-generation-unknown',
      modelCapability: 'embedding',
    );
    final music = resolve(
      kind: UniversalMediaKind.music,
      modelName: 'music-generation-unknown',
      modelCapability: 'embedding',
      mediaModel: 'music-test',
      mediaEndpoint: '/v1/audio/music',
    );

    expect(video.status, UniversalMediaCapabilityStatus.unavailable);
    expect(music.status, UniversalMediaCapabilityStatus.unavailable);
  });

  test(
    'selected media channel model is used instead of the Chat channel',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.channelDao.createChannel(
        id: 'chat-channel',
        name: 'Chat 渠道',
        baseUrl: 'https://chat.example/v1',
        apiKeyEncrypted: 'chat-key',
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'chat-model',
        channelId: 'chat-channel',
        modelName: 'mimo-v2.5-chat',
        capability: ModelCapability.chat,
      );
      await db.channelDao.createChannel(
        id: 'video-channel',
        name: 'Video 渠道',
        baseUrl: 'https://video.example/v1',
        apiKeyEncrypted: 'video-key',
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'video-model',
        channelId: 'video-channel',
        modelName: 'sora-2',
        capability: ModelCapability.video,
      );

      final chatModel = await db.channelDao.getModelWithChannel('chat-model');
      expect(chatModel, isNotNull);
      final selected = await resolveUniversalMediaRouteModelForTesting(
        channelDao: db.channelDao,
        chatModel: chatModel!,
        config: const UniversalMediaConfig(
          videoModel: 'sora-2',
          videoChannelModelId: 'video-model',
        ),
        kind: UniversalMediaKind.video,
      );

      expect(selected?.channelModel.id, 'video-model');
      expect(selected?.channel.baseUrl, 'https://video.example/v1');
      expect(selected?.channelModel.modelName, 'sora-2');
    },
  );

  test(
    'stale or disabled media route does not fall back to Chat silently',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.channelDao.createChannel(
        id: 'chat-channel',
        name: 'Chat 渠道',
        baseUrl: 'https://chat.example/v1',
        apiKeyEncrypted: 'chat-key',
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'chat-model',
        channelId: 'chat-channel',
        modelName: 'chat-model',
        capability: ModelCapability.chat,
      );
      final chatModel = await db.channelDao.getModelWithChannel('chat-model');
      expect(chatModel, isNotNull);

      final stale = await resolveUniversalMediaRouteModelForTesting(
        channelDao: db.channelDao,
        chatModel: chatModel!,
        config: const UniversalMediaConfig(
          videoChannelModelId: 'deleted-route',
        ),
        kind: UniversalMediaKind.video,
      );
      expect(stale, isNull);

      await db.channelDao.createChannel(
        id: 'disabled-channel',
        name: 'Disabled Video',
        baseUrl: 'https://disabled.example/v1',
        apiKeyEncrypted: 'disabled-key',
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'disabled-model',
        channelId: 'disabled-channel',
        modelName: 'sora-disabled',
        capability: ModelCapability.video,
      );
      await db.channelDao.updateChannel('disabled-channel', isEnabled: false);

      final disabled = await resolveUniversalMediaRouteModelForTesting(
        channelDao: db.channelDao,
        chatModel: chatModel,
        config: const UniversalMediaConfig(
          videoChannelModelId: 'disabled-model',
        ),
        kind: UniversalMediaKind.video,
      );
      expect(disabled, isNull);
    },
  );
}
