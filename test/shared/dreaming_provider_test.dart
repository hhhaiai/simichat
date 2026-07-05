import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/dreaming_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('maybeRunDueDreaming runs once after configured time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kDreamingScheduleStorageKey: jsonEncode({
        'enabled': true,
        'hour': 8,
        'minute': 0,
      }),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.messageDao.insertMessage(
      id: 'm1',
      sessionId: 's1',
      role: 'user',
      content: '请记住我喜欢移动端优先和本地隐私。',
    );
    final targetDayMessageTime = DateTime(2026, 6, 27, 8, 30);
    await db.customStatement(
      "UPDATE messages SET created_at = ${targetDayMessageTime.millisecondsSinceEpoch} WHERE id = 'm1'",
    );

    DreamingDigest? firstRun;
    DreamingDigest? secondRun;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              return ElevatedButton(
                onPressed: () async {
                  final now = DateTime(2026, 6, 27, 9);
                  firstRun = await maybeRunDueDreaming(ref, now: now);
                  secondRun = await maybeRunDueDreaming(ref, now: now);
                },
                child: const Text('run'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(firstRun, isNotNull);
    expect(firstRun!.originalMessageCount, 1);
    expect(secondRun, isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
    expect(
      prefs.getString(kDreamingScheduleStorageKey),
      contains('2026-06-27'),
    );
  });
}
