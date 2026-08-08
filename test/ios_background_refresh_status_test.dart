import 'dart:io';

import 'package:ai_chat_app/core/background/dreaming_background_workmanager.dart';
import 'package:ai_chat_app/core/background/ios_background_refresh_status.dart';
import 'package:ai_chat_app/core/memory/dreaming_schedule.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(kIosBackgroundRefreshStatusChannelName),
          null,
        );
  });

  test('maps the native iOS background refresh status', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(kIosBackgroundRefreshStatusChannelName),
          (call) async {
            expect(call.method, 'getBackgroundRefreshStatus');
            return 1;
          },
        );

    expect(
      await readIosBackgroundRefreshStatus(),
      IosBackgroundRefreshStatus.denied,
    );
  });

  test('opens iOS app settings through the native status channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(kIosBackgroundRefreshStatusChannelName),
          (call) async {
            expect(call.method, 'openAppSettings');
            return true;
          },
        );

    expect(await openIosAppSettings(), isTrue);
  });

  test('denied background refresh produces actionable scheduling feedback', () {
    expect(
      () => ensureIosBackgroundRefreshAvailable(
        statusReader: () async => IosBackgroundRefreshStatus.denied,
      ),
      throwsA(
        isA<IosBackgroundRefreshUnavailableException>().having(
          (error) => error.userMessage,
          'userMessage',
          contains('后台 App 刷新已关闭'),
        ),
      ),
    );
  });

  test('iOS Dreaming schedule does not silently succeed when denied', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(kIosBackgroundRefreshStatusChannelName),
          (call) async => 1,
        );

    await expectLater(
      syncDreamingBackgroundSchedule(const DreamingScheduleConfig()),
      throwsA(isA<IosBackgroundRefreshUnavailableException>()),
    );
  });

  test('AppDelegate exposes the background refresh status channel', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains(kIosBackgroundRefreshStatusChannelName));
    expect(source, contains('getBackgroundRefreshStatus'));
    expect(source, contains('backgroundRefreshStatus.rawValue'));
    expect(source, contains('openAppSettings'));
    expect(source, contains('UIApplication.openSettingsURLString'));
  });
}
