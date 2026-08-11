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

  test(
    'normal app startup initializes mobile Dreaming background work after first frame',
    () {
      final main = File('lib/main.dart').readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(pubspec, contains('workmanager:'));
      expect(main, contains('syncDreamingBackgroundScheduleFromStorage'));
      // 后台任务调度不能阻塞 iOS/Android 的 Flutter 首帧；AppBootstrap 在首帧
      // 呈现后才调度它，同时仍使用 Provider 管理的正常应用数据库。
      expect(
        main,
        contains('runApp(const ProviderScope(child: AppBootstrap()))'),
      );
      expect(main, contains('WidgetsBinding.instance.addPostFrameCallback'));
      expect(main, contains('runDeferredAppStartupTasks'));
      expect(
        main,
        contains('unawaited(runStartupTasks(ref.read(databaseProvider)))'),
      );
    },
  );

  test('Dreaming settings reschedule mobile system background work', () {
    final settings = File(
      'lib/features/settings/settings_page.dart',
    ).readAsStringSync();

    expect(settings, contains('syncDreamingBackgroundSchedule'));
    expect(settings, contains('系统后台择机执行'));
  });
}
