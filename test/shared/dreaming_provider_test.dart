import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/dreaming_provider.dart';
import 'package:ai_chat_app/shared/providers/key_point_memory_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(resetDreamingAutoRunStateForTesting);
  tearDown(resetDreamingAutoRunStateForTesting);

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
    final jobs = await db.dreamingDao.getJobsByDay('2026-06-27');
    expect(jobs, hasLength(1));
    expect(jobs.single.status, 'completed');
    expect(jobs.single.trigger, 'foreground_due');
  });

  testWidgets('maybeRunDueDreaming ignores concurrent duplicate triggers', (
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
      content: '请记住我每天晚上需要整理当天重点。',
    );
    final targetDayMessageTime = DateTime(2026, 6, 27, 8, 30);
    await db.customStatement(
      "UPDATE messages SET created_at = ${targetDayMessageTime.millisecondsSinceEpoch} WHERE id = 'm1'",
    );

    List<DreamingDigest?> runs = const [];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              return ElevatedButton(
                onPressed: () async {
                  final now = DateTime(2026, 6, 27, 9);
                  runs = await Future.wait([
                    maybeRunDueDreaming(ref, now: now),
                    maybeRunDueDreaming(ref, now: now),
                  ]);
                },
                child: const Text('run concurrent'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('run concurrent'));
    await tester.pumpAndSettle();

    expect(runs.whereType<DreamingDigest>(), hasLength(1));
    expect(runs.where((digest) => digest == null), hasLength(1));
    expect(runs.whereType<DreamingDigest>().single.originalMessageCount, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(kDreamingScheduleStorageKey),
      contains('2026-06-27'),
    );
  });

  testWidgets(
    'maybeRunDueDreaming adopts completed automatic job without rerunning',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kDreamingScheduleStorageKey: jsonEncode({
          'enabled': true,
          'hour': 8,
          'minute': 0,
        }),
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.dreamingDao.createJob(
        id: 'dreaming-auto-2026-06-27',
        dayKey: '2026-06-27',
        scheduledFor: DateTime(2026, 6, 27, 8).millisecondsSinceEpoch,
        trigger: 'android_background',
      );
      await db.dreamingDao.markJobCompleted('dreaming-auto-2026-06-27');

      DreamingDigest? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () async {
                  result = await maybeRunDueDreaming(
                    ref,
                    now: DateTime(2026, 6, 27, 9),
                  );
                },
                child: const Text('adopt completed'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('adopt completed'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(await db.dreamingDao.getJobsByDay('2026-06-27'), hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kDreamingScheduleStorageKey),
        contains('2026-06-27'),
      );
    },
  );

  testWidgets('dreaming digest history keeps latest 20 reports by day', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    for (var i = 0; i < 22; i++) {
      final day = DateTime(2026, 6, 1 + i, 22);
      await db.sessionDao.createSession(id: 'history-session-$i');
      await db.messageDao.insertMessage(
        id: 'history-message-$i',
        sessionId: 'history-session-$i',
        role: 'user',
        content: '请记住 Dreaming 历史第 $i 天，我喜欢本地长期整理。',
      );
      await db.customStatement(
        "UPDATE messages SET created_at = ${day.millisecondsSinceEpoch} WHERE id = 'history-message-$i'",
      );
      await runDreamingDigest(capturedRef, day: day);
    }

    final history = capturedRef.read(dreamingDigestHistoryProvider);
    expect(history, hasLength(20));
    expect(history.first.dayKey, '2026-06-22');
    expect(history.last.dayKey, '2026-06-03');
    expect(
      history.map((digest) => digest.dayKey),
      isNot(contains('2026-06-01')),
    );
    expect(
      history.map((digest) => digest.dayKey),
      isNot(contains('2026-06-02')),
    );

    await runDreamingDigest(capturedRef, day: DateTime(2026, 6, 22, 23));
    final deduped = capturedRef.read(dreamingDigestHistoryProvider);
    expect(deduped, hasLength(20));
    expect(
      deduped.where((digest) => digest.dayKey == '2026-06-22'),
      hasLength(1),
    );

    final prefs = await SharedPreferences.getInstance();
    final rawHistory = prefs.getString(kDreamingDigestHistoryStorageKey);
    expect(rawHistory, isNotNull);
    expect(rawHistory, contains('2026-06-22'));
    expect(rawHistory, isNot(contains('2026-06-01')));

    await capturedRef
        .read(dreamingDigestHistoryProvider.notifier)
        .removeDay('2026-06-22');
    final removed = capturedRef.read(dreamingDigestHistoryProvider);
    expect(removed, hasLength(19));
    expect(
      removed.map((digest) => digest.dayKey),
      isNot(contains('2026-06-22')),
    );
    expect(
      prefs.getString(kDreamingDigestHistoryStorageKey),
      isNot(contains('2026-06-22')),
    );
  });

  testWidgets('runDreamingDigest persists sqlite job and report', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const sessionId = 'sqlite-dreaming-session';
    const messageId = 'sqlite-dreaming-message';
    final day = DateTime(2026, 7, 7, 22);
    await db.sessionDao.createSession(id: sessionId);
    await db.messageDao.insertMessage(
      id: messageId,
      sessionId: sessionId,
      role: 'user',
      content: '现在帮我继续推进 Dreaming 后台调度表持久化。',
    );
    await db.customStatement(
      "UPDATE messages SET created_at = ${day.millisecondsSinceEpoch} WHERE id = '$messageId'",
    );

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final digest = await runDreamingDigest(capturedRef, day: day);
    expect(digest.dayKey, '2026-07-07');

    final jobs = await db.dreamingDao.getJobsByDay('2026-07-07');
    expect(jobs, hasLength(1));
    expect(jobs.single.status, 'completed');
    expect(jobs.single.trigger, 'manual');
    expect(jobs.single.startedAt, isNotNull);
    expect(jobs.single.finishedAt, isNotNull);

    final report = await db.dreamingDao.getReportByDay('2026-07-07');
    expect(report, isNotNull);
    expect(report!.jobId, jobs.single.id);
    expect(report.markdown, contains('# Dreaming 日报 2026-07-07'));
    final reportJson = jsonDecode(report.digestJson) as Map;
    expect(reportJson['day'], startsWith('2026-07-07'));
    expect(report.originalMessageCount, 1);
    expect(report.memoryCandidateCount, digest.memoryCandidates.length);
  });

  testWidgets('runDreamingDigest reuses same-day in-flight job', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const sessionId = 'dedupe-dreaming-session';
    const messageId = 'dedupe-dreaming-message';
    final day = DateTime(2026, 7, 10, 22);
    await db.sessionDao.createSession(id: sessionId);
    await db.messageDao.insertMessage(
      id: messageId,
      sessionId: sessionId,
      role: 'user',
      content: '现在帮我验证 Dreaming job 去重，避免同一天前台整理重复落库。',
    );
    await db.customStatement(
      "UPDATE messages SET created_at = ${day.millisecondsSinceEpoch} WHERE id = '$messageId'",
    );

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final digests = await Future.wait([
      runDreamingDigest(capturedRef, day: day),
      runDreamingDigest(capturedRef, day: day),
    ]);

    expect(digests.map((digest) => digest.dayKey), everyElement('2026-07-10'));

    final jobs = await db.dreamingDao.getJobsByDay('2026-07-10');
    expect(jobs, hasLength(1));
    expect(jobs.single.status, 'completed');

    final report = await db.dreamingDao.getReportByDay('2026-07-10');
    expect(report, isNotNull);
    expect(report!.jobId, jobs.single.id);
    expect(capturedRef.read(dreamingDigestHistoryProvider), hasLength(1));
  });

  testWidgets('runDreamingDigest fails stale unfinished jobs before new run', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const sessionId = 'recover-dreaming-session';
    const messageId = 'recover-dreaming-message';
    final day = DateTime(2026, 7, 11, 22);
    await db.sessionDao.createSession(id: sessionId);
    await db.messageDao.insertMessage(
      id: messageId,
      sessionId: sessionId,
      role: 'user',
      content: '请继续补 Dreaming job 恢复策略，避免崩溃残留 pending 或 running 状态。',
    );
    await db.customStatement(
      "UPDATE messages SET created_at = ${day.millisecondsSinceEpoch} WHERE id = '$messageId'",
    );
    await db.dreamingDao.createJob(
      id: 'stale-pending',
      dayKey: '2026-07-11',
      scheduledFor: day.millisecondsSinceEpoch,
      createdAt: day
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
    );
    await db.dreamingDao.createJob(
      id: 'stale-running',
      dayKey: '2026-07-11',
      scheduledFor: day.millisecondsSinceEpoch,
      createdAt: day
          .subtract(const Duration(minutes: 9))
          .millisecondsSinceEpoch,
    );
    await db.dreamingDao.markJobRunning(
      'stale-running',
      startedAt: day
          .subtract(const Duration(minutes: 8))
          .millisecondsSinceEpoch,
    );

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final digest = await runDreamingDigest(capturedRef, day: day);

    expect(digest.dayKey, '2026-07-11');
    final jobs = await db.dreamingDao.getJobsByDay('2026-07-11');
    expect(jobs.where((job) => job.status == 'completed'), hasLength(1));
    expect(
      jobs.where((job) => job.status == 'pending' || job.status == 'running'),
      isEmpty,
    );

    final pending = await db.dreamingDao.getJob('stale-pending');
    final running = await db.dreamingDao.getJob('stale-running');
    expect(pending!.status, 'failed');
    expect(pending.error, contains('superseded'));
    expect(running!.status, 'failed');
    expect(running.error, contains('superseded'));
  });

  testWidgets(
    'runDreamingDigest failure marks job failed without publishing stale report',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      const sessionId = 'failed-dreaming-session';
      const messageId = 'failed-dreaming-message';
      final day = DateTime(2026, 7, 8, 22);
      await db.sessionDao.createSession(id: sessionId);
      await db.messageDao.insertMessage(
        id: messageId,
        sessionId: sessionId,
        role: 'user',
        content: '请记住 Dreaming 失败时不能把半成功日报发布给用户。',
      );
      await db.customStatement(
        "UPDATE messages SET created_at = ${day.millisecondsSinceEpoch} WHERE id = '$messageId'",
      );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            keyPointMemoryProvider.overrideWith(
              (ref) => _FailingRememberAllKeyPointMemoryNotifier(),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await expectLater(
        runDreamingDigest(capturedRef, day: day),
        throwsA(isA<StateError>()),
      );

      final jobs = await db.dreamingDao.getJobsByDay('2026-07-08');
      expect(jobs, hasLength(1));
      expect(jobs.single.status, 'failed');
      expect(jobs.single.error, contains('simulated key point persistence'));
      expect(jobs.single.finishedAt, isNotNull);

      expect(await db.dreamingDao.getReportByDay('2026-07-08'), isNull);
      expect(capturedRef.read(dreamingDigestProvider), isNull);
      expect(capturedRef.read(dreamingDigestHistoryProvider), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kDreamingDigestStorageKey), isNull);
      expect(prefs.getString(kDreamingDigestHistoryStorageKey), isNull);
    },
  );

  testWidgets(
    'runDreamingDigest does not complete job before provider state is durable',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      const sessionId = 'provider-failure-dreaming-session';
      const messageId = 'provider-failure-dreaming-message';
      final day = DateTime(2026, 7, 14, 22);
      await db.sessionDao.createSession(id: sessionId);
      await db.messageDao.insertMessage(
        id: messageId,
        sessionId: sessionId,
        role: 'user',
        content: '验证 Dreaming 在发布本地状态失败时不会留下静默 completed job。',
      );
      await db.customStatement(
        "UPDATE messages SET created_at = ${day.millisecondsSinceEpoch} WHERE id = '$messageId'",
      );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dreamingDigestProvider.overrideWith(
              (ref) => _FailingSaveDreamingDigestNotifier(),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await expectLater(
        runDreamingDigest(capturedRef, day: day),
        throwsA(isA<StateError>()),
      );

      final jobs = await db.dreamingDao.getJobsByDay('2026-07-14');
      expect(jobs, hasLength(1));
      expect(jobs.single.status, 'failed');
      expect(jobs.single.error, contains('simulated digest persistence'));
      expect(await db.dreamingDao.getReportByDay('2026-07-14'), isNotNull);
      expect(capturedRef.read(dreamingDigestHistoryProvider), isEmpty);
    },
  );

  testWidgets('syncs dreaming provider state from sqlite reports', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final generatedAt = DateTime(2026, 7, 9, 22, 30);
    final digest = DreamingDigest(
      day: DateTime(2026, 7, 9),
      generatedAt: generatedAt,
      sessionCount: 1,
      originalMessageCount: 2,
      userMessageCount: 1,
      assistantMessageCount: 1,
      sessions: [
        DreamingSessionDigest(
          sessionId: 'restored-session',
          title: '导入恢复会话',
          messageCount: 2,
          userMessageCount: 1,
          assistantMessageCount: 1,
          highlights: const ['恢复后的 Dreaming 报告应该重新出现在设置页'],
          firstMessageAt: generatedAt.subtract(const Duration(minutes: 5)),
          lastMessageAt: generatedAt,
          lastMessageRole: 'assistant',
          latestUserHighlight: '请恢复 Dreaming 报告',
        ),
      ],
      memoryCandidates: const [],
      keywords: const ['Dreaming', '恢复'],
      elapsedMs: 12,
    );
    await db.dreamingDao.upsertReport(
      id: 'dreaming-report-restored',
      dayKey: digest.dayKey,
      generatedAt: generatedAt.millisecondsSinceEpoch,
      markdown: digest.toMarkdown(),
      digestJson: jsonEncode(digest.toJson()),
      sessionCount: digest.sessionCount,
      originalMessageCount: digest.originalMessageCount,
      totalOriginalMessageCount: digest.totalOriginalMessageCount,
      memoryCandidateCount: digest.memoryCandidates.length,
      createdAt: generatedAt.millisecondsSinceEpoch,
    );

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(capturedRef.read(dreamingDigestProvider), isNull);
    expect(capturedRef.read(dreamingDigestHistoryProvider), isEmpty);

    final restored = await syncDreamingDigestStateFromDatabase(capturedRef);

    expect(restored, 1);
    expect(capturedRef.read(dreamingDigestProvider)?.dayKey, '2026-07-09');
    expect(capturedRef.read(dreamingDigestHistoryProvider), hasLength(1));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDreamingDigestStorageKey), contains('2026-07-09'));
    expect(
      prefs.getString(kDreamingDigestHistoryStorageKey),
      contains('2026-07-09'),
    );
  });

  testWidgets(
    'maybeRunDueDreaming returns digest if auto-run marker save fails',
    (tester) async {
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
        content: '请记住自动整理完成后即使标记失败也要继续后续处理。',
      );
      final targetDayMessageTime = DateTime(2026, 6, 28, 8, 30);
      await db.customStatement(
        "UPDATE messages SET created_at = ${targetDayMessageTime.millisecondsSinceEpoch} WHERE id = 'm1'",
      );

      DreamingDigest? firstRun;
      DreamingDigest? secondRun;
      Object? firstError;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dreamingScheduleProvider.overrideWith(
              (ref) => _FailingMarkAutoRunScheduleNotifier(),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                return ElevatedButton(
                  onPressed: () async {
                    final now = DateTime(2026, 6, 28, 9);
                    try {
                      firstRun = await maybeRunDueDreaming(ref, now: now);
                    } catch (error) {
                      firstError = error;
                    }
                    secondRun = await maybeRunDueDreaming(ref, now: now);
                  },
                  child: const Text('run marker failure'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('run marker failure'));
      await tester.pumpAndSettle();

      expect(firstError, isNull);
      expect(firstRun, isNotNull);
      expect(firstRun!.originalMessageCount, 1);
      expect(secondRun, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kDreamingDigestStorageKey), isNotNull);
      expect(
        prefs.getString(kDreamingScheduleStorageKey),
        isNot(contains('2026-06-28')),
      );
    },
  );
}

class _FailingMarkAutoRunScheduleNotifier extends DreamingScheduleNotifier {
  @override
  Future<void> markAutoRun(DateTime day) async {
    throw StateError('simulated schedule marker persistence failure');
  }
}

class _FailingRememberAllKeyPointMemoryNotifier extends KeyPointMemoryNotifier {
  @override
  Future<List<KeyPointMemoryItem>> rememberAll(
    List<KeyPointMemoryItem> items,
  ) async {
    throw StateError('simulated key point persistence failure');
  }
}

class _FailingSaveDreamingDigestNotifier extends DreamingDigestNotifier {
  @override
  Future<void> save(DreamingDigest digest) async {
    throw StateError('simulated digest persistence failure');
  }
}
