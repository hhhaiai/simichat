import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS declares microphone usage description for voice input', () async {
    final plist = await File('ios/Runner/Info.plist').readAsString();

    expect(plist, contains('NSMicrophoneUsageDescription'));
    expect(plist, contains('用于录制语音消息'));
  });

  test(
    'iOS declares speech recognition usage description for fallback STT',
    () async {
      final plist = await File('ios/Runner/Info.plist').readAsString();

      expect(plist, contains('NSSpeechRecognitionUsageDescription'));
      expect(plist, contains('系统语音识别'));
    },
  );

  test('Android declares RECORD_AUDIO permission for voice input', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(manifest, contains('android.permission.RECORD_AUDIO'));
  });

  test(
    'native shells register audio player channel for TTS playback',
    () async {
      final androidActivity = await File(
        'android/app/src/main/kotlin/top/simitalk/aichat/MainActivity.kt',
      ).readAsString();
      final iosAppDelegate = await File(
        'ios/Runner/AppDelegate.swift',
      ).readAsString();

      expect(androidActivity, contains('simichat/audio_player'));
      expect(androidActivity, contains('MediaPlayer'));
      expect(iosAppDelegate, contains('simichat/audio_player'));
      expect(iosAppDelegate, contains('AVAudioPlayer'));
    },
  );

  test('iOS shell registers native speech-to-text fallback channel', () async {
    final iosAppDelegate = await File(
      'ios/Runner/AppDelegate.swift',
    ).readAsString();

    expect(iosAppDelegate, contains('import Speech'));
    expect(iosAppDelegate, contains('simichat/native_speech_to_text'));
    expect(iosAppDelegate, contains('SFSpeechURLRecognitionRequest'));
    expect(iosAppDelegate, contains('OUTSIDE_APP_DATA'));
  });
}
