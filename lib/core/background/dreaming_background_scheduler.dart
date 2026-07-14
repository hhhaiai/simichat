import '../memory/dreaming_schedule.dart';

abstract interface class DreamingBackgroundTaskClient {
  Future<void> initialize();

  Future<void> register({
    required Duration initialDelay,
    required DreamingScheduleConfig config,
  });

  Future<void> cancel();
}

class DreamingBackgroundScheduler {
  DreamingBackgroundScheduler({required this.client});

  final DreamingBackgroundTaskClient client;
  bool _initialized = false;

  Future<void> sync(DreamingScheduleConfig config, {DateTime? now}) async {
    if (!_initialized) {
      await client.initialize();
      _initialized = true;
    }

    final delay = dreamingBackgroundInitialDelay(
      config,
      now: now ?? DateTime.now(),
    );
    if (delay == null) {
      await client.cancel();
      return;
    }
    await client.register(initialDelay: delay, config: config);
  }
}
