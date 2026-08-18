import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/universal_media_service.dart';
import '../../core/crypto/key_encryptor.dart';
import '../../core/database/app_database.dart' as database;
import '../../core/database/dao/channel_dao.dart';
import '../../core/database/dao/media_job_dao.dart' as media_database;
import 'database_provider.dart';
import 'universal_media_provider.dart';

/// 恢复阶段的本地交付回调。回调必须在本地文件和会话事务成功后，把
/// media job 一并推进到 completed；它不能把云端响应当成最终成功。
typedef UniversalMediaRecoveryDelivery =
    Future<void> Function({
      required database.MediaJob row,
      required UniversalMediaJobResult result,
      required String leaseId,
    });

typedef UniversalMediaRecoveryServiceFactory =
    UniversalMediaService Function(
      database.MediaJob row,
      ChannelModelWithChannel model,
      String apiKey,
    );

/// 启动恢复只允许在单个 ProviderContainer 内创建一个 worker。
///
/// 该 coordinator 不在构造阶段发起网络请求；[start] 由首帧后的启动钩子
/// 显式调用，且重复调用只复用同一个 Future。每个任务都先原子 claim，再
/// 根据提交时保存的 channelModelId 解密当前渠道密钥，最后执行有限轮询。
class UniversalMediaRecoveryCoordinator {
  UniversalMediaRecoveryCoordinator({
    required this.appDatabase,
    required this.notifier,
    this.serviceFactory = _defaultServiceFactory,
    this.maxJobs = 32,
  }) {
    if (maxJobs <= 0) {
      throw ArgumentError.value(maxJobs, 'maxJobs', '必须大于 0');
    }
  }

  final database.AppDatabase appDatabase;
  final UniversalMediaJobNotifier notifier;
  final UniversalMediaRecoveryServiceFactory serviceFactory;
  final int maxJobs;

  Future<void>? _runFuture;

  bool get isStarted => _runFuture != null;

  Future<void> start({required UniversalMediaRecoveryDelivery delivery}) {
    final existing = _runFuture;
    if (existing != null) return existing;
    final future = _run(delivery);
    _runFuture = future;
    return future;
  }

  Future<void> _run(UniversalMediaRecoveryDelivery delivery) async {
    try {
      // Notifier 的 ready 是数据库恢复和内存镜像的边界；不能在它完成前
      // 读取 recoverable jobs，否则首个 worker 可能遗漏冷启动任务。
      await notifier.ready;
      final rows = await appDatabase.mediaJobDao.listRecoverableJobs();
      var processed = 0;
      for (final row in rows) {
        if (processed >= maxJobs) break;
        processed++;
        try {
          await _recoverOne(row, delivery);
        } catch (_) {
          // A single malformed row or database race must not prevent later
          // recoverable media jobs from getting their own recovery attempt.
        }
      }
    } catch (_) {
      // 启动恢复不能阻塞首屏。单任务异常在 _recoverOne 内收敛为明确
      // terminal 状态；数据库整体异常则留给下一次进程启动重试。
    }
  }

