import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import '../../core/database/dao/dreaming_dao.dart';
import '../../core/memory/dreaming_service.dart';
import '../../core/memory/dreaming_schedule.dart';
import 'database_provider.dart';
import 'key_point_memory_provider.dart';
import 'provider_access.dart';

const kDreamingDigestStorageKey = 'dreaming_digest_v1';
const kDreamingDigestHistoryStorageKey = 'dreaming_digest_history_v1';
const kDreamingScheduleStorageKey = 'dreaming_schedule_v1';
const _kMaxDreamingDigestHistoryEntries = 20;

final dreamingServiceProvider = Provider<DreamingService>((ref) {
  return DreamingService(
    sessionDao: ref.watch(sessionDaoProvider),
    messageDao: ref.watch(messageDaoProvider),
    extractor: ref.watch(keyPointExtractorProvider),
  );
});

final dreamingDigestProvider =
    StateNotifierProvider<DreamingDigestNotifier, DreamingDigest?>((ref) {
      return DreamingDigestNotifier();
    });

final dreamingDigestHistoryProvider =
    StateNotifierProvider<DreamingDigestHistoryNotifier, List<DreamingDigest>>((
      ref,
    ) {
      return DreamingDigestHistoryNotifier();
    });

final dreamingScheduleProvider =
    StateNotifierProvider<DreamingScheduleNotifier, DreamingScheduleConfig>(
      (ref) => DreamingScheduleNotifier(),
    );

final latestFailedDreamingJobProvider = FutureProvider<DreamingJob?>((ref) {
  return ref.watch(dreamingDaoProvider).getLatestUnresolvedFailedJob();
});

class DreamingDigestNotifier extends StateNotifier<DreamingDigest?> {
  DreamingDigestNotifier() : super(null) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kDreamingDigestStorageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map;
      state = DreamingDigest.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      state = null;
    }
  }

  Future<void> save(DreamingDigest digest) async {
    await ready;
    state = digest;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kDreamingDigestStorageKey,
      jsonEncode(digest.toJson()),
    );
  }

  Future<void> clear() async {
    await ready;
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kDreamingDigestStorageKey);
  }
}

class DreamingDigestHistoryNotifier
    extends StateNotifier<List<DreamingDigest>> {
  DreamingDigestHistoryNotifier() : super(const []) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = _decodeDreamingDigestHistory(
      prefs.getString(kDreamingDigestHistoryStorageKey),
    );
  }

  Future<void> record(DreamingDigest digest) async {
    await ready;
    if (!digest.hasContent) return;
    final updated = <DreamingDigest>[
      digest,
      ...state.where((item) => item.dayKey != digest.dayKey),
    ].take(_kMaxDreamingDigestHistoryEntries).toList(growable: false);
    state = List.unmodifiable(updated);
    await _save();
  }

  Future<void> clear() async {
    await ready;
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kDreamingDigestHistoryStorageKey);
  }

  Future<void> removeDay(String dayKey) async {
    await ready;
    final updated = state
        .where((digest) => digest.dayKey != dayKey)
        .toList(growable: false);
    if (updated.length == state.length) return;
    state = List.unmodifiable(updated);
    await _save();
  }

  Future<void> mergeRestored(List<DreamingDigest> digests) async {
    await ready;
    final contentDigests = digests
        .where((digest) => digest.hasContent)
        .toList(growable: false);
    if (contentDigests.isEmpty) return;
    final restoredDayKeys = contentDigests
        .map((digest) => digest.dayKey)
        .toSet();
    final updated = <DreamingDigest>[
      ...contentDigests,
      ...state.where((digest) => !restoredDayKeys.contains(digest.dayKey)),
    ].take(_kMaxDreamingDigestHistoryEntries).toList(growable: false);
    state = List.unmodifiable(updated);
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (state.isEmpty) {
      await prefs.remove(kDreamingDigestHistoryStorageKey);
      return;
    }
    await prefs.setString(
      kDreamingDigestHistoryStorageKey,
      jsonEncode(state.map((digest) => digest.toJson()).toList()),
    );
  }
}

List<DreamingDigest> _decodeDreamingDigestHistory(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => DreamingDigest.fromJson(item.cast<String, dynamic>()))
        .where((digest) => digest.hasContent)
        .take(_kMaxDreamingDigestHistoryEntries)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

DreamingDigest? _decodeDreamingReportDigest(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = decoded.cast<String, dynamic>();
    if (!map.containsKey('day') || !map.containsKey('generatedAt')) {
      return null;
    }
    final digest = DreamingDigest.fromJson(map);
    if (digest.day.year < 2000 || digest.generatedAt.year < 2000) {
      return null;
    }
    return digest;
  } catch (_) {
    return null;
  }
}

