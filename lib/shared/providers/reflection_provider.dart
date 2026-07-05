import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/memory/dreaming_service.dart';
import '../../core/memory/reflection_service.dart';
import 'dreaming_provider.dart';
import 'user_profile_provider.dart';

const kAssistantReflectionStorageKey = 'assistant_reflection_v1';
const kAssistantReflectionHistoryStorageKey = 'assistant_reflection_history_v1';
const kAssistantReflectionPromptEnabledStorageKey =
    'assistant_reflection_prompt_enabled_v1';
const _kMaxAssistantReflectionHistoryEntries = 20;

final reflectionServiceProvider = Provider<ReflectionService>(
  (ref) => const ReflectionService(),
);

final assistantReflectionProvider =
    StateNotifierProvider<AssistantReflectionNotifier, ReflectionReport?>((
      ref,
    ) {
      return AssistantReflectionNotifier();
    });

final assistantReflectionPromptEnabledProvider =
    StateNotifierProvider<AssistantReflectionPromptEnabledNotifier, bool>((
      ref,
    ) {
      return AssistantReflectionPromptEnabledNotifier();
    });

final assistantReflectionHistoryProvider =
    StateNotifierProvider<
      AssistantReflectionHistoryNotifier,
      List<ReflectionReport>
    >((ref) {
      return AssistantReflectionHistoryNotifier();
    });

class AssistantReflectionNotifier extends StateNotifier<ReflectionReport?> {
  AssistantReflectionNotifier() : super(null) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = decodeReflectionReport(
      prefs.getString(kAssistantReflectionStorageKey),
    );
  }

  Future<void> save(ReflectionReport report) async {
    await ready;
    state = report;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kAssistantReflectionStorageKey,
      encodeReflectionReport(report),
    );
  }

  Future<void> clear() async {
    await ready;
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAssistantReflectionStorageKey);
  }
}

class AssistantReflectionHistoryNotifier
    extends StateNotifier<List<ReflectionReport>> {
  AssistantReflectionHistoryNotifier() : super(const []) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = decodeReflectionReportHistory(
      prefs.getString(kAssistantReflectionHistoryStorageKey),
    );
  }

  Future<void> record(ReflectionReport report) async {
    await ready;
    if (!report.hasContent) return;
    final updated = <ReflectionReport>[
      report,
      ...state.where(
        (item) =>
            item.dayKey != report.dayKey ||
            item.sourceDigestDayKey != report.sourceDigestDayKey,
      ),
    ].take(_kMaxAssistantReflectionHistoryEntries).toList(growable: false);
    state = List.unmodifiable(updated);
    await _save();
  }

  Future<void> clear() async {
    await ready;
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAssistantReflectionHistoryStorageKey);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (state.isEmpty) {
      await prefs.remove(kAssistantReflectionHistoryStorageKey);
      return;
    }
    await prefs.setString(
      kAssistantReflectionHistoryStorageKey,
      encodeReflectionReportHistory(state),
    );
  }
}

class AssistantReflectionPromptEnabledNotifier extends StateNotifier<bool> {
  AssistantReflectionPromptEnabledNotifier() : super(true) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(kAssistantReflectionPromptEnabledStorageKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    await ready;
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAssistantReflectionPromptEnabledStorageKey, enabled);
  }
}

Future<ReflectionReport?> runAssistantReflection(
  WidgetRef ref, {
  DreamingDigest? digest,
  int pendingProfileProposalCount = 0,
}) async {
  final digestNotifier = ref.read(dreamingDigestProvider.notifier);
  final profileNotifier = ref.read(userProfileProvider.notifier);
  final reflectionNotifier = ref.read(assistantReflectionProvider.notifier);
  final reflectionHistoryNotifier = ref.read(
    assistantReflectionHistoryProvider.notifier,
  );
  await digestNotifier.ready;
  await profileNotifier.ready;
  await reflectionNotifier.ready;
  await reflectionHistoryNotifier.ready;

  final sourceDigest = digest ?? ref.read(dreamingDigestProvider);
  if (sourceDigest == null || !sourceDigest.hasContent) return null;

  final report = ref
      .read(reflectionServiceProvider)
      .buildDailyReflection(
        digest: sourceDigest,
        profile: ref.read(userProfileProvider),
        pendingProfileProposalCount: pendingProfileProposalCount,
      );
  await reflectionNotifier.save(report);
  await reflectionHistoryNotifier.record(report);
  return report;
}
