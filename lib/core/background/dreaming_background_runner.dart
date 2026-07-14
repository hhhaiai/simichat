import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/dreaming_provider.dart';
import '../../shared/providers/provider_access.dart';
import '../../shared/providers/reflection_provider.dart';
import '../../shared/providers/user_profile_provider.dart';
import '../memory/dreaming_service.dart';
import '../memory/reflection_service.dart';

enum DreamingBackgroundRunStatus {
  notDue,
  completed,
  reflectionPending,
  failed,
}

typedef DreamingBackgroundCompleteNotifier =
    Future<void> Function({
      required DreamingDigest digest,
      required int profileProposalCount,
    });

typedef DreamingBackgroundFailedNotifier =
    Future<void> Function({required String dayKey});

Future<void> _runOptionalNotification(
  String label,
  Future<void> Function() notify,
) async {
  try {
    await notify();
  } catch (error) {
    debugPrint(
      'Background Dreaming $label notification failed: ${error.runtimeType}',
    );
  }
}

class DreamingBackgroundRunResult {
  const DreamingBackgroundRunResult({
    required this.status,
    this.digest,
    this.reflection,
  });

  final DreamingBackgroundRunStatus status;
  final DreamingDigest? digest;
  final ReflectionReport? reflection;
}

Future<DreamingBackgroundRunResult> runDreamingBackgroundTask({
  required ProviderContainer container,
  DateTime? now,
  String trigger = 'android_background',
  required DreamingBackgroundCompleteNotifier notifyComplete,
  required DreamingBackgroundFailedNotifier notifyFailed,
}) async {
  final current = now ?? DateTime.now();
  final access = ContainerProviderAccess(container);

  ReflectionReport? recoveredReflection;
  var pendingReflectionRetryFailed = false;
  try {
    recoveredReflection = await retryPendingAssistantReflectionWithAccess(
      access,
    );
  } catch (_) {
    pendingReflectionRetryFailed = true;
    // Pending remains durable and WorkManager will retry the task.
  }

  DreamingDigest? digest;
  try {
    digest = await maybeRunDueDreamingWithAccess(
      access,
      now: current,
      trigger: trigger,
    );
  } catch (_) {
    await _runOptionalNotification(
      'failure',
      () => notifyFailed(dayKey: formatDreamingDay(current)),
    );
    return const DreamingBackgroundRunResult(
      status: DreamingBackgroundRunStatus.failed,
    );
  }

  if (digest == null) {
    if (recoveredReflection != null) {
      final digestNotifier = access.read(dreamingDigestProvider.notifier);
      final historyNotifier = access.read(
        dreamingDigestHistoryProvider.notifier,
      );
      await digestNotifier.ready;
      await historyNotifier.ready;
      final currentDigest = access.read(dreamingDigestProvider);
      final recoveredDigest =
          currentDigest?.dayKey == recoveredReflection.sourceDigestDayKey
          ? currentDigest
          : access
                .read(dreamingDigestHistoryProvider)
                .where(
                  (item) =>
                      item.dayKey == recoveredReflection!.sourceDigestDayKey,
                )
                .firstOrNull;
      if (recoveredDigest != null) {
        final proposalsNotifier = access.read(
          userProfileChangeProposalsProvider.notifier,
        );
        await proposalsNotifier.ready;
        final proposalCount = access
            .read(userProfileChangeProposalsProvider)
            .fold<int>(0, (total, item) => total + item.diff.items.length);
        await _runOptionalNotification(
          'completion',
          () => notifyComplete(
            digest: recoveredDigest,
            profileProposalCount: proposalCount,
          ),
        );
        return DreamingBackgroundRunResult(
          status: DreamingBackgroundRunStatus.completed,
          digest: recoveredDigest,
          reflection: recoveredReflection,
        );
      }
    }
    return DreamingBackgroundRunResult(
      status: recoveredReflection == null
          ? pendingReflectionRetryFailed
                ? DreamingBackgroundRunStatus.reflectionPending
                : DreamingBackgroundRunStatus.notDue
          : DreamingBackgroundRunStatus.completed,
      reflection: recoveredReflection,
    );
  }
  final completedDigest = digest;

  var profileProposalCount = 0;
  try {
    final proposal = await proposeUserProfileChangesWithAccess(
      access,
      now: current,
      reason: '${trigger}_profile_proposal',
    );
    profileProposalCount = proposal?.diff.items.length ?? 0;
  } catch (_) {
    // Profile proposals are optional and must not invalidate the digest.
  }

  ReflectionReport? reflection;
  try {
    reflection = await runAssistantReflectionWithAccess(
      access,
      digest: completedDigest,
      pendingProfileProposalCount: profileProposalCount,
    );
  } catch (_) {
    return DreamingBackgroundRunResult(
      status: DreamingBackgroundRunStatus.reflectionPending,
      digest: digest,
    );
  }

  await _runOptionalNotification(
    'completion',
    () => notifyComplete(
      digest: completedDigest,
      profileProposalCount: profileProposalCount,
    ),
  );
  return DreamingBackgroundRunResult(
    status: DreamingBackgroundRunStatus.completed,
    digest: completedDigest,
    reflection: reflection,
  );
}
