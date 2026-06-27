import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/memory/dreaming_service.dart';
import '../../core/memory/dreaming_schedule.dart';
import 'database_provider.dart';
import 'key_point_memory_provider.dart';

const kDreamingDigestStorageKey = 'dreaming_digest_v1';
const kDreamingScheduleStorageKey = 'dreaming_schedule_v1';

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

final dreamingScheduleProvider =
    StateNotifierProvider<DreamingScheduleNotifier, DreamingScheduleConfig>(
      (ref) => DreamingScheduleNotifier(),
    );

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

Future<DreamingDigest> runDreamingDigest(WidgetRef ref, {DateTime? day}) async {
  final digest = await ref
      .read(dreamingServiceProvider)
      .runDailyDigest(day: day);
  await ref.read(dreamingDigestProvider.notifier).save(digest);
  if (digest.memoryCandidates.isNotEmpty) {
    await ref
        .read(keyPointMemoryProvider.notifier)
        .rememberAll(digest.memoryCandidates);
  }
  return digest;
}

Future<DreamingDigest?> maybeRunDueDreaming(
  WidgetRef ref, {
  DateTime? now,
}) async {
  final scheduleNotifier = ref.read(dreamingScheduleProvider.notifier);
  await scheduleNotifier.ready;
  final current = now ?? DateTime.now();
  final config = ref.read(dreamingScheduleProvider);
  if (!shouldRunDreamingSchedule(config, now: current)) return null;
  final digest = await runDreamingDigest(ref, day: current);
  await scheduleNotifier.markAutoRun(current);
  return digest;
}
