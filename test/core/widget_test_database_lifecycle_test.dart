import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('basic widget smoke uses disposable test database override', () {
    final source = File('test/widget_test.dart').readAsStringSync();

    expect(source, contains('AppDatabase.forTesting(NativeDatabase.memory())'));
    expect(source, contains('databaseProvider.overrideWithValue(db)'));
    expect(source, contains('addTearDown(db.close)'));
    expect(source, isNot(contains('ProviderScope(child: AiChatApp())')));
  });
}
