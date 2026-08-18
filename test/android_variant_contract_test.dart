import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('Android app declares the complete smoke flavor matrix', () {
    final gradle = _read('android/app/build.gradle.kts');

    expect(gradle, contains('flavorDimensions += "smoke"'));
    expect(gradle, contains('create("production")'));
    expect(gradle, contains('create("modelswitch")'));
    expect(gradle, contains('create("realtimepcm")'));
    expect(gradle, contains('dimension = "smoke"'));
    expect(
      gradle,
      contains(
        'create("production") {\n            dimension = "smoke"\n            applicationId = "top.simitalk.aichat"',
      ),
    );
    expect(gradle, contains('isDebuggable = false'));
    expect(gradle, contains('applicationVariants.all'));
    expect(
      gradle,
      contains('productionRelease must keep applicationId=top.simitalk.aichat'),
    );
    expect(gradle, contains('gradleProperty("simichatApplicationId")'));
    expect(
      gradle,
      contains('applicationId = "top.simitalk.aichat.modelswitch"'),
    );
    expect(
      gradle,
      contains('applicationId = "top.simitalk.aichat.realtimepcm"'),
    );
  });

  test(
    'formal release smoke selects production and verifies install identity',
    () {
      final script = _read('scripts/smoke_android_release_install_launch.sh');

      expect(script, contains('FLAVOR="production"'));
      expect(script, contains('FORMAL_PACKAGE_ID="top.simitalk.aichat"'));
      expect(script, contains('PACKAGE_ID override is not allowed'));
      expect(script, contains(r'app-${FLAVOR}-release.apk'));
      expect(script, contains(r'--release --flavor "$FLAVOR" --no-pub'));
      expect(script, contains('EXPECTED_APK_PATH'));
      expect(script, contains('current-worktree production APK'));
      expect(script, contains('LAUNCH_COMPONENT override is not allowed'));
      expect(script, contains('simichatApplicationId override is not allowed'));
      expect(script, contains('apk_package_id'));
      expect(script, contains('dump badging'));
      expect(script, contains('apksigner'));
      expect(script, contains('BUILT_PACKAGE_ID'));
      expect(script, contains('BUILT_CERT_SHA256'));
      expect(script, contains('INSTALLED_CERT_SHA256'));
      expect(script, contains('ORIGINAL_CERT_SHA256'));
      expect(script, contains('application-debuggable'));
      expect(script, contains('DEBUGGABLE'));
      expect(script, contains('TEST_ONLY'));
      expect(script, contains('assert_no_isolated_smoke_packages'));
      expect(script, contains('pm list packages'));
      expect(script, contains('base.apk'));
      expect(script, contains('package_identity'));
      expect(script, contains('ORIGINAL_FIRST_INSTALL_TIME'));
      expect(script, contains('ORIGINAL_DATA_DIR'));
      expect(script, contains('ORIGINAL_APK_HASH'));
      expect(script, contains('BUILT_APK_HASH'));
      expect(script, contains('INSTALLED_APK_HASH'));
      expect(script, contains('ANDROID_RELEASE_PARITY status=verified'));
      expect(script, contains('sha256'));
      expect(script, contains(r'adb -s "$DEVICE_ID" install -r "$APK_PATH"'));
      expect(
        script,
        contains(r'adb -s "$DEVICE_ID" shell am start -n "$LAUNCH_COMPONENT"'),
      );
      expect(script, contains('ANDROID_RELEASE_FINAL_STATE'));
      expect(script, isNot(contains('uninstall')));
      expect(script, isNot(contains('pm clear')));
      expect(script, isNot(contains('force-stop')));
      expect(
        script,
        isNot(contains(r'PACKAGE_ID="${PACKAGE_ID:-top.simitalk.aichat}"')),
      );
    },
  );

  test(
    'model switch and realtime PCM smoke commands select isolated flavors',
    () {
      final modelSwitch = _read(
        'scripts/smoke_device_integration_model_switch.sh',
      );
      final realtimePcm = _read(
        'scripts/smoke_device_integration_realtime_pcm.sh',
      );

      expect(modelSwitch, contains('SMOKE_FLAVOR="modelswitch"'));
      expect(
        modelSwitch,
        contains('SMOKE_PACKAGE_ID="top.simitalk.aichat.modelswitch"'),
      );
      expect(modelSwitch, contains(r'--flavor "$SMOKE_FLAVOR"'));
      expect(modelSwitch.split(r'--flavor "$SMOKE_FLAVOR"').length - 1, 2);

      expect(realtimePcm, contains('SMOKE_FLAVOR="realtimepcm"'));
      expect(
        realtimePcm,
        contains('SMOKE_PACKAGE_ID="top.simitalk.aichat.realtimepcm"'),
      );
      expect(realtimePcm, contains(r'app-${SMOKE_FLAVOR}-debug.apk'));
      expect(realtimePcm, contains(r'--flavor "$SMOKE_FLAVOR"'));
      expect(realtimePcm.split(r'--flavor "$SMOKE_FLAVOR"').length - 1, 2);
      expect(realtimePcm, contains(r'install -r -d "$DEBUG_APK_PATH"'));
      expect(realtimePcm, contains('pm grant'));
      expect(
        realtimePcm,
        contains(r'"$SMOKE_PACKAGE_ID" android.permission.RECORD_AUDIO'),
      );
      expect(realtimePcm, contains(r'uninstall "$SMOKE_PACKAGE_ID"'));
      expect(realtimePcm, isNot(contains('RELEASE_APK_PATH')));
      expect(
        realtimePcm,
        isNot(contains(r'PACKAGE_ID="${PACKAGE_ID:-top.simitalk.aichat}"')),
      );
      expect(realtimePcm, isNot(contains(r'force-stop "$PACKAGE_ID"')));
    },
  );

  test(
    'voice recording smoke uses realtimepcm without formal package operations',
    () {
      final script = _read(
        'scripts/smoke_device_integration_voice_recording.sh',
      );

      expect(script, contains('SMOKE_FLAVOR="realtimepcm"'));
      expect(
        script,
        contains('SMOKE_PACKAGE_ID="top.simitalk.aichat.realtimepcm"'),
      );
      expect(script, contains(r'app-${SMOKE_FLAVOR}-debug.apk'));
      expect(script, contains(r'--flavor "$SMOKE_FLAVOR"'));
      expect(script.split(r'--flavor "$SMOKE_FLAVOR"').length - 1, 2);
      expect(script, contains(r'install -r -d "$APK_PATH"'));
      expect(script, contains('pm grant'));
      expect(
        script,
        contains(r'"$SMOKE_PACKAGE_ID" android.permission.RECORD_AUDIO'),
      );
      expect(script, contains(r'uninstall "$SMOKE_PACKAGE_ID"'));
      expect(script, isNot(contains('ANDROID_PACKAGE')));
      expect(script, isNot(contains(r'force-stop "$SMOKE_PACKAGE_ID"')));
      expect(script, isNot(contains(r'pm grant "$PACKAGE_ID"')));
    },
  );

  test(
    'Dreaming and background smoke retain dynamic package isolation on production',
    () {
      final reflection = _read(
        'scripts/smoke_device_dreaming_reflection_recovery.sh',
      );
      final background = _read(
        'scripts/smoke_device_android_background_dreaming.sh',
      );

      for (final script in [reflection, background]) {
        expect(script, contains('SMOKE_FLAVOR="production"'));
        expect(script, contains(r'app-${SMOKE_FLAVOR}-debug.apk'));
        expect(script, contains(r'--flavor "$SMOKE_FLAVOR"'));
        expect(script, contains('ORG_GRADLE_PROJECT_simichatApplicationId'));
      }
    },
  );

  test(
    'variant scripts are syntactically valid without touching a device',
    () async {
      final result = await Process.run('bash', [
        '-n',
        'scripts/smoke_android_release_install_launch.sh',
        'scripts/smoke_device_integration_model_switch.sh',
        'scripts/smoke_device_integration_realtime_pcm.sh',
        'scripts/smoke_device_integration_voice_recording.sh',
        'scripts/smoke_device_dreaming_reflection_recovery.sh',
        'scripts/smoke_device_android_background_dreaming.sh',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
