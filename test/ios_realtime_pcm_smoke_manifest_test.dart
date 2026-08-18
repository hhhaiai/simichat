import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS realtime PCM bridge is in the Runner target and wired once', () {
    final swift = File('ios/Runner/RealtimePcmAudio.swift').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();

    expect(project, contains('RealtimePcmAudio.swift in Sources'));
    expect(project, contains('RealtimePcmAudio.swift */'));
    expect(appDelegate, contains('registerRealtimePcmAudioChannel'));
    expect(
      RegExp(
        r'registerRealtimePcmAudioChannel\(messenger: messenger\)',
      ).allMatches(appDelegate),
      hasLength(1),
    );
    expect(appDelegate, contains('FlutterEventChannel'));
    expect(info, contains('<key>NSMicrophoneUsageDescription</key>'));

    expect(swift, contains('AVAudioEngine'));
    expect(swift, contains('AVAudioConverter'));
    expect(swift, contains('AVAudioPlayerNode'));
    expect(swift, contains('inputSampleRate = 16_000'));
    expect(swift, contains('outputSampleRate = 24_000'));
    expect(swift, contains('channels = 1'));
    expect(swift, contains('bitsPerSample = 16'));
    expect(swift, contains('inputTargetBitsPerSample'));
    expect(swift, contains('outputBitsPerSample'));
    expect(swift, contains('converter.primeMethod = .none'));
    expect(swift, contains('converter.downmix = true'));
    expect(swift, contains('AVAudioSession.interruptionNotification'));
    expect(swift, contains('AVAudioSession.routeChangeNotification'));
    expect(swift, contains('AUDIO_SESSION_INTERRUPTED'));
    expect(swift, contains('AUDIO_ROUTE_CHANGED'));
    expect(swift, contains('case .categoryChange:'));
    expect(swift, contains('inputNode.removeTap(onBus: 0)'));
    expect(swift, contains('notifyOthersOnDeactivation'));
    expect(swift, contains('writesAudioFiles'));
    expect(swift, isNot(contains('AVAudioFile(')));
    expect(swift, isNot(contains('AVAudioRecorder(')));
    expect(swift, isNot(contains('FileManager.default')));
  });

  test('iOS realtime PCM integration smoke keeps release/debug evidence', () {
    final test = File(
      'integration_test/ios_realtime_pcm_smoke_test.dart',
    ).readAsStringSync();
    final driver = File(
      'integration_test/ios_realtime_pcm_smoke_driver.dart',
    ).readAsStringSync();
    final script = File('scripts/smoke_ios_realtime_pcm.sh').readAsStringSync();

    for (final marker in [
      'SIMICHAT_IOS_REALTIME_PCM_SMOKE_START',
      'SIMICHAT_IOS_REALTIME_PCM_PLAYBACK_EVIDENCE',
      'SIMICHAT_IOS_REALTIME_PCM_CAPTURE_EVIDENCE',
      'SIMICHAT_IOS_REALTIME_PCM_STOP_CLEANUP_EVIDENCE',
      'SIMICHAT_IOS_REALTIME_PCM_INTERRUPTION_EVIDENCE',
      'SIMICHAT_IOS_REALTIME_PCM_ROUTE_CHANGE_EVIDENCE',
      'SIMICHAT_IOS_REALTIME_PCM_SMOKE_PASS',
    ]) {
      expect(test, contains(marker), reason: 'missing marker: $marker');
      expect(script, contains(marker), reason: 'script does not gate: $marker');
    }
    expect(test, contains('debugSimulateInterruption'));
    expect(test, contains('debugSimulateRouteUnavailable'));
    expect(test, contains('getDiagnostics'));
    expect(test, contains('writesAudioFiles'));
    expect(driver, contains('integrationDriver'));

    expect(script, contains('FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER'));
    expect(script, contains('SMOKE_BUNDLE_ID'));
    expect(script, contains('FORMAL_BUNDLE_ID'));
    expect(script, contains('BUILD_MODE'));
    expect(script, contains('hardwareProperties'));
    expect(
      script,
      isNot(contains('run_logged env')),
      reason: 'the local RTK env shim does not exec its arguments',
    );
    expect(script, contains('prepare_integration_test_dependency'));
    expect(script, contains('restore_pubspec'));
    expect(script, contains('pubspec.yaml.bak'));
    expect(script, contains('pubspec.lock.bak'));
    expect(script, contains('cleanup_smoke_app'));
    expect(script, contains('device uninstall app'));
    expect(script, contains('SMOKE_ISOLATED_PACKAGE_CLEANED'));
    expect(script, isNot(contains('device process terminate')));
    expect(script, isNot(contains('force-stop')));
    expect(script, isNot(contains('pm clear')));
    expect(script, isNot(contains('adb ')));
  });

  test('iOS realtime PCM smoke shell script is syntactically valid', () async {
    final result = await Process.run('bash', [
      '-n',
      'scripts/smoke_ios_realtime_pcm.sh',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
