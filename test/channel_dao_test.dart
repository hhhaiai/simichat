import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'deleteChannel clears model references before deleting channel',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.channelDao.createChannel(
        id: 'channel-1',
        name: 'Test Channel',
        baseUrl: 'https://api.example.com/v1',
        apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'model-1',
        channelId: 'channel-1',
        modelName: 'gpt-test',
      );
      await db.sessionDao.createSession(
        id: 'session-1',
        defaultChannelModelId: 'model-1',
      );
      await db.messageDao.insertMessage(
        id: 'message-1',
        sessionId: 'session-1',
        role: 'assistant',
        content: 'ok',
        channelModelId: 'model-1',
      );

      await db.channelDao.deleteChannel('channel-1');

      expect(await db.channelDao.getAllChannels(), isEmpty);
      expect(await db.channelDao.getModelsByChannel('channel-1'), isEmpty);
      final session = await db.sessionDao.getSession('session-1');
      expect(session!.defaultChannelModelId, isNull);
      final messages = await db.messageDao.getMessagesBySession('session-1');
      expect(messages.single.channelModelId, isNull);
    },
  );

  test('deleteModel clears session and message references', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'channel-1',
      name: 'Test Channel',
      baseUrl: 'https://api.example.com/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'model-1',
      channelId: 'channel-1',
      modelName: 'gpt-test',
    );
    await db.sessionDao.createSession(
      id: 'session-1',
      defaultChannelModelId: 'model-1',
    );
    await db.messageDao.insertMessage(
      id: 'message-1',
      sessionId: 'session-1',
      role: 'assistant',
      content: 'ok',
      channelModelId: 'model-1',
    );

    await db.channelDao.deleteModel('model-1');

    expect(await db.channelDao.getModelsByChannel('channel-1'), isEmpty);
    final session = await db.sessionDao.getSession('session-1');
    expect(session!.defaultChannelModelId, isNull);
    final messages = await db.messageDao.getMessagesBySession('session-1');
    expect(messages.single.channelModelId, isNull);
  });

  test(
    'chat model query uses strict capability filtering for selector models',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.channelDao.createChannel(
        id: 'channel-capabilities',
        name: 'Capability Channel',
        baseUrl: 'https://api.example.com/v1',
        apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
        protocol: 'openai_chat',
      );
      await db.channelDao.addModel(
        id: 'legacy-chat-model',
        channelId: 'channel-capabilities',
        modelName: 'legacy-chat-model',
        capability: ModelCapability.chat,
      );
      await db.channelDao.addModel(
        id: 'vision-model',
        channelId: 'channel-capabilities',
        modelName: 'vision-model',
        capability: ModelCapability.vision,
      );
      await db.channelDao.addModel(
        id: 'reasoner-model',
        channelId: 'channel-capabilities',
        modelName: 'deepseek-reasoner',
        capability: ModelCapability.reasoner,
      );
      await db.channelDao.addModel(
        id: 'embedding-model',
        channelId: 'channel-capabilities',
        modelName: 'gemini-embedding-001',
        capability: ModelCapability.embedding,
      );
      await db.channelDao.addModel(
        id: 'image-model',
        channelId: 'channel-capabilities',
        modelName: 'image-service-model',
        capability: ModelCapability.image,
      );
      await db.channelDao.addModel(
        id: 'video-model',
        channelId: 'channel-capabilities',
        modelName: 'video-service-model',
        capability: ModelCapability.video,
      );
      await db.channelDao.addModel(
        id: 'audio-model',
        channelId: 'channel-capabilities',
        modelName: 'audio-service-model',
        capability: ModelCapability.audio,
      );
      // SimiRouter's mimo TTS model is often returned by an OpenAI-compatible
      // model catalog with a stale `chat` capability.  The model-name veto
      // must still keep it out of the ordinary chat selector; TTS selects it
      // through the independent speech-provider preset.
      await db.channelDao.addModel(
        id: 'mimo-tts-model',
        channelId: 'channel-capabilities',
        modelName: 'mimo-v2.5-tts',
        capability: ModelCapability.chat,
      );
      await db.channelDao.addModel(
        id: 'music-model',
        channelId: 'channel-capabilities',
        modelName: 'music-service-model',
        capability: ModelCapability.music,
      );
      await db.channelDao.addModel(
        id: 'stale-chat-image-model',
        channelId: 'channel-capabilities',
        modelName: 'dall-e-3',
        capability: ModelCapability.chat,
      );

      final models = await db.channelDao.getChatModels();
      expect(models.map((item) => item.channelModel.id).toSet(), {
        'legacy-chat-model',
        'vision-model',
        'reasoner-model',
      });
    },
  );

  test('persists secondary capabilities for chat plus media models', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'multi-capability-channel',
      name: 'Multi Capability Channel',
      baseUrl: 'https://api.example.com/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('test-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'multi-capability-model',
      channelId: 'multi-capability-channel',
      modelName: 'chat-video-model',
      capability: ModelCapability.chat,
      capabilities: const <String>{ModelCapability.video},
    );

    final model = await db.channelDao.getModelWithChannel(
      'multi-capability-model',
    );
    expect(model, isNotNull);
    expect(model!.channelModel.capability, ModelCapability.chat);
    expect(
      model.capabilities,
      containsAll(<String>[ModelCapability.chat, ModelCapability.video]),
    );

    final chatModels = await db.channelDao.getChatModels();
    expect(
      chatModels.map((item) => item.channelModel.id),
      contains('multi-capability-model'),
    );
  });
}
