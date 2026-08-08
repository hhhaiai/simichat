import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile shells register ai-chat custom URL scheme', () async {
    final androidManifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    final androidActivity = await File(
      'android/app/src/main/kotlin/top/simitalk/aichat/MainActivity.kt',
    ).readAsString();
    final iosInfoPlist = await File('ios/Runner/Info.plist').readAsString();
    final iosAppDelegate = await File(
      'ios/Runner/AppDelegate.swift',
    ).readAsString();
    final iosSceneDelegate = await File(
      'ios/Runner/SceneDelegate.swift',
    ).readAsString();

    expect(androidManifest, contains('android.intent.action.VIEW'));
    expect(androidManifest, contains('android.intent.category.BROWSABLE'));
    expect(androidManifest, contains('android:scheme="ai-chat"'));
    expect(androidActivity, contains('simichat/deep_link'));
    expect(androidActivity, contains('getInitialLink'));
    expect(androidActivity, contains('onNewIntent'));

    expect(iosInfoPlist, contains('CFBundleURLTypes'));
    expect(iosInfoPlist, contains('<string>ai-chat</string>'));
    expect(iosAppDelegate, contains('simichat/deep_link'));
    expect(iosAppDelegate, contains('application('));
    expect(iosAppDelegate, contains('open url: URL'));
    expect(iosSceneDelegate, contains('openURLContexts'));
    expect(iosSceneDelegate, contains('handleIncomingDeepLink'));
  });
}
