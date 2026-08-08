import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile app display name and package identifiers are SimiAIChat', () {
    final androidGradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final androidActivity = File(
      'android/app/src/main/kotlin/top/simitalk/aichat/MainActivity.kt',
    ).readAsStringSync();
    final iosInfoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(androidGradle, contains('namespace = "top.simitalk.aichat"'));
    expect(androidGradle, contains('applicationId = "top.simitalk.aichat"'));
    expect(androidManifest, contains('android:label="SimiAIChat"'));
    expect(androidActivity, contains('package top.simitalk.aichat'));
    expect(iosInfoPlist, contains('<string>SimiAIChat</string>'));
    expect(
      iosProject,
      contains('PRODUCT_BUNDLE_IDENTIFIER = top.simitalk.aichat;'),
    );
  });
}
