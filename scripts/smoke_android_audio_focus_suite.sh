#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
RESTORE_RELEASE="${RESTORE_RELEASE:-1}"
RELEASE_RESTORED=0

if [[ "$DEVICE_ID" == *-* ]]; then
  cat >&2 <<'EOF'
iOS devices must be validated with release-only flows for this project.
This Android audio-focus suite is only for adb devices.
EOF
  exit 2
fi

cleanup() {
  local status=$?
  if [[ "$status" != "0" && "$RESTORE_RELEASE" == "1" && "$RELEASE_RESTORED" != "1" ]]; then
    echo "Audio focus suite failed; restoring Android release build..." >&2
    scripts/smoke_android_release_install_launch.sh "$DEVICE_ID" || true
  fi
  exit "$status"
}
trap cleanup EXIT

echo "==> Android audio focus suite: debug-only competing focus"
scripts/smoke_device_integration_audio_focus_loss.sh "$DEVICE_ID"

echo "==> Android audio focus suite: external helper APK focus takeover"
scripts/smoke_device_external_audio_focus.sh "$DEVICE_ID"

if [[ "$RESTORE_RELEASE" == "1" ]]; then
  echo "==> Android audio focus suite: restore ordinary release"
  scripts/smoke_android_release_install_launch.sh "$DEVICE_ID"
  RELEASE_RESTORED=1
fi

echo "Android audio focus suite passed for $DEVICE_ID"
