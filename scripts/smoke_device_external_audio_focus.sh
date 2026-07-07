#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ROOT_DIR="$(pwd)"
DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TEST_TARGET="integration_test/mobile_external_audio_focus_smoke_test.dart"
HELPER_PACKAGE="top.simitalk.aichat.audiofocusstealer"

if [[ "$DEVICE_ID" == *-* ]]; then
  cat >&2 <<'EOF'
iOS devices must be validated with release-only flows for this project.
This external audio-focus smoke builds an Android helper APK and is only for adb devices.
EOF
  exit 2
fi

if [[ ! -f "$TEST_TARGET" ]]; then
  echo "Missing integration test: $TEST_TARGET" >&2
  exit 1
fi

if [[ -z "${ANDROID_HOME:-}" || ! -d "${ANDROID_HOME:-}/platforms/android-36" ]]; then
  echo "ANDROID_HOME with android-36 platform is required" >&2
  exit 1
fi

PUBSPEC_BACKUP="$(mktemp /tmp/simichat-pubspec.XXXXXX)"
PUBSPEC_LOCK_BACKUP="$(mktemp /tmp/simichat-pubspec-lock.XXXXXX)"
HELPER_DIR="$(mktemp -d /tmp/simichat-audio-focus-helper.XXXXXX)"
TEST_LOG="$(mktemp /tmp/simichat-external-audio-focus.XXXXXX)"
TEST_PID=""

cp pubspec.yaml "$PUBSPEC_BACKUP"
cp pubspec.lock "$PUBSPEC_LOCK_BACKUP"

cleanup() {
  local status=$?
  if [[ -n "${TEST_PID:-}" ]] && kill -0 "$TEST_PID" >/dev/null 2>&1; then
    kill "$TEST_PID" >/dev/null 2>&1 || true
    wait "$TEST_PID" >/dev/null 2>&1 || true
  fi
  adb -s "$DEVICE_ID" uninstall "$HELPER_PACKAGE" >/dev/null 2>&1 || true
  cp "$PUBSPEC_BACKUP" pubspec.yaml
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  "$FLUTTER_BIN" --no-version-check pub get >/dev/null || true
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  rm -f "$PUBSPEC_BACKUP"
  rm -f "$PUBSPEC_LOCK_BACKUP"
  rm -f "$TEST_LOG"
  rm -rf "$HELPER_DIR"
  exit "$status"
}
trap cleanup EXIT

cat >"$HELPER_DIR/settings.gradle.kts" <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "SimiChatAudioFocusStealer"
include(":app")
EOF

mkdir -p "$HELPER_DIR/app/src/main/java/top/simitalk/aichat/audiofocusstealer"
cat >"$HELPER_DIR/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application") version "8.11.1" apply false
}
EOF

cat >"$HELPER_DIR/app/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application")
}

android {
    namespace = "top.simitalk.aichat.audiofocusstealer"
    compileSdk = 36

    defaultConfig {
        applicationId = "top.simitalk.aichat.audiofocusstealer"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
}
EOF

cat >"$HELPER_DIR/app/src/main/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="false"
        android:label="SimiChat Focus Stealer"
        android:theme="@style/AppTheme">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

mkdir -p "$HELPER_DIR/app/src/main/res/values"
cat >"$HELPER_DIR/app/src/main/res/values/styles.xml" <<'EOF'
<resources>
    <style name="AppTheme" parent="@android:style/Theme.Material.NoActionBar">
        <item name="android:windowNoTitle">true</item>
    </style>
</resources>
EOF

cat >"$HELPER_DIR/app/src/main/java/top/simitalk/aichat/audiofocusstealer/MainActivity.java" <<'EOF'
package top.simitalk.aichat.audiofocusstealer;

import android.app.Activity;
import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

public class MainActivity extends Activity {
    private AudioManager audioManager;
    private AudioFocusRequest audioFocusRequest;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final AudioManager.OnAudioFocusChangeListener listener = focusChange -> {};

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestCompetingFocus();
        handler.postDelayed(this::finish, 6000);
    }

    private void requestCompetingFocus() {
        audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        if (audioManager == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest = new AudioFocusRequest.Builder(
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build())
                .setOnAudioFocusChangeListener(listener)
                .build();
            audioManager.requestAudioFocus(audioFocusRequest);
        } else {
            audioManager.requestAudioFocus(
                listener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
            );
        }
    }

    private void abandonCompetingFocus() {
        if (audioManager == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
            audioManager.abandonAudioFocusRequest(audioFocusRequest);
        } else {
            audioManager.abandonAudioFocus(listener);
        }
        audioFocusRequest = null;
        audioManager = null;
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        abandonCompetingFocus();
        super.onDestroy();
    }
}
EOF

echo "Building external audio-focus helper APK..."
(cd "$HELPER_DIR" && "$ROOT_DIR/android/gradlew" --quiet :app:assembleDebug)
HELPER_APK="$HELPER_DIR/app/build/outputs/apk/debug/app-debug.apk"
if [[ ! -f "$HELPER_APK" ]]; then
  echo "Missing helper APK: $HELPER_APK" >&2
  exit 1
fi
adb -s "$DEVICE_ID" install -r "$HELPER_APK" >/dev/null

python3 - <<'PY'
from pathlib import Path
p = Path('pubspec.yaml')
s = p.read_text()
if '\nhooks:' not in s:
    p.write_text(s.rstrip() + '\n\nhooks:\n  user_defines:\n    sqlite3:\n      source: system\n')
PY

"$FLUTTER_BIN" --no-version-check pub get >/dev/null
set +e
"$FLUTTER_BIN" --no-version-check test "$TEST_TARGET" \
  -d "$DEVICE_ID" --no-pub -r expanded 2>&1 | tee "$TEST_LOG" &
TEST_PID=$!
set -e

ready=0
for _ in $(seq 1 120); do
  if grep -q 'SIMICHAT_EXTERNAL_AUDIO_FOCUS_READY' "$TEST_LOG"; then
    ready=1
    break
  fi
  if ! kill -0 "$TEST_PID" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

if [[ "$ready" != "1" ]]; then
  echo "Timed out waiting for external audio focus smoke readiness marker" >&2
  wait "$TEST_PID" || true
  exit 1
fi

echo "Launching external audio-focus helper..."
adb -s "$DEVICE_ID" shell monkey -p "$HELPER_PACKAGE" \
  -c android.intent.category.LAUNCHER 1 >/dev/null

set +e
wait "$TEST_PID"
test_status=$?
set -e
TEST_PID=""
exit "$test_status"
