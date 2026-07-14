import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../shared/providers/database_provider.dart';
import '../../shared/providers/dreaming_provider.dart';
import '../database/app_database.dart';
import '../memory/dreaming_schedule.dart';
import '../memory/dreaming_service.dart';
import '../notification/notification_service.dart';
import '../smoke/ios_background_dreaming_smoke_result.dart';
import 'dreaming_background_runner.dart';
import 'dreaming_background_scheduler.dart';
import 'ios_background_refresh_status.dart';

const kAndroidDreamingBackgroundTaskName =
    'simichat.android.dreaming.background.v1';
const kAndroidDreamingBackgroundTaskTag =
    'simichat-android-dreaming-background';
const _kAndroidDreamingBackgroundUniquePrefix =
    'simichat.android.dreaming.background';
const kIosDreamingBackgroundTaskIdentifier = String.fromEnvironment(
  'SIMICHAT_IOS_BACKGROUND_DREAMING_TASK_IDENTIFIER',
  defaultValue: 'top.simitalk.aichat.dreaming.processing',
);
const kIosDreamingBackgroundRetryDelay = Duration(minutes: 15);
const kIosBackgroundDreamingSmokeResultStorageKey =
    'ios_background_dreaming_smoke_result_v1';
const androidBackgroundDreamingSmokeEnabled = bool.fromEnvironment(
  'SIMICHAT_ANDROID_BACKGROUND_DREAMING_SMOKE',
);
const iosBackgroundDreamingSmokeEnabled = bool.fromEnvironment(
  'SIMICHAT_IOS_BACKGROUND_DREAMING_SMOKE',
);

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

final DreamingBackgroundScheduler _androidDreamingBackgroundScheduler =
    DreamingBackgroundScheduler(
      client: const WorkmanagerDreamingBackgroundTaskClient(),
    );
final DreamingBackgroundScheduler _iosDreamingBackgroundScheduler =
    DreamingBackgroundScheduler(
      client: const WorkmanagerIosDreamingBackgroundTaskClient(),
    );

class WorkmanagerDreamingBackgroundTaskClient
    implements DreamingBackgroundTaskClient {
  const WorkmanagerDreamingBackgroundTaskClient();

  @override
  Future<void> initialize() {
    return Workmanager().initialize(dreamingBackgroundCallbackDispatcher);
  }

  @override
  Future<void> register({
    required Duration initialDelay,
    required DreamingScheduleConfig config,
  }) {
    final scheduledAt = DateTime.now().add(initialDelay);
    return _registerAndroidDreamingBackgroundWork(
      scheduledAt: scheduledAt,
      initialDelay: initialDelay,
      config: config,
    );
  }

  @override
  Future<void> cancel() {
    return Workmanager().cancelByTag(kAndroidDreamingBackgroundTaskTag);
  }
}

class WorkmanagerIosDreamingBackgroundTaskClient
    implements DreamingBackgroundTaskClient {
  const WorkmanagerIosDreamingBackgroundTaskClient();

  @override
  Future<void> initialize() {
    return Workmanager().initialize(dreamingBackgroundCallbackDispatcher);
  }

  @override
  Future<void> register({
    required Duration initialDelay,
    required DreamingScheduleConfig config,
  }) async {
    await Workmanager().cancelByUniqueName(
      kIosDreamingBackgroundTaskIdentifier,
    );
    await Workmanager().registerProcessingTask(
      kIosDreamingBackgroundTaskIdentifier,
      kIosDreamingBackgroundTaskIdentifier,
      initialDelay: initialDelay,
      constraints: buildIosDreamingBackgroundConstraints(config),
    );
  }

  @override
  Future<void> cancel() {
    return Workmanager().cancelByUniqueName(
      kIosDreamingBackgroundTaskIdentifier,
    );
  }
}

