import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android background Dreaming smoke uses an isolated APK', () {
    final harness = File(
      'lib/core/smoke/android_background_dreaming_smoke_harness.dart',
    ).readAsStringSync();
    final script = File(
      'scripts/smoke_device_android_background_dreaming.sh',
    ).readAsStringSync();

    expect(harness, contains('SIMICHAT_ANDROID_BACKGROUND_DREAMING_READY'));
    expect(harness, contains('Workmanager().registerOneOffTask'));
    expect(
      harness,
      contains('SIMICHAT_ANDROID_BACKGROUND_DREAMING_SMOKE_DELAY_SECONDS'),
    );
    expect(harness, contains('buildAndroidDreamingBackgroundConstraints'));
    expect(script, contains('top.simitalk.aichat.backgroundsmoke'));
    expect(script, contains('SIMICHAT_ANDROID_BACKGROUND_DREAMING_SMOKE=true'));
    expect(script, contains('cmd jobscheduler run'));
    expect(script, contains('    -f'));
    expect(script, contains('-n androidx.work.systemjobscheduler'));
    expect(
      script,
      contains(r'if ! adb -s "$DEVICE_ID" shell cmd jobscheduler'),
    );
    expect(script, contains('SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT'));
    expect(script, contains('assistant_reflection_v1'));
    expect(script, contains('assistant_reflection_pending_v1'));
    expect(script, contains(r'triggerMode=$TRIGGER_MODE'));
    expect(script, contains(r'elapsedSeconds=$RESULT_ELAPSED_SECONDS'));
    expect(script, isNot(contains('flutter test')));
    expect(script, contains(r'if [[ "$SMOKE_PACKAGE" == "$PACKAGE_ID" ]]'));
    expect(
      script.indexOf(r'if [[ "$SMOKE_PACKAGE" == "$PACKAGE_ID" ]]'),
      lessThan(
        script.indexOf(r'adb -s "$DEVICE_ID" uninstall "$SMOKE_PACKAGE"'),
      ),
    );
  });

  test('Android background Dreaming smoke exposes natural scheduling mode', () {
    final script = File(
      'scripts/smoke_device_android_background_dreaming.sh',
    ).readAsStringSync();
    final naturalScript = File(
      'scripts/smoke_device_android_background_dreaming_natural.sh',
    );

    expect(script, contains('TRIGGER_MODE'));
    expect(script, contains('SMOKE_INITIAL_DELAY_SECONDS'));
    expect(script, contains('RESULT_WAIT_SECONDS'));
    expect(script, contains('ANDROID_BACKGROUND_DREAMING_NATURAL_WAIT'));
    expect(script, contains(r'if [[ "$TRIGGER_MODE" == "force" ]]'));
    expect(naturalScript.existsSync(), isTrue);
    final natural = naturalScript.readAsStringSync();
    expect(natural, contains('TRIGGER_MODE=natural'));
    expect(natural, contains('SMOKE_INITIAL_DELAY_SECONDS'));
    expect(natural, contains('RESULT_WAIT_SECONDS'));
    expect(natural, contains('smoke_device_android_background_dreaming.sh'));
  });

  test('Android background Dreaming smoke safely verifies deep idle mode', () {
    final script = File(
      'scripts/smoke_device_android_background_dreaming.sh',
    ).readAsStringSync();
    final dozeScript = File(
      'scripts/smoke_device_android_background_dreaming_doze.sh',
    );

    expect(script, contains('DEVICE_IDLE_MODE'));
    expect(script, contains('cmd deviceidle force-idle'));
    expect(script, contains('cmd deviceidle unforce'));
    expect(script, contains('IDLE_STATE_AT_SCHEDULE'));
    expect(script, contains('IDLE_STATE_AT_RESULT'));
    expect(script, contains(r'idleMode=$DEVICE_IDLE_MODE'));
    expect(dozeScript.existsSync(), isTrue);
    final doze = dozeScript.readAsStringSync();
    expect(doze, contains('TRIGGER_MODE=natural'));
    expect(doze, contains('DEVICE_IDLE_MODE=force'));
    expect(doze, contains('SMOKE_INITIAL_DELAY_SECONDS'));
    expect(doze, contains('RESULT_WAIT_SECONDS'));
    expect(doze, contains('smoke_device_android_background_dreaming.sh'));
  });

  test(
    'Android background Dreaming smoke ignores unrelated global job logs',
    () {
      final script = File(
        'scripts/smoke_device_android_background_dreaming.sh',
      ).readAsStringSync();

      expect(
        script,
        isNot(contains('WM-SystemJobScheduler: Scheduling work ID')),
      );
      expect(script, contains('dumpsys jobscheduler'));
      expect(script, contains(r'$SMOKE_PACKAGE/.*SystemJobService'));
    },
  );

  test(
    'Android background Dreaming smoke verifies headless process restart',
    () {
      final script = File(
        'scripts/smoke_device_android_background_dreaming.sh',
      ).readAsStringSync();
      final processDeathScript = File(
        'scripts/smoke_device_android_background_dreaming_process_death.sh',
      );

      expect(script, contains('BACKGROUND_PROCESS_MODE'));
      expect(script, contains(r'am kill "$SMOKE_PACKAGE"'));
      expect(script, contains('SMOKE_PID_BEFORE'));
      expect(script, contains('SMOKE_PID_AFTER'));
      expect(script, contains('PROCESS_KILL_SETTLE_SECONDS'));
      expect(script, contains(r'processMode=$BACKGROUND_PROCESS_MODE'));
      expect(processDeathScript.existsSync(), isTrue);
      final processDeath = processDeathScript.readAsStringSync();
      expect(processDeath, contains('TRIGGER_MODE=force'));
      expect(processDeath, contains('BACKGROUND_PROCESS_MODE=kill'));
      expect(processDeath, contains('PROCESS_KILL_SETTLE_SECONDS'));
      expect(
        processDeath,
        contains('smoke_device_android_background_dreaming.sh'),
      );
    },
  );

  test(
    'Android background Dreaming smoke verifies natural restart after process death',
    () {
      final naturalProcessDeathScript = File(
        'scripts/smoke_device_android_background_dreaming_process_death_natural.sh',
      );

      expect(naturalProcessDeathScript.existsSync(), isTrue);
      final naturalProcessDeath = naturalProcessDeathScript.readAsStringSync();
      expect(naturalProcessDeath, contains('TRIGGER_MODE=natural'));
      expect(naturalProcessDeath, contains('BACKGROUND_PROCESS_MODE=kill'));
      expect(naturalProcessDeath, contains('SMOKE_INITIAL_DELAY_SECONDS'));
      expect(
        naturalProcessDeath,
        contains(r'RESULT_WAIT_SECONDS="${RESULT_WAIT_SECONDS:-900}"'),
      );
      expect(
        naturalProcessDeath,
        contains('smoke_device_android_background_dreaming.sh'),
      );
    },
  );

  test('Android background Dreaming smoke supports cross-day verification', () {
    final harness = File(
      'lib/core/smoke/android_background_dreaming_smoke_harness.dart',
    ).readAsStringSync();
    final crossDayScript = File(
      'scripts/smoke_device_android_background_dreaming_cross_day.sh',
    );

    expect(harness, contains('scheduledMessageAt'));
    expect(harness, contains('UPDATE messages SET created_at'));
    expect(crossDayScript.existsSync(), isTrue);
    final crossDay = crossDayScript.readAsStringSync();
    expect(crossDay, contains('schedule)'));
    expect(crossDay, contains('verify)'));
    expect(crossDay, contains('cleanup)'));
    expect(crossDay, contains('BACKGROUND_DETACH_AFTER_SCHEDULE=1'));
    expect(crossDay, contains('SMOKE_INITIAL_DELAY_SECONDS:-86400'));
    expect(
      crossDay,
      contains('.omx/state/android-background-dreaming-cross-day.state'),
    );
    expect(crossDay, contains(r'mkdir -p "$(dirname "$STATE_PATH")"'));
    expect(crossDay, contains('assistant_reflection_v1'));
    expect(crossDay, contains('assistant_reflection_pending_v1'));
  });

  test(
    'Android background Dreaming smoke verifies user constraints safely',
    () {
      final harness = File(
        'lib/core/smoke/android_background_dreaming_smoke_harness.dart',
      ).readAsStringSync();
      final mainScript = File(
        'scripts/smoke_device_android_background_dreaming.sh',
      ).readAsStringSync();
      final constraintsScript = File(
        'scripts/smoke_device_android_background_dreaming_constraints.sh',
      );

      expect(
        harness,
        contains('SIMICHAT_ANDROID_BACKGROUND_DREAMING_REQUIRES_CHARGING'),
      );
      expect(
        harness,
        contains(
          'SIMICHAT_ANDROID_BACKGROUND_DREAMING_REQUIRES_UNMETERED_NETWORK',
        ),
      );
      expect(harness, contains('buildAndroidDreamingBackgroundConstraints'));
      expect(mainScript, contains('SMOKE_REQUIRES_CHARGING'));
      expect(mainScript, contains('SMOKE_REQUIRES_UNMETERED_NETWORK'));
      expect(constraintsScript.existsSync(), isTrue);
      final constraints = constraintsScript.readAsStringSync();
      expect(
        constraints,
        contains('top.simitalk.aichat.chargingconstraintsmoke'),
      );
      expect(
        constraints,
        contains('top.simitalk.aichat.networkconstraintsmoke'),
      );
      expect(constraints, contains('cmd battery unplug'));
      expect(constraints, contains('cmd battery reset'));
      expect(constraints, contains('svc wifi disable'));
      expect(constraints, contains('svc wifi enable'));
      expect(constraints, contains('cmd jobscheduler run -s'));
      expect(constraints, contains('ANDROID_DREAMING_CHARGING_CONSTRAINT_OK'));
      expect(constraints, contains('ANDROID_DREAMING_NETWORK_CONSTRAINT_OK'));
      expect(
        constraints,
        contains('.omx/state/android-background-dreaming-cross-day.state'),
      );
      expect(
        constraints,
        isNot(
          contains('/tmp/simichat-android-background-dreaming-cross-day.state'),
        ),
      );
      expect(constraints, contains('sqlite3\\.source'));
    },
  );

  test(
    'Android background Dreaming smoke uses an isolated remote OpenAI model',
    () {
      final harness = File(
        'lib/core/smoke/android_background_dreaming_smoke_harness.dart',
      ).readAsStringSync();
      final mainScript = File(
        'scripts/smoke_device_android_background_dreaming.sh',
      ).readAsStringSync();
      final realModelScript = File(
        'scripts/smoke_device_android_background_dreaming_real_model.sh',
      );

      expect(
        harness,
        contains('SIMICHAT_ANDROID_BACKGROUND_DREAMING_REAL_MODEL'),
      );
      expect(harness, contains('loadAndroidBackgroundDreamingModelConfig'));
      expect(harness, contains('kAssistantReflectionModelEnabledStorageKey'));
      expect(harness, contains('KeyEncryptor.encrypt(modelConfig.apiKey)'));
      expect(harness, contains('protocol: modelConfig.protocol'));
      expect(harness, contains('setDefaultModel'));
      expect(harness.toLowerCase(), isNot(contains('ollama')));
      expect(mainScript, contains('SMOKE_REAL_MODEL'));
      expect(mainScript, contains('SMOKE_MODEL_CONFIG_FILE'));
      expect(mainScript, contains('remote_model_config_mode'));
      expect(
        mainScript,
        contains('android_background_dreaming_model_smoke.json'),
      );
      expect(mainScript, contains(r'run-as $SMOKE_PACKAGE sh -c'));
      expect(mainScript, contains('Isolated smoke package contains unsafe'));
      expect(
        mainScript,
        isNot(contains('SIMICHAT_ANDROID_BACKGROUND_DREAMING_MODEL_BASE_URL')),
      );
      expect(
        mainScript,
        isNot(contains('SIMICHAT_ANDROID_BACKGROUND_DREAMING_MODEL_NAME')),
      );
      expect(mainScript.toLowerCase(), isNot(contains('ollama')));

      expect(realModelScript.existsSync(), isTrue);
      final realModel = realModelScript.readAsStringSync();
      expect(realModel, contains('top.simitalk.aichat.backgroundmodelsmoke'));
      expect(realModel, isNot(contains('SMOKE_PACKAGE=top.simitalk.aichat ')));
      expect(
        realModel,
        isNot(contains('SMOKE_PACKAGE=top.simitalk.aichat.backgroundsmoke')),
      );
      expect(realModel, contains('TRIGGER_MODE=natural'));
      expect(realModel, contains('SMOKE_REAL_MODEL=1'));
      expect(realModel, contains('MODEL_CONFIG_FILE'));
      expect(realModel, contains('remote_model_config_mode'));
      expect(realModel, contains('/v1/chat/completions'));
      expect(realModel, contains('REMOTE_MODEL_API_READY'));
      expect(realModel, contains('REMOTE_MODEL_PREFLIGHT_ATTEMPTS'));
      expect(realModel, contains('REMOTE_MODEL_API_RETRY'));
      expect(realModel, contains('401|408|429|5??'));
      expect(realModel, isNot(contains('head -c')));
      expect(realModel.toLowerCase(), isNot(contains('ollama')));
      expect(realModel, isNot(contains('adb reverse')));
      expect(realModel, isNot(contains('http://')));
      expect(realModel, isNot(contains(r'API_BASE_URL="${API_BASE_URL:-')));
      expect(realModel, isNot(contains(r'MODEL_NAME="${MODEL_NAME:-')));
      expect(realModel, isNot(contains('Bearer sk-')));
      expect(mainScript, contains('generationMode'));
      expect(mainScript, contains('model_fallback'));
      expect(mainScript, contains('user_profile_change_proposals_v1'));
      expect(mainScript, contains('Profile proposal did not use'));
      expect(mainScript, contains('flutter.user_profile_v1'));
      expect(mainScript, contains('modified the formal user profile'));
      expect(
        realModel,
        contains('android-background-dreaming-cross-day.state'),
      );
      expect(realModel, isNot(contains('flutter test')));
    },
  );
}
