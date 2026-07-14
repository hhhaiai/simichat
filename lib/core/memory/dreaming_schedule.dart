import 'dreaming_service.dart';

const kDefaultDreamingHour = 22;
const kDefaultDreamingMinute = 0;

class DreamingScheduleConfig {
  const DreamingScheduleConfig({
    this.enabled = true,
    this.hour = kDefaultDreamingHour,
    this.minute = kDefaultDreamingMinute,
    this.requiresCharging = false,
    this.requiresUnmeteredNetwork = false,
    this.lastAutoRunDayKey,
  });

  factory DreamingScheduleConfig.fromJson(Map<String, dynamic> json) {
    return DreamingScheduleConfig(
      enabled: json['enabled'] as bool? ?? true,
      hour: normalizeDreamingHour(json['hour'] as int?),
      minute: normalizeDreamingMinute(json['minute'] as int?),
      requiresCharging: json['requiresCharging'] as bool? ?? false,
      requiresUnmeteredNetwork:
          json['requiresUnmeteredNetwork'] as bool? ?? false,
      lastAutoRunDayKey: json['lastAutoRunDayKey'] as String?,
    );
  }

  final bool enabled;
  final int hour;
  final int minute;
  final bool requiresCharging;
  final bool requiresUnmeteredNetwork;
  final String? lastAutoRunDayKey;

  DreamingScheduleConfig copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    bool? requiresCharging,
    bool? requiresUnmeteredNetwork,
    String? lastAutoRunDayKey,
  }) {
    return DreamingScheduleConfig(
      enabled: enabled ?? this.enabled,
      hour: normalizeDreamingHour(hour ?? this.hour),
      minute: normalizeDreamingMinute(minute ?? this.minute),
      requiresCharging: requiresCharging ?? this.requiresCharging,
      requiresUnmeteredNetwork:
          requiresUnmeteredNetwork ?? this.requiresUnmeteredNetwork,
      lastAutoRunDayKey: lastAutoRunDayKey ?? this.lastAutoRunDayKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'requiresCharging': requiresCharging,
    'requiresUnmeteredNetwork': requiresUnmeteredNetwork,
    if (lastAutoRunDayKey != null) 'lastAutoRunDayKey': lastAutoRunDayKey,
  };
}

int normalizeDreamingHour(int? value) {
  if (value == null) return kDefaultDreamingHour;
  return value.clamp(0, 23);
}

int normalizeDreamingMinute(int? value) {
  if (value == null) return kDefaultDreamingMinute;
  return value.clamp(0, 59);
}

String formatDreamingScheduleTime(DreamingScheduleConfig config) {
  return '${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}';
}

String formatDreamingBackgroundConditions(DreamingScheduleConfig config) {
  final conditions = <String>[
    if (config.requiresCharging) '充电',
    if (config.requiresUnmeteredNetwork) '非计费网络（通常 Wi-Fi）',
  ];
  return conditions.isEmpty ? '后台附加条件：无' : '后台附加条件：${conditions.join(' + ')}';
}

String formatNextDreamingForegroundRun(
  DreamingScheduleConfig config, {
  required DateTime now,
}) {
  if (!config.enabled) return '下次前台整理：已关闭';

  final today = DateTime(now.year, now.month, now.day);
  final scheduledAt = DateTime(
    today.year,
    today.month,
    today.day,
    config.hour,
    config.minute,
  );
  final scheduleTime = formatDreamingScheduleTime(config);
  if (config.lastAutoRunDayKey == formatDreamingDay(today)) {
    return '下次前台整理：明日 $scheduleTime';
  }
  if (now.isBefore(scheduledAt)) {
    return '下次前台整理：今日 $scheduleTime';
  }
  return '下次前台整理：现在已到期';
}

DateTime? nextDreamingBackgroundRunAt(
  DreamingScheduleConfig config, {
  required DateTime now,
}) {
  if (!config.enabled) return null;

  final today = DateTime(now.year, now.month, now.day);
  final scheduledToday = DateTime(
    today.year,
    today.month,
    today.day,
    config.hour,
    config.minute,
  );
  if (config.lastAutoRunDayKey == formatDreamingDay(today)) {
    final tomorrow = today.add(const Duration(days: 1));
    return DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      config.hour,
      config.minute,
    );
  }
  if (now.isBefore(scheduledToday)) return scheduledToday;
  return now;
}

Duration? dreamingBackgroundInitialDelay(
  DreamingScheduleConfig config, {
  required DateTime now,
}) {
  final scheduledAt = nextDreamingBackgroundRunAt(config, now: now);
  if (scheduledAt == null) return null;
  final delay = scheduledAt.difference(now);
  return delay.isNegative ? Duration.zero : delay;
}

bool shouldRunDreamingSchedule(
  DreamingScheduleConfig config, {
  required DateTime now,
}) {
  if (!config.enabled) return false;
  final day = DateTime(now.year, now.month, now.day);
  final scheduledAt = DateTime(
    day.year,
    day.month,
    day.day,
    config.hour,
    config.minute,
  );
  if (now.isBefore(scheduledAt)) return false;
  return config.lastAutoRunDayKey != formatDreamingDay(day);
}