class DreamingScheduleNotifier extends StateNotifier<DreamingScheduleConfig> {
  DreamingScheduleNotifier() : super(const DreamingScheduleConfig()) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kDreamingScheduleStorageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map;
      state = DreamingScheduleConfig.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      state = const DreamingScheduleConfig();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await ready;
    state = state.copyWith(enabled: enabled);
    await _save();
  }

  Future<void> setTime({required int hour, required int minute}) async {
    await ready;
    state = state.copyWith(hour: hour, minute: minute);
    await _save();
  }

  Future<void> setRequiresCharging(bool value) async {
    await ready;
    state = state.copyWith(requiresCharging: value);
    await _save();
  }

  Future<void> setRequiresUnmeteredNetwork(bool value) async {
    await ready;
    state = state.copyWith(requiresUnmeteredNetwork: value);
    await _save();
  }

  Future<void> markAutoRun(DateTime day) async {
    await ready;
    state = state.copyWith(lastAutoRunDayKey: formatDreamingDay(day));
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kDreamingScheduleStorageKey,
      jsonEncode(state.toJson()),
    );
  }
}

final _dreamingDigestInFlightByDayKey = <String, Future<DreamingDigest>>{};

Future<DreamingDigest> runDreamingDigest(
  WidgetRef ref, {
  DateTime? day,
  String trigger = 'manual',
}) {
  return runDreamingDigestWithAccess(
    WidgetRefProviderAccess(ref),
    day: day,
    trigger: trigger,
  );
}

Future<DreamingDigest> runDreamingDigestWithAccess(
  ProviderAccess access, {
  DateTime? day,
  String trigger = 'manual',
}) async {
  final targetDay = day ?? DateTime.now();
  final dayKey = formatDreamingDay(targetDay);
  final inFlight = _dreamingDigestInFlightByDayKey[dayKey];
  if (inFlight != null) return inFlight;

  final run = _runDreamingDigest(
    access,
    targetDay: targetDay,
    dayKey: dayKey,
    serviceDay: day,
    trigger: trigger,
  );
  _dreamingDigestInFlightByDayKey[dayKey] = run;
  try {
    return await run;
  } finally {
    if (identical(_dreamingDigestInFlightByDayKey[dayKey], run)) {
      _dreamingDigestInFlightByDayKey.remove(dayKey);
    }
  }
}

Future<DreamingDigest> _runDreamingDigest(
  ProviderAccess access, {
  required DateTime targetDay,
  required String dayKey,
  required DateTime? serviceDay,
  required String trigger,
  String? claimedJobId,
}) async {
  final service = access.read(dreamingServiceProvider);
  final dreamingDao = access.read(dreamingDaoProvider);
  final digestNotifier = access.read(dreamingDigestProvider.notifier);
  final historyNotifier = access.read(dreamingDigestHistoryProvider.notifier);
  final memoryNotifier = access.read(keyPointMemoryProvider.notifier);
  final createdAt = DateTime.now().millisecondsSinceEpoch;
  final jobId =
      claimedJobId ??
      'dreaming-job-$dayKey-${DateTime.now().microsecondsSinceEpoch}';
  if (claimedJobId == null) {
    await dreamingDao.failUnfinishedJobsByDay(
      dayKey,
      error: 'superseded by a newer Dreaming run',
      finishedAt: createdAt,
    );
    await dreamingDao.createJob(
      id: jobId,
      dayKey: dayKey,
      scheduledFor: targetDay.millisecondsSinceEpoch,
      trigger: trigger,
      createdAt: createdAt,
    );
  }
  await dreamingDao.markJobRunning(jobId);
  var durableCompleted = false;
  try {
    final digest = await service.runDailyDigest(day: serviceDay);
    if (digest.memoryCandidates.isNotEmpty) {
      await memoryNotifier.rememberAll(digest.memoryCandidates);
    }
    await dreamingDao.upsertReport(
      id: 'dreaming-report-${digest.dayKey}',
      dayKey: digest.dayKey,
      jobId: jobId,
      generatedAt: digest.generatedAt.millisecondsSinceEpoch,
      markdown: digest.toMarkdown(),
      digestJson: jsonEncode(digest.toJson()),
      sessionCount: digest.sessionCount,
      originalMessageCount: digest.originalMessageCount,
      totalOriginalMessageCount: digest.totalOriginalMessageCount,
      memoryCandidateCount: digest.memoryCandidates.length,
      isTruncated: digest.isTruncated,
      createdAt: digest.generatedAt.millisecondsSinceEpoch,
    );
    await digestNotifier.save(digest);
    await historyNotifier.record(digest);
    await dreamingDao.markJobCompleted(jobId);
    durableCompleted = true;
    access.invalidate(latestFailedDreamingJobProvider);
    return digest;
  } catch (error) {
    if (!durableCompleted) {
      try {
        await dreamingDao.markJobFailed(jobId, error: error.toString());
      } catch (_) {
        // 保留原始错误，避免 job 状态写入失败掩盖 Dreaming 主错误。
      }
    }
    access.invalidate(latestFailedDreamingJobProvider);
    rethrow;
  }
}

