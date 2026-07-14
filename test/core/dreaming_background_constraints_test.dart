import 'package:ai_chat_app/core/background/dreaming_background_workmanager.dart';
import 'package:ai_chat_app/core/memory/dreaming_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  test('Android Dreaming maps user background conditions to WorkManager', () {
    final unconstrained = buildAndroidDreamingBackgroundConstraints(
      const DreamingScheduleConfig(),
    );
    final constrained = buildAndroidDreamingBackgroundConstraints(
      const DreamingScheduleConfig(
        requiresCharging: true,
        requiresUnmeteredNetwork: true,
      ),
    );

    expect(unconstrained.networkType, NetworkType.notRequired);
    expect(unconstrained.requiresCharging, isFalse);
    expect(unconstrained.requiresBatteryNotLow, isTrue);
    expect(unconstrained.requiresStorageNotLow, isTrue);
    expect(constrained.networkType, NetworkType.unmetered);
    expect(constrained.requiresCharging, isTrue);
  });

  test('iOS Dreaming maps charging and network capability honestly', () {
    final unconstrained = buildIosDreamingBackgroundConstraints(
      const DreamingScheduleConfig(),
    );
    final constrained = buildIosDreamingBackgroundConstraints(
      const DreamingScheduleConfig(
        requiresCharging: true,
        requiresUnmeteredNetwork: true,
      ),
    );

    expect(unconstrained.networkType, NetworkType.notRequired);
    expect(unconstrained.requiresCharging, isFalse);
    expect(constrained.networkType, NetworkType.connected);
    expect(constrained.requiresCharging, isTrue);
  });
}
