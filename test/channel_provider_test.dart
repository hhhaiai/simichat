import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allModelsProvider keeps selector filtering across refreshes', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.channelDao.createChannel(
      id: 'channel-provider',
      name: 'Provider Channel',
      baseUrl: 'https://api.example.com/v1',
      apiKeyEncrypted: 'encrypted-test-key',
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: 'chat-model',
      channelId: 'channel-provider',
      modelName: 'legacy-chat-model',
      capability: ModelCapability.chat,
    );
    await db.channelDao.addModel(
      id: 'vision-model',
      channelId: 'channel-provider',
      modelName: 'gpt-4o',
      capability: ModelCapability.vision,
    );
    await db.channelDao.addModel(
      id: 'embedding-model',
      channelId: 'channel-provider',
      modelName: 'text-embedding-3-small',
      capability: ModelCapability.embedding,
    );
    await db.channelDao.addModel(
      id: 'image-model',
      channelId: 'channel-provider',
      modelName: 'dall-e-3',
      capability: ModelCapability.image,
    );

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    container.read(selectedModelIdProvider.notifier).state = 'chat-model';
    final initialModels = await container.read(allModelsProvider.future);
    expect(initialModels.map((item) => item.channelModel.id).toSet(), {
      'chat-model',
      'vision-model',
    });

    container.invalidate(allModelsProvider);
    final refreshedModels = await container.read(allModelsProvider.future);
    expect(refreshedModels.map((item) => item.channelModel.id).toSet(), {
      'chat-model',
      'vision-model',
    });
    expect(container.read(selectedModelIdProvider), 'chat-model');
  });
}
