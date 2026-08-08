import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live model profile quality gate is remote-config only', () {
    final qualityTest = File(
      'tool/model_user_profile_live_quality_test.dart',
    ).readAsStringSync();
    final script = File(
      'scripts/smoke_model_user_profile_live_quality.sh',
    ).readAsStringSync();

    expect(qualityTest, contains('MODEL_CONFIG_FILE'));
    expect(qualityTest, contains('OpenAiChatProtocol'));
    expect(qualityTest, contains('fetchMessageOnce'));
    expect(qualityTest, contains('loadModelReflectionLiveConfig'));
    expect(qualityTest, contains('SIMICHAT_LIVE_PROFILE_MODEL_RUNS'));
    expect(qualityTest.toLowerCase(), isNot(contains('ollama')));
    expect(qualityTest, isNot(contains('127.0.0.1')));
    expect(qualityTest, isNot(contains('11434')));

    expect(script, contains('MODEL_CONFIG_FILE'));
    expect(script, contains('permissions must be 600 or 400'));
    expect(script, contains('SIMICHAT_LIVE_PROFILE_MODEL_RUNS'));
    expect(script, contains('model_user_profile_live_quality_test.dart'));
    expect(script.toLowerCase(), isNot(contains('ollama')));
    expect(script, isNot(contains('http://')));
    expect(script, isNot(contains('Bearer sk-')));
    expect(script, isNot(contains('11434')));
  });
}
