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

  test('direct native audio smoke fixtures stay silent', () async {
    const smokeFiles = [
      'integration_test/mobile_native_audio_player_smoke_test.dart',
      'integration_test/mobile_long_audio_playback_smoke_test.dart',
      'integration_test/mobile_audio_playback_replace_smoke_test.dart',
      'integration_test/mobile_external_audio_focus_smoke_test.dart',
    ];

    for (final path in smokeFiles) {
      final source = await File(path).readAsString();

      expect(source, contains('_buildSilentWav'));
      expect(source, contains('zero-filled'));
      expect(source, isNot(contains("import 'dart:math'")));
      expect(source, isNot(contains('math.sin')));
      expect(source, isNot(contains('_buildSineWaveWav')));
    }
  });

  test('Android audio player handles audio focus interruptions', () async {
    final androidActivity = await File(
      'android/app/src/main/kotlin/top/simitalk/aichat/MainActivity.kt',
    ).readAsString();

    expect(androidActivity, contains('android.media.AudioFocusRequest'));
    expect(androidActivity, contains('android.media.AudioManager'));
    expect(androidActivity, contains('OnAudioFocusChangeListener'));
    expect(androidActivity, contains('AUDIOFOCUS_LOSS'));
    expect(androidActivity, contains('AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK'));
    expect(androidActivity, contains('Context.AUDIO_SERVICE'));
    expect(androidActivity, contains('skipAudioFocusRequest'));
    expect(androidActivity, contains('simulateAudioFocusLossForTesting'));
    expect(androidActivity, contains('requestCompetingAudioFocusForTesting'));
    expect(androidActivity, contains('abandonCompetingAudioFocusForTesting'));
    expect(androidActivity, contains('ApplicationInfo.FLAG_DEBUGGABLE'));
    expect(androidActivity, contains('requestAudioFocus'));
    expect(androidActivity, contains('abandonAudioFocus'));
  });

  test(
    'Android external audio focus smoke uses a separate helper package',
    () async {
      final script = await File(
        'scripts/smoke_device_external_audio_focus.sh',
      ).readAsString();
      final smoke = await File(
        'integration_test/mobile_external_audio_focus_smoke_test.dart',
      ).readAsString();

      expect(script, contains('top.simitalk.aichat.audiofocusstealer'));
      expect(script, contains('AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE'));
      expect(script, contains('SIMICHAT_EXTERNAL_AUDIO_FOCUS_READY'));
      expect(script, contains(r'adb -s "$DEVICE_ID" install -r "$HELPER_APK"'));
      expect(smoke, contains('SIMICHAT_EXTERNAL_AUDIO_FOCUS_READY'));
      expect(smoke, contains('playFileForTesting(audioFile.path)'));
      expect(smoke, isNot(contains('skipAudioFocusRequest: true')));
    },
  );

  test('iOS audio player handles audio session interruptions', () async {
    final iosAppDelegate = await File(
      'ios/Runner/AppDelegate.swift',
    ).readAsString();

    expect(iosAppDelegate, contains('AVAudioSession.interruptionNotification'));
    expect(iosAppDelegate, contains('AVAudioSessionInterruptionTypeKey'));
    expect(iosAppDelegate, contains('InterruptionType'));
    expect(iosAppDelegate, contains('type == .began'));
    expect(iosAppDelegate, contains('stopAudioPlayback()'));
    expect(iosAppDelegate, contains('setActive('));
    expect(iosAppDelegate, contains('false,'));
    expect(iosAppDelegate, contains('notifyOthersOnDeactivation'));
  });

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
