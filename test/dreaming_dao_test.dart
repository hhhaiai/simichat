import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/database/dao/dreaming_dao.dart';

void main() {
  test('dreaming dao atomically claims one automatic job per day', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final first = await db.dreamingDao.claimAutomaticJob(
      id: 'dreaming-auto-2026-07-14',
      dayKey: '2026-07-14',
      scheduledFor: 1000,
      trigger: 'android_background',
      claimedAt: 1100,
      staleBefore: 100,
    );
    final concurrent = await db.dreamingDao.claimAutomaticJob(
      id: 'dreaming-auto-2026-07-14',
      dayKey: '2026-07-14',
      scheduledFor: 1000,
      trigger: 'foreground_due',
      claimedAt: 1200,
      staleBefore: 200,
    );

    expect(first, DreamingAutomaticJobClaim.claimed);
    expect(concurrent, DreamingAutomaticJobClaim.inFlight);

    await db.dreamingDao.markJobCompleted(
      'dreaming-auto-2026-07-14',
      finishedAt: 1300,
    );
    final completed = await db.dreamingDao.claimAutomaticJob(
      id: 'dreaming-auto-2026-07-14',
      dayKey: '2026-07-14',
      scheduledFor: 1000,
      trigger: 'android_background',
      claimedAt: 1400,
      staleBefore: 300,
    );
    expect(completed, DreamingAutomaticJobClaim.completed);
  });

  test('dreaming dao reclaims failed or stale automatic jobs', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.dreamingDao.claimAutomaticJob(
      id: 'dreaming-auto-failed',
      dayKey: '2026-07-15',
      scheduledFor: 1000,
      trigger: 'android_background',
      claimedAt: 1100,
      staleBefore: 100,
    );
    await db.dreamingDao.markJobFailed(
      'dreaming-auto-failed',
      error: 'temporary failure',
      finishedAt: 1200,
    );
    expect(
      await db.dreamingDao.claimAutomaticJob(
        id: 'dreaming-auto-failed',
        dayKey: '2026-07-15',
        scheduledFor: 1000,
        trigger: 'android_background',
        claimedAt: 1300,
        staleBefore: 300,
      ),
      DreamingAutomaticJobClaim.claimed,
    );

    await db.dreamingDao.claimAutomaticJob(
      id: 'dreaming-auto-stale',
      dayKey: '2026-07-16',
      scheduledFor: 2000,
      trigger: 'foreground_due',
      claimedAt: 2100,
      staleBefore: 100,
    );
    expect(
      await db.dreamingDao.claimAutomaticJob(
        id: 'dreaming-auto-stale',
        dayKey: '2026-07-16',
        scheduledFor: 2000,
        trigger: 'android_background',
        claimedAt: 4000,
        staleBefore: 3000,
      ),
      DreamingAutomaticJobClaim.claimed,
    );
  });

  test('dreaming dao persists job lifecycle and latest report', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final scheduledFor = DateTime.utc(2026, 7, 7, 22).millisecondsSinceEpoch;
    await db.dreamingDao.createJob(
      id: 'dreaming-job-1',
      dayKey: '2026-07-07',
      scheduledFor: scheduledFor,
      trigger: 'foreground_due',
      messageLimit: 5000,
      createdAt: scheduledFor - 1000,
    );

    var job = await db.dreamingDao.getJob('dreaming-job-1');
    expect(job, isNotNull);
    expect(job!.dayKey, '2026-07-07');
    expect(job.status, 'pending');
    expect(job.trigger, 'foreground_due');

    await db.dreamingDao.markJobRunning(
      'dreaming-job-1',
      startedAt: scheduledFor + 100,
    );
    job = await db.dreamingDao.getJob('dreaming-job-1');
    expect(job!.status, 'running');
    expect(job.startedAt, scheduledFor + 100);

    await db.dreamingDao.upsertReport(
      id: 'dreaming-report-1',
      dayKey: '2026-07-07',
      jobId: 'dreaming-job-1',
      generatedAt: scheduledFor + 200,
      markdown: '# Dreaming 日报 2026-07-07',
      digestJson: '{"dayKey":"2026-07-07","hasContent":true}',
      sessionCount: 2,
      originalMessageCount: 12,
      totalOriginalMessageCount: 12,
      memoryCandidateCount: 4,
      isTruncated: false,
      createdAt: scheduledFor + 200,
    );
    await db.dreamingDao.markJobCompleted(
      'dreaming-job-1',
      finishedAt: scheduledFor + 250,
    );

    job = await db.dreamingDao.getJob('dreaming-job-1');
    expect(job!.status, 'completed');
    expect(job.finishedAt, scheduledFor + 250);
    expect(job.error, isNull);

    final latest = await db.dreamingDao.getLatestReport();
    expect(latest, isNotNull);
    expect(latest!.dayKey, '2026-07-07');
    expect(latest.markdown, contains('Dreaming 日报'));
    expect(latest.memoryCandidateCount, 4);

    final byDay = await db.dreamingDao.getReportByDay('2026-07-07');
    expect(byDay!.id, latest.id);
  });

  test('dreaming report upsert keeps one report per day', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.dreamingDao.upsertReport(
      id: 'old-report',
      dayKey: '2026-07-07',
      generatedAt: 1000,
      markdown: 'old',
      digestJson: '{"version":1}',
      sessionCount: 1,
      originalMessageCount: 1,
      totalOriginalMessageCount: 1,
      memoryCandidateCount: 1,
      createdAt: 1000,
    );
    await db.dreamingDao.upsertReport(
      id: 'new-report',
      dayKey: '2026-07-07',
      generatedAt: 2000,
      markdown: 'new',
      digestJson: '{"version":2}',
      sessionCount: 1,
      originalMessageCount: 2,
      totalOriginalMessageCount: 2,
      memoryCandidateCount: 2,
      createdAt: 2000,
    );

    final reports = await db.dreamingDao.getRecentReports(limit: 20);
    expect(reports, hasLength(1));
    expect(reports.single.id, 'new-report');
    expect(reports.single.markdown, 'new');
    expect(reports.single.memoryCandidateCount, 2);
  });

  test('dreaming dao can fail unfinished jobs for a day', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.dreamingDao.createJob(
      id: 'pending-job',
      dayKey: '2026-07-10',
      scheduledFor: 1000,
      createdAt: 1000,
    );
    await db.dreamingDao.createJob(
      id: 'running-job',
      dayKey: '2026-07-10',
      scheduledFor: 1000,
      createdAt: 1100,
    );
    await db.dreamingDao.markJobRunning('running-job', startedAt: 1200);
    await db.dreamingDao.createJob(
      id: 'completed-job',
      dayKey: '2026-07-10',
      scheduledFor: 1000,
      createdAt: 900,
    );
    await db.dreamingDao.markJobCompleted('completed-job', finishedAt: 1300);

    await db.dreamingDao.failUnfinishedJobsByDay(
      '2026-07-10',
      error: 'superseded by a newer Dreaming run',
      finishedAt: 2000,
    );

    final pending = await db.dreamingDao.getJob('pending-job');
    final running = await db.dreamingDao.getJob('running-job');
    final completed = await db.dreamingDao.getJob('completed-job');

    expect(pending!.status, 'failed');
    expect(pending.finishedAt, 2000);
    expect(pending.error, contains('superseded'));
    expect(running!.status, 'failed');
    expect(running.finishedAt, 2000);
    expect(running.error, contains('superseded'));
    expect(completed!.status, 'completed');
    expect(completed.error, isNull);
  });

  test('dreaming dao returns latest unresolved failed job', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.dreamingDao.createJob(
      id: 'failed-job',
      dayKey: '2026-07-12',
      scheduledFor: 1000,
      createdAt: 1000,
    );
    await db.dreamingDao.markJobRunning('failed-job', startedAt: 1100);
    await db.dreamingDao.markJobFailed(
      'failed-job',
      error: 'simulated failure',
      finishedAt: 1200,
    );

    var unresolved = await db.dreamingDao.getLatestUnresolvedFailedJob();
    expect(unresolved, isNotNull);
    expect(unresolved!.id, 'failed-job');
    expect(unresolved.error, contains('simulated failure'));

    await db.dreamingDao.createJob(
      id: 'retry-completed-job',
      dayKey: '2026-07-12',
      scheduledFor: 1000,
      createdAt: 1300,
    );
    await db.dreamingDao.markJobRunning('retry-completed-job', startedAt: 1400);
    await db.dreamingDao.markJobCompleted(
      'retry-completed-job',
      finishedAt: 1500,
    );

    unresolved = await db.dreamingDao.getLatestUnresolvedFailedJob();
    expect(unresolved, isNull);
  });

  test(
    'dreaming dao scans past resolved failures for unresolved job',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.dreamingDao.createJob(
        id: 'older-unresolved-failed-job',
        dayKey: '2026-07-01',
        scheduledFor: 100,
        createdAt: 100,
      );
      await db.dreamingDao.markJobFailed(
        'older-unresolved-failed-job',
        error: 'still needs user attention',
        finishedAt: 200,
      );

      for (var i = 0; i < 21; i++) {
        final dayKey = '2026-08-${(i + 1).toString().padLeft(2, '0')}';
        final failedId = 'newer-resolved-failed-job-$i';
        final completedId = 'newer-resolved-completed-job-$i';
        final base = 1000 + i * 10;
        await db.dreamingDao.createJob(
          id: failedId,
          dayKey: dayKey,
          scheduledFor: base,
          createdAt: base,
        );
        await db.dreamingDao.markJobFailed(
          failedId,
          error: 'resolved failure $i',
          finishedAt: base + 1,
        );
        await db.dreamingDao.createJob(
          id: completedId,
          dayKey: dayKey,
          scheduledFor: base,
          createdAt: base + 2,
        );
        await db.dreamingDao.markJobCompleted(
          completedId,
          finishedAt: base + 3,
        );
      }

      final unresolved = await db.dreamingDao.getLatestUnresolvedFailedJob();

      expect(unresolved, isNotNull);
      expect(unresolved!.id, 'older-unresolved-failed-job');
    },
  );

  test('dreaming dao can dismiss a failed job', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.dreamingDao.createJob(
      id: 'dismissible-failed-job',
      dayKey: '2026-07-13',
      scheduledFor: 1000,
      createdAt: 1000,
    );
    await db.dreamingDao.markJobRunning(
      'dismissible-failed-job',
      startedAt: 1100,
    );
    await db.dreamingDao.markJobFailed(
      'dismissible-failed-job',
      error: 'user wants to ignore this failure',
      finishedAt: 1200,
    );

    await db.dreamingDao.dismissFailedJob(
      'dismissible-failed-job',
      dismissedAt: 1300,
    );

    final job = await db.dreamingDao.getJob('dismissible-failed-job');
    expect(job, isNotNull);
    expect(job!.status, 'dismissed');
    expect(job.updatedAt, 1300);
    expect(job.error, contains('user wants to ignore'));
    expect(await db.dreamingDao.getLatestUnresolvedFailedJob(), isNull);
  });
}
