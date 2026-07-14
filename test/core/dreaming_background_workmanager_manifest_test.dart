import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android WorkManager owns a headless Dreaming callback', () {
    final source = File(
      'lib/core/background/dreaming_background_workmanager.dart',
    ).readAsStringSync();

    expect(source, contains("@pragma('vm:entry-point')"));
    expect(source, contains('Workmanager().executeTask'));
    expect(source, contains('DartPluginRegistrant.ensureInitialized'));
    expect(source, contains('ProviderContainer'));
    expect(source, contains('AppDatabase()'));
    expect(source, contains('runDreamingBackgroundTask'));
    expect(source, contains('NotificationService'));
    expect(source, contains('registerOneOffTask'));
    expect(source, contains('ExistingWorkPolicy.replace'));
    expect(source, contains('cancelByTag'));
    expect(source, contains('!kIsWeb'));
    expect(source, isNot(contains("import 'dart:io'")));
  });

  test('normal app startup initializes mobile Dreaming background work', () {
    final main = File('lib/main.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('workmanager:'));
    expect(main, contains('syncDreamingBackgroundScheduleFromStorage'));
    expect(
      main.indexOf('syncDreamingBackgroundScheduleFromStorage'),
      lessThan(main.indexOf('runApp(const ProviderScope')),
    );
  });

  test('Dreaming settings reschedule mobile system background work', () {
    final settings = File(
      'lib/features/settings/settings_page.dart',
    ).readAsStringSync();

    expect(settings, contains('syncDreamingBackgroundSchedule'));
    expect(settings, contains('系统后台择机执行'));
  });
}
