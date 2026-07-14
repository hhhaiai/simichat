import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS background refresh status script is read-only and build-free', () {
    final script = File(
      'scripts/check_ios_background_refresh_status.sh',
    ).readAsStringSync();

    expect(script, contains('backgroundRefreshStatus'));
    expect(script, contains('IOS_BACKGROUND_REFRESH_STATUS_OK'));
    expect(script, contains('restricted'));
    expect(script, contains('denied'));
    expect(script, contains('available'));
    expect(script, contains('Production app identity changed'));
    expect(script, contains('device process attach'));
    expect(script, contains('process detach'));
    expect(script, contains('MAX_LLDB_ATTEMPTS=2'));
    expect(script, contains('Retrying iOS background refresh status read'));
    expect(script, contains('/usr/bin/true'));
    expect(script, isNot(contains('build/ios')));
    expect(script, isNot(contains('Runner.app/Runner')));
    expect(script, isNot(contains('flutter build')));
    expect(script, isNot(contains('build ios')));
    expect(script, isNot(contains('device install app')));
    expect(script, isNot(contains('device uninstall app')));
    expect(script, isNot(contains('SIMICHAT_IOS_BACKGROUND_DREAMING_SMOKE')));
  });
}