Future<int> syncDreamingDigestStateFromDatabase(
  WidgetRef ref, {
  int limit = _kMaxDreamingDigestHistoryEntries,
}) async {
  final safeLimit = limit < 1 ? 1 : limit;
  final reports = await ref
      .read(dreamingDaoProvider)
      .getRecentReports(limit: safeLimit);
  final digests = reports
      .map((report) => _decodeDreamingReportDigest(report.digestJson))
      .whereType<DreamingDigest>()
      .toList(growable: false);
  if (digests.isEmpty) return 0;

  await ref.read(dreamingDigestProvider.notifier).save(digests.first);
  await ref.read(dreamingDigestHistoryProvider.notifier).mergeRestored(digests);
  return digests.length;
}

Future<DreamingDigest?>? _dueDreamingAutoRunInFlight;
final _locallyCompletedDueDreamingDayKeys = <String>{};

@visibleForTesting
void resetDreamingAutoRunStateForTesting() {
  _dueDreamingAutoRunInFlight = null;
  _locallyCompletedDueDreamingDayKeys.clear();
  _dreamingDigestInFlightByDayKey.clear();
}

Future<DreamingDigest?> maybeRunDueDreaming(WidgetRef ref, {DateTime? now}) {
  return maybeRunDueDreamingWithAccess(WidgetRefProviderAccess(ref), now: now);
}

Future<DreamingDigest?> maybeRunDueDreamingWithAccess(
  ProviderAccess access, {
  DateTime? now,
  String trigger = 'foreground_due',
}) async {
  if (_dueDreamingAutoRunInFlight != null) return null;
  final run = _maybeRunDueDreaming(access, now: now, trigger: trigger);
  _dueDreamingAutoRunInFlight = run;
  try {
    return await run;
  } finally {
    if (identical(_dueDreamingAutoRunInFlight, run)) {
      _dueDreamingAutoRunInFlight = null;
    }
  }
}

Future<DreamingDigest?> _maybeRunDueDreaming(
  ProviderAccess access, {
  DateTime? now,
  required String trigger,
}) async {
  final scheduleNotifier = access.read(dreamingScheduleProvider.notifier);
  await scheduleNotifier.ready;
  final current = now ?? DateTime.now();
  final dayKey = formatDreamingDay(current);
  if (_locallyCompletedDueDreamingDayKeys.contains(dayKey)) return null;
  final config = access.read(dreamingScheduleProvider);
  if (!shouldRunDreamingSchedule(config, now: current)) return null;
  final automaticRun = await _runAutomaticDreamingDigestWithAccess(
    access,
    day: current,
    trigger: trigger,
  );
  if (automaticRun == null) return null;
  try {
    await scheduleNotifier.markAutoRun(current);
  } catch (_) {
    _locallyCompletedDueDreamingDayKeys.add(dayKey);
  }
  return automaticRun.digest;
}

typedef _AutomaticDreamingRun = ({DreamingDigest? digest});

Future<_AutomaticDreamingRun?> _runAutomaticDreamingDigestWithAccess(
  ProviderAccess access, {
  required DateTime day,
  required String trigger,
}) async {
  final dayKey = formatDreamingDay(day);
  final claimedAt = DateTime.now().millisecondsSinceEpoch;
  final claim = await access
      .read(dreamingDaoProvider)
      .claimAutomaticJob(
        id: 'dreaming-auto-$dayKey',
        dayKey: dayKey,
        scheduledFor: day.millisecondsSinceEpoch,
        trigger: trigger,
        claimedAt: claimedAt,
        staleBefore: claimedAt - const Duration(minutes: 15).inMilliseconds,
      );
  switch (claim) {
    case DreamingAutomaticJobClaim.claimed:
      return (
        digest: await _runDreamingDigest(
          access,
          targetDay: day,
          dayKey: dayKey,
          serviceDay: day,
          trigger: trigger,
          claimedJobId: 'dreaming-auto-$dayKey',
        ),
      );
    case DreamingAutomaticJobClaim.completed:
    case DreamingAutomaticJobClaim.dismissed:
      return (digest: null);
    case DreamingAutomaticJobClaim.inFlight:
      return null;
  }
}
