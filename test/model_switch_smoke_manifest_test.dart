import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production AppBar wires the accessible top model selector', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('class ChatModelSelector extends ConsumerWidget'));
    expect(source, contains('const ChatModelSelector()'));
    expect(source, contains('title: _buildChatTitle(context, activeSession)'));
    expect(source, contains('key: selectorKey'));
    expect(source, contains('toolbarHeight: 72'));
  });

  test('Android model-switch flavor has an isolated application id', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('applicationId = "top.simitalk.aichat"'));
    expect(gradle, contains('flavorDimensions += "smoke"'));
    expect(gradle, contains('create("modelswitch")'));
    expect(gradle, contains('dimension = "smoke"'));
    expect(
      gradle,
      contains('applicationId = "top.simitalk.aichat.modelswitch"'),
    );
  });

  test('model switch device smoke drives the real top selector', () {
    final source = File(
      'integration_test/mobile_model_switch_smoke_test.dart',
    ).readAsStringSync();

    expect(source, contains('NativeDatabase.memory()'));
    expect(source, contains('channelDao.createChannel'));
    expect(source, contains("const firstModelId = 'model-switch-first'"));
    expect(source, contains("const secondModelId = 'model-switch-second'"));
    expect(source, contains('id: firstModelId'));
    expect(source, contains('id: secondModelId'));
    expect(source, contains('sessionDao.createSession'));
    expect(
      source,
      contains('activeSessionIdProvider.notifier).state = sessionId'),
    );
    expect(
      source,
      contains('selectedModelIdProvider.notifier).state = firstModelId'),
    );
    expect(source, contains("find.byTooltip('切换模型')"));
    expect(source, contains("tester.tap(topModelSelector)"));
    expect(source, contains("tester.tap(find.text('switch-model-b'))"));
    expect(source, contains('selectedModelIdProvider'));
    expect(source, contains('kModelSwitchMessageType'));
    expect(source, contains('SIMICHAT_MODEL_SWITCH_BASELINE'));
    expect(source, contains('SIMICHAT_MODEL_SWITCH_UI_ACTION'));
    expect(source, contains('SIMICHAT_MODEL_SWITCH_DB_EVIDENCE'));
    expect(source, contains('SIMICHAT_MODEL_SWITCH_SMOKE_PASS'));
  });

  test(
    'model switch Android script skips safely and preserves the formal APK',
    () async {
      final script = File(
        'scripts/smoke_device_integration_model_switch.sh',
      ).readAsStringSync();

      expect(script, contains('SMOKE_SKIPPED reason=device_unavailable'));
      expect(script, contains('FORMAL_PACKAGE_ID="top.simitalk.aichat"'));
      expect(script, contains('SMOKE_FLAVOR="modelswitch"'));
      expect(
        script,
        contains('SMOKE_PACKAGE_ID="top.simitalk.aichat.modelswitch"'),
      );
      expect(script, contains('EXPECTED_DEBUG_APK_NAME'));
      expect(script, contains(r'app-${SMOKE_FLAVOR}-debug.apk'));
      expect(
        script,
        contains(
          r'EXPECTED_DEBUG_APK_PATH="$PWD/build/app/outputs/flutter-apk/$EXPECTED_DEBUG_APK_NAME"',
        ),
      );
      expect(
        script,
        contains('DEBUG_APK_PATH must point to the current-worktree smoke APK'),
      );
      expect(script, contains('AAPT_BIN'));
      expect(script, contains('apk_package_id'));
      expect(script, contains('ORIGINAL_FORMAL_APK_PATHS'));
      expect(script, contains('ORIGINAL_FORMAL_APK_HASH'));
      expect(script, contains('remote_apk_hash'));
      expect(
        script,
        contains('Smoke package already exists; refusing to overwrite'),
      );
      expect(script, contains(r'package_apk_path "$FORMAL_PACKAGE_ID"'));
      expect(script, contains('ORIGINAL_FIRST_INSTALL_TIME'));
      expect(script, contains('ORIGINAL_DATA_DIR'));
      expect(script, contains('DEBUG_APK_PATH'));
      expect(script, contains(r'--flavor "$SMOKE_FLAVOR"'));
      expect(
        script.split(r'--flavor "$SMOKE_FLAVOR"').length - 1,
        2,
        reason:
            'the APK build and integration test must both select the smoke flavor',
      );
      expect(script, contains('install -r -d'));
      expect(script, contains('SMOKE_DEBUG_RUNNER_INSTALLED'));
      expect(script, contains('SMOKE_DEBUG_RUNNER_CLEANED'));
      expect(script, contains('cleanup=already-removed'));
      expect(script, isNot(contains('shell logcat -c')));
      final cleanupPackageCheck = script.indexOf(
        r'smoke_apk_path="$(package_apk_path "$SMOKE_PACKAGE_ID")"',
      );
      final cleanupForceStop = script.indexOf(
        r'shell am force-stop "$SMOKE_PACKAGE_ID"',
      );
      final cleanupUninstall = script.indexOf(r'uninstall "$SMOKE_PACKAGE_ID"');
      expect(cleanupPackageCheck, greaterThanOrEqualTo(0));
      expect(cleanupForceStop, greaterThan(cleanupPackageCheck));
      expect(cleanupUninstall, greaterThan(cleanupPackageCheck));
      expect(script, contains('assert_formal_package_unchanged'));
      expect(script, contains('SMOKE_FORMAL_PACKAGE_PRESERVED'));
      expect(script, contains('SIMICHAT_MODEL_SWITCH_BASELINE'));
      expect(script, contains('SIMICHAT_MODEL_SWITCH_UI_ACTION'));
      expect(script, contains('SIMICHAT_MODEL_SWITCH_DB_EVIDENCE'));
      expect(script, contains('SIMICHAT_MODEL_SWITCH_SMOKE_PASS'));
      expect(script, contains('trap cleanup EXIT'));
      expect(script, contains(r'uninstall "$SMOKE_PACKAGE_ID"'));
      final integrationCommand = script.indexOf(
        r'"$FLUTTER_BIN" --no-version-check test "$TEST_TARGET"',
      );
      expect(integrationCommand, greaterThanOrEqualTo(0));
      expect(
        script.indexOf(r'-d "$DEVICE_ID"', integrationCommand),
        greaterThan(integrationCommand),
        reason: 'device integration_test must select an explicit device',
      );
      expect(script, isNot(contains('RELEASE_APK_PATH')));
      expect(script, isNot(contains('simichat_release_pubspec')));
      expect(script, isNot(contains(r'install -r -d "$FORMAL_PACKAGE_ID"')));
      expect(script, isNot(contains(r'uninstall "$FORMAL_PACKAGE_ID"')));
      expect(script, isNot(contains(r'pm clear "$FORMAL_PACKAGE_ID"')));
      expect(script, isNot(contains(r'force-stop "$FORMAL_PACKAGE_ID"')));
      expect(script, isNot(contains('pm clear')));
      expect(script, isNot(contains('ensure_formal_process_recoverable')));
      expect(script, isNot(contains(r'-p "$FORMAL_PACKAGE_ID"')));
      expect(
        script,
        isNot(
          contains(r'shell am start -n "$FORMAL_PACKAGE_ID/.MainActivity"'),
        ),
      );
      expect(script, isNot(contains('SMOKE_FORMAL_PROCESS_RECOVERED')));

      final result = await Process.run('bash', [
        '-n',
        'scripts/smoke_device_integration_model_switch.sh',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test(
    'model switch script succeeds when the runner already removed the smoke package',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'simichat-model-switch-manifest-',
      );
      late final File apk;
      late final File existingApkBackup;
      try {
        final fakeAdb = File('${temp.path}/adb');
        final fakeAapt = File('${temp.path}/aapt');
        final fakeFlutter = File('${temp.path}/flutter');
        final state = File('${temp.path}/package-state');
        final calls = File('${temp.path}/adb-calls.log');
        apk = File(
          '${Directory.current.path}/build/app/outputs/flutter-apk/app-modelswitch-debug.apk',
        );
        existingApkBackup = File('${temp.path}/existing-smoke.apk');
        if (apk.existsSync()) {
          await apk.copy(existingApkBackup.path);
        }
        final log = File('${temp.path}/smoke.log');
        final logcat = File('${temp.path}/logcat.log');

        state.writeAsStringSync('absent\n');
        calls.writeAsStringSync('');
        fakeAdb.writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail

state="${FAKE_ADB_STATE:?}"
calls="${FAKE_ADB_CALLS:?}"
printf '%s\n' "$*" >>"$calls"

if [[ "${1:-}" == "-s" ]]; then
  shift 2
fi

case "${1:-}" in
  exec-out)
    if [[ "${2:-}" == "cat" ]]; then
      printf 'formal-apk-bytes\n'
    fi
    ;;
  get-state)
    printf 'device\n'
    ;;
  install)
    printf 'present\n' >"$state"
    printf 'Success\n'
    ;;
  uninstall)
    if [[ "${2:-}" == "top.simitalk.aichat" ||
      "${2:-}" == "top.simitalk.aichat.modelswitch" ]]; then
      echo 'unexpected package uninstall' >&2
      exit 88
    fi
    ;;
  shell)
    shift
    case "${1:-}" in
      pm)
        if [[ "${2:-}" == "path" ]]; then
          package="${3:-}"
          if [[ "$package" == "top.simitalk.aichat" ]]; then
            printf 'package:/data/app/formal/base.apk\n'
          elif [[ "$package" == "top.simitalk.aichat.modelswitch" &&
            "$(cat "$state")" == "present" ]]; then
            printf 'package:/data/app/smoke/base.apk\n'
          fi
        fi
        ;;
      dumpsys)
        package="${3:-}"
        if [[ "$package" == "top.simitalk.aichat" ]]; then
          printf 'firstInstallTime=2026-08-18 12:00:00\n'
          printf 'dataDir=/data/user/0/top.simitalk.aichat\n'
        elif [[ "$package" == "top.simitalk.aichat.modelswitch" &&
          "$(cat "$state")" == "present" ]]; then
          printf 'dataDir=/data/user/0/top.simitalk.aichat.modelswitch\n'
        fi
        ;;
      am)
        if [[ "${2:-}" == "force-stop" &&
          ("${3:-}" == "top.simitalk.aichat" ||
            "${3:-}" == "top.simitalk.aichat.modelswitch") ]]; then
          echo 'unexpected package force-stop' >&2
          exit 89
        fi
        ;;
      logcat)
        printf 'fake logcat\n'
        ;;
    esac
    ;;
