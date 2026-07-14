import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_protocol.dart';
import '../../core/database/dao/channel_dao.dart';
import '../../core/memory/dreaming_service.dart';
import '../../core/memory/model_reflection_service.dart';
import '../../core/memory/reflection_service.dart';
import '../../core/relay/channel_model_relay_bridge.dart';
import 'database_provider.dart';
import 'dreaming_provider.dart';
import 'provider_access.dart';
import 'user_profile_provider.dart';

const kAssistantReflectionStorageKey = 'assistant_reflection_v1';
const kAssistantReflectionHistoryStorageKey = 'assistant_reflection_history_v1';
const kAssistantReflectionPromptEnabledStorageKey =
    'assistant_reflection_prompt_enabled_v1';
const kAssistantReflectionModelEnabledStorageKey =
    'assistant_reflection_model_enabled_v1';
const kAssistantReflectionPendingStorageKey = 'assistant_reflection_pending_v1';
const _kMaxAssistantReflectionHistoryEntries = 20;

final reflectionServiceProvider = Provider<ReflectionService>(
  (ref) => const ReflectionService(),
);
final modelReflectionServiceProvider = Provider<ModelReflectionService>(
  (ref) => const ModelReflectionService(),
);

typedef AssistantReflectionModelEnhancer =
    Future<ReflectionReport> Function({
      required DreamingDigest digest,
      required ReflectionReport localReport,
    });

final assistantReflectionModelEnhancerProvider =
    Provider<AssistantReflectionModelEnhancer>((ref) {
      final channelDao = ref.watch(channelDaoProvider);
      final service = ref.watch(modelReflectionServiceProvider);
      return ({required digest, required localReport}) {
        return _enhanceReflectionWithConfiguredModel(
          channelDao: channelDao,
          service: service,
          digest: digest,
          localReport: localReport,
        );
      };
    });

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

final assistantReflectionModelEnabledProvider =
    StateNotifierProvider<AssistantReflectionModelEnabledNotifier, bool>((ref) {
      return AssistantReflectionModelEnabledNotifier();
    });

final assistantReflectionHistoryProvider =
    StateNotifierProvider<
      AssistantReflectionHistoryNotifier,
      List<ReflectionReport>
    >((ref) {
      return AssistantReflectionHistoryNotifier();
    });

final assistantReflectionPendingProvider =
    StateNotifierProvider<
      AssistantReflectionPendingNotifier,
      AssistantReflectionPending?
    >((ref) {
      return AssistantReflectionPendingNotifier();
    });

class AssistantReflectionPending {
  const AssistantReflectionPending({
    required this.sourceDigestDayKey,
    required this.updatedAt,
    required this.attemptCount,
  });

  factory AssistantReflectionPending.fromJson(Map<String, dynamic> json) {
    return AssistantReflectionPending(
      sourceDigestDayKey: json['sourceDigestDayKey'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      attemptCount: json['attemptCount'] as int? ?? 1,
    );
  }

  final String sourceDigestDayKey;
  final DateTime updatedAt;
  final int attemptCount;

  Map<String, dynamic> toJson() => {
    'sourceDigestDayKey': sourceDigestDayKey,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'attemptCount': attemptCount,
  };
}

AssistantReflectionPending? decodeAssistantReflectionPending(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final pending = AssistantReflectionPending.fromJson(decoded.cast());
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(pending.sourceDigestDayKey)) {
      return null;
    }
    if (pending.attemptCount < 1) return null;
    return pending;
  } catch (_) {
    return null;
  }
}

