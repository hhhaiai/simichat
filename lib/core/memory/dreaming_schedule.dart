import 'dreaming_service.dart';

const kDefaultDreamingHour = 22;
const kDefaultDreamingMinute = 0;

class DreamingScheduleConfig {
  const DreamingScheduleConfig({
    this.enabled = true,
    this.hour = kDefaultDreamingHour,
    this.minute = kDefaultDreamingMinute,
    this.lastAutoRunDayKey,
  });

  factory DreamingScheduleConfig.fromJson(Map<String, dynamic> json) {
    return DreamingScheduleConfig(
      enabled: json['enabled'] as bool? ?? true,
      hour: normalizeDreamingHour(json['hour'] as int?),
      minute: normalizeDreamingMinute(json['minute'] as int?),
      lastAutoRunDayKey: json['lastAutoRunDayKey'] as String?,
    );
  }

  final bool enabled;
  final int hour;
  final int minute;
  final String? lastAutoRunDayKey;

  DreamingScheduleConfig copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    String? lastAutoRunDayKey,
  }) {
    return DreamingScheduleConfig(
      enabled: enabled ?? this.enabled,
      hour: normalizeDreamingHour(hour ?? this.hour),
      minute: normalizeDreamingMinute(minute ?? this.minute),
      lastAutoRunDayKey: lastAutoRunDayKey ?? this.lastAutoRunDayKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
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