  Future<void> _recoverOne(
    database.MediaJob original,
    UniversalMediaRecoveryDelivery delivery,
  ) async {
    if (original.status == media_database.mediaJobCompletedStatus) {
      await appDatabase.mediaJobDao.failUndeliveredJob(
        original.id,
        error: '媒体任务已有完成记录，但缺少可靠的本地交付记录，请重试',
      );
      return;
    }

    database.MediaJob? claimed;
    String? leaseId;
    try {
      claimed = await appDatabase.mediaJobDao.claimJob(
        original.id,
        allowUnleasedRunning: true,
      );
      if (claimed == null || claimed.leaseId == null) return;
      leaseId = claimed.leaseId!;

      final deadline = claimed.deadline;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (deadline != null && deadline <= now) {
        await appDatabase.mediaJobDao.expireJob(
          claimed.id,
          error: '媒体任务已过期，未在恢复窗口内完成',
          leaseId: leaseId,
        );
        return;
      }

      final channelModelId = claimed.channelModelId?.trim();
      if (channelModelId == null || channelModelId.isEmpty) {
        await _failClaimed(claimed.id, leaseId, '恢复失败：任务未绑定提交时的渠道模型');
        return;
      }

      final model = await appDatabase.channelDao.getModelWithChannel(
        channelModelId,
      );
      if (model == null) {
        await _failClaimed(claimed.id, leaseId, '恢复失败：提交时渠道模型不存在，无法重建凭据');
        return;
      }

      final encryptedKey = model.channel.apiKeyEncrypted.trim();
      final apiKey = _decryptApiKey(encryptedKey);
      if (apiKey == null || apiKey.isEmpty) {
        await _failClaimed(
          claimed.id,
          leaseId,
          '恢复失败：固定渠道 API Key 缺失或无法解密，请重新配置该渠道',
        );
        return;
      }

      final service = serviceFactory(claimed, model, apiKey);
      final pollingOptions = _boundedPollingOptions(claimed.deadline);
      if (pollingOptions == null) {
        await appDatabase.mediaJobDao.expireJob(
          claimed.id,
          error: '媒体任务已过期，未在恢复窗口内完成',
          leaseId: leaseId,
        );
        return;
      }

      final result = await notifier.restoreAndPoll(
        operationId: claimed.id,
        service: service,
        pollingOptions: pollingOptions,
        leaseId: leaseId,
      );
      if (result == null) return;
      if (result.job.status == UniversalMediaJobStatus.completed) {
        if (result.asset == null) {
          await _failClaimed(claimed.id, leaseId, '恢复失败：任务完成但没有可交付的媒体内容');
          return;
        }
        final current = await appDatabase.mediaJobDao.getJob(claimed.id);
        if (current?.leaseId != leaseId) return;
        await delivery(
          row: current ?? claimed,
          result: result,
          leaseId: leaseId,
        );
        final delivered = await appDatabase.mediaJobDao.getJob(claimed.id);
        if (delivered?.status != media_database.mediaJobCompletedStatus ||
            delivered?.deliveryPhase !=
                media_database.mediaJobDeliveryCompletedPhase) {
          await _failClaimed(claimed.id, leaseId, '恢复失败：本地媒体交付未提交完成');
        } else {
          notifier.releaseDeliveryLease(claimed.id);
        }
      }
    } catch (error) {
      final current = claimed;
      final owner = leaseId;
      if (current != null && owner != null) {
        await _failClaimed(
          current.id,
          owner,
          '恢复轮询或本地交付失败：${_diagnostic(error)}',
        );
      }
    }
  }

  Future<void> _failClaimed(String id, String leaseId, String error) async {
    await appDatabase.mediaJobDao.failJob(
      id,
      error: sanitizeUniversalMediaDiagnostic(error) ?? '恢复失败',
      leaseId: leaseId,
    );
    notifier.releaseDeliveryLease(id);
  }

  UniversalMediaPollingOptions? _boundedPollingOptions(int? deadline) {
    const maxDeadline = Duration(minutes: 10);
    if (deadline == null) {
      return const UniversalMediaPollingOptions(deadline: maxDeadline);
    }
    final remaining = Duration(
      milliseconds: deadline - DateTime.now().millisecondsSinceEpoch,
    );
    if (remaining <= Duration.zero) return null;
    return UniversalMediaPollingOptions(
      deadline: remaining < maxDeadline ? remaining : maxDeadline,
    );
  }

  static String? _decryptApiKey(String encrypted) {
    if (encrypted.isEmpty) return null;
    try {
      return KeyEncryptor.decryptOrEmpty(encrypted).trim();
    } catch (_) {
      return null;
    }
  }

  static String _diagnostic(Object error) {
    return sanitizeUniversalMediaDiagnostic(error, maxLength: 400) ?? '未知错误';
  }

  static UniversalMediaService _defaultServiceFactory(
    database.MediaJob row,
    ChannelModelWithChannel model,
    String apiKey,
  ) {
    return UniversalMediaService(
      baseUrl: model.channel.baseUrl,
      apiKey: apiKey,
    );
  }
}

final universalMediaRecoveryProvider =
    Provider<UniversalMediaRecoveryCoordinator>((ref) {
      final db = ref.read(databaseProvider);
      return UniversalMediaRecoveryCoordinator(
        appDatabase: db,
        notifier: ref.read(universalMediaJobProvider.notifier),
      );
    });
