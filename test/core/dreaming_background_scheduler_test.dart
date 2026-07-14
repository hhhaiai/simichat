import 'package:ai_chat_app/core/background/dreaming_background_scheduler.dart';
import 'package:ai_chat_app/core/memory/dreaming_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android scheduler registers one unique task at the next run', () async {
    final client = _FakeDreamingBackgroundTaskClient();
    final scheduler = DreamingBackgroundScheduler(client: client);
    final now = DateTime(2026, 7, 14, 18);

    await scheduler.sync(
      const DreamingScheduleConfig(hour: 22, minute: 30),
      now: now,
    );

    expect(client.initializeCount, 1);
    expect(client.registerCount, 1);
    expect(client.cancelCount, 0);
    expect(client.lastInitialDelay, const Duration(hours: 4, minutes: 30));
    expect(client.lastConfig?.hour, 22);
    expect(client.lastConfig?.minute, 30);
  });

  test('Android scheduler cancels unique work when Dreaming is off', () async {
    final client = _FakeDreamingBackgroundTaskClient();
    final scheduler = DreamingBackgroundScheduler(client: client);

    await scheduler.sync(
      const DreamingScheduleConfig(enabled: false),
      now: DateTime(2026, 7, 14, 18),
    );

    expect(client.initializeCount, 1);
    expect(client.registerCount, 0);
    expect(client.cancelCount, 1);
  });

  test('Android scheduler initializes WorkManager only once', () async {
    final client = _FakeDreamingBackgroundTaskClient();
    final scheduler = DreamingBackgroundScheduler(client: client);

    await scheduler.sync(
      const DreamingScheduleConfig(hour: 22),
      now: DateTime(2026, 7, 14, 18),
    );
    await scheduler.sync(
      const DreamingScheduleConfig(
        hour: 23,
        requiresCharging: true,
        requiresUnmeteredNetwork: true,
      ),
      now: DateTime(2026, 7, 14, 18),
    );

    expect(client.initializeCount, 1);
    expect(client.registerCount, 2);
    expect(client.lastConfig?.requiresCharging, isTrue);
    expect(client.lastConfig?.requiresUnmeteredNetwork, isTrue);
  });
}

class _FakeDreamingBackgroundTaskClient
    implements DreamingBackgroundTaskClient {
  int initializeCount = 0;
  int registerCount = 0;
  int cancelCount = 0;
  Duration? lastInitialDelay;
  DreamingScheduleConfig? lastConfig;

  @override
  Future<void> initialize() async {
    initializeCount += 1;
  }

  @override
  Future<void> register({
    required Duration initialDelay,
    required DreamingScheduleConfig config,
  }) async {
    registerCount += 1;
    lastInitialDelay = initialDelay;
    lastConfig = config;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }
}
