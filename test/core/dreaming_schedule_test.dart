import 'package:ai_chat_app/core/memory/dreaming_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dreaming schedule defaults to enabled 22:00', () {
    const config = DreamingScheduleConfig();

    expect(config.enabled, isTrue);
    expect(config.hour, 22);
    expect(config.minute, 0);
    expect(config.requiresCharging, isFalse);
    expect(config.requiresUnmeteredNetwork, isFalse);
    expect(formatDreamingScheduleTime(config), '22:00');
  });

  test('dreaming schedule persists optional background constraints', () {
    final config = DreamingScheduleConfig.fromJson({
      'enabled': true,
      'hour': 21,
      'minute': 45,
      'requiresCharging': true,
      'requiresUnmeteredNetwork': true,
    });

    expect(config.requiresCharging, isTrue);
    expect(config.requiresUnmeteredNetwork, isTrue);
    expect(config.toJson(), containsPair('requiresCharging', true));
    expect(config.toJson(), containsPair('requiresUnmeteredNetwork', true));
    expect(
      formatDreamingBackgroundConditions(config),
      '后台附加条件：充电 + 非计费网络（通常 Wi-Fi）',
    );
  });

  test('legacy dreaming schedule keeps background constraints disabled', () {
    final config = DreamingScheduleConfig.fromJson({
      'enabled': true,
      'hour': 22,
      'minute': 0,
    });

    expect(config.requiresCharging, isFalse);
    expect(config.requiresUnmeteredNetwork, isFalse);
    expect(formatDreamingBackgroundConditions(config), '后台附加条件：无');
  });

  test('dreaming schedule only runs after configured time once per day', () {
    const config = DreamingScheduleConfig(hour: 22, minute: 30);

    expect(
      shouldRunDreamingSchedule(config, now: DateTime(2026, 6, 27, 22, 29)),
      isFalse,
    );
    expect(
      shouldRunDreamingSchedule(config, now: DateTime(2026, 6, 27, 22, 30)),
      isTrue,
    );
    expect(
      shouldRunDreamingSchedule(
        config.copyWith(lastAutoRunDayKey: '2026-06-27'),
        now: DateTime(2026, 6, 27, 23),
      ),
      isFalse,
    );
  });

  test(
    'dreaming schedule respects disabled config and clamps invalid time',
    () {
      final config = DreamingScheduleConfig.fromJson({
        'enabled': false,
        'hour': 99,
        'minute': -10,
      });

      expect(config.enabled, isFalse);
      expect(config.hour, 23);
      expect(config.minute, 0);
      expect(
        shouldRunDreamingSchedule(config, now: DateTime(2026, 6, 27, 23)),
        isFalse,
      );
    },
  );

  test('dreaming schedule formats next foreground run status', () {
    const config = DreamingScheduleConfig(hour: 22, minute: 30);

    expect(
      formatNextDreamingForegroundRun(config, now: DateTime(2026, 6, 27, 21)),
      '下次前台整理：今日 22:30',
    );
    expect(
      formatNextDreamingForegroundRun(
        config,
        now: DateTime(2026, 6, 27, 22, 31),
      ),
      '下次前台整理：现在已到期',
    );
    expect(
      formatNextDreamingForegroundRun(
        config.copyWith(lastAutoRunDayKey: '2026-06-27'),
        now: DateTime(2026, 6, 27, 22, 31),
      ),
      '下次前台整理：明日 22:30',
    );
    expect(
      formatNextDreamingForegroundRun(
        config.copyWith(enabled: false),
        now: DateTime(2026, 6, 27, 21),
      ),
      '下次前台整理：已关闭',
    );
  });
}
