import 'dart:async';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/reflection_service.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/dreaming_provider.dart';
import 'package:ai_chat_app/shared/providers/reflection_provider.dart';
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
    expect(prefs.getString(kAssistantReflectionStorageKey), isNotNull);
    expect(prefs.getString(kAssistantReflectionHistoryStorageKey), isNotNull);
    expect(prefs.getString(kUserProfileStorageKey), isNull);
    final proposals = decodeUserProfileChangeProposals(
      prefs.getString(kUserProfileChangeProposalsStorageKey),
    );
    expect(proposals, hasLength(1));
    expect(proposals.single.diff.hasChanges, isTrue);
  });

  testWidgets(
    'dreaming dialog run survives closing route before digest returns',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final digestGate = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dreamingServiceProvider.overrideWithValue(
              _DelayedDreamingService(db: db, gate: digestGate),
            ),
          ],
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

      await tester.tap(find.text('Dreaming 夜间整理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('运行今日整理'));
      await tester.pumpAndSettle();

      expect(find.text('运行今日整理'), findsNothing);

      digestGate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
    },
  );

  testWidgets('reflection dialog previews short prompt injection', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 6, 22);
    final report = ReflectionReport(
      dayKey: '2026-07-06',
      generatedAt: now,
      sourceDigestDayKey: '2026-07-06',
      sessionCount: 1,
      originalMessageCount: 12,
      userMessageCount: 7,
      assistantMessageCount: 5,
      pendingProfileProposalCount: 0,
      insights: const [
        ReflectionInsight(
          category: '任务推进',
          text: '需要优先推进长会话质量基线。',
          priority: 'high',
        ),
      ],
      actionItems: const ['下次先推进长会话质量基线。'],
    );
    SharedPreferences.setMockInitialValues({
      kAssistantReflectionStorageKey: encodeReflectionReport(report),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('本地反思 / 自我优化'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('本地反思 / 自我优化'));
    await tester.pumpAndSettle();

    expect(find.text('下一轮短期提示预览'), findsOneWidget);
    expect(find.textContaining('下次先推进长会话质量基线'), findsWidgets);
  });
}

class _DelayedDreamingService extends DreamingService {
  _DelayedDreamingService({required AppDatabase db, required this.gate})
    : super(sessionDao: db.sessionDao, messageDao: db.messageDao);

  final Completer<void> gate;

  @override
  Future<DreamingDigest> runDailyDigest({
    DateTime? day,
    int maxMessages = 5000,
    int maxMemoryCandidates = 40,
  }) async {
    await gate.future;
    final now = DateTime(2026, 7, 6, 22);
    return DreamingDigest.empty(
      day: day ?? now,
      generatedAt: now,
      elapsedMs: 1,
    );
  }
}
