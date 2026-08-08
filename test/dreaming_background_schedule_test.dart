import 'package:ai_chat_app/core/memory/dreaming_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled dreaming does not schedule Android background work', () {
    final scheduledAt = nextDreamingBackgroundRunAt(
      const DreamingScheduleConfig(enabled: false),
      now: DateTime(2026, 7, 14, 18),
    );

    expect(scheduledAt, isNull);
  });

  test('background dreaming schedules today before configured time', () {
    final scheduledAt = nextDreamingBackgroundRunAt(
      const DreamingScheduleConfig(hour: 22, minute: 30),
      now: DateTime(2026, 7, 14, 18),
    );

    expect(scheduledAt, DateTime(2026, 7, 14, 22, 30));
  });

  test('overdue background dreaming is eligible immediately', () {
    final now = DateTime(2026, 7, 14, 22, 31);
    final scheduledAt = nextDreamingBackgroundRunAt(
      const DreamingScheduleConfig(hour: 22, minute: 30),
      now: now,
    );

    expect(scheduledAt, now);
    expect(
      dreamingBackgroundInitialDelay(
        const DreamingScheduleConfig(hour: 22, minute: 30),
        now: now,
      ),
      Duration.zero,
    );
  });

  test('completed background dreaming schedules the next local day', () {
    final scheduledAt = nextDreamingBackgroundRunAt(
      const DreamingScheduleConfig(
        hour: 22,
        minute: 30,
        lastAutoRunDayKey: '2026-07-14',
      ),
      now: DateTime(2026, 7, 14, 22, 31),
    );

    expect(scheduledAt, DateTime(2026, 7, 15, 22, 30));
  });
}