esac
''');
        fakeAapt.writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "dump" && "${2:-}" == "badging" ]]; then
  printf "package: name='top.simitalk.aichat.modelswitch' versionCode='1'\n"
fi
''');
        fakeFlutter.writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail

if [[ " $* " == *' build apk '* ]]; then
  mkdir -p "$(dirname "$FAKE_DEBUG_APK_PATH")"
  printf 'fake apk\n' >"$FAKE_DEBUG_APK_PATH"
  exit 0
fi

if [[ " $* " == *' test '* ]]; then
  printf '%s\n' \
    SIMICHAT_MODEL_SWITCH_BASELINE \
    SIMICHAT_MODEL_SWITCH_UI_ACTION \
    SIMICHAT_MODEL_SWITCH_DB_EVIDENCE \
    SIMICHAT_MODEL_SWITCH_SMOKE_PASS
  printf 'absent\n' >"$FAKE_ADB_STATE"
  exit 0
fi

echo "unexpected flutter command: $*" >&2
exit 1
''');

        final chmod = await Process.run('chmod', [
          '+x',
          fakeAdb.path,
          fakeAapt.path,
          fakeFlutter.path,
        ]);
        expect(chmod.exitCode, 0, reason: '${chmod.stdout}\n${chmod.stderr}');

        final environment = Map<String, String>.from(Platform.environment)
          ..addAll({
            'ADB_BIN': fakeAdb.path,
            'AAPT_BIN': fakeAapt.path,
            'DEBUG_APK_PATH': apk.path,
            'DEVICE_ID': 'manifest_device',
            'FAKE_ADB_CALLS': calls.path,
            'FAKE_ADB_STATE': state.path,
            'FAKE_DEBUG_APK_PATH': apk.path,
            'FLUTTER_BIN': fakeFlutter.path,
            'LOGCAT_PATH': logcat.path,
            'LOG_PATH': log.path,
          });
        final result = await Process.run('bash', [
          'scripts/smoke_device_integration_model_switch.sh',
        ], environment: environment);
        final output = '${result.stdout}\n${result.stderr}';
        final adbCalls = calls.readAsStringSync();

        expect(result.exitCode, 0, reason: output);
        expect(output, contains('SMOKE_DEBUG_RUNNER_CLEANED'));
        expect(output, contains('package=top.simitalk.aichat.modelswitch'));
        expect(output, contains('flavor=modelswitch'));
        expect(output, contains('cleanup=already-removed'));
        expect(output, contains('SMOKE_FORMAL_PACKAGE_STATE stage=cleanup'));
        expect(output, contains('SMOKE_FORMAL_PACKAGE_PRESERVED'));
        expect(output, contains('SIMICHAT_MODEL_SWITCH_BASELINE'));
        expect(output, contains('SIMICHAT_MODEL_SWITCH_UI_ACTION'));
        expect(output, contains('SIMICHAT_MODEL_SWITCH_DB_EVIDENCE'));
        expect(output, contains('SIMICHAT_MODEL_SWITCH_SMOKE_PASS'));
        expect(state.readAsStringSync().trim(), 'absent');
        expect(adbCalls, isNot(contains('force-stop top.simitalk.aichat')));
        expect(
          adbCalls,
          isNot(contains('uninstall top.simitalk.aichat.modelswitch')),
        );
      } finally {
        if (existingApkBackup.existsSync()) {
          await existingApkBackup.copy(apk.path);
        } else if (apk.existsSync()) {
          await apk.delete();
        }
        await temp.delete(recursive: true);
      }
    },
  );
}
