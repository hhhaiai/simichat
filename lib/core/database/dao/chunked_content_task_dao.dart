import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../context/chunked_content_task.dart';
import '../app_database.dart';
import '../tables.dart';

part 'chunked_content_task_dao.g.dart';

const chunkedContentPreparingStatus = 'preparing';
const chunkedContentRunningStatus = 'running';
const chunkedContentReducingStatus = 'reducing';
const chunkedContentCompletedStatus = 'completed';
const chunkedContentFailedStatus = 'failed';
const chunkedContentCancelledStatus = 'cancelled';

const _terminalChunkedContentStatuses = <String>{
  chunkedContentCompletedStatus,
  chunkedContentFailedStatus,
  chunkedContentCancelledStatus,
};
const _chunkedContentTaskUuid = Uuid();

/// 持久化 ChunkedContentTask 的 DAO。
///
/// SQLite 行与其 lease 是唯一事实来源。内存 worker 只是执行器：无论重启、
/// 多个 isolate 还是 Stop 与网络回调竞争，都必须通过带 owner 条件的更新
/// 修改任务。中间结果只存在此表，绝不插入普通聊天消息或 Markdown 档案。
@DriftAccessor(tables: [ChunkedContentTasks, Messages, Sessions])
class ChunkedContentTaskDao extends DatabaseAccessor<AppDatabase>
    with _$ChunkedContentTaskDaoMixin {
  ChunkedContentTaskDao(super.db);

  Future<ChunkedContentTask?> getTask(String id) {
    return (select(
      chunkedContentTasks,
    )..where((t) => t.id.equals(_id(id)))).getSingleOrNull();
  }

  Future<ChunkedContentTask> createTask({
    required String id,
    required String sessionId,
    required String sourceMessageId,
    required String sourceAttachmentId,
    required String originalPrompt,
    required String channelModelId,
    required String providerId,
    required ChunkedContentStrategy strategy,
    required ChunkedContentRequestSnapshot requestSnapshot,
    int? createdAt,
  }) async {
    final timestamp = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final normalizedId = _id(id);
    final assistantId = '$normalizedId:assistant';
    await into(chunkedContentTasks).insert(
      ChunkedContentTasksCompanion.insert(
        id: normalizedId,
        sessionId: _required(sessionId, 'sessionId'),
        sourceMessageId: _required(sourceMessageId, 'sourceMessageId'),
        sourceAttachmentId: _required(sourceAttachmentId, 'sourceAttachmentId'),
        originalPrompt: _prompt(originalPrompt),
        channelModelId: _required(channelModelId, 'channelModelId'),
        providerId: _required(providerId, 'providerId'),
        strategy: strategy.name,
        requestSnapshot: requestSnapshot.encode(),
        status: chunkedContentPreparingStatus,
        phase: chunkedContentPreparingStatus,
        totalChunks: const Value(0),
        completedChunks: const Value(0),
        chunkResults: const Value('[]'),
        retryMetadata: const Value('{"max_automatic_retries":2}'),
        finalResponseMessageId: Value(assistantId),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    final result = await getTask(normalizedId);
    if (result == null) throw StateError('无法创建分批任务');
    return result;
  }

  /// 竞争取得当前任务。创建后处于 preparing 的任务也可被抢占；崩溃留下的
  /// running/reducing 行只有在 lease 已超时或无 lease 时才能恢复。
  Future<ChunkedContentTask?> claimTask(
    String id, {
    String? leaseId,
    DateTime? claimedAt,
    Duration staleAfter = const Duration(minutes: 2),
    bool allowUnleasedActive = false,
  }) async {
    final normalizedId = _id(id);
    final timestamp = (claimedAt ?? DateTime.now()).millisecondsSinceEpoch;
    final staleBefore = timestamp - staleAfter.inMilliseconds;
    final owner = _leaseId(leaseId) ?? _chunkedContentTaskUuid.v4();
    return transaction(() async {
      final changed =
          await (update(chunkedContentTasks)..where(
                (t) =>
                    t.id.equals(normalizedId) &
                    (t.status.equals(chunkedContentPreparingStatus) |
                        ((t.status.equals(chunkedContentRunningStatus) |
                                t.status.equals(chunkedContentReducingStatus)) &
                            (t.updatedAt.isSmallerOrEqualValue(staleBefore) |
                                (allowUnleasedActive
                                    ? t.leaseId.isNull()
                                    : const Constant(false))))),
              ))
              .write(
                ChunkedContentTasksCompanion(
                  leaseId: Value(owner),
                  updatedAt: Value(timestamp),
                ),
              );
      if (changed != 1) return null;
      return getTask(normalizedId);
    });
  }

  Future<ChunkedContentTask?> initializePlan(
    String id, {
    required String leaseId,
    required List<ChunkedContentChunkResult> plan,
    int? updatedAt,
  }) async {
    if (plan.isEmpty) throw ArgumentError.value(plan, 'plan', '不能为空');
    final timestamp = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final owner = _requiredLease(leaseId);
    final encoded = encodeChunkedContentResults(plan);
    final changed =
        await (update(chunkedContentTasks)..where(
              (t) =>
                  t.id.equals(_id(id)) &
                  t.status.equals(chunkedContentPreparingStatus) &
                  t.leaseId.equals(owner),
            ))
            .write(
              ChunkedContentTasksCompanion(
                status: const Value(chunkedContentRunningStatus),
                phase: const Value(chunkedContentRunningStatus),
                totalChunks: Value(plan.length),
                completedChunks: const Value(0),
                chunkResults: Value(encoded),
                error: const Value(null),
                updatedAt: Value(timestamp),
              ),
            );
    return changed == 1 ? getTask(id) : getTask(id);
  }

  /// 以 owner 条件写入单个 chunk 的当前尝试次数和结果。调用方必须每次以
  /// 最新数据库 rows 为基准更新，避免旧 worker 覆盖新 worker 的成功结果。
  Future<ChunkedContentTask?> saveChunkResults(
    String id, {
    required String leaseId,
    required List<ChunkedContentChunkResult> results,
    int? updatedAt,
  }) async {
    final owner = _requiredLease(leaseId);
    final timestamp = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final completed = results.where((result) => result.isCompleted).length;
    final changed =
        await (update(chunkedContentTasks)..where(
              (t) =>
                  t.id.equals(_id(id)) &
                  t.status.equals(chunkedContentRunningStatus) &
                  t.leaseId.equals(owner),
            ))
            .write(
              ChunkedContentTasksCompanion(
                chunkResults: Value(encodeChunkedContentResults(results)),
                completedChunks: Value(completed),
                updatedAt: Value(timestamp),
              ),
            );
    return changed == 1 ? getTask(id) : getTask(id);
  }

  Future<ChunkedContentTask?> beginReducing(
    String id, {
    required String leaseId,
    int? updatedAt,
  }) async {
    final owner = _requiredLease(leaseId);
    final timestamp = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final changed =
        await (update(chunkedContentTasks)..where(
              (t) =>
                  t.id.equals(_id(id)) &
                  t.status.equals(chunkedContentRunningStatus) &
                  t.leaseId.equals(owner) &
                  t.totalChunks.equalsExp(t.completedChunks),
            ))
            .write(
              ChunkedContentTasksCompanion(
                status: const Value(chunkedContentReducingStatus),
                phase: const Value(chunkedContentReducingStatus),
                updatedAt: Value(timestamp),
              ),
            );
    return changed == 1 ? getTask(id) : getTask(id);
  }

  /// 在单个 SQLite transaction 内插入唯一的最终 assistant 消息、更新会话
  /// 时间并关闭任务。固定的 finalResponseMessageId + insertOrIgnore 保证恢复
  /// 重放不会产生第二条 assistant 消息。
  Future<ChunkedContentTask?> completeWithFinalResponse(
    String id, {
    required String leaseId,
    required String content,
    required int tokens,
    int? completedAt,
  }) async {
    final normalizedId = _id(id);
    final owner = _requiredLease(leaseId);
    final timestamp = completedAt ?? DateTime.now().millisecondsSinceEpoch;
    return transaction(() async {
      final task = await getTask(normalizedId);
      if (task == null) return null;
      if (task.status == chunkedContentCompletedStatus) return task;
      if (task.leaseId != owner ||
          (task.status != chunkedContentRunningStatus &&
              task.status != chunkedContentReducingStatus)) {
        return task;
      }
      final finalMessageId = task.finalResponseMessageId?.trim();
      if (finalMessageId == null || finalMessageId.isEmpty) {
        throw StateError('分批任务缺少最终回复 ID');
      }
      await into(messages).insert(
        MessagesCompanion.insert(
          id: finalMessageId,
          sessionId: task.sessionId,
          role: 'assistant',
          content: content,
          channelModelId: Value(task.channelModelId),
          tokens: Value(tokens < 0 ? 0 : tokens),
          createdAt: timestamp,
        ),
        mode: InsertMode.insertOrIgnore,
      );
      await (update(sessions)..where((t) => t.id.equals(task.sessionId))).write(
        SessionsCompanion(lastMessageAt: Value(timestamp)),
      );
      final changed =
          await (update(chunkedContentTasks)..where(
                (t) =>
                    t.id.equals(normalizedId) &
                    t.leaseId.equals(owner) &
                    (t.status.equals(chunkedContentRunningStatus) |
                        t.status.equals(chunkedContentReducingStatus)),
              ))
              .write(
                ChunkedContentTasksCompanion(
                  status: const Value(chunkedContentCompletedStatus),
                  phase: const Value(chunkedContentCompletedStatus),
                  completedChunks: Value(task.totalChunks),
                  error: const Value(null),
                  updatedAt: Value(timestamp),
                  leaseId: const Value(null),
                ),
              );
      if (changed != 1) return getTask(normalizedId);
      return getTask(normalizedId);
    });
  }

  Future<ChunkedContentTask?> failTask(
    String id, {
    required String leaseId,
    required String error,
    int? failedAt,
  }) => _finish(
    id,
    leaseId: leaseId,
    status: chunkedContentFailedStatus,
    error: error,
    updatedAt: failedAt,
  );

  Future<ChunkedContentTask?> cancelTask(
    String id, {
    String? leaseId,
    int? cancelledAt,
  }) => _finish(
    id,
    leaseId: leaseId,
    status: chunkedContentCancelledStatus,
    error: '用户已停止该长内容任务',
    updatedAt: cancelledAt,
  );

  /// 将恢复时未完成的 active task 显式收敛为失败。App 重启后没有可靠的
  /// 远端 resume token，不能继续假装正在运行；中间结果仍完整保留，可显式
  /// 调用 [retryTask] 继续未完成部分。
  Future<ChunkedContentTask?> markInterrupted(
    String id, {
    int? interruptedAt,
  }) async {
    final timestamp = interruptedAt ?? DateTime.now().millisecondsSinceEpoch;
    final changed =
        await (update(chunkedContentTasks)..where(
              (t) =>
                  t.id.equals(_id(id)) &
                  (t.status.equals(chunkedContentPreparingStatus) |
                      t.status.equals(chunkedContentRunningStatus) |
                      t.status.equals(chunkedContentReducingStatus)),
            ))
            .write(
              ChunkedContentTasksCompanion(
                status: const Value(chunkedContentFailedStatus),
                phase: const Value(chunkedContentFailedStatus),
                error: const Value('应用已中断任务，可继续未完成部分或从头重试'),
                updatedAt: Value(timestamp),
                leaseId: const Value(null),
              ),
            );
    return changed == 1 ? getTask(id) : getTask(id);
  }

  /// 显式重试 terminal task。`continueIncomplete=true` 保留已完成 chunk；
  /// `false` 则清空结果并从头重新切块。completed 任务不允许重试覆盖。
  Future<ChunkedContentTask?> retryTask(
    String id, {
    required bool continueIncomplete,
    int? retriedAt,
  }) async {
    final timestamp = retriedAt ?? DateTime.now().millisecondsSinceEpoch;
    return transaction(() async {
      final current = await getTask(id);
      if (current == null ||
          current.status == chunkedContentCompletedStatus ||
          !_terminalChunkedContentStatuses.contains(current.status)) {
        return current;
      }
      List<ChunkedContentChunkResult> results;
      try {
        results = decodeChunkedContentResults(current.chunkResults);
      } on FormatException {
        results = const <ChunkedContentChunkResult>[];
      }
      final resetResults = continueIncomplete
          ? results
          : results
                .map(
                  (item) => ChunkedContentChunkResult(
                    chunkIndex: item.chunkIndex,
                    startOffset: item.startOffset,
                    endOffset: item.endOffset,
                    sha256: item.sha256,
                    estimatedTokens: item.estimatedTokens,
                  ),
                )
                .toList(growable: false);
      final phase = resetResults.isEmpty
          ? chunkedContentPreparingStatus
          : chunkedContentRunningStatus;
      final total = resetResults.length;
      final completed = resetResults.where((item) => item.isCompleted).length;
      await (update(
        chunkedContentTasks,
      )..where((t) => t.id.equals(_id(id)))).write(
        ChunkedContentTasksCompanion(
          status: Value(phase),
          phase: Value(phase),
          totalChunks: Value(total),
          completedChunks: Value(completed),
          chunkResults: Value(encodeChunkedContentResults(resetResults)),
          error: const Value(null),
          updatedAt: Value(timestamp),
          leaseId: const Value(null),
        ),
      );
      return getTask(id);
    });
  }

  Future<List<ChunkedContentTask>> listTasksBySession(String sessionId) {
    return (select(chunkedContentTasks)
          ..where((t) => t.sessionId.equals(_required(sessionId, 'sessionId')))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<List<ChunkedContentTask>> listRecoverableTasks() {
    return (select(chunkedContentTasks)
          ..where(
            (t) =>
                t.status.equals(chunkedContentPreparingStatus) |
                t.status.equals(chunkedContentRunningStatus) |
                t.status.equals(chunkedContentReducingStatus),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<int> deleteTask(String id) {
    return (delete(
      chunkedContentTasks,
    )..where((t) => t.id.equals(_id(id)))).go();
  }

  Future<ChunkedContentTask?> _finish(
    String id, {
    required String status,
    String? leaseId,
    required String error,
    int? updatedAt,
  }) async {
    final owner = _leaseId(leaseId);
    final timestamp = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final companion = ChunkedContentTasksCompanion(
      status: Value(status),
      phase: Value(status),
      error: Value(sanitizeChunkedContentDiagnostic(error)),
      updatedAt: Value(timestamp),
      leaseId: const Value(null),
    );
    final changed = owner == null
        ? await (update(chunkedContentTasks)..where(
                (t) =>
                    t.id.equals(_id(id)) &
                    (t.status.equals(chunkedContentPreparingStatus) |
                        t.status.equals(chunkedContentRunningStatus) |
                        t.status.equals(chunkedContentReducingStatus)),
              ))
              .write(companion)
        : await (update(chunkedContentTasks)..where(
                (t) =>
                    t.id.equals(_id(id)) &
                    t.leaseId.equals(owner) &
                    (t.status.equals(chunkedContentPreparingStatus) |
                        t.status.equals(chunkedContentRunningStatus) |
                        t.status.equals(chunkedContentReducingStatus)),
              ))
              .write(companion);
    return changed == 1 ? getTask(id) : getTask(id);
  }

  static String _id(String value) => _required(value, 'id');

  static String _required(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 256) {
      throw ArgumentError.value(value, name, '$name 不能为空或过长');
    }
    return normalized;
  }

  static String _prompt(String value) {
    final normalized = value.trim();
    if (normalized.length > 16000) {
      throw ArgumentError.value(value, 'originalPrompt', '原始问题不能超过 16000 字符');
    }
    return normalized;
  }

  static String? _leaseId(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(normalized)) {
      throw ArgumentError.value(value, 'leaseId', 'leaseId 格式无效');
    }
    return normalized;
  }

  static String _requiredLease(String value) {
    return _leaseId(value) ??
        (throw ArgumentError.value(value, 'leaseId', 'leaseId 不能为空'));
  }
}

/// 任务错误可能被展示在工作视图、导出诊断或恢复提示中。禁止写入 URL、认证
/// 值、密钥或设备绝对路径。
String sanitizeChunkedContentDiagnostic(Object? value, {int maxLength = 512}) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return '长内容任务失败';
  var safe = raw.replaceAll(RegExp(r'\s+'), ' ');
  safe = safe.replaceAll(
    RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    'Bearer ***',
  );
  safe = safe.replaceAll(
    RegExp(r'\bsk-[A-Za-z0-9_-]+', caseSensitive: false),
    'sk-***',
  );
  safe = safe.replaceAllMapped(
    RegExp(
      r'''((?:api[_-]?key|access[_-]?token|token|secret|password))\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;&]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=***',
  );
  safe = safe.replaceAll(RegExp(r'''https?://[^\s<>"']+'''), '[链接]');
  safe = safe.replaceAll(
    RegExp(
      r'''(?:[A-Za-z]:[\\/](?:Users|home|private|var)[^\s<>"']*|/(?:Users|home|private|var)/[^\s<>"']+)''',
    ),
    '[本机路径]',
  );
  return safe.length <= maxLength ? safe : '${safe.substring(0, maxLength)}…';
}
