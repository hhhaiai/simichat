import 'dart:io';

import '../tool/model_reflection_live_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads a private remote model config without deleting it', () async {
    final directory = await Directory.systemTemp.createTemp(
      'simichat-live-model-config-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/model.json');
    await file.writeAsString('''
{
  "protocol": "openai_chat",
  "baseUrl": "https://example.test/api/",
  "apiKey": "test-secret",
  "model": "remote-model"
}
''');
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', ['600', file.path]);
      expect(chmod.exitCode, 0);
    }

    final config = await loadModelReflectionLiveConfig(file);

    expect(config.protocol, 'openai_chat');
    expect(config.baseUrl, 'https://example.test/api');
    expect(config.apiKey, 'test-secret');
    expect(config.model, 'remote-model');
    expect(await file.exists(), isTrue);
  });

  test('rejects loopback model endpoints', () async {
    final file = await _writeConfig(baseUrl: 'http://127.0.0.1:11434');
    addTearDown(() => file.parent.delete(recursive: true));

    await expectLater(
      loadModelReflectionLiveConfig(file),
      throwsFormatException,
    );
  });

  test('rejects non OpenAI chat protocols', () async {
    final file = await _writeConfig(protocol: 'local_model');
    addTearDown(() => file.parent.delete(recursive: true));

    await expectLater(
      loadModelReflectionLiveConfig(file),
      throwsFormatException,
    );
  });

  test('rejects model config with broad file permissions', () async {
    if (Platform.isWindows) return;
    final file = await _writeConfig();
    addTearDown(() => file.parent.delete(recursive: true));
    final chmod = await Process.run('chmod', ['644', file.path]);
    expect(chmod.exitCode, 0);

    await expectLater(
      loadModelReflectionLiveConfig(file),
      throwsA(isA<FileSystemException>()),
    );
  });
}

Future<File> _writeConfig({
  String protocol = 'openai_chat',
  String baseUrl = 'https://example.test',
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'simichat-live-model-config-',
  );
  final file = File('${directory.path}/model.json');
  await file.writeAsString('''
{
  "protocol": "$protocol",
  "baseUrl": "$baseUrl",
  "apiKey": "test-secret",
  "model": "remote-model"
}
''');
  if (!Platform.isWindows) {
    final chmod = await Process.run('chmod', ['600', file.path]);
    expect(chmod.exitCode, 0);
  }
  return file;
}
