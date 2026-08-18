import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release smoke scripts keep sqlite hook temporary and restorable', () {
    final helper = File(
      'scripts/lib/release_pubspec_hook.sh',
    ).readAsStringSync();
    final iosInstall = File(
      'scripts/smoke_ios_release_install_launch.sh',
    ).readAsStringSync();
    final iosSend = File(
      'scripts/smoke_ios_release_send.sh',
    ).readAsStringSync();
    final iosDeepLink = File(
      'scripts/smoke_ios_release_deep_link.sh',
    ).readAsStringSync();
    final iosNetwork = File(
      'scripts/smoke_ios_release_network_restore.sh',
    ).readAsStringSync();
    final androidInstall = File(
      'scripts/smoke_android_release_install_launch.sh',
    ).readAsStringSync();
    final fullStabilityGate = File(
      'scripts/smoke_full_stability_gate.sh',
    ).readAsStringSync();

    expect(helper, contains('simichat_release_pubspec_setup()'));
    expect(helper, contains('simichat_release_pubspec_restore()'));
    expect(helper, contains('source: system'));
    expect(helper, contains('pubspec.yaml.bak'));
    expect(helper, contains('pubspec.lock.bak'));
    expect(helper, contains('integration_test dev_dependency block not found'));

    for (final script in [
      iosInstall,
      iosSend,
      iosDeepLink,
      iosNetwork,
      androidInstall,
    ]) {
      expect(script, contains('source scripts/lib/release_pubspec_hook.sh'));
      expect(script, contains('trap cleanup EXIT'));
      expect(script, contains('simichat_release_pubspec_restore'));
    }

    expect(
      fullStabilityGate,
      contains('source scripts/lib/release_pubspec_hook.sh'),
    );
    expect(fullStabilityGate, contains('trap cleanup EXIT'));
    expect(fullStabilityGate, contains('simichat_release_pubspec_restore'));
    expect(fullStabilityGate, contains('simichat_release_pubspec_setup 0'));
    expect(fullStabilityGate, contains(r'--no-test-assets'));
    expect(fullStabilityGate, contains('Refusing --no-test-assets'));
    expect(fullStabilityGate, contains('shaders/ink_sparkle.frag'));
    expect(
      fullStabilityGate,
      contains(r'"$FLUTTER_BIN" --no-version-check test --no-pub -r expanded'),
    );

    expect(iosInstall, contains('simichat_release_pubspec_setup 0'));
    expect(iosSend, contains('simichat_release_pubspec_setup 0'));
    expect(iosNetwork, contains('simichat_release_pubspec_setup 0'));
    expect(androidInstall, contains('simichat_release_pubspec_setup 1'));
    expect(androidInstall, contains(r'adb -s "$DEVICE_ID" install -r'));
    expect(androidInstall, contains('--no-version-check build apk'));
    expect(androidInstall, contains(r'pidof "$PACKAGE_ID"'));
    expect(
      androidInstall,
      contains(
        r'LAUNCH_COMPONENT="${LAUNCH_COMPONENT:-${PACKAGE_ID}/.MainActivity}"',
      ),
    );
    expect(androidInstall, contains(r'adb -s "$DEVICE_ID" shell monkey'));
    expect(
      androidInstall,
      contains(r'adb -s "$DEVICE_ID" shell am start -n "$LAUNCH_COMPONENT"'),
    );
    expect(
      androidInstall,
      contains('SIMICHAT_ANDROID_RELEASE_LAUNCH_FALLBACK'),
    );
    expect(androidInstall, contains('SIMICHAT_ANDROID_RELEASE_LAUNCH_RESULT'));
    expect(androidInstall, contains('PID_POLL_ATTEMPTS'));
    expect(androidInstall, contains(r'sleep "$PID_POLL_INTERVAL_SECONDS"'));
    expect(androidInstall, isNot(contains('uninstall')));
    expect(androidInstall, isNot(contains('pm clear')));
  });

  test('release smoke shell scripts are syntactically valid', () async {
    final result = await Process.run('bash', [
      '-n',
      'scripts/lib/release_pubspec_hook.sh',
      'scripts/smoke_android_background_restore.sh',
      'scripts/smoke_android_background_stream_cancel.sh',
      'scripts/smoke_android_network_stream_cancel.sh',
      'scripts/smoke_android_deep_link.sh',
      'scripts/smoke_device_integration_audio_focus_loss.sh',
      'scripts/smoke_device_external_audio_focus.sh',
      'scripts/smoke_android_audio_focus_suite.sh',
      'scripts/smoke_android_release_install_launch.sh',
      'scripts/smoke_android_network_restore.sh',
      'scripts/smoke_ios_release_install_launch.sh',
      'scripts/smoke_ios_release_background_restore.sh',
      'scripts/smoke_ios_release_deep_link.sh',
      'scripts/smoke_ios_release_network_restore.sh',
      'scripts/smoke_ios_release_send.sh',
      'scripts/smoke_full_stability_gate.sh',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test(
    'release and integration smoke scripts use portable mktemp templates',
    () {
      final scripts = [
        'scripts/smoke_device_integration_send.sh',
        'scripts/smoke_device_integration_audio_focus_loss.sh',
        'scripts/smoke_device_external_audio_focus.sh',
        'scripts/smoke_android_background_stream_cancel.sh',
        'scripts/smoke_android_network_stream_cancel.sh',
        'scripts/smoke_android_deep_link.sh',
        'scripts/smoke_ios_release_background_restore.sh',
        'scripts/smoke_ios_release_deep_link.sh',
        'scripts/smoke_ios_release_network_restore.sh',
        'scripts/smoke_ios_release_install_launch.sh',
        'scripts/smoke_ios_release_send.sh',
      ];

      for (final path in scripts) {
        final content = File(path).readAsStringSync();
        expect(
          content,
          isNot(contains(RegExp(r'mktemp /tmp/[^\n]*XXXXXX\.[A-Za-z0-9]+'))),
          reason: '$path must keep XXXXXX at the end of mktemp templates',
        );
      }
    },
  );

  test('iOS release send smoke is guarded by release dart-defines', () {
    final main = File('lib/main.dart').readAsStringSync();
    final harness = File(
      'lib/core/smoke/release_send_smoke_harness.dart',
    ).readAsStringSync();
    final chatProvider = File(
      'lib/shared/providers/chat_provider.dart',
    ).readAsStringSync();
    final script = File('scripts/smoke_ios_release_send.sh').readAsStringSync();

    expect(main, contains('releaseSendSmokeEnabled'));
    expect(
      harness,
      contains("bool.fromEnvironment(\n  'SIMICHAT_RELEASE_SEND_SMOKE'"),
    );
    expect(
      harness,
      contains("String.fromEnvironment(\n  'SIMICHAT_RELEASE_SMOKE_RUN_ID'"),
    );
    expect(script, contains('--dart-define=SIMICHAT_RELEASE_SEND_SMOKE=true'));
    expect(
      script,
      contains(r'--dart-define=SIMICHAT_RELEASE_SMOKE_RUN_ID="$RUN_ID"'),
    );
    expect(
      script,
      contains(r'RESTORE_NORMAL_RELEASE="${RESTORE_NORMAL_RELEASE:-1}"'),
    );
    expect(script, contains('NEEDS_NORMAL_RESTORE=0'));
    expect(script, contains('assert_device_unlocked_for_launch'));
    expect(
      script,
      contains(
        'Refusing to install iOS release send smoke build while device is locked',
      ),
    );
    expect(
      script,
      contains(
        'Refusing to install iOS release send smoke build because launch preflight did not prove the device is unlocked',
      ),
    );
    expect(script, contains('RESULT_SOURCE="Documents/ai_chat/release_smoke"'));
    expect(harness, contains("_deleteStaleSmokeArchive"));
    expect(harness, contains('switchConversationModel'));
    expect(harness, contains('retryLastUserMessage'));
    expect(harness, contains('cancelStreaming'));
    expect(harness, contains('request.response.bufferOutput = false'));
    expect(
      chatProvider,
      contains('final subscription = _streamSubscriptions.remove(sessionId);'),
    );
    expect(
      chatProvider,
      contains('unawaited(subscription.cancel().catchError((_) {}))'),
    );
    expect(script, contains('modelSwitch.requestModel'));
    expect(script, contains('stop.partialReply'));
    expect(
      script.indexOf(r'assert_device_unlocked_for_launch "$DEVICE_ID"'),
      lessThan(script.indexOf('simichat_release_pubspec_setup 0')),
    );
    expect(script, contains(r'launch_release_app "$device" || true'));
  });

  test('Android network restore smoke has explicit safety gates', () {
    final script = File(
      'scripts/smoke_android_network_restore.sh',
    ).readAsStringSync();
    final test = File(
      'integration_test/mobile_network_restore_smoke_test.dart',
    ).readAsStringSync();

    expect(
      script,
      contains(r'REAL_NETWORK_TOGGLE="${REAL_NETWORK_TOGGLE:-0}"'),
    );
    expect(script, contains('Refusing to toggle device network'));
    expect(script, contains('svc wifi disable'));
    expect(script, contains('svc wifi enable'));
    expect(script, contains('cleanup_network'));
    expect(script, contains('trap cleanup EXIT'));
    expect(script, contains('mobile_network_restore_smoke_test.dart'));
    expect(script, contains('SIMICHAT_NETWORK_RESTORE_READY'));
    expect(
      script,
      contains(r'NETWORK_TOGGLE_MODE="${NETWORK_TOGGLE_MODE:-wifi_data}"'),
    );
    expect(script, contains('NETWORK_TOGGLE_MODE=airplane'));
    expect(script, contains('cmd connectivity airplane-mode enable'));
    expect(script, contains('cmd connectivity airplane-mode disable'));
    expect(script, contains('sqlite3'));
    expect(test, contains('当前网络不可用，已保留输入，联网后可重试'));
    expect(test, contains('网络已恢复，可发送保留的输入'));
    expect(test, contains('SIMICHAT_NETWORK_RESTORE_READY'));
    expect(test, contains('mobile network restore smoke draft 20260706'));
  });

  test('Android background restore smoke has explicit safety gates', () {
    final script = File(
      'scripts/smoke_android_background_restore.sh',
    ).readAsStringSync();
    final test = File(
      'integration_test/mobile_background_restore_smoke_test.dart',
    ).readAsStringSync();

    expect(
      script,
      contains(r'REAL_BACKGROUND_TOGGLE="${REAL_BACKGROUND_TOGGLE:-0}"'),
    );
    expect(script, contains('Refusing to background the device'));
    expect(script, contains('KEYCODE_HOME'));
    expect(script, contains(r'monkey -p "$PACKAGE_ID"'));
    expect(script, contains('SIMICHAT_BACKGROUND_RESTORE_READY'));
    expect(script, contains('cleanup'));
    expect(script, contains('trap cleanup EXIT'));
    expect(script, contains('sqlite3'));
    expect(test, contains('SIMICHAT_BACKGROUND_RESTORE_READY'));
    expect(test, contains('mobile background restore draft 20260706'));
    expect(test, contains('AppLifecycleState.resumed'));
  });

  test('Android background stream cancel smoke has explicit safety gates', () {
    final script = File(
      'scripts/smoke_android_background_stream_cancel.sh',
    ).readAsStringSync();
    final test = File(
      'integration_test/mobile_background_stream_cancel_smoke_test.dart',
    ).readAsStringSync();

    expect(script, contains('only for adb devices'));
    expect(script, contains('cleanup'));
    expect(script, contains('trap cleanup EXIT'));
    expect(script, contains('sqlite3'));
    expect(script, contains('mobile_background_stream_cancel_smoke_test.dart'));
    expect(test, contains('partial background stream reply 20260707'));
    expect(test, contains('backgroundStreamingInterruptedMessage'));
    expect(
      test,
      contains('handleAppLifecycleStateChanged(AppLifecycleState.inactive)'),
    );
    expect(
      test,
      contains('handleAppLifecycleStateChanged(AppLifecycleState.resumed)'),
    );
  });

  test('Android network stream cancel smoke has explicit safety gates', () {
    final script = File(
      'scripts/smoke_android_network_stream_cancel.sh',
    ).readAsStringSync();
    final test = File(
      'integration_test/mobile_network_stream_cancel_smoke_test.dart',
    ).readAsStringSync();

    expect(
      script,
      contains(r'REAL_NETWORK_TOGGLE="${REAL_NETWORK_TOGGLE:-0}"'),
    );
    expect(script, contains('Refusing to toggle device network'));
    expect(script, contains('svc wifi disable'));
    expect(script, contains('svc wifi enable'));
    expect(script, contains('cleanup_network'));
    expect(script, contains('trap cleanup EXIT'));
    expect(script, contains('mobile_network_stream_cancel_smoke_test.dart'));
    expect(script, contains('SIMICHAT_NETWORK_STREAM_CANCEL_READY'));
    expect(script, contains('SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED'));
    expect(
      script,
      contains(r'NETWORK_TOGGLE_MODE="${NETWORK_TOGGLE_MODE:-wifi_data}"'),
    );
    expect(script, contains('NETWORK_TOGGLE_MODE=airplane'));
    expect(script, contains('cmd connectivity airplane-mode enable'));
    expect(script, contains('cmd connectivity airplane-mode disable'));
    expect(script, contains('sqlite3'));
    expect(test, contains('partial network stream reply 20260707'));
    expect(test, contains('networkStreamingInterruptedMessage'));
    expect(test, contains('网络已恢复，可点“重试”继续'));
    expect(test, contains('SIMICHAT_NETWORK_STREAM_CANCEL_READY'));
    expect(test, contains('SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED'));
  });

  test('Android deep link smoke drives external VIEW intents', () {
    final script = File(
      'scripts/smoke_android_deep_link.sh',
    ).readAsStringSync();
    final test = File(
      'integration_test/mobile_deep_link_smoke_test.dart',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(script, contains('only for adb devices'));
    expect(script, contains('mobile_deep_link_smoke_test.dart'));
    expect(script, contains('android.intent.action.VIEW'));
    expect(script, contains(r'-n "$PACKAGE_ID/.MainActivity"'));
    expect(script, contains('ai-chat://settings'));
    expect(script, contains('ai-chat://session/deep-link-target-session'));
    expect(script, contains('SIMICHAT_DEEP_LINK_READY'));
    expect(script, contains('SIMICHAT_DEEP_LINK_SETTINGS_OK'));
    expect(script, contains('trap cleanup EXIT'));
    expect(script, contains('sqlite3'));
    expect(test, contains('Deep Link Target Smoke'));
    expect(test, contains('已打开链接中的会话'));
    expect(test, contains('SIMICHAT_DEEP_LINK_READY'));
    expect(test, contains('SIMICHAT_DEEP_LINK_SETTINGS_OK'));
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android.intent.category.BROWSABLE'));
    expect(manifest, contains('android:scheme="ai-chat"'));
  });

  test('Android audio focus loss smoke has debug-only simulation gate', () {
    final script = File(
      'scripts/smoke_device_integration_audio_focus_loss.sh',
    ).readAsStringSync();
    final test = File(
      'integration_test/mobile_audio_focus_loss_smoke_test.dart',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/top/simitalk/aichat/MainActivity.kt',
    ).readAsStringSync();

    expect(script, contains('only for adb devices'));
    expect(script, contains('mobile_audio_focus_loss_smoke_test.dart'));
    expect(script, contains('sqlite3'));
    expect(script, contains('trap cleanup EXIT'));
    expect(test, contains('requestCompetingAudioFocusForTesting'));
    expect(test, contains('abandonCompetingAudioFocusForTesting'));
    expect(test, contains('AudioPlaybackEventType.stopped'));
    expect(test, contains('AudioPlaybackEventType.completed'));
    expect(activity, contains('simulateAudioFocusLossForTesting'));
    expect(activity, contains('requestCompetingAudioFocusForTesting'));
    expect(activity, contains('abandonCompetingAudioFocusForTesting'));
    expect(activity, contains('ApplicationInfo.FLAG_DEBUGGABLE'));
    expect(activity, contains('AUDIOFOCUS_LOSS_TRANSIENT'));
  });

  test(
    'Android audio focus suite runs both focus smokes and restores release',
    () {
      final suite = File(
        'scripts/smoke_android_audio_focus_suite.sh',
      ).readAsStringSync();

      expect(suite, contains('smoke_device_integration_audio_focus_loss.sh'));
      expect(suite, contains('smoke_device_external_audio_focus.sh'));
      expect(suite, contains('smoke_android_release_install_launch.sh'));
      expect(
        suite,
        contains('Audio focus suite failed; restoring Android release build'),
      );
      expect(suite, contains(r'RESTORE_RELEASE="${RESTORE_RELEASE:-1}"'));
      expect(suite, contains('only for adb devices'));
      expect(suite, contains('trap cleanup EXIT'));
    },
  );

  test('iOS release deep link smoke is release-only and restorable', () {
    final main = File('lib/main.dart').readAsStringSync();
    final harness = File(
      'lib/core/smoke/release_deep_link_smoke_harness.dart',
    ).readAsStringSync();
    final script = File(
      'scripts/smoke_ios_release_deep_link.sh',
    ).readAsStringSync();

    expect(main, contains('releaseDeepLinkSmokeEnabled'));
    expect(main, contains('navigatorObservers'));
    expect(
      harness,
      contains("bool.fromEnvironment(\n  'SIMICHAT_RELEASE_DEEP_LINK_SMOKE'"),
    );
    expect(harness, contains('SIMICHAT_RELEASE_DEEP_LINK_SETTINGS_READY'));
    expect(harness, contains('releaseDeepLinkSmokeTargetSessionId'));
    expect(harness, contains('activeSessionIdProvider'));
    expect(harness, contains('NavigatorObserver'));
    expect(script, contains('SIMICHAT_RELEASE_DEEP_LINK_SMOKE=true'));
    expect(script, contains('SIMICHAT_RELEASE_DEEP_LINK_SETTINGS_READY'));
    expect(script, contains(r'--payload-url "$payload_url"'));
    expect(script, contains('ai-chat://settings'));
    expect(
      script,
      contains('ai-chat://session/ios-release-deep-link-target-session'),
    );
    expect(script, contains('assert_device_unlocked_for_launch'));
    expect(
      script,
      contains(
        'Refusing to install iOS deep link smoke build while device is locked',
      ),
    );
    expect(
      script,
      contains(
        'Refusing to install iOS deep link smoke build because launch preflight did not prove the device is unlocked',
      ),
    );
    expect(
      script,
      contains(r'RESTORE_NORMAL_RELEASE="${RESTORE_NORMAL_RELEASE:-1}"'),
    );
    expect(script, contains('simichat_release_pubspec_setup 0'));
    expect(script, contains('simichat_release_pubspec_restore'));
    expect(script, contains(r'restore_normal_release "$DEVICE_ID"'));
    expect(
      script.indexOf(r'assert_device_unlocked_for_launch "$DEVICE_ID"'),
      lessThan(script.indexOf('simichat_release_pubspec_setup 0')),
    );
  });

  test('iOS release background restore smoke is release-only and restorable', () {
    final main = File('lib/main.dart').readAsStringSync();
    final harness = File(
      'lib/core/smoke/release_background_smoke_harness.dart',
    ).readAsStringSync();
    final script = File(
      'scripts/smoke_ios_release_background_restore.sh',
    ).readAsStringSync();

    expect(main, contains('releaseBackgroundSmokeEnabled'));
    expect(
      harness,
      contains("bool.fromEnvironment(\n  'SIMICHAT_RELEASE_BACKGROUND_SMOKE'"),
    );
    expect(harness, contains('SIMICHAT_RELEASE_BACKGROUND_READY'));
    expect(harness, contains('AppLifecycleState.resumed'));
    expect(script, contains('SIMICHAT_RELEASE_BACKGROUND_SMOKE=true'));
    expect(script, contains('SIMICHAT_RELEASE_BACKGROUND_READY'));
    expect(script, contains('devicectl device process suspend'));
    expect(script, contains('devicectl device process resume'));
    expect(script, contains('assert_device_unlocked_for_launch'));
    expect(
      script,
      contains(
        'Checking iOS device unlock state before installing smoke build',
      ),
    );
    expect(
      script,
      contains(
        'Refusing to install iOS background smoke build while device is locked',
      ),
    );
    expect(
      script,
      contains(
        'Refusing to install iOS background smoke build because launch preflight did not prove the device is unlocked',
      ),
    );
    expect(
      script,
      contains(r'RESTORE_NORMAL_RELEASE="${RESTORE_NORMAL_RELEASE:-1}"'),
    );
    expect(script, contains('simichat_release_pubspec_setup 0'));
    expect(script, contains('simichat_release_pubspec_restore'));
    expect(
      script.indexOf(r'assert_device_unlocked_for_launch "$DEVICE_ID"'),
      lessThan(script.indexOf('simichat_release_pubspec_setup 0')),
    );
  });

  test('iOS release network restore smoke is release-only and restorable', () {
    final main = File('lib/main.dart').readAsStringSync();
    final harness = File(
      'lib/core/smoke/release_network_smoke_harness.dart',
    ).readAsStringSync();
    final script = File(
      'scripts/smoke_ios_release_network_restore.sh',
    ).readAsStringSync();

    expect(main, contains('releaseNetworkSmokeEnabled'));
    expect(
      harness,
      contains("bool.fromEnvironment(\n  'SIMICHAT_RELEASE_NETWORK_SMOKE'"),
    );
    expect(
      harness,
      contains(
        "String.fromEnvironment(\n  'SIMICHAT_RELEASE_NETWORK_SMOKE_RUN_ID'",
      ),
    );
    expect(harness, contains('connectivityMonitorProvider'));
    expect(harness, contains('ConnectivityResult.none'));
    expect(harness, contains('ConnectivityResult.wifi'));
    expect(harness, contains('当前网络不可用，已保留输入，联网后可重试'));
    expect(harness, contains('网络已恢复，可发送保留的输入'));
    expect(script, contains('SIMICHAT_RELEASE_NETWORK_SMOKE=true'));
    expect(script, contains('SIMICHAT_RELEASE_NETWORK_READY'));
    expect(script, contains('release_network_smoke'));
    expect(script, contains('assert_device_unlocked_for_launch'));
    expect(
      script,
      contains(
        'Refusing to install iOS network smoke build while device is locked',
      ),
    );
    expect(
      script,
      contains(
        'Refusing to install iOS network smoke build because launch preflight did not prove the device is unlocked',
      ),
    );
    expect(
      script,
      contains(r'RESTORE_NORMAL_RELEASE="${RESTORE_NORMAL_RELEASE:-1}"'),
    );
    expect(script, contains('simichat_release_pubspec_setup 0'));
    expect(script, contains('simichat_release_pubspec_restore'));
    expect(script, contains(r'restore_normal_release "$DEVICE_ID"'));
    expect(
      script.indexOf(r'assert_device_unlocked_for_launch "$DEVICE_ID"'),
      lessThan(script.indexOf('simichat_release_pubspec_setup 0')),
    );
  });
}
