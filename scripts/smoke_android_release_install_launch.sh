#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
PACKAGE_ID="${PACKAGE_ID:-top.simitalk.aichat}"
TARGET_PLATFORM="${TARGET_PLATFORM:-android-arm64}"
APK_PATH="${APK_PATH:-build/app/outputs/flutter-apk/app-release.apk}"

source scripts/lib/release_pubspec_hook.sh

cleanup() {
  simichat_release_pubspec_restore
}
trap cleanup EXIT

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required for Android release smoke" >&2
  exit 1
fi

if ! adb -s "$DEVICE_ID" get-state >/dev/null 2>&1; then
  echo "Android device $DEVICE_ID is not available" >&2
  exit 1
fi

simichat_release_pubspec_setup 1

build_args=(--release --no-pub)
if [[ -n "$TARGET_PLATFORM" ]]; then
  build_args+=(--target-platform "$TARGET_PLATFORM")
fi

"$FLUTTER_BIN" --no-version-check build apk "${build_args[@]}"

if [[ ! -f "$APK_PATH" ]]; then
  echo "Missing release APK: $APK_PATH" >&2
  exit 1
fi

ls -lh "$APK_PATH"

adb -s "$DEVICE_ID" install -r "$APK_PATH"
adb -s "$DEVICE_ID" shell monkey \
  -p "$PACKAGE_ID" \
  -c android.intent.category.LAUNCHER \
  1

echo "Installed Android release app:"
adb -s "$DEVICE_ID" shell dumpsys package "$PACKAGE_ID" \
  | grep -E "versionName=|versionCode=|firstInstallTime=|lastUpdateTime=|dataDir=" \
  | head -20

pid="$(adb -s "$DEVICE_ID" shell pidof "$PACKAGE_ID" || true)"
if [[ -n "$pid" ]]; then
  echo "Launched Android release app:"
  echo "- pid: $pid"
else
  echo "Android release process is not visible after launch" >&2
  exit 1
fi
