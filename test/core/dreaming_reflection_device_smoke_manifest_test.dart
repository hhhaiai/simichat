import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Gradle supports an isolated smoke application id', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('gradleProperty("simichatApplicationId")'));
    expect(gradle, contains('applicationId = "top.simitalk.aichat"'));
  });

  test(
    'Dreaming Reflection device smoke harness uses isolated data and recovery',
    () {
      final harness = File(
        'lib/core/smoke/dreaming_reflection_smoke_harness.dart',
      ).readAsStringSync();

      expect(
        harness,
        contains('AppDatabase.forTesting(NativeDatabase.memory())'),
      );
      expect(harness, contains('dreamingReflectionSmokeEnabled'));
      expect(harness, contains('assistantReflectionPendingProvider'));
      expect(harness, contains('SIMICHAT_DREAMING_REFLECTION_PENDING'));
      expect(harness, contains('SIMICHAT_DREAMING_REFLECTION_RECOVERED'));
      expect(
        harness,
        contains('SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERY_SMOKE'),
      );
      expect(harness, contains('AppDatabase()'));
      expect(harness, contains('SIMICHAT_DREAMING_REFLECTION_SQLITE_READY'));
      expect(
        harness,
        contains('SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERED'),
      );
    },
  );

  test(
    'Dreaming Reflection device smoke script cleans and preserves release',
    () {
      final script = File(
        'scripts/smoke_device_dreaming_reflection_recovery.sh',
      ).readAsStringSync();

      expect(script, contains('top.simitalk.aichat.dreamingsmoke'));
      expect(script, contains(r'if [[ "$SMOKE_PACKAGE" == "$PACKAGE_ID" ]]'));
      expect(script, contains(r'if [[ "$SMOKE_PACKAGE" != "$PACKAGE_ID".* ]]'));
      expect(
        script.indexOf(r'if [[ "$SMOKE_PACKAGE" == "$PACKAGE_ID" ]]'),
        lessThan(
          script.indexOf(r'adb -s "$DEVICE_ID" uninstall "$SMOKE_PACKAGE"'),
        ),
      );
      expect(script, contains('ORG_GRADLE_PROJECT_simichatApplicationId'));
      expect(script, contains('--no-version-check build apk'));
      expect(script, isNot(contains('flutter test')));
      expect(
        script,
        contains(r'adb -s "$DEVICE_ID" uninstall "$SMOKE_PACKAGE"'),
      );
      expect(script, contains('SIMICHAT_DREAMING_REFLECTION_PENDING'));
      expect(script, contains('SIMICHAT_DREAMING_REFLECTION_RECOVERED'));
      expect(script, contains('SMOKE_SQLITE_RECOVERY'));
      expect(
        script,
        contains('SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERY_SMOKE=true'),
      );
      expect(script, contains('SIMICHAT_DREAMING_REFLECTION_SQLITE_READY'));
      expect(script, contains('SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERED'));
      expect(script, contains('am force-stop'));
      expect(script, contains('pidof'));
      expect(script, contains('firstInstallTime'));
      expect(
        script,
        contains('scripts/smoke_android_release_install_launch.sh'),
      );
      expect(script, contains('sqlite3'));
    },
  );
}