Future<void> syncDreamingBackgroundSchedule(
  DreamingScheduleConfig config, {
  DateTime? now,
}) async {
  if (_isAndroid) {
    await _androidDreamingBackgroundScheduler.sync(config, now: now);
  } else if (_isIos) {
    if (config.enabled && !iosBackgroundDreamingSmokeEnabled) {
      await ensureIosBackgroundRefreshAvailable();
    }
    await _iosDreamingBackgroundScheduler.sync(config, now: now);
  }
}

Future<void> syncDreamingBackgroundScheduleFromStorage({DateTime? now}) async {
  if (!_isAndroid && !_isIos) return;
  final config = await _loadDreamingScheduleConfig();
  await syncDreamingBackgroundSchedule(config, now: now);
}

Future<void> syncAndroidDreamingBackgroundSchedule(
  DreamingScheduleConfig config, {
  DateTime? now,
}) async {
  if (!_isAndroid) return;
  await _androidDreamingBackgroundScheduler.sync(config, now: now);
}

Future<void> syncAndroidDreamingBackgroundScheduleFromStorage({
  DateTime? now,
}) async {
  if (!_isAndroid) return;
  final config = await _loadDreamingScheduleConfig();
  await syncAndroidDreamingBackgroundSchedule(config, now: now);
}

Future<DreamingScheduleConfig> _loadDreamingScheduleConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kDreamingScheduleStorageKey);
  if (raw == null || raw.isEmpty) return const DreamingScheduleConfig();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const DreamingScheduleConfig();
    return DreamingScheduleConfig.fromJson(decoded.cast<String, dynamic>());
  } catch (_) {
    return const DreamingScheduleConfig();
  }
}

Future<void> _registerAndroidDreamingBackgroundWork({
  required DateTime scheduledAt,
  required Duration initialDelay,
  required DreamingScheduleConfig config,
}) {
  final uniqueName =
      '$_kAndroidDreamingBackgroundUniquePrefix.${formatDreamingDay(scheduledAt)}';
  return Workmanager().registerOneOffTask(
    uniqueName,
    kAndroidDreamingBackgroundTaskName,
    initialDelay: initialDelay,
    inputData: {'scheduledDayKey': formatDreamingDay(scheduledAt)},
    constraints: buildAndroidDreamingBackgroundConstraints(config),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
    tag: kAndroidDreamingBackgroundTaskTag,
  );
}

Constraints buildAndroidDreamingBackgroundConstraints(
  DreamingScheduleConfig config,
) {
  return Constraints(
    networkType: config.requiresUnmeteredNetwork
        ? NetworkType.unmetered
        : NetworkType.notRequired,
    requiresCharging: config.requiresCharging,
    requiresBatteryNotLow: true,
    requiresStorageNotLow: true,
  );
}

Constraints buildIosDreamingBackgroundConstraints(
  DreamingScheduleConfig config,
) {
  return Constraints(
    networkType: config.requiresUnmeteredNetwork
        ? NetworkType.connected
        : NetworkType.notRequired,
    requiresCharging: config.requiresCharging,
  );
}

Future<void> _rescheduleAndroidDreamingBackgroundWork() async {
  final now = DateTime.now();
  final config = await _loadDreamingScheduleConfig();
  final scheduledAt = nextDreamingBackgroundRunAt(config, now: now);
  if (scheduledAt == null) {
    await Workmanager().cancelByTag(kAndroidDreamingBackgroundTaskTag);
    return;
  }
  final delay = scheduledAt.difference(now);
  await _registerAndroidDreamingBackgroundWork(
    scheduledAt: scheduledAt,
    initialDelay: delay.isNegative ? Duration.zero : delay,
    config: config,
  );
}

Future<void> _rescheduleIosDreamingBackgroundWork({
  Duration? retryDelay,
}) async {
  final config = await _loadDreamingScheduleConfig();
  if (!config.enabled) {
    await Workmanager().cancelByUniqueName(
      kIosDreamingBackgroundTaskIdentifier,
    );
    return;
  }
  final now = DateTime.now();
  final delay = retryDelay ?? dreamingBackgroundInitialDelay(config, now: now);
  if (delay == null) {
    await Workmanager().cancelByUniqueName(
      kIosDreamingBackgroundTaskIdentifier,
    );
    return;
  }
  await const WorkmanagerIosDreamingBackgroundTaskClient().register(
    initialDelay: delay.isNegative ? Duration.zero : delay,
    config: config,
  );
}

