import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS registers a BGProcessingTask before launch completes', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(infoPlist, contains('BGTaskSchedulerPermittedIdentifiers'));
    expect(infoPlist, contains('top.simitalk.aichat.dreaming.processing'));
    expect(infoPlist, contains('<key>UIBackgroundModes</key>'));
    expect(infoPlist, contains('<string>processing</string>'));

    expect(appDelegate, contains('import workmanager_apple'));
    expect(
      appDelegate,
      contains('SwiftWorkmanagerPlugin.setPluginRegistrantCallback'),
    );
    expect(
      appDelegate,
      contains('SwiftWorkmanagerPlugin.registerBGProcessingTask'),
    );
    expect(
      appDelegate.indexOf('SwiftWorkmanagerPlugin.registerBGProcessingTask'),
      lessThan(
        appDelegate.indexOf(
          'return super.application(application, '
          'didFinishLaunchingWithOptions: launchOptions)',
        ),
      ),
    );
  });

  test('Flutter schedules and handles the iOS Dreaming processing task', () {
    final background = File(
      'lib/core/background/dreaming_background_workmanager.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final settings = File(
      'lib/features/settings/settings_page.dart',
    ).readAsStringSync();

    expect(background, contains('TargetPlatform.iOS'));
    expect(
      background,
      contains('SIMICHAT_IOS_BACKGROUND_DREAMING_TASK_IDENTIFIER'),
    );
    expect(
      background,
      contains("defaultValue: 'top.simitalk.aichat.dreaming.processing'"),
    );
    expect(background, contains('registerProcessingTask'));
    expect(background, contains('cancelByUniqueName'));
    expect(background, contains("isIosTask ? 'ios_background'"));
    expect(background, contains('const Duration(minutes: 15)'));
    expect(background, contains('syncDreamingBackgroundScheduleFromStorage'));

    expect(main, contains('syncDreamingBackgroundScheduleFromStorage'));
    expect(
      main,
      isNot(contains('syncAndroidDreamingBackgroundScheduleFromStorage')),
    );
    expect(settings, contains('syncDreamingBackgroundSchedule'));
    expect(settings, contains('iOS BGTaskScheduler'));
  });
}
