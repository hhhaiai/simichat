import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android share channel uses FileProvider without broad root-path', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final paths = File(
      'android/app/src/main/res/xml/simichat_file_paths.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/aichat/ai_chat_app/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('androidx.core.content.FileProvider'));
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains(r'${applicationId}.fileprovider'));
    expect(manifest, contains('android:exported="false"'));
    expect(manifest, contains('android:grantUriPermissions="true"'));
    expect(paths, contains('name="app_flutter"'));
    expect(paths, isNot(contains('<root-path')));
    expect(activity, contains('simichat/data_export_share'));
    expect(activity, contains('OUTSIDE_APP_DATA'));
    expect(activity, contains('isSimiChatExportArchive'));
    expect(activity, contains('FLAG_GRANT_READ_URI_PERMISSION'));
  });

  test('iOS share channel validates export archive and app-private path', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(appDelegate, contains('simichat/data_export_share'));
    expect(appDelegate, contains('isSimiChatExportArchive'));
    expect(appDelegate, contains('OUTSIDE_APP_DATA'));
    expect(appDelegate, contains('UIActivityViewController'));
    expect(appDelegate, contains('popoverPresentationController'));
    expect(infoPlist, contains('NSLocalNetworkUsageDescription'));
    expect(infoPlist, contains('电脑端本地传输'));
  });
}
