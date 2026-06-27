import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deleteChannel clears model references before deleting channel', () async {
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
  });

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
}
