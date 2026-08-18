#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
FORMAL_PACKAGE_ID="top.simitalk.aichat"
if [[ -n "${PACKAGE_ID:-}" && "$PACKAGE_ID" != "$FORMAL_PACKAGE_ID" ]]; then
  echo "PACKAGE_ID override is not allowed for the formal Android release: $PACKAGE_ID" >&2
  exit 2
fi
PACKAGE_ID="$FORMAL_PACKAGE_ID"
REQUESTED_LAUNCH_COMPONENT="${LAUNCH_COMPONENT:-${PACKAGE_ID}/.MainActivity}"
LAUNCH_COMPONENT="${PACKAGE_ID}/.MainActivity"
if [[ "$REQUESTED_LAUNCH_COMPONENT" != "$LAUNCH_COMPONENT" ]]; then
  echo "LAUNCH_COMPONENT override is not allowed for the formal Android release: $REQUESTED_LAUNCH_COMPONENT" >&2
  exit 2
fi
FLAVOR="production"
EXPECTED_APK_NAME="app-${FLAVOR}-release.apk"
EXPECTED_APK_PATH="$PWD/build/app/outputs/flutter-apk/$EXPECTED_APK_NAME"
REQUESTED_APK_PATH="${APK_PATH:-$EXPECTED_APK_PATH}"
TARGET_PLATFORM="${TARGET_PLATFORM:-android-arm64}"
APK_PATH="$EXPECTED_APK_PATH"
PID_POLL_ATTEMPTS="${PID_POLL_ATTEMPTS:-20}"
PID_POLL_INTERVAL_SECONDS="${PID_POLL_INTERVAL_SECONDS:-1}"

if [[ "$REQUESTED_APK_PATH" != "$EXPECTED_APK_PATH" ]]; then
  echo "APK_PATH must point to the current-worktree production APK: $EXPECTED_APK_PATH" >&2
  exit 2
fi

# Isolated production-flavor smoke scripts use this Gradle property for debug
# builds. Never allow that override to leak into the production release build.
if [[ -n "${ORG_GRADLE_PROJECT_simichatApplicationId:-}" ]]; then
  echo "simichatApplicationId override is not allowed for the formal Android release" >&2
  exit 2
fi

source scripts/lib/release_pubspec_hook.sh