class AssistantReflectionPendingNotifier
    extends StateNotifier<AssistantReflectionPending?> {
  AssistantReflectionPendingNotifier() : super(null) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAssistantReflectionPendingStorageKey);
    state = decodeAssistantReflectionPending(raw);
    if (raw != null && state == null) {
      await prefs.remove(kAssistantReflectionPendingStorageKey);
    }
  }

  Future<void> markPending(String sourceDigestDayKey) async {
    await ready;
    final previous = state;
    final pending = AssistantReflectionPending(
      sourceDigestDayKey: sourceDigestDayKey,
      updatedAt: DateTime.now(),
      attemptCount: previous?.sourceDigestDayKey == sourceDigestDayKey
          ? previous!.attemptCount + 1
          : 1,
    );
    state = pending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kAssistantReflectionPendingStorageKey,
      jsonEncode(pending.toJson()),
    );
  }

  Future<void> clear() async {
    await ready;
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAssistantReflectionPendingStorageKey);
  }
}

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

  Future<void> removeDay(String dayKey) async {
    await removeWhere((report) => report.dayKey == dayKey);
  }

  Future<void> removeReport({
    required String dayKey,
    required String sourceDigestDayKey,
  }) async {
    await removeWhere(
      (report) =>
          report.dayKey == dayKey &&
          report.sourceDigestDayKey == sourceDigestDayKey,
    );
  }

  Future<void> removeWhere(bool Function(ReflectionReport report) test) async {
    await ready;
    final updated = state
        .where((report) => !test(report))
        .toList(growable: false);
    if (updated.length == state.length) return;
    state = List.unmodifiable(updated);
    await _save();
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

class AssistantReflectionModelEnabledNotifier extends StateNotifier<bool> {
  AssistantReflectionModelEnabledNotifier() : super(false) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(kAssistantReflectionModelEnabledStorageKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    await ready;
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAssistantReflectionModelEnabledStorageKey, enabled);
  }
}

Future<ReflectionReport?> runAssistantReflection(
  WidgetRef ref, {
  DreamingDigest? digest,
  int pendingProfileProposalCount = 0,
}) {
  return runAssistantReflectionWithAccess(
    WidgetRefProviderAccess(ref),
    digest: digest,
    pendingProfileProposalCount: pendingProfileProposalCount,
  );
}

Future<ReflectionReport?> runAssistantReflectionWithAccess(
  ProviderAccess access, {
  DreamingDigest? digest,
  int pendingProfileProposalCount = 0,
}) async {
  final digestNotifier = access.read(dreamingDigestProvider.notifier);
  final profileNotifier = access.read(userProfileProvider.notifier);
  final reflectionNotifier = access.read(assistantReflectionProvider.notifier);
  final reflectionHistoryNotifier = access.read(
    assistantReflectionHistoryProvider.notifier,
  );
  final pendingNotifier = access.read(
    assistantReflectionPendingProvider.notifier,
  );
  final modelEnabledNotifier = access.read(
    assistantReflectionModelEnabledProvider.notifier,
  );
  await digestNotifier.ready;
  await profileNotifier.ready;
  await reflectionNotifier.ready;
  await reflectionHistoryNotifier.ready;
  await pendingNotifier.ready;
  await modelEnabledNotifier.ready;

  final sourceDigest = digest ?? access.read(dreamingDigestProvider);
  if (sourceDigest == null || !sourceDigest.hasContent) return null;

  await pendingNotifier.markPending(sourceDigest.dayKey);
  var report = access
      .read(reflectionServiceProvider)
      .buildDailyReflection(
        digest: sourceDigest,
        profile: access.read(userProfileProvider),
        pendingProfileProposalCount: pendingProfileProposalCount,
      );
  if (access.read(assistantReflectionModelEnabledProvider)) {
    try {
      report = await access.read(assistantReflectionModelEnhancerProvider)(
        digest: sourceDigest,
        localReport: report,
      );
    } catch (error) {
      report = report.withGenerationMode(
        kReflectionGenerationModeModelFallback,
      );
      debugPrint(
        'Model reflection enhancement failed; using local fallback '
        '(${error.runtimeType})',
      );
    }
  }
  await reflectionNotifier.save(report);
  await reflectionHistoryNotifier.record(report);
  await pendingNotifier.clear();
  return report;
}

