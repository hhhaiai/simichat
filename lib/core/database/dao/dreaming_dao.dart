import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'dreaming_dao.g.dart';

@DriftAccessor(tables: [DreamingJobs, DreamingReports])
class DreamingDao extends DatabaseAccessor<AppDatabase>
    with _$DreamingDaoMixin {
  DreamingDao(super.db);

  Future<int> createJob({
    required String id,
    required String dayKey,
    required int scheduledFor,
    String trigger = 'foreground',
    int messageLimit = 5000,
    int? createdAt,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final timestamp = createdAt ?? now;
    return into(dreamingJobs).insert(
      DreamingJobsCompanion.insert(
        id: id,
        dayKey: dayKey,
        scheduledFor: scheduledFor,
        trigger: Value(trigger),
        messageLimit: Value(messageLimit),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  }

  Future<DreamingJob?> getJob(String id) {
    return (select(
      dreamingJobs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<DreamingJob>> getJobsByDay(String dayKey) {
    return (select(dreamingJobs)
          ..where((t) => t.dayKey.equals(dayKey))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<DreamingJob?> getLatestUnresolvedFailedJob({int limit = 20}) async {
    final safeLimit = limit < 1 ? 1 : limit;
    var offset = 0;
    while (true) {
      final failedJobs =
          await (select(dreamingJobs)
                ..where((t) => t.status.equals('failed'))
                ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
                ..limit(safeLimit, offset: offset))
              .get();
      if (failedJobs.isEmpty) return null;
      for (final failedJob in failedJobs) {
        final dayJobs = await getJobsByDay(failedJob.dayKey);
        final resolved = dayJobs.any(
          (job) =>
              job.status == 'completed' && job.updatedAt > failedJob.updatedAt,
        );
        if (!resolved) return failedJob;
      }
      if (failedJobs.length < safeLimit) return null;
      offset += safeLimit;
    }
  }

  Future<void> markJobRunning(String id, {int? startedAt}) {
    final timestamp = startedAt ?? DateTime.now().millisecondsSinceEpoch;
    return (update(dreamingJobs)..where((t) => t.id.equals(id))).write(
      DreamingJobsCompanion(
        status: const Value('running'),
        startedAt: Value(timestamp),
        updatedAt: Value(timestamp),
        error: const Value(null),
      ),
    );
  }

  Future<void> markJobCompleted(String id, {int? finishedAt}) {
    final timestamp = finishedAt ?? DateTime.now().millisecondsSinceEpoch;
    return (update(dreamingJobs)..where((t) => t.id.equals(id))).write(
      DreamingJobsCompanion(
        status: const Value('completed'),
        finishedAt: Value(timestamp),
        updatedAt: Value(timestamp),
        error: const Value(null),
      ),
    );
  }

  Future<void> markJobFailed(
    String id, {
    required String error,
    int? finishedAt,
  }) {
    final timestamp = finishedAt ?? DateTime.now().millisecondsSinceEpoch;
    return (update(dreamingJobs)..where((t) => t.id.equals(id))).write(
      DreamingJobsCompanion(
        status: const Value('failed'),
        finishedAt: Value(timestamp),
        updatedAt: Value(timestamp),
        error: Value(error),
      ),
    );
  }

  Future<void> dismissFailedJob(String id, {int? dismissedAt}) {
    final timestamp = dismissedAt ?? DateTime.now().millisecondsSinceEpoch;
    return (update(
      dreamingJobs,
    )..where((t) => t.id.equals(id) & t.status.equals('failed'))).write(
      DreamingJobsCompanion(
        status: const Value('dismissed'),
        updatedAt: Value(timestamp),
      ),
    );
  }

  Future<void> failUnfinishedJobsByDay(
    String dayKey, {
    required String error,
    int? finishedAt,
  }) {
    final timestamp = finishedAt ?? DateTime.now().millisecondsSinceEpoch;
    return (update(dreamingJobs)..where(
          (t) =>
              t.dayKey.equals(dayKey) &
              (t.status.equals('pending') | t.status.equals('running')),
        ))
        .write(
          DreamingJobsCompanion(
            status: const Value('failed'),
            finishedAt: Value(timestamp),
            updatedAt: Value(timestamp),
            error: Value(error),
          ),
        );
  }

  Future<int> upsertReport({
    required String id,
    required String dayKey,
    String? jobId,
    required int generatedAt,
    required String markdown,
    required String digestJson,
    required int sessionCount,
    required int originalMessageCount,
    required int totalOriginalMessageCount,
    required int memoryCandidateCount,
    bool isTruncated = false,
    int? createdAt,
  }) {
    return into(dreamingReports).insert(
      DreamingReportsCompanion.insert(
        id: id,
        dayKey: dayKey,
        jobId: Value(jobId),
        generatedAt: generatedAt,
        markdown: markdown,
        digestJson: digestJson,
        sessionCount: sessionCount,
        originalMessageCount: originalMessageCount,
        totalOriginalMessageCount: totalOriginalMessageCount,
        memoryCandidateCount: memoryCandidateCount,
        isTruncated: Value(isTruncated),
        createdAt: createdAt ?? generatedAt,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<DreamingReport?> getReportByDay(String dayKey) {
    return (select(
      dreamingReports,
    )..where((t) => t.dayKey.equals(dayKey))).getSingleOrNull();
  }

  Future<DreamingReport?> getLatestReport() {
    return (select(dreamingReports)
          ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<DreamingReport>> getRecentReports({int limit = 20}) {
    final safeLimit = limit < 1 ? 1 : limit;
    return (select(dreamingReports)
          ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)])
          ..limit(safeLimit))
        .get();
  }

  Future<void> deleteReportByDay(String dayKey) {
    return (delete(
      dreamingReports,
    )..where((t) => t.dayKey.equals(dayKey))).go();
  }

  Future<void> clearReports() {
    return delete(dreamingReports).go();
  }
}
