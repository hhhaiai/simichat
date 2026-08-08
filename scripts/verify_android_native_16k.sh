#!/usr/bin/env bash
set -euo pipefail

# Verify both ELF load-segment alignment and APK ZIP alignment. These are
# independent checks: a correctly aligned APK can still contain a 4 KB ELF,
# and a correctly linked ELF can still be placed at an invalid ZIP offset.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JNI_LIB_DIR="${SIMICHAT_ANDROID_JNI_LIB_DIR:-$ROOT_DIR/android/app/src/main/jniLibs}"
APK_PATH="${1:-${SIMICHAT_ANDROID_APK:-}}"
REQUIRED_ALIGNMENT=16384

find_tool() {
  local requested="$1"
  shift
  if [[ -n "$requested" && -x "$requested" ]]; then
    printf '%s\n' "$requested"
    return 0
  fi
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

READELF=""
if [[ -n "${LLVM_READELF:-}" ]]; then
  READELF="$LLVM_READELF"
elif [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
  for host in darwin-x86_64 darwin-arm64 linux-x86_64 linux-arm64; do
    candidate="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host/bin/llvm-readelf"
    if [[ -x "$candidate" ]]; then
      READELF="$candidate"
      break
    fi
  done
fi
if [[ -z "$READELF" ]]; then
  READELF="$(find_tool '' llvm-readelf readelf || true)"
fi
if [[ -z "$READELF" ]]; then
  echo "No llvm-readelf/readelf found; set LLVM_READELF or ANDROID_NDK_HOME." >&2
  exit 2
fi

declare -a LIBRARIES=()
while IFS= read -r -d '' library; do
  LIBRARIES+=("$library")
done < <(find "$JNI_LIB_DIR" -type f -name '*.so' -print0 2>/dev/null)

staging=""
cleanup() {
  if [[ -n "$staging" ]]; then
    rm -rf "$staging"
  fi
}
trap cleanup EXIT

if [[ -n "$APK_PATH" ]]; then
  [[ -f "$APK_PATH" ]] || { echo "APK not found: $APK_PATH" >&2; exit 1; }
  staging="$(mktemp -d "${TMPDIR:-/tmp}/simichat-android-16k.XXXXXX")"
  unzip -q "$APK_PATH" 'lib/*/*.so' -d "$staging"
  while IFS= read -r -d '' library; do
    LIBRARIES+=("$library")
  done < <(find "$staging/lib" -type f -name '*.so' -print0 2>/dev/null)
fi

if [[ "${#LIBRARIES[@]}" -eq 0 ]]; then
  echo "No Android ELF libraries found under $JNI_LIB_DIR${APK_PATH:+ or $APK_PATH}." >&2
  exit 1
fi

status=0
for library in "${LIBRARIES[@]}"; do
  alignment_count=0
  library_status=0
  while IFS= read -r alignment; do
    [[ -n "$alignment" ]] || continue
    alignment_count=$((alignment_count + 1))
    value=$((alignment))
    if ((value < REQUIRED_ALIGNMENT)); then
      echo "FAIL ELF alignment ${alignment} (< 0x4000): $library" >&2
      status=1
      library_status=1
    fi
  done < <("$READELF" -l "$library" | awk '$1 == "LOAD" { print $NF }')
  if ((alignment_count == 0)); then
    echo "FAIL no LOAD segments: $library" >&2
    status=1
    library_status=1
    continue
  fi
  if ((library_status == 0)); then
    echo "PASS ELF 16 KB alignment: $library"
  fi
done

if [[ -n "$APK_PATH" ]]; then
  ZIPALIGN="$(find_tool "${ZIPALIGN:-}" zipalign || true)"
  if [[ -z "$ZIPALIGN" ]]; then
    echo "No zipalign found; APK ZIP alignment cannot be verified." >&2
    exit 2
  fi
  if "$ZIPALIGN" -c -P 16 -v 4 "$APK_PATH" >/dev/null 2>&1; then
    echo "PASS APK ZIP 16 KB alignment: $APK_PATH"
  else
    # `-p` is not an equivalent 16 KB verification mode: older zipalign
    # versions can only page-align stored .so entries and may report a false
    # result for the rest of the APK. Require the Android 15-era -P 16 flag.
    if "$ZIPALIGN" -h 2>&1 | grep -q -- '-P 16'; then
      echo "FAIL APK ZIP 16 KB alignment: $APK_PATH" >&2
      status=1
    else
      echo "No zipalign with -P 16 support; install Android build-tools 35+." >&2
      exit 2
    fi
  fi
fi

if ((status != 0)); then
  echo "ANDROID_16K_NATIVE_AUDIT_FAIL"
  exit "$status"
fi
echo "ANDROID_16K_NATIVE_AUDIT_PASS"
