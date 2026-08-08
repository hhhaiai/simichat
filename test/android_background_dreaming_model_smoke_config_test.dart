import 'dart:io';

import 'package:ai_chat_app/core/smoke/android_background_dreaming_model_smoke_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads and deletes one-time remote model smoke configuration', () async {
    final dir = await Directory.systemTemp.createTemp(
      'simichat-background-model-config-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/config.json');
    await file.writeAsString('''
{
  "protocol": "openai_chat",
  "baseUrl": "https://example.test/api",
  "apiKey": "test-secret",
  "model": "remote-model"
}
''');

    final config = await loadAndroidBackgroundDreamingModelConfig(
      configFile: file,
    );

    expect(config.protocol, 'openai_chat');
    expect(config.baseUrl, 'https://example.test/api');
    expect(config.apiKey, 'test-secret');
    expect(config.model, 'remote-model');
    expect(await file.exists(), isFalse);
  });

  test(
    'rejects unsupported model smoke protocols and deletes the file',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'simichat-background-model-config-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/config.json');
      await file.writeAsString('''
{
  "protocol": "ollama",
  "baseUrl": "http://127.0.0.1:11434",
  "apiKey": "unused",
  "model": "local"
}
''');

      await expectLater(
        loadAndroidBackgroundDreamingModelConfig(configFile: file),
        throwsFormatException,
      );
      expect(await file.exists(), isFalse);
    },
  );
}
