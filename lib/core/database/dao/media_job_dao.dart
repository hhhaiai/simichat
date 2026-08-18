import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables.dart';
import '../../media/media_job.dart';

part 'media_job_dao.g.dart';

const mediaJobPendingStatus = 'pending';
const mediaJobRunningStatus = 'running';
const mediaJobCompletedStatus = 'completed';
const mediaJobFailedStatus = 'failed';
const mediaJobExpiredStatus = 'expired';
const mediaJobCancelledStatus = 'cancelled';

const mediaJobDeliveryPlannedPhase = 'planned';
const mediaJobDeliverySavingPhase = 'saving';
const mediaJobDeliveryFileWrittenPhase = 'file_written';
const mediaJobDeliveryCompletedPhase = 'completed';
const mediaJobDeliveryFailedPhase = 'failed';

const _mediaJobActiveStatuses = <String>{
  mediaJobPendingStatus,
  mediaJobRunningStatus,
};

const _mediaJobTerminalStatuses = <String>{
  mediaJobCompletedStatus,
  mediaJobFailedStatus,
  mediaJobExpiredStatus,
  mediaJobCancelledStatus,
};

const _mediaJobLeaseMaxLength = 128;
const _mediaJobUuid = Uuid();

/// Drift 持久化层的媒体任务 DAO。
///
/// 所有状态迁移都在 SQL 条件中限制源状态；`claimJob` 通过一次条件
/// `UPDATE` 获得所有权，避免两个 isolate 同时恢复并轮询同一任务。
@DriftAccessor(tables: [MediaJobs])
class MediaJobDao extends DatabaseAccessor<AppDatabase>
    with _$MediaJobDaoMixin {
  MediaJobDao(super.db);

  Future<MediaJob?> getJob(String id) {
    return (select(mediaJobs)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 插入或更新任务。已进入 terminal 的记录不会被旧的 pending/running
  /// 状态回写；重试必须显式调用 [retryJob]。
  Future<MediaJob?> upsertJob({
    required String id,
    required String kind,
    required String status,
    String? sessionId,
    String? provider,
    String? model,
    String? endpoint,
    int? progress,
    String? phase,
    String? requestUrl,
    String? providerJobId,
    String? requestId,
    String? pollUrl,
    String? cancelUrl,
    String? contentUrl,
    String? assetPath,
    String? assetMime,
    String? assetExtension,
    String? prompt,
    String? error,
    int attempts = 0,
    int? createdAt,
    int? updatedAt,
    int? deadline,
    String? endpointStyle,
    String? leaseId,
    String? channelModelId,
    String? deliveryUserMessageId,
    String? deliveryAssistantMessageId,
    String? deliveryAttachmentId,
    String? deliverySourceAttachmentId,
    String? deliveryPhase,
    String? deliveryUserContent,
    String? deliveryAssistantContent,
    String? deliveryFileType,
    String? deliverySourcePath,
    String? deliverySourceFileName,
    String? deliverySourceFileType,
  }) async {
    final normalizedId = _required(id, 'id');
    final normalizedKind = _required(kind, 'kind');
    final normalizedStatus = _status(status);
    final normalizedProgress = _progress(progress);
    final now = DateTime.now().millisecondsSinceEpoch;
    final created = createdAt ?? now;
    final updated = updatedAt ?? now;
    final normalizedAttempts = attempts < 0 ? 0 : attempts;
    final normalizedLeaseId = _leaseId(leaseId);
    final companion = MediaJobsCompanion.insert(
      id: normalizedId,
      sessionId: Value(_optional(sessionId)),
      kind: normalizedKind,
      provider: Value(_safeText(provider, maxLength: 256)),
      model: Value(_safeText(model, maxLength: 256)),
      endpoint: Value(_safeEndpoint(endpoint)),
      status: normalizedStatus,
      progress: Value(normalizedProgress),
      phase: Value(_safeText(phase, maxLength: 64)),
      requestUrl: Value(_safeUrl(requestUrl)),
      providerJobId: Value(_safeText(providerJobId, maxLength: 512)),
      requestId: Value(_safeText(requestId, maxLength: 512)),
      pollUrl: Value(_safeUrl(pollUrl, preserveQuery: true)),
      cancelUrl: Value(_safeUrl(cancelUrl, preserveQuery: true)),
      contentUrl: Value(_safeUrl(contentUrl, preserveQuery: true)),
      assetPath: Value(_safeAppOwnedPath(assetPath)),
      assetMime: Value(_safeText(assetMime, maxLength: 128)),
      assetExtension: Value(_safeText(assetExtension, maxLength: 32)),
      prompt: Value(_safeText(prompt, maxLength: 4000)),
      error: Value(_safeText(error, maxLength: 512)),
      attempts: Value(normalizedAttempts),
      createdAt: created,
      updatedAt: updated,
      deadline: Value(deadline),
      endpointStyle: Value(_safeText(endpointStyle, maxLength: 32)),
      leaseId: Value(
        normalizedStatus == mediaJobRunningStatus ? normalizedLeaseId : null,
      ),
      channelModelId: Value(_safeText(channelModelId, maxLength: 256)),
      deliveryUserMessageId: Value(
        _safeText(deliveryUserMessageId, maxLength: 256),
      ),
      deliveryAssistantMessageId: Value(
        _safeText(deliveryAssistantMessageId, maxLength: 256),
      ),
      deliveryAttachmentId: Value(
        _safeText(deliveryAttachmentId, maxLength: 256),
      ),
      deliverySourceAttachmentId: Value(
        _safeText(deliverySourceAttachmentId, maxLength: 256),
      ),
      deliveryPhase: Value(_safeText(deliveryPhase, maxLength: 64)),
      deliveryUserContent: Value(
        _safeText(deliveryUserContent, maxLength: 4000),
      ),
      deliveryAssistantContent: Value(
        _safeText(deliveryAssistantContent, maxLength: 4000),
      ),
      deliveryFileType: Value(_safeText(deliveryFileType, maxLength: 32)),
      deliverySourcePath: Value(_safeAppOwnedPath(deliverySourcePath)),
      deliverySourceFileName: Value(
        _safeText(deliverySourceFileName, maxLength: 256),
      ),
      deliverySourceFileType: Value(
        _safeText(deliverySourceFileType, maxLength: 32),
      ),
    );
    final idempotentTerminalCompanion = MediaJobsCompanion(
      kind: Value(normalizedKind),
      status: Value(normalizedStatus),
      sessionId: sessionId == null
          ? const Value.absent()
          : Value(_optional(sessionId)),
      provider: provider == null
          ? const Value.absent()
          : Value(_safeText(provider, maxLength: 256)),
      model: model == null
          ? const Value.absent()
          : Value(_safeText(model, maxLength: 256)),
      endpoint: endpoint == null
          ? const Value.absent()
          : Value(_safeEndpoint(endpoint)),
      progress: normalizedProgress == null
          ? const Value.absent()
          : Value(normalizedProgress),
      phase: phase == null
          ? const Value.absent()
          : Value(_safeText(phase, maxLength: 64)),
      requestUrl: requestUrl == null
          ? const Value.absent()
          : Value(_safeUrl(requestUrl)),
      providerJobId: providerJobId == null
          ? const Value.absent()
          : Value(_safeText(providerJobId, maxLength: 512)),
      requestId: requestId == null
          ? const Value.absent()
          : Value(_safeText(requestId, maxLength: 512)),
      pollUrl: pollUrl == null
          ? const Value.absent()
          : Value(_safeUrl(pollUrl, preserveQuery: true)),
      cancelUrl: cancelUrl == null
          ? const Value.absent()
          : Value(_safeUrl(cancelUrl, preserveQuery: true)),
      contentUrl: contentUrl == null
          ? const Value.absent()
          : Value(_safeUrl(contentUrl, preserveQuery: true)),
      assetPath: assetPath == null
          ? const Value.absent()
          : Value(_safeAppOwnedPath(assetPath)),
      assetMime: assetMime == null
          ? const Value.absent()
          : Value(_safeText(assetMime, maxLength: 128)),
      assetExtension: assetExtension == null
          ? const Value.absent()
          : Value(_safeText(assetExtension, maxLength: 32)),
      prompt: prompt == null
          ? const Value.absent()
          : Value(_safeText(prompt, maxLength: 4000)),
      error: error == null
          ? const Value.absent()
          : Value(_safeText(error, maxLength: 512)),
      attempts: Value(normalizedAttempts),
      updatedAt: Value(updated),
      deadline: deadline == null ? const Value.absent() : Value(deadline),
      endpointStyle: endpointStyle == null
          ? const Value.absent()
          : Value(_safeText(endpointStyle, maxLength: 32)),
      // Terminal rows do not retain a worker lease. This also releases a
      // legacy lease when the same terminal state is refreshed idempotently.
      leaseId: const Value(null),
      channelModelId: channelModelId == null
          ? const Value.absent()
          : Value(_safeText(channelModelId, maxLength: 256)),
      deliveryUserMessageId: deliveryUserMessageId == null
          ? const Value.absent()
          : Value(_safeText(deliveryUserMessageId, maxLength: 256)),
      deliveryAssistantMessageId: deliveryAssistantMessageId == null
          ? const Value.absent()
          : Value(_safeText(deliveryAssistantMessageId, maxLength: 256)),
      deliveryAttachmentId: deliveryAttachmentId == null
          ? const Value.absent()
          : Value(_safeText(deliveryAttachmentId, maxLength: 256)),
      deliverySourceAttachmentId: deliverySourceAttachmentId == null
          ? const Value.absent()
          : Value(_safeText(deliverySourceAttachmentId, maxLength: 256)),
      deliveryPhase: deliveryPhase == null
          ? const Value.absent()
          : Value(_safeText(deliveryPhase, maxLength: 64)),
      deliveryUserContent: deliveryUserContent == null
          ? const Value.absent()
          : Value(_safeText(deliveryUserContent, maxLength: 4000)),
      deliveryAssistantContent: deliveryAssistantContent == null
          ? const Value.absent()
          : Value(_safeText(deliveryAssistantContent, maxLength: 4000)),
      deliveryFileType: deliveryFileType == null
          ? const Value.absent()
          : Value(_safeText(deliveryFileType, maxLength: 32)),
      deliverySourcePath: deliverySourcePath == null
          ? const Value.absent()
          : Value(_safeAppOwnedPath(deliverySourcePath)),
      deliverySourceFileName: deliverySourceFileName == null
          ? const Value.absent()
          : Value(_safeText(deliverySourceFileName, maxLength: 256)),
      deliverySourceFileType: deliverySourceFileType == null
          ? const Value.absent()
          : Value(_safeText(deliverySourceFileType, maxLength: 32)),
    );

    return transaction(() async {
      // INSERT OR IGNORE removes the read-then-write race for first creation.
      // Existing rows are changed only by the conditional UPDATE below; in
      // particular a different terminal state can never overwrite a terminal
      // state, even when two workers race in separate isolates.
      await into(mediaJobs).insert(companion, mode: InsertMode.insertOrIgnore);

      final changed =
          await (update(mediaJobs)..where(
                (t) =>
                    t.id.equals(normalizedId) &
                    _activeUpsertCondition(normalizedStatus, normalizedLeaseId),
              ))
              .write(companion);
      if (changed == 0 &&
          _mediaJobTerminalStatuses.contains(normalizedStatus)) {
        await (update(mediaJobs)..where(
              (t) =>
                  t.id.equals(normalizedId) & t.status.equals(normalizedStatus),
            ))
            .write(idempotentTerminalCompanion);
      }
      // The current row is intentionally returned after both the successful
      // and rejected paths so callers can reconcile with the authoritative
      // terminal state instead of assuming their stale result won.
      if (changed != 1) return getJob(normalizedId);
      return getJob(normalizedId);
    });
  }

  /// 原子地把 pending 任务 claim 为 running。
  ///
  /// 已 running 的任务只有在超过 [staleAfter] 后才允许被重新 claim；
  /// 默认值足以覆盖进程重启，同时避免并发启动的第二个 worker 抢占活任务。
  Future<MediaJob?> claimJob(
    String id, {
    DateTime? claimedAt,
    Duration staleAfter = const Duration(minutes: 2),
    String? leaseId,
    bool allowUnleasedRunning = false,
  }) async {
    final normalizedId = _required(id, 'id');
    final now = claimedAt ?? DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    final staleBefore = timestamp - staleAfter.inMilliseconds;
    final normalizedLeaseId = _leaseId(leaseId) ?? _mediaJobUuid.v4();
    return transaction(() async {
      final changed =
          await (update(mediaJobs)..where(
                (t) =>
                    t.id.equals(normalizedId) &
                    (t.status.equals(mediaJobPendingStatus) |
                        (t.status.equals(mediaJobRunningStatus) &
                            (t.updatedAt.isSmallerOrEqualValue(staleBefore) |
                                (allowUnleasedRunning
                                    ? t.leaseId.isNull()
                                    : const Constant(false))))),
              ))
              .write(
                MediaJobsCompanion(
                  status: const Value(mediaJobRunningStatus),
                  phase: const Value('polling'),
                  updatedAt: Value(timestamp),
                  leaseId: Value(normalizedLeaseId),
                ),
              );
      if (changed != 1) return null;
      return getJob(normalizedId);
    });
  }

  /// bool 形式的 claim 便捷 API，适合多个恢复 worker 竞争时使用。
  Future<bool> tryClaimJob(
    String id, {
    DateTime? claimedAt,
    Duration staleAfter = const Duration(minutes: 2),
    String? leaseId,
  }) async {
    return (await claimJob(
          id,
          claimedAt: claimedAt,
          staleAfter: staleAfter,
          leaseId: leaseId,
        )) !=
        null;
  }

  /// 续租只能由当前 running owner 执行。返回 null 表示 owner 已失效、
  /// 任务已进入 terminal，或任务已被删除；调用方必须立即停止网络 worker。
  Future<MediaJob?> heartbeatJob(
    String id,
    String leaseId, {
    DateTime? heartbeatAt,
  }) async {
    final normalizedId = _required(id, 'id');
    final normalizedLeaseId = _leaseId(leaseId);
    if (normalizedLeaseId == null) {
      throw ArgumentError.value(leaseId, 'leaseId', 'leaseId 不能为空');
    }
    final timestamp = (heartbeatAt ?? DateTime.now()).millisecondsSinceEpoch;
    final changed =
        await (update(mediaJobs)..where(
              (t) =>
                  t.id.equals(normalizedId) &
                  t.status.equals(mediaJobRunningStatus) &
                  t.leaseId.equals(normalizedLeaseId),
            ))
            .write(MediaJobsCompanion(updatedAt: Value(timestamp)));
    return changed == 1 ? getJob(normalizedId) : null;
  }

  /// 在持有 pending/running owner 时写入本地交付计划。
  ///
  /// 交付计划先于写盘持久化；这样进程可以在“文件已写入但 SQLite
  /// 事务尚未提交”的窗口重启后复用同一组 ID 和同一路径，而不是重新
  /// 创建第二条用户消息或第二个附件。
  Future<MediaJob?> updateDeliveryPlan(
    String id, {
    required String deliveryPhase,
    String? assetPath,
    String? assetMime,
    String? assetExtension,
    String? deliveryUserMessageId,
    String? deliveryAssistantMessageId,
    String? deliveryAttachmentId,
    String? deliverySourceAttachmentId,
    String? deliveryUserContent,
    String? deliveryAssistantContent,
    String? deliveryFileType,
    String? deliverySourcePath,
    String? deliverySourceFileName,
    String? deliverySourceFileType,
    int? updatedAt,
    String? leaseId,
  }) async {
    final normalizedId = _required(id, 'id');
    final normalizedLeaseId = _leaseId(leaseId);
    final timestamp = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final changed =
        await (update(mediaJobs)..where(
              (t) =>
                  t.id.equals(normalizedId) &
                  (t.status.equals(mediaJobPendingStatus) |
                      (t.status.equals(mediaJobRunningStatus) &
                          _ownerCondition(normalizedLeaseId))),
            ))
            .write(
              MediaJobsCompanion(
                phase: Value(_safeText(deliveryPhase, maxLength: 64)),
                deliveryPhase: Value(_safeText(deliveryPhase, maxLength: 64)),
                assetPath: Value(_safeAppOwnedPath(assetPath)),
                assetMime: Value(_safeText(assetMime, maxLength: 128)),
                assetExtension: Value(_safeText(assetExtension, maxLength: 32)),
                deliveryUserMessageId: Value(
                  _safeText(deliveryUserMessageId, maxLength: 256),
                ),
                deliveryAssistantMessageId: Value(
                  _safeText(deliveryAssistantMessageId, maxLength: 256),
                ),
                deliveryAttachmentId: Value(
                  _safeText(deliveryAttachmentId, maxLength: 256),
                ),
                deliverySourceAttachmentId: Value(
                  _safeText(deliverySourceAttachmentId, maxLength: 256),
                ),
                deliveryUserContent: Value(
                  _safeText(deliveryUserContent, maxLength: 4000),
                ),
                deliveryAssistantContent: Value(
                  _safeText(deliveryAssistantContent, maxLength: 4000),
                ),
                deliveryFileType: Value(
                  _safeText(deliveryFileType, maxLength: 32),
                ),
                deliverySourcePath: Value(
                  _safeAppOwnedPath(deliverySourcePath),
                ),
                deliverySourceFileName: Value(
                  _safeText(deliverySourceFileName, maxLength: 256),
                ),
                deliverySourceFileType: Value(
                  _safeText(deliverySourceFileType, maxLength: 32),
                ),
                updatedAt: Value(timestamp),
              ),
            );
    return changed == 1 ? getJob(normalizedId) : getJob(normalizedId);
  }

  /// 仅允许 active 状态更新；terminal 记录不可被旧请求改回 pending。
  Future<MediaJob?> updateStatus(
    String id,
    String status, {
    int? progress,
    String? phase,
    String? error,
    int? attempts,
    int? updatedAt,
    int? deadline,
    String? leaseId,
  }) async {
    final normalizedStatus = _status(status);
    final timestamp = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final normalizedLeaseId = _leaseId(leaseId);
    final companion = MediaJobsCompanion(
      status: Value(normalizedStatus),
      progress: Value(_progress(progress)),
      phase: Value(_safeText(phase, maxLength: 64)),
      error: Value(_safeText(error, maxLength: 512)),
      attempts: attempts == null
          ? const Value.absent()
          : Value(attempts < 0 ? 0 : attempts),
      updatedAt: Value(timestamp),
      deadline: Value(deadline),
      leaseId: Value(
        normalizedStatus == mediaJobRunningStatus ? normalizedLeaseId : null,
      ),
    );
    final sourceCondition = _activeUpsertCondition(
      normalizedStatus,
      normalizedLeaseId,
    );
    final changed =
        await (update(
              mediaJobs,
            )..where((t) => t.id.equals(_required(id, 'id')) & sourceCondition))
            .write(companion);
    if (changed != 1) return getJob(id);
    return getJob(id);
  }

  Future<MediaJob?> completeJob(
    String id, {
    String? assetPath,
    String? assetMime,
    String? assetExtension,
    int? updatedAt,
    String? leaseId,
    String? deliveryUserMessageId,
    String? deliveryAssistantMessageId,
    String? deliveryAttachmentId,
    String? deliverySourceAttachmentId,
    String? deliveryPhase,
  }) {
    return _finish(
      id,
      status: mediaJobCompletedStatus,
      assetPath: assetPath,
      assetMime: assetMime,
      assetExtension: assetExtension,
      updatedAt: updatedAt,
      leaseId: leaseId,
      deliveryUserMessageId: deliveryUserMessageId,
      deliveryAssistantMessageId: deliveryAssistantMessageId,
      deliveryAttachmentId: deliveryAttachmentId,
      deliverySourceAttachmentId: deliverySourceAttachmentId,
      deliveryPhase: deliveryPhase,
    );
  }

  Future<MediaJob?> failJob(
    String id, {
    required String error,
    int? updatedAt,
    String? leaseId,
  }) {
    return _finish(
      id,
      status: mediaJobFailedStatus,
      error: error,
      updatedAt: updatedAt,
      leaseId: leaseId,
    );
  }

  Future<MediaJob?> expireJob(
    String id, {
    String error = '媒体任务已过期',
    int? updatedAt,
    String? leaseId,
  }) {
    return _finish(
      id,
      status: mediaJobExpiredStatus,
      error: error,
      updatedAt: updatedAt,
      leaseId: leaseId,
    );
  }

  Future<MediaJob?> cancelJob(String id, {int? updatedAt, String? leaseId}) {
    return _finish(
      id,
      status: mediaJobCancelledStatus,
      error: '请求已取消',
      updatedAt: updatedAt,
      leaseId: leaseId,
    );
  }

  /// 旧版本可能已经把任务写成 completed，但没有本地交付计划。这样的
  /// 记录不能继续假装成功，也不能回到无限 pending；启动恢复会把它
  /// 收敛为明确的 failed，等待用户显式重试。
  Future<MediaJob?> failUndeliveredJob(
    String id, {
    required String error,
    int? updatedAt,
  }) async {
    final timestamp = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final changed =
        await (update(mediaJobs)..where(
              (t) =>
                  t.id.equals(_required(id, 'id')) &
                  t.status.equals(mediaJobCompletedStatus) &
                  (t.deliveryPhase.isNull() |
                      t.deliveryPhase
                          .equals(mediaJobDeliveryCompletedPhase)
                          .not()),
            ))
            .write(
              MediaJobsCompanion(
                status: const Value(mediaJobFailedStatus),
                phase: const Value(mediaJobFailedStatus),
                deliveryPhase: const Value(mediaJobDeliveryFailedPhase),
                progress: const Value(100),
                error: Value(_safeText(error, maxLength: 512)),
                updatedAt: Value(timestamp),
                leaseId: const Value(null),
              ),
            );
    return changed == 1 ? getJob(id) : getJob(id);
  }

  /// 将 terminal 任务显式恢复为 pending。completed 不允许被重试覆盖。
  Future<MediaJob?> retryJob(String id, {int? deadline, int? updatedAt}) async {
    final timestamp = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final changed =
        await (update(mediaJobs)..where(
              (t) =>
                  t.id.equals(_required(id, 'id')) &
                  (t.status.equals(mediaJobFailedStatus) |
                      t.status.equals(mediaJobExpiredStatus) |
                      t.status.equals(mediaJobCancelledStatus)),
            ))
            .write(
              MediaJobsCompanion(
                status: const Value(mediaJobPendingStatus),
                progress: const Value(null),
                phase: const Value('pending'),
                error: const Value(null),
                attempts: const Value(0),
                updatedAt: Value(timestamp),
                deadline: Value(deadline),
                leaseId: const Value(null),
                deliveryPhase: const Value(mediaJobDeliveryPlannedPhase),
                assetPath: const Value(null),
                assetMime: const Value(null),
                assetExtension: const Value(null),
              ),
            );
    return changed == 1 ? getJob(id) : getJob(id);
  }

  Future<List<MediaJob>> listPendingJobs() {
    return (select(mediaJobs)
          ..where((t) => t.status.equals(mediaJobPendingStatus))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<MediaJob>> listRunningJobs() {
    return (select(mediaJobs)
          ..where((t) => t.status.equals(mediaJobRunningStatus))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<MediaJob>> listRecoverableJobs() {
    return (select(mediaJobs)
          ..where(
            (t) =>
                t.status.equals(mediaJobPendingStatus) |
                t.status.equals(mediaJobRunningStatus) |
                (t.status.equals(mediaJobCompletedStatus) &
                    (t.deliveryPhase.isNull() |
                        t.deliveryPhase
                            .equals(mediaJobDeliveryCompletedPhase)
                            .not())),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<MediaJob>> listJobsBySession(String sessionId) {
    return (select(mediaJobs)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<int> deleteJob(String id) {
    return (delete(mediaJobs)..where((t) => t.id.equals(id))).go();
  }

  Future<int> deleteJobsBySession(String sessionId) {
    return (delete(
      mediaJobs,
    )..where((t) => t.sessionId.equals(sessionId))).go();
  }

  Future<MediaJob?> _finish(
    String id, {
    required String status,
    String? error,
    String? assetPath,
    String? assetMime,
    String? assetExtension,
    int? updatedAt,
    String? leaseId,
    String? deliveryUserMessageId,
    String? deliveryAssistantMessageId,
    String? deliveryAttachmentId,
    String? deliverySourceAttachmentId,
    String? deliveryPhase,
  }) async {
    final timestamp = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final normalizedLeaseId = _leaseId(leaseId);
    final changed =
        await (update(mediaJobs)..where(
              (t) =>
                  t.id.equals(_required(id, 'id')) &
                  _terminalCondition(status, normalizedLeaseId),
            ))
            .write(
              MediaJobsCompanion(
                status: Value(status),
                phase: Value(status),
                progress: const Value(100),
                error: Value(_safeText(error, maxLength: 512)),
                assetPath: Value(_safeAppOwnedPath(assetPath)),
                assetMime: Value(_safeText(assetMime, maxLength: 128)),
                assetExtension: Value(_safeText(assetExtension, maxLength: 32)),
                updatedAt: Value(timestamp),
                leaseId: const Value(null),
                deliveryUserMessageId: deliveryUserMessageId == null
                    ? const Value.absent()
                    : Value(_safeText(deliveryUserMessageId, maxLength: 256)),
                deliveryAssistantMessageId: deliveryAssistantMessageId == null
                    ? const Value.absent()
                    : Value(
                        _safeText(deliveryAssistantMessageId, maxLength: 256),
                      ),
                deliveryAttachmentId: deliveryAttachmentId == null
                    ? const Value.absent()
                    : Value(_safeText(deliveryAttachmentId, maxLength: 256)),
                deliverySourceAttachmentId: deliverySourceAttachmentId == null
                    ? const Value.absent()
                    : Value(
                        _safeText(deliverySourceAttachmentId, maxLength: 256),
                      ),
                deliveryPhase: Value(
                  _safeText(
                    deliveryPhase ??
                        (status == mediaJobCompletedStatus
                            ? mediaJobDeliveryCompletedPhase
                            : status),
                    maxLength: 64,
                  ),
                ),
              ),
            );
    return changed == 1 ? getJob(id) : getJob(id);
  }

  Expression<bool> _activeUpsertCondition(String status, String? leaseId) {
    final current = mediaJobs.status;
    final owner = _ownerCondition(leaseId);
    if (status == mediaJobPendingStatus) {
      // A worker must never turn its running lease back into pending. Retry
      // uses retryJob(), which is the explicit terminal-to-pending boundary.
      return current.equals(mediaJobPendingStatus);
    }
    if (status == mediaJobRunningStatus) {
      return current.equals(mediaJobPendingStatus) |
          (current.equals(mediaJobRunningStatus) & owner);
    }
    return current.equals(mediaJobPendingStatus) |
        (current.equals(mediaJobRunningStatus) & owner);
  }

  Expression<bool> _terminalCondition(String status, String? leaseId) {
    final current = mediaJobs.status;
    return current.equals(mediaJobPendingStatus) |
        (current.equals(mediaJobRunningStatus) & _ownerCondition(leaseId)) |
        // Same-terminal idempotence does not require a live lease because the
        // terminal row has already released its owner.
        current.equals(status);
  }

  Expression<bool> _ownerCondition(String? leaseId) {
    return leaseId == null
        ? mediaJobs.leaseId.isNull()
        : mediaJobs.leaseId.equals(leaseId);
  }

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError('$field 不能为空');
    if (normalized.length > 256) throw ArgumentError('$field 过长');
    return normalized;
  }

  static String? _leaseId(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.length > _mediaJobLeaseMaxLength) {
      throw ArgumentError.value(value, 'leaseId', 'leaseId 过长');
    }
    // Lease IDs are generated locally or supplied by a worker as opaque
    // identifiers. Keep the accepted alphabet deliberately narrow so this
    // column can never become a place to persist headers or credentials.
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(normalized)) {
      throw ArgumentError.value(value, 'leaseId', 'leaseId 格式无效');
    }
    return normalized;
  }

  static String _status(String value) {
    final normalized = _required(value, 'status');
    if (!_activeAndTerminalStatuses.contains(normalized)) {
      throw ArgumentError.value(value, 'status', '不支持的媒体任务状态');
    }
    return normalized;
  }

  static final Set<String> _activeAndTerminalStatuses = <String>{
    ..._mediaJobActiveStatuses,
    ..._mediaJobTerminalStatuses,
  };

  static int? _progress(int? value) {
    if (value == null) return null;
    return value.clamp(0, 100);
  }

  static String? _optional(String? value, {int maxLength = 1024}) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized.length <= maxLength
        ? normalized
        : normalized.substring(0, maxLength);
  }

  static String? _safeText(String? value, {required int maxLength}) {
    return sanitizeUniversalMediaDiagnostic(value, maxLength: maxLength);
  }

  static String? _safeUrl(String? value, {bool preserveQuery = false}) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    final uri = Uri.tryParse(normalized);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        uri.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      return null;
    }
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: uri.pathSegments,
      query: preserveQuery && uri.hasQuery ? uri.query : null,
    ).toString();
  }

  static String? _safeEndpoint(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    final withoutQuery = normalized.replaceFirst(RegExp(r'[?#].*'), '').trim();
    if (withoutQuery.isEmpty) return null;
    return _safeText(withoutQuery, maxLength: 512);
  }

  static String? _safeAppOwnedPath(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.contains('\u0000') ||
        normalized.contains('?') ||
        normalized.contains('#')) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri != null && uri.scheme.isNotEmpty && uri.scheme != 'file') {
      return null;
    }
    final path = uri?.scheme == 'file' ? uri!.path : normalized;
    if (path.split('/').contains('..')) return null;
    if (path.startsWith('/')) {
      const allowedAbsoluteRoots = <String>[
        '/data/user/0/',
        '/data/data/',
        '/var/mobile/Containers/Data/Application/',
        '/private/var/mobile/Containers/Data/Application/',
      ];
      final isKnownAppRoot =
          allowedAbsoluteRoots.any(path.startsWith) ||
          path.contains('/Library/Application Support/') ||
          path.contains('/Library/Containers/');
      if (!isKnownAppRoot) return null;
    }
    return path.length <= 2048 ? path : path.substring(0, 2048);
  }
}
