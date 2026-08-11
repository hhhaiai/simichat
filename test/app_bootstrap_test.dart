import 'dart:async';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a failed deferred startup step does not skip later steps', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final completed = <String>[];
    final failures = <String>[];

    await runDeferredAppStartupTasks(
      database,
      syncDreamingSchedule: () async {
        throw StateError('simulated scheduler failure');
      },
      initializeNotifications: () async {
        completed.add('notifications');
      },
      seedBuiltInSkills: (_) async {
        completed.add('skills');
      },
      onError: (taskName, _, _) => failures.add(taskName),
    );

    expect(failures, ['Background Dreaming schedule']);
    expect(completed, ['notifications', 'skills']);
  });

  testWidgets('first application frame is not blocked by deferred startup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final startupCompleter = Completer<void>();
    var startupCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: AppBootstrap(
          startupTasksRunner: (_) {
            startupCalls += 1;
            return startupCompleter.future;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AiChatApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(startupCalls, 1);

    startupCompleter.complete();
    await tester.pump();
  });
}
