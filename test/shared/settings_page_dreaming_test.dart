import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/dreaming_provider.dart';
import 'package:ai_chat_app/shared/providers/user_profile_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings page can run local dreaming digest', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 's1');
    await db.sessionDao.updateTitle('s1', '用户画像');
    await db.messageDao.insertMessage(
      id: 'm1',
      sessionId: 's1',
      role: 'user',
      content: '请记住我喜欢中文总结，晚上帮我整理今天的重点。',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Dreaming 夜间整理'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Dreaming 夜间整理'), findsOneWidget);
    expect(find.textContaining('自动整理已开启'), findsOneWidget);

    await tester.tap(find.text('Dreaming 夜间整理'));
    await tester.pumpAndSettle();

    expect(find.text('运行今日整理'), findsOneWidget);
    expect(find.text('前台到期自动整理'), findsOneWidget);
    expect(find.text('整理时间'), findsOneWidget);
    expect(find.text('22:00'), findsWidgets);

    await tester.tap(find.text('运行今日整理'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dreaming 已完成'), findsOneWidget);
    expect(find.textContaining('待确认画像变更'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
    expect(prefs.getString(kUserProfileStorageKey), isNull);
    final proposals = decodeUserProfileChangeProposals(
      prefs.getString(kUserProfileChangeProposalsStorageKey),
    );
    expect(proposals, hasLength(1));
    expect(proposals.single.diff.hasChanges, isTrue);
  });
}
