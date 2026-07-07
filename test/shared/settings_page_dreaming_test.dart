import 'dart:async';
import 'dart:convert';

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
  testWidgets('dreaming tile explains foreground-only schedule boundary', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
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
      find.text('Dreaming 夜间整理'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Dreaming 夜间整理'), findsOneWidget);
    expect(find.textContaining('前台到期'), findsOneWidget);
    expect(find.textContaining('非系统后台'), findsOneWidget);
    expect(find.textContaining('下次前台整理'), findsOneWidget);
  });

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

  testWidgets('dreaming UI shows truncated coverage as processed over total', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dreamingServiceProvider.overrideWithValue(
            _TruncatedDreamingService(db: db),
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

    expect(find.textContaining('Dreaming 已完成：2 / 5 条消息'), findsOneWidget);
    expect(find.textContaining('最近 2026-07-06 · 2 / 5 条消息'), findsOneWidget);
  });

  testWidgets('dreaming dialog shows retained report history', (tester) async {
    final first = _digestForDay(day: DateTime(2026, 7, 6), messageCount: 8);
    final second = _digestForDay(day: DateTime(2026, 7, 5), messageCount: 4);
    SharedPreferences.setMockInitialValues({
      kDreamingDigestHistoryStorageKey: jsonEncode([
        first.toJson(),
        second.toJson(),
      ]),
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
      find.text('Dreaming 夜间整理'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('历史 2 次'), findsOneWidget);

    await tester.tap(find.text('Dreaming 夜间整理'));
    await tester.pumpAndSettle();

    expect(find.text('暂无 Dreaming 报告。'), findsOneWidget);
    expect(find.text('历史报告已保留 2 次'), findsOneWidget);
    expect(find.textContaining('2026-07-06 · 8 条消息'), findsOneWidget);
    expect(find.textContaining('2026-07-05 · 4 条消息'), findsOneWidget);
    expect(find.textContaining('Dreaming 日报 2026-07-06'), findsNothing);

    await tester.tap(find.text('2026-07-06 · 8 条消息'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dreaming 日报 2026-07-06'), findsOneWidget);
    expect(find.textContaining('历史重点'), findsWidgets);
  });

  testWidgets('dreaming dialog can clear retained reports', (tester) async {
    final latest = _digestForDay(day: DateTime(2026, 7, 6), messageCount: 8);
    final previous = _digestForDay(day: DateTime(2026, 7, 5), messageCount: 4);
    SharedPreferences.setMockInitialValues({
      kDreamingDigestStorageKey: jsonEncode(latest.toJson()),
      kDreamingDigestHistoryStorageKey: jsonEncode([
        latest.toJson(),
        previous.toJson(),
      ]),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedDreamingReport(db, latest);
    await _seedDreamingReport(db, previous);

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

    await tester.tap(find.text('Dreaming 夜间整理'));
    await tester.pumpAndSettle();

    expect(find.textContaining('最近报告：2026-07-06'), findsOneWidget);
    expect(find.text('历史报告已保留 2 次'), findsOneWidget);

    await tester.tap(find.text('清空报告'));
    await tester.pumpAndSettle();

    expect(find.text('暂无 Dreaming 报告。'), findsOneWidget);
    expect(find.text('暂无历史报告。'), findsOneWidget);
    expect(find.text('Dreaming 报告已清空'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), isNull);
    expect(prefs.getString(kDreamingDigestHistoryStorageKey), isNull);
    expect(await db.dreamingDao.getRecentReports(), isEmpty);
  });

  testWidgets('dreaming dialog can delete one retained report', (tester) async {
    final latest = _digestForDay(day: DateTime(2026, 7, 6), messageCount: 8);
    final previous = _digestForDay(day: DateTime(2026, 7, 5), messageCount: 4);
    SharedPreferences.setMockInitialValues({
      kDreamingDigestStorageKey: jsonEncode(latest.toJson()),
      kDreamingDigestHistoryStorageKey: jsonEncode([
        latest.toJson(),
        previous.toJson(),
      ]),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedDreamingReport(db, latest);
    await _seedDreamingReport(db, previous);

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

    await tester.tap(find.text('Dreaming 夜间整理'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('2026-07-06 · 8 条消息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-07-06 · 8 条消息'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('删除此报告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除此报告'));
    await tester.pumpAndSettle();

    expect(find.textContaining('最近报告：2026-07-05'), findsOneWidget);
    expect(find.text('历史报告已保留 1 次'), findsOneWidget);
    expect(find.text('2026-07-06 · 8 条消息'), findsNothing);
    expect(find.text('2026-07-05 · 4 条消息'), findsOneWidget);
    expect(find.text('已删除 Dreaming 报告：2026-07-06'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), contains('2026-07-05'));
    final rawHistory = prefs.getString(kDreamingDigestHistoryStorageKey);
    expect(rawHistory, isNotNull);
    expect(rawHistory, contains('2026-07-05'));
    expect(rawHistory, isNot(contains('2026-07-06')));
    expect(await db.dreamingDao.getReportByDay('2026-07-06'), isNull);
    expect(await db.dreamingDao.getReportByDay('2026-07-05'), isNotNull);
  });

  testWidgets('dreaming dialog surfaces failed job and retries it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final failedDay = DateTime(2026, 7, 6, 22);
    await db.dreamingDao.createJob(
      id: 'failed-retry-job',
      dayKey: '2026-07-06',
      scheduledFor: failedDay.millisecondsSinceEpoch,
      trigger: 'foreground_due',
      createdAt: failedDay
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
    );
    await db.dreamingDao.markJobRunning(
      'failed-retry-job',
      startedAt: failedDay
          .subtract(const Duration(minutes: 9))
          .millisecondsSinceEpoch,
    );
    await db.dreamingDao.markJobFailed(
      'failed-retry-job',
      error: 'simulated retryable failure',
      finishedAt: failedDay
          .subtract(const Duration(minutes: 8))
          .millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dreamingServiceProvider.overrideWithValue(
            _RetryDreamingService(db: db),
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

    expect(find.textContaining('最近失败 2026-07-06'), findsOneWidget);

    await tester.tap(find.text('Dreaming 夜间整理'));
    await tester.pumpAndSettle();

    expect(find.textContaining('最近 Dreaming 失败：2026-07-06'), findsOneWidget);
    expect(find.textContaining('simulated retryable failure'), findsOneWidget);

    await tester.tap(find.text('重试最近失败'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dreaming 已完成'), findsOneWidget);
    expect(find.textContaining('最近失败 2026-07-06'), findsNothing);
    expect(await db.dreamingDao.getLatestUnresolvedFailedJob(), isNull);
    final jobs = await db.dreamingDao.getJobsByDay('2026-07-06');
    expect(jobs.where((job) => job.status == 'completed'), hasLength(1));
  });

  testWidgets('dreaming dialog can dismiss failed job prompt', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final failedDay = DateTime(2026, 7, 6, 22);
    await db.dreamingDao.createJob(
      id: 'failed-dismiss-job',
      dayKey: '2026-07-06',
      scheduledFor: failedDay.millisecondsSinceEpoch,
      trigger: 'foreground_due',
      createdAt: failedDay.millisecondsSinceEpoch,
    );
    await db.dreamingDao.markJobRunning(
      'failed-dismiss-job',
      startedAt: failedDay
          .add(const Duration(milliseconds: 100))
          .millisecondsSinceEpoch,
    );
    await db.dreamingDao.markJobFailed(
      'failed-dismiss-job',
      error: 'dismissible failure',
      finishedAt: failedDay
          .add(const Duration(milliseconds: 200))
          .millisecondsSinceEpoch,
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

    expect(find.textContaining('最近失败 2026-07-06'), findsOneWidget);

    await tester.tap(find.text('Dreaming 夜间整理'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最近 Dreaming 失败：2026-07-06'), findsOneWidget);

    await tester.tap(find.text('清除此失败'));
    await tester.pumpAndSettle();

    expect(find.textContaining('最近 Dreaming 失败：2026-07-06'), findsNothing);
    expect(find.textContaining('最近失败 2026-07-06'), findsNothing);
    expect(await db.dreamingDao.getLatestUnresolvedFailedJob(), isNull);
    final job = await db.dreamingDao.getJob('failed-dismiss-job');
    expect(job!.status, 'dismissed');
  });

  testWidgets('dreaming failed job error summary is sanitized', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final failedDay = DateTime(2026, 7, 7, 22);
    await db.dreamingDao.createJob(
      id: 'failed-secret-job',
      dayKey: '2026-07-07',
      scheduledFor: failedDay.millisecondsSinceEpoch,
      trigger: 'manual',
      createdAt: failedDay.millisecondsSinceEpoch,
    );
    await db.dreamingDao.markJobRunning(
      'failed-secret-job',
      startedAt: failedDay
          .add(const Duration(milliseconds: 100))
          .millisecondsSinceEpoch,
    );
    await db.dreamingDao.markJobFailed(
      'failed-secret-job',
      error:
          'Authorization Bearer sk-live-secret-token at /Users/sanbo/.simichat/key.txt https://example.test/stt?token=raw token=loose',
      finishedAt: failedDay
          .add(const Duration(milliseconds: 200))
          .millisecondsSinceEpoch,
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
    await tester.tap(find.text('Dreaming 夜间整理'));
    await tester.pumpAndSettle();

    expect(find.textContaining('手动运行'), findsOneWidget);
    expect(find.textContaining('Bearer ***'), findsOneWidget);
    expect(find.textContaining('[本机路径]'), findsOneWidget);
    expect(find.textContaining('[链接]'), findsOneWidget);
    expect(find.textContaining('token=***'), findsOneWidget);
    expect(find.textContaining('sk-live-secret-token'), findsNothing);
    expect(find.textContaining('/Users/sanbo'), findsNothing);
    expect(find.textContaining('https://example.test'), findsNothing);
    expect(find.textContaining('token=raw'), findsNothing);
  });

  testWidgets('dreaming manual run failure shows retryable feedback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.sessionDao.createSession(id: 'manual-failure-session');
    await db.messageDao.insertMessage(
      id: 'manual-failure-message',
      sessionId: 'manual-failure-session',
      role: 'user',
      content: '请记住手动 Dreaming 失败时也要给出可重试反馈。',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dreamingServiceProvider.overrideWithValue(
            _FailingDreamingService(db: db),
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

    expect(find.text('Dreaming 失败，可到设置页重试'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Dreaming 夜间整理'));
    await tester.pumpAndSettle();

    expect(find.textContaining('最近 Dreaming 失败：'), findsOneWidget);
    expect(find.textContaining('manual failure'), findsOneWidget);
    expect(await db.dreamingDao.getLatestUnresolvedFailedJob(), isNotNull);
  });

  testWidgets('reflection tile surfaces stale dreaming source', (tester) async {
    final report = _reflectionReport(
      '2026-07-07',
      sourceDigestDayKey: '2026-07-05',
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

    expect(find.text('本地反思 / 自我优化'), findsOneWidget);
    expect(find.textContaining('来源 2026-07-05'), findsOneWidget);
    expect(find.textContaining('先运行今日 Dreaming'), findsOneWidget);
  });

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

  testWidgets('reflection dialog can clear local report and history', (
    tester,
  ) async {
    final latest = _reflectionReport('2026-07-06');
    final previous = _reflectionReport('2026-07-05');
    SharedPreferences.setMockInitialValues({
      kAssistantReflectionStorageKey: encodeReflectionReport(latest),
      kAssistantReflectionHistoryStorageKey: encodeReflectionReportHistory([
        latest,
        previous,
      ]),
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

    expect(find.textContaining('最近反思：2026-07-06'), findsOneWidget);
    expect(find.textContaining('历史反思已保留 2 次'), findsOneWidget);

    await tester.tap(find.text('清空反思'));
    await tester.pumpAndSettle();

    expect(find.text('暂无本地反思报告。'), findsOneWidget);
    expect(find.text('本地反思报告已清空'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAssistantReflectionStorageKey), isNull);
    expect(prefs.getString(kAssistantReflectionHistoryStorageKey), isNull);
  });

  testWidgets('reflection dialog can delete current report and fall back', (
    tester,
  ) async {
    final latest = _reflectionReport('2026-07-06', actionItem: '最新反思动作。');
    final previous = _reflectionReport('2026-07-05', actionItem: '上一条反思动作。');
    SharedPreferences.setMockInitialValues({
      kAssistantReflectionStorageKey: encodeReflectionReport(latest),
      kAssistantReflectionHistoryStorageKey: encodeReflectionReportHistory([
        latest,
        previous,
      ]),
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

    expect(find.textContaining('最近反思：2026-07-06'), findsOneWidget);
    expect(find.text('历史反思已保留 2 次'), findsOneWidget);

    await tester.ensureVisible(find.text('2026-07-06 · 来源 2026-07-06'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-07-06 · 来源 2026-07-06'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最新反思动作。'), findsWidgets);

    await tester.ensureVisible(find.text('删除此反思'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除此反思'));
    await tester.pumpAndSettle();

    expect(find.text('已删除本地反思：2026-07-06 · 来源 2026-07-06'), findsOneWidget);
    expect(find.textContaining('最近反思：2026-07-05'), findsOneWidget);
    expect(find.text('历史反思已保留 1 次'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final current = decodeReflectionReport(
      prefs.getString(kAssistantReflectionStorageKey),
    );
    final history = decodeReflectionReportHistory(
      prefs.getString(kAssistantReflectionHistoryStorageKey),
    );
    expect(current?.dayKey, '2026-07-05');
    expect(history.map((item) => item.dayKey), ['2026-07-05']);
  });

  testWidgets('reflection dialog deletes only selected same-day source', (
    tester,
  ) async {
    final latest = _reflectionReport(
      '2026-07-06',
      sourceDigestDayKey: '2026-07-06',
      actionItem: '今天来源反思动作。',
    );
    final sameDayOtherSource = _reflectionReport(
      '2026-07-06',
      sourceDigestDayKey: '2026-07-05',
      actionItem: '昨天来源反思动作。',
    );
    SharedPreferences.setMockInitialValues({
      kAssistantReflectionStorageKey: encodeReflectionReport(latest),
      kAssistantReflectionHistoryStorageKey: encodeReflectionReportHistory([
        latest,
        sameDayOtherSource,
      ]),
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

    await tester.ensureVisible(find.text('2026-07-06 · 来源 2026-07-06'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-07-06 · 来源 2026-07-06'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('删除此反思'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除此反思'));
    await tester.pumpAndSettle();

    expect(find.text('已删除本地反思：2026-07-06 · 来源 2026-07-06'), findsOneWidget);
    expect(
      find.textContaining('最近反思：2026-07-06 · 来源 2026-07-05'),
      findsOneWidget,
    );

    final prefs = await SharedPreferences.getInstance();
    final current = decodeReflectionReport(
      prefs.getString(kAssistantReflectionStorageKey),
    );
    final history = decodeReflectionReportHistory(
      prefs.getString(kAssistantReflectionHistoryStorageKey),
    );
    expect(current?.sourceDigestDayKey, '2026-07-05');
    expect(history.map((item) => item.sourceDigestDayKey), ['2026-07-05']);
  });
}

DreamingDigest _digestForDay({
  required DateTime day,
  required int messageCount,
}) {
  final generatedAt = DateTime(day.year, day.month, day.day, 22);
  return DreamingDigest(
    day: day,
    generatedAt: generatedAt,
    sessionCount: 1,
    originalMessageCount: messageCount,
    totalOriginalMessageCount: messageCount,
    userMessageCount: messageCount,
    assistantMessageCount: 0,
    sessions: [
      DreamingSessionDigest(
        sessionId: 's-${day.day}',
        title: '历史会话 ${day.day}',
        messageCount: messageCount,
        userMessageCount: messageCount,
        assistantMessageCount: 0,
        highlights: const ['历史重点'],
        firstMessageAt: generatedAt.subtract(const Duration(minutes: 10)),
        lastMessageAt: generatedAt,
      ),
    ],
    memoryCandidates: const [],
    keywords: const ['历史'],
    elapsedMs: 1,
  );
}

Future<void> _seedDreamingReport(AppDatabase db, DreamingDigest digest) async {
  await db.dreamingDao.upsertReport(
    id: 'dreaming-report-${digest.dayKey}',
    dayKey: digest.dayKey,
    generatedAt: digest.generatedAt.millisecondsSinceEpoch,
    markdown: digest.toMarkdown(),
    digestJson: jsonEncode(digest.toJson()),
    sessionCount: digest.sessionCount,
    originalMessageCount: digest.originalMessageCount,
    totalOriginalMessageCount: digest.totalOriginalMessageCount,
    memoryCandidateCount: digest.memoryCandidates.length,
    createdAt: digest.generatedAt.millisecondsSinceEpoch,
  );
}

ReflectionReport _reflectionReport(
  String dayKey, {
  String? sourceDigestDayKey,
  String actionItem = '继续推进本地反思可控管理。',
}) {
  final generatedAt = DateTime.parse('${dayKey}T22:00:00Z');
  return ReflectionReport(
    dayKey: dayKey,
    generatedAt: generatedAt,
    sourceDigestDayKey: sourceDigestDayKey ?? dayKey,
    sessionCount: 1,
    originalMessageCount: 8,
    userMessageCount: 5,
    assistantMessageCount: 3,
    pendingProfileProposalCount: 0,
    insights: const [
      ReflectionInsight(
        category: '任务推进',
        text: '需要继续推进本地反思可控管理。',
        priority: 'high',
      ),
    ],
    actionItems: [actionItem],
  );
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

class _TruncatedDreamingService extends DreamingService {
  _TruncatedDreamingService({required AppDatabase db})
    : super(sessionDao: db.sessionDao, messageDao: db.messageDao);

  @override
  Future<DreamingDigest> runDailyDigest({
    DateTime? day,
    int maxMessages = 5000,
    int maxMemoryCandidates = 40,
  }) async {
    final now = DateTime(2026, 7, 6, 22);
    return DreamingDigest(
      day: day ?? now,
      generatedAt: now,
      sessionCount: 1,
      originalMessageCount: 2,
      totalOriginalMessageCount: 5,
      userMessageCount: 2,
      assistantMessageCount: 0,
      sessions: [
        DreamingSessionDigest(
          sessionId: 's1',
          title: '长会话',
          messageCount: 2,
          userMessageCount: 2,
          assistantMessageCount: 0,
          highlights: const ['最近任务需要继续推进'],
          firstMessageAt: now.subtract(const Duration(minutes: 2)),
          lastMessageAt: now,
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['稳定性'],
      elapsedMs: 1,
      isTruncated: true,
      messageLimit: 2,
    );
  }
}

class _RetryDreamingService extends DreamingService {
  _RetryDreamingService({required AppDatabase db})
    : super(sessionDao: db.sessionDao, messageDao: db.messageDao);

  @override
  Future<DreamingDigest> runDailyDigest({
    DateTime? day,
    int maxMessages = 5000,
    int maxMemoryCandidates = 40,
  }) async {
    final target = day ?? DateTime(2026, 7, 6, 22);
    return DreamingDigest.empty(
      day: target,
      generatedAt: DateTime(target.year, target.month, target.day, 22),
      elapsedMs: 1,
    );
  }
}

class _FailingDreamingService extends DreamingService {
  _FailingDreamingService({required AppDatabase db})
    : super(sessionDao: db.sessionDao, messageDao: db.messageDao);

  @override
  Future<DreamingDigest> runDailyDigest({
    DateTime? day,
    int maxMessages = 5000,
    int maxMemoryCandidates = 40,
  }) async {
    throw StateError('manual failure should be shown to the user');
  }
}