Future<ReflectionReport> _enhanceReflectionWithConfiguredModel({
  required ChannelDao channelDao,
  required ModelReflectionService service,
  required DreamingDigest digest,
  required ReflectionReport localReport,
}) async {
  final configuredModels = await channelDao.getChatModels();
  if (configuredModels.isEmpty) {
    throw StateError('No enabled chat model');
  }
  var selected = configuredModels.first;
  for (final item in configuredModels) {
    if (item.channelModel.isDefault) {
      selected = item;
      break;
    }
  }

  final bridge = ChannelModelRelayBridge(channelDao: channelDao);
  final model = await bridge.resolveModel(selected.channelModel.id);
  if (model == null) throw StateError('Default chat model is unavailable');

  final cancelToken = CancelToken();
  final messages = [
    AiMessage(
      role: 'user',
      content: service.buildUserPrompt(
        digest: digest,
        localReport: localReport,
      ),
    ),
  ];
  late final String response;
  try {
    final oneShot = await bridge
        .forwardOnce(
          model: model,
          messages: messages,
          systemPrompt: service.systemPrompt,
          cancelToken: cancelToken,
        )
        .timeout(
          kModelReflectionTimeout,
          onTimeout: () {
            cancelToken.cancel('model reflection timed out');
            throw TimeoutException('模型反思超过总时限', kModelReflectionTimeout);
          },
        );
    if (oneShot != null) {
      response = oneShot.content ?? '';
    } else {
      response = await service.collectResponse(
        chunks: bridge
            .forward(
              model: model,
              messages: messages,
              systemPrompt: service.systemPrompt,
              cancelToken: cancelToken,
              jsonResponse: true,
            )
            .map((chunk) => chunk.content ?? ''),
        onTimeout: () => cancelToken.cancel('model reflection timed out'),
      );
    }
  } catch (_) {
    if (!cancelToken.isCancelled) {
      cancelToken.cancel('model reflection stopped');
    }
    rethrow;
  }
  return service.enhanceFromResponse(
    localReport: localReport,
    response: response,
  );
}

Future<ReflectionReport?>? _pendingAssistantReflectionRetryInFlight;

Future<ReflectionReport?> retryPendingAssistantReflection(WidgetRef ref) {
  return retryPendingAssistantReflectionWithAccess(
    WidgetRefProviderAccess(ref),
  );
}

Future<ReflectionReport?> retryPendingAssistantReflectionWithAccess(
  ProviderAccess access,
) {
  final inFlight = _pendingAssistantReflectionRetryInFlight;
  if (inFlight != null) return inFlight;
  final run = _retryPendingAssistantReflection(access);
  _pendingAssistantReflectionRetryInFlight = run;
  return run.whenComplete(() {
    if (identical(_pendingAssistantReflectionRetryInFlight, run)) {
      _pendingAssistantReflectionRetryInFlight = null;
    }
  });
}

Future<ReflectionReport?> _retryPendingAssistantReflection(
  ProviderAccess access,
) async {
  final pendingNotifier = access.read(
    assistantReflectionPendingProvider.notifier,
  );
  await pendingNotifier.ready;
  final pending = access.read(assistantReflectionPendingProvider);
  if (pending == null) return null;

  final digestNotifier = access.read(dreamingDigestProvider.notifier);
  await digestNotifier.ready;
  var digest = access.read(dreamingDigestProvider);
  DreamingDigest? restoredFromDatabase;
  if (digest?.dayKey != pending.sourceDigestDayKey) {
    final historyNotifier = access.read(dreamingDigestHistoryProvider.notifier);
    await historyNotifier.ready;
    digest = access
        .read(dreamingDigestHistoryProvider)
        .where((item) => item.dayKey == pending.sourceDigestDayKey)
        .firstOrNull;
    if (digest == null) {
      final report = await access
          .read(dreamingDaoProvider)
          .getReportByDay(pending.sourceDigestDayKey);
      restoredFromDatabase = _decodePendingDreamingDigest(report?.digestJson);
      digest = restoredFromDatabase;
    }
    if (restoredFromDatabase != null) {
      final currentDigest = access.read(dreamingDigestProvider);
      if (currentDigest == null ||
          currentDigest.generatedAt.isBefore(
            restoredFromDatabase.generatedAt,
          )) {
        await digestNotifier.save(restoredFromDatabase);
      }
      await historyNotifier.record(restoredFromDatabase);
    }
  }
  if (digest == null ||
      !digest.hasContent ||
      digest.dayKey != pending.sourceDigestDayKey) {
    return null;
  }

  final proposalsNotifier = access.read(
    userProfileChangeProposalsProvider.notifier,
  );
  await proposalsNotifier.ready;
  final pendingProfileProposalCount = access
      .read(userProfileChangeProposalsProvider)
      .fold<int>(0, (total, item) => total + item.diff.items.length);
  return runAssistantReflectionWithAccess(
    access,
    digest: digest,
    pendingProfileProposalCount: pendingProfileProposalCount,
  );
}

DreamingDigest? _decodePendingDreamingDigest(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return DreamingDigest.fromJson(decoded.cast());
  } catch (_) {
    return null;
  }
}

@visibleForTesting
void resetAssistantReflectionRetryStateForTesting() {
  _pendingAssistantReflectionRetryInFlight = null;
}