@pragma('vm:entry-point')
void dreamingBackgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final isAndroidTask = taskName == kAndroidDreamingBackgroundTaskName;
    final isIosTask = taskName == kIosDreamingBackgroundTaskIdentifier;
    if (!isAndroidTask && !isIosTask) return true;
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final db = AppDatabase();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    try {
      final result = await runDreamingBackgroundTask(
        container: container,
        trigger: isIosTask ? 'ios_background' : 'android_background',
        notifyComplete: ({required digest, required profileProposalCount}) {
          return NotificationService().showDreamingDigestComplete(
            dayKey: digest.dayKey,
            originalMessageCount: digest.originalMessageCount,
            totalOriginalMessageCount: digest.totalOriginalMessageCount,
            memoryCandidateCount: digest.memoryCandidates.length,
            profileProposalCount: profileProposalCount,
          );
        },
        notifyFailed: ({required dayKey}) {
          return NotificationService().showDreamingDigestFailed(dayKey: dayKey);
        },
      );
      final succeeded =
          result.status == DreamingBackgroundRunStatus.completed ||
          result.status == DreamingBackgroundRunStatus.notDue;
      if (isIosTask && iosBackgroundDreamingSmokeEnabled) {
        final smokeResult = jsonEncode({
          'status': result.status.name,
          'digestDayKey': result.digest?.dayKey,
          'reflectionDayKey': result.reflection?.sourceDigestDayKey,
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          kIosBackgroundDreamingSmokeResultStorageKey,
          smokeResult,
        );
        await writeIosBackgroundDreamingSmokeResult({
          'marker': 'SIMICHAT_IOS_BACKGROUND_DREAMING_RESULT',
          'status': result.status.name,
          'digestDayKey': result.digest?.dayKey,
          'reflectionDayKey': result.reflection?.sourceDigestDayKey,
        });
        debugPrint('SIMICHAT_IOS_BACKGROUND_DREAMING_RESULT $smokeResult');
      }
      if (androidBackgroundDreamingSmokeEnabled) {
        debugPrint(
          'SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT '
          'status=${result.status.name} '
          'digest=${result.digest?.dayKey ?? 'none'} '
          'reflection=${result.reflection?.sourceDigestDayKey ?? 'none'}',
        );
      }
      if (succeeded) {
        if (isIosTask) {
          await _rescheduleIosDreamingBackgroundWork();
        } else {
          await _rescheduleAndroidDreamingBackgroundWork();
        }
      } else if (isIosTask) {
        await _rescheduleIosDreamingBackgroundWork(
          retryDelay: kIosDreamingBackgroundRetryDelay,
        );
      }
      return succeeded;
    } catch (error, stackTrace) {
      final platform = isIosTask ? 'iOS' : 'Android';
      debugPrint('$platform background Dreaming failed: $error\n$stackTrace');
      if (isIosTask && iosBackgroundDreamingSmokeEnabled) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          kIosBackgroundDreamingSmokeResultStorageKey,
          jsonEncode({'status': 'failed'}),
        );
        await writeIosBackgroundDreamingSmokeResult({
          'marker': 'SIMICHAT_IOS_BACKGROUND_DREAMING_RESULT',
          'status': 'failed',
        });
      }
      if (isIosTask) {
        try {
          await _rescheduleIosDreamingBackgroundWork(
            retryDelay: kIosDreamingBackgroundRetryDelay,
          );
        } catch (retryError, retryStackTrace) {
          debugPrint(
            'iOS background Dreaming retry schedule failed: '
            '$retryError\n$retryStackTrace',
          );
        }
      }
      return false;
    } finally {
      container.dispose();
      await db.close();
    }
  });
}