ORIGINAL_BASE_APK_COPY=""
INSTALLED_BASE_APK_COPY=""
cleanup() {
  if [[ -n "${ORIGINAL_BASE_APK_COPY:-}" ]]; then
    rm -f "$ORIGINAL_BASE_APK_COPY"
  fi
  if [[ -n "${INSTALLED_BASE_APK_COPY:-}" ]]; then
    rm -f "$INSTALLED_BASE_APK_COPY"
  fi
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

resolve_android_tool() {
  local tool="$1"
  local candidate
  local selected=""
  local sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

  if candidate="$(command -v "$tool" 2>/dev/null)"; then
    printf '%s' "$candidate"
    return 0
  fi

  [[ -n "$sdk_root" ]] || return 1
  if [[ "$tool" == "aapt" || "$tool" == "apksigner" ]]; then
    for candidate in "$sdk_root"/build-tools/*/"$tool"; do
      if [[ -x "$candidate" ]]; then
        selected="$candidate"
      fi
    done
  fi

  [[ -n "$selected" ]] || return 1
  printf '%s' "$selected"
}

AAPT_BIN="$(resolve_android_tool aapt || true)"
APKSIGNER_BIN="$(resolve_android_tool apksigner || true)"
if [[ -z "$AAPT_BIN" || -z "$APKSIGNER_BIN" ]]; then
  echo "aapt and apksigner are required to verify production APK identity/signature" >&2
  exit 2
fi

package_dump() {
  local package="$1"
  adb -s "$DEVICE_ID" shell dumpsys package "$package" 2>/dev/null | tr -d '\r'
}

package_field_from_dump() {
  local dump="$1"
  local field="$2"
  printf '%s\n' "$dump" \
    | sed -n "s/.*${field}=//p" | head -1 | tr -d '\r'
}

package_field() {
  local package="$1"
  local field="$2"
  package_field_from_dump "$(package_dump "$package")" "$field"
}

package_identity() {
  local package="$1"
  package_dump "$package" \
    | sed -n 's/.*Package \[\([^]]*\)\].*/\1/p' | head -1 | tr -d '\r'
}

package_apk_path() {
  local package="$1"
  local path
  path="$(adb -s "$DEVICE_ID" shell pm path "$package" 2>/dev/null \
    | tr -d '\r' | sed -n 's/^package://p' | head -1)"
  [[ "$path" == */base.apk ]] || return 1
  printf '%s' "$path"
}

copy_installed_base_apk() {
  local package="$1"
  local destination="$2"
  local apk_path

  apk_path="$(package_apk_path "$package")" || return 1
  adb -s "$DEVICE_ID" exec-out cat "$apk_path" >"$destination"
  [[ -s "$destination" ]]
}

apk_package_id() {
  local apk_path="$1"
  local package_id
  package_id="$("$AAPT_BIN" dump badging "$apk_path" 2>/dev/null \
    | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
  if [[ -z "$package_id" ]]; then
    echo "Unable to read APK package identity: $apk_path" >&2
    return 1
  fi
  printf '%s' "$package_id"
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    echo "Neither shasum nor sha256sum is available" >&2
    return 1
  fi
}

assert_valid_apk_signature() {
  local label="$1"
  local apk_path="$2"
  local report

  SIGNATURE_CERT_SHA256=""
  SIGNATURE_SCHEMES=""
  if ! report="$("$APKSIGNER_BIN" verify --verbose --print-certs "$apk_path" 2>&1)"; then
    echo "${label} APK signature verification failed: $report" >&2
    return 1
  fi
  if ! printf '%s\n' "$report" | grep -Fxq 'Verifies'; then
    echo "${label} APK did not report Verifies" >&2
    return 1
  fi
  if ! printf '%s\n' "$report" \
    | grep -Eq '^Verified using v[0-9.]+ scheme.*: true$'; then
    echo "${label} APK has no verified APK signature scheme" >&2
    return 1
  fi

  SIGNATURE_CERT_SHA256="$(printf '%s\n' "$report" \
    | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' \
    | head -1 | tr -d '[:space:]')"
  SIGNATURE_SCHEMES="$(printf '%s\n' "$report" \
    | grep -E '^Verified using v[0-9.]+ scheme.*: true$' \
    | tr '\n' ',' | sed 's/,$//' || true)"
  if [[ -z "$SIGNATURE_CERT_SHA256" ]]; then
    echo "${label} APK signer certificate SHA-256 digest is missing" >&2
    return 1
  fi

  printf 'ANDROID_RELEASE_APK_SIGNATURE stage=%s certSha256=%s schemes=%s\n' \
    "$label" "$SIGNATURE_CERT_SHA256" "$SIGNATURE_SCHEMES"
}

assert_release_package_flags() {
  local label="$1"
  local dump="$2"
  local flags

  flags="$(printf '%s\n' "$dump" \
    | grep -E '(^|[[:space:]])(pkgFlags|flags)=\[[^]]*\]' \
    | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' || true)"
  if printf '%s\n' "$dump" \
    | grep -Eq '(^|[^[:alnum:]_])(DEBUGGABLE|TEST_ONLY)([^[:alnum:]_]|$)'; then
    echo "${label} production package has forbidden DEBUGGABLE/TEST_ONLY flag: ${flags:-unreported}" >&2
    return 1
  fi
  if printf '%s\n' "$dump" \
    | grep -Eiq '(^|[^[:alnum:]_])debuggable[[:space:]]*=[[:space:]]*(true|1)'; then
    echo "${label} production package is debuggable: ${flags:-unreported}" >&2
    return 1
  fi
  printf 'ANDROID_RELEASE_PACKAGE_FLAGS stage=%s flags=%s\n' \
    "$label" "${flags:-unreported}"
}

assert_no_isolated_smoke_packages() {
  local stage="$1"
  local packages

  if ! packages="$(adb -s "$DEVICE_ID" shell pm list packages 2>/dev/null \
    | tr -d '\r' | sed 's/^package://' \
    | awk -v prefix="${FORMAL_PACKAGE_ID}." 'index($0, prefix) == 1 { print }')"; then
    echo "Unable to inspect installed Android packages for isolated smoke residue" >&2
    return 1
  fi
  if [[ -n "$packages" ]]; then
    printf 'ANDROID_RELEASE_ISOLATED_PACKAGE_CHECK stage=%s status=blocked packages=%s\n' \
      "$stage" "$(printf '%s' "$packages" | tr '\n' ',')" >&2
    return 1
  fi
  printf 'ANDROID_RELEASE_ISOLATED_PACKAGE_CHECK stage=%s status=clean prefix=%s.\n' \
    "$stage" "$FORMAL_PACKAGE_ID"
}

if ! assert_no_isolated_smoke_packages pre_install; then
  echo "Refusing release parity while an isolated smoke package remains installed" >&2
  exit 2
fi

ORIGINAL_PACKAGE_DUMP="$(package_dump "$PACKAGE_ID")"
if ! printf '%s\n' "$ORIGINAL_PACKAGE_DUMP" \
  | grep -Fq "Package [$PACKAGE_ID]"; then
  echo "Formal production package is missing; refusing to compare install state: $PACKAGE_ID" >&2
  exit 2
fi
ORIGINAL_PACKAGE_ID="$(package_identity "$PACKAGE_ID")"
if [[ "$ORIGINAL_PACKAGE_ID" != "$PACKAGE_ID" ]]; then
  echo "Installed production package identity mismatch: expected=$PACKAGE_ID actual=$ORIGINAL_PACKAGE_ID" >&2
  exit 2
fi

ORIGINAL_FIRST_INSTALL_TIME="$(package_field_from_dump "$ORIGINAL_PACKAGE_DUMP" firstInstallTime)"
ORIGINAL_DATA_DIR="$(package_field_from_dump "$ORIGINAL_PACKAGE_DUMP" dataDir)"
ORIGINAL_APK_PATH="$(package_apk_path "$PACKAGE_ID")"
ORIGINAL_BASE_APK_COPY="$(mktemp "${TMPDIR:-/tmp}/simichat-production-original-base.XXXXXX.apk")"
if ! copy_installed_base_apk "$PACKAGE_ID" "$ORIGINAL_BASE_APK_COPY"; then
  echo "Unable to read the installed production base.apk before install -r" >&2
  exit 2
fi
ORIGINAL_APK_HASH="$(sha256_file "$ORIGINAL_BASE_APK_COPY")"
if [[ -z "$ORIGINAL_FIRST_INSTALL_TIME" || -z "$ORIGINAL_DATA_DIR" || \
  -z "$ORIGINAL_APK_PATH" || -z "$ORIGINAL_APK_HASH" ]]; then
  echo "Unable to capture pre-install production package state" >&2
  exit 2
fi
if ! assert_release_package_flags pre_install "$ORIGINAL_PACKAGE_DUMP"; then
  exit 2
fi
if ! assert_valid_apk_signature pre_install "$ORIGINAL_BASE_APK_COPY"; then
  exit 2
fi
ORIGINAL_CERT_SHA256="$SIGNATURE_CERT_SHA256"
printf 'ANDROID_RELEASE_PRE_INSTALL package=%s firstInstallTime=%s dataDir=%s apk=%s apkHash=%s\n' \
  "$PACKAGE_ID" "$ORIGINAL_FIRST_INSTALL_TIME" "$ORIGINAL_DATA_DIR" \
  "$ORIGINAL_APK_PATH" "$ORIGINAL_APK_HASH"

simichat_release_pubspec_setup 1

build_args=(--release --flavor "$FLAVOR" --no-pub)
if [[ -n "$TARGET_PLATFORM" ]]; then
  build_args+=(--target-platform "$TARGET_PLATFORM")
fi

"$FLUTTER_BIN" --no-version-check build apk "${build_args[@]}"

if [[ ! -f "$APK_PATH" ]]; then
  echo "Missing release APK: $APK_PATH" >&2
  exit 1
fi

ls -lh "$APK_PATH"

BUILT_APK_BADGING="$("$AAPT_BIN" dump badging "$APK_PATH" 2>&1)" || {
  echo "Unable to read APK manifest/badging: $BUILT_APK_BADGING" >&2
  exit 1
}
BUILT_PACKAGE_ID="$(apk_package_id "$APK_PATH")"
if [[ "$BUILT_PACKAGE_ID" != "$PACKAGE_ID" ]]; then
  echo "Built production APK identity mismatch: expected=$PACKAGE_ID actual=$BUILT_PACKAGE_ID" >&2
  exit 1
fi
BUILT_APK_FLAGS="$(printf '%s\n' "$BUILT_APK_BADGING" \
  | grep -E '^(application-debuggable|testOnly)' | tr '\n' ',' | sed 's/,$//' || true)"
if [[ -n "$BUILT_APK_FLAGS" ]]; then
  echo "Production APK has forbidden debug/test flags: $BUILT_APK_FLAGS" >&2
  exit 1
fi
printf 'ANDROID_RELEASE_APK_IDENTITY source=%s package=%s flags=%s\n' \
  "$APK_PATH" "$BUILT_PACKAGE_ID" "${BUILT_APK_FLAGS:-none}"

if ! assert_valid_apk_signature built "$APK_PATH"; then
  exit 1
fi
BUILT_CERT_SHA256="$SIGNATURE_CERT_SHA256"
if [[ "$BUILT_CERT_SHA256" != "$ORIGINAL_CERT_SHA256" ]]; then
  echo "Production signing certificate changed; refusing install -r" >&2
  echo "preInstallCertSha256=$ORIGINAL_CERT_SHA256 builtCertSha256=$BUILT_CERT_SHA256" >&2
  exit 2
fi

BUILT_APK_HASH="$(sha256_file "$APK_PATH")"
if [[ -z "$BUILT_APK_HASH" ]]; then
  echo "Unable to hash built production APK: $APK_PATH" >&2
  exit 1
fi

adb -s "$DEVICE_ID" install -r "$APK_PATH"

if ! assert_no_isolated_smoke_packages post_install; then
  echo "Isolated smoke package residue appeared during production install" >&2
  exit 1
fi

AFTER_PACKAGE_DUMP="$(package_dump "$PACKAGE_ID")"
if ! printf '%s\n' "$AFTER_PACKAGE_DUMP" \
  | grep -Fq "Package [$PACKAGE_ID]"; then
  echo "Production package disappeared after install -r: $PACKAGE_ID" >&2
  exit 1
fi
INSTALLED_APK_PATH="$(package_apk_path "$PACKAGE_ID")"
INSTALLED_PACKAGE_ID="$(package_identity "$PACKAGE_ID")"
INSTALLED_BASE_APK_COPY="$(mktemp "${TMPDIR:-/tmp}/simichat-production-installed-base.XXXXXX.apk")"
if ! copy_installed_base_apk "$PACKAGE_ID" "$INSTALLED_BASE_APK_COPY"; then
  echo "Unable to read the installed production base.apk after install -r" >&2
  exit 1
fi
INSTALLED_APK_HASH="$(sha256_file "$INSTALLED_BASE_APK_COPY")"
AFTER_FIRST_INSTALL_TIME="$(package_field_from_dump "$AFTER_PACKAGE_DUMP" firstInstallTime)"
AFTER_DATA_DIR="$(package_field_from_dump "$AFTER_PACKAGE_DUMP" dataDir)"
AFTER_LAST_UPDATE_TIME="$(package_field_from_dump "$AFTER_PACKAGE_DUMP" lastUpdateTime)"
printf 'ANDROID_RELEASE_POST_INSTALL package=%s installedPackage=%s firstInstallTime=%s dataDir=%s baseApk=%s apkHash=%s builtApkHash=%s\n' \
  "$PACKAGE_ID" "$INSTALLED_PACKAGE_ID" "$AFTER_FIRST_INSTALL_TIME" "$AFTER_DATA_DIR" \
  "$INSTALLED_APK_PATH" "$INSTALLED_APK_HASH" "$BUILT_APK_HASH"
if [[ "$INSTALLED_PACKAGE_ID" != "$PACKAGE_ID" || \
  "$AFTER_FIRST_INSTALL_TIME" != "$ORIGINAL_FIRST_INSTALL_TIME" || \
  "$AFTER_DATA_DIR" != "$ORIGINAL_DATA_DIR" || \
  "$INSTALLED_APK_PATH" != */base.apk || \
  "$INSTALLED_APK_HASH" != "$BUILT_APK_HASH" ]]; then
  echo "Production package install state/base.apk/hash mismatch" >&2
  exit 1
fi
if ! assert_release_package_flags post_install "$AFTER_PACKAGE_DUMP"; then
  exit 1
fi
if ! assert_valid_apk_signature post_install "$INSTALLED_BASE_APK_COPY"; then
  exit 1
fi
INSTALLED_CERT_SHA256="$SIGNATURE_CERT_SHA256"
if [[ "$INSTALLED_CERT_SHA256" != "$BUILT_CERT_SHA256" ]]; then
  echo "Installed base.apk signing certificate does not match the built production APK" >&2
  exit 1
fi
printf 'ANDROID_RELEASE_PARITY status=verified source=%s baseApk=%s package=%s ' \
  "$APK_PATH" "$INSTALLED_APK_PATH" "$PACKAGE_ID"
printf 'apkHash=%s certSha256=%s firstInstallTime=%s dataDir=%s lastUpdateTime=%s\n' \
  "$INSTALLED_APK_HASH" "$INSTALLED_CERT_SHA256" "$AFTER_FIRST_INSTALL_TIME" \
  "$AFTER_DATA_DIR" "${AFTER_LAST_UPDATE_TIME:-unknown}"

monkey_status=0
if adb -s "$DEVICE_ID" shell monkey \
  -p "$PACKAGE_ID" \
  -c android.intent.category.LAUNCHER \
  1; then
  echo "SIMICHAT_ANDROID_RELEASE_MONKEY_RESULT status=success package=$PACKAGE_ID"
else
  monkey_status=$?
  echo "SIMICHAT_ANDROID_RELEASE_MONKEY_RESULT status=failed exit=$monkey_status package=$PACKAGE_ID" >&2
fi

echo "Installed Android release app:"
adb -s "$DEVICE_ID" shell dumpsys package "$PACKAGE_ID" \
  | grep -E "versionName=|versionCode=|firstInstallTime=|lastUpdateTime=|dataDir=" \
  | head -20

wait_for_package_pid() {
  local attempt candidate

  for ((attempt = 1; attempt <= PID_POLL_ATTEMPTS; attempt++)); do
    candidate="$(
      adb -s "$DEVICE_ID" shell pidof "$PACKAGE_ID" 2>/dev/null \
        | tr -d '\r' || true
    )"
    if [[ -n "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
    if ((attempt < PID_POLL_ATTEMPTS)); then
      sleep "$PID_POLL_INTERVAL_SECONDS"
    fi
  done

  return 1
}

pid=""
launch_mode="monkey"
if [[ "$monkey_status" -eq 0 ]]; then
  pid="$(wait_for_package_pid || true)"
fi

if [[ -z "$pid" ]]; then
  if [[ "$monkey_status" -ne 0 ]]; then
    fallback_reason="monkey_failed"
  else
    fallback_reason="monkey_pid_missing"
  fi
  echo "SIMICHAT_ANDROID_RELEASE_LAUNCH_FALLBACK mode=am_start component=$LAUNCH_COMPONENT reason=$fallback_reason"

  if adb -s "$DEVICE_ID" shell am start -n "$LAUNCH_COMPONENT"; then
    launch_mode="am_start"
    echo "SIMICHAT_ANDROID_RELEASE_AM_START_RESULT status=success component=$LAUNCH_COMPONENT"
  else
    am_start_status=$?
    echo "SIMICHAT_ANDROID_RELEASE_AM_START_RESULT status=failed exit=$am_start_status component=$LAUNCH_COMPONENT" >&2
    exit 1
  fi

  pid="$(wait_for_package_pid || true)"
fi

if [[ -n "$pid" ]]; then
  echo "SIMICHAT_ANDROID_RELEASE_LAUNCH_RESULT status=success mode=$launch_mode component=$LAUNCH_COMPONENT package=$PACKAGE_ID pid=$pid"
  echo "Launched Android release app:"
  echo "- pid: $pid"
else
  echo "SIMICHAT_ANDROID_RELEASE_LAUNCH_RESULT status=failed mode=$launch_mode component=$LAUNCH_COMPONENT package=$PACKAGE_ID" >&2
  echo "Android release process is not visible after launch" >&2
  exit 1
fi

FINAL_FIRST_INSTALL_TIME="$(package_field "$PACKAGE_ID" firstInstallTime)"
FINAL_DATA_DIR="$(package_field "$PACKAGE_ID" dataDir)"
if [[ "$FINAL_FIRST_INSTALL_TIME" != "$ORIGINAL_FIRST_INSTALL_TIME" || \
  "$FINAL_DATA_DIR" != "$ORIGINAL_DATA_DIR" ]]; then
  echo "Production package identity changed after launch" >&2
  exit 1
fi
printf 'ANDROID_RELEASE_FINAL_STATE package=%s firstInstallTime=%s dataDir=%s\n' \
  "$PACKAGE_ID" "$FINAL_FIRST_INSTALL_TIME" "$FINAL_DATA_DIR"
