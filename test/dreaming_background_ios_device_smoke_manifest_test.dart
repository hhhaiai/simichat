import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS background Dreaming smoke is release-only and isolated', () {
    final main = File('lib/main.dart').readAsStringSync();
    final harness = File(
      'lib/core/smoke/ios_background_dreaming_smoke_harness.dart',
    ).readAsStringSync();
    final background = File(
      'lib/core/background/dreaming_background_workmanager.dart',
    ).readAsStringSync();
    final script = File(
      'scripts/smoke_ios_release_background_dreaming.sh',
    ).readAsStringSync();

    expect(background, contains('SIMICHAT_IOS_BACKGROUND_DREAMING_SMOKE'));
    expect(main, contains('iosBackgroundDreamingSmokeEnabled'));
    expect(main, contains('runIosBackgroundDreamingSmokeApp'));
    expect(harness, contains('AppDatabase()'));
    expect(harness, contains('syncDreamingBackgroundSchedule'));
    expect(harness, contains('printScheduledTasks'));
    expect(harness, contains("'scheduledTasks'"));
    expect(harness, contains("'backgroundRefreshStatus'"));
    expect(harness, contains('readIosBackgroundRefreshStatus'));
    expect(harness, contains('SIMICHAT_IOS_BACKGROUND_DREAMING_READY'));
    expect(harness, contains('SIMICHAT_IOS_BACKGROUND_DREAMING_VERIFIED'));
    expect(harness, contains('writeIosBackgroundDreamingSmokeResult'));
    expect(background, contains('SIMICHAT_IOS_BACKGROUND_DREAMING_RESULT'));

    expect(script, contains('build ios --release'));
    expect(
      script,
      contains('--dart-define=SIMICHAT_IOS_BACKGROUND_DREAMING_SMOKE=true'),
    );
    expect(script, contains('top.simitalk.aichat.iosbackgroundsmoke'));
    expect(script, contains('top.simitalk.aichat.dreaming.processing'));
    expect(
      script,
      contains('SIMICHAT_IOS_BACKGROUND_DREAMING_TASK_IDENTIFIER'),
    );
    expect(script, contains('ios/Runner/AppDelegate.swift'));
    expect(script, contains('ios/Runner/Info.plist'));
    expect(script, contains('iOS background smoke launch preflight'));
    expect(script, contains('_simulateLaunchForTaskWithIdentifier'));
    expect(script, contains('device process attach'));
    expect(script, contains('GetState()'));
    expect(script, contains("StateAsCString"));
    expect(script, contains('"stopped"'));
    expect(script, contains('-l c --'));
    expect(script, contains('objc_msgSend'));
    expect(script, contains('-a false -t 5000000'));
    expect(script, isNot(contains('expression -l objc')));
    expect(script, contains('device copy from'));
    expect(script, contains('appDataContainer'));
    expect(script, contains('ios-background-dreaming-smoke.json'));
    expect(script, contains('scheduledTasks'));
    expect(script, contains('backgroundRefreshStatus'));
    expect(script, contains('PRODUCTION_APP_BEFORE'));
    expect(script, contains('Production app identity changed'));
    expect(script, contains('device uninstall app'));
    expect(script, contains('simichat_release_pubspec_setup'));
    expect(script, contains('simichat_release_pubspec_restore'));
    expect(script, isNot(contains('flutter test -d')));
  });
}
