#!/usr/bin/env bash
# Temporary pubspec adjustments for release builds.
# - Adds sqlite3 source=system to avoid release builds depending on GitHub
#   native-asset downloads.
# - Optionally removes the integration_test dev plugin for Android release
#   builds, where the generated registrant can otherwise reference a class that
#   is not on the release classpath.

SIMICHAT_RELEASE_PUBSPEC_TMP="${SIMICHAT_RELEASE_PUBSPEC_TMP:-}"

simichat_release_pubspec_setup() {
  local remove_integration_test="${1:-0}"
  if [[ -n "${SIMICHAT_RELEASE_PUBSPEC_TMP:-}" ]]; then
    return 0
  fi
  SIMICHAT_RELEASE_PUBSPEC_TMP="$(mktemp -d /tmp/simichat-release-pubspec.XXXXXX)"
  cp pubspec.yaml "$SIMICHAT_RELEASE_PUBSPEC_TMP/pubspec.yaml.bak"
  cp pubspec.lock "$SIMICHAT_RELEASE_PUBSPEC_TMP/pubspec.lock.bak"

  python3 - "$remove_integration_test" <<'PY'
from pathlib import Path
import sys

remove_integration_test = sys.argv[1] == '1'
p = Path('pubspec.yaml')
s = p.read_text()

if remove_integration_test:
    block = '  integration_test:\n    sdk: flutter\n'
    if block in s:
        s = s.replace(block, '')
    else:
        raise SystemExit('integration_test dev_dependency block not found')

if '\nhooks:' in s or s.startswith('hooks:'):
    if 'sqlite3:' not in s or 'source: system' not in s:
        raise SystemExit(
            'pubspec.yaml already has hooks; refusing to merge temporary sqlite3 hook'
        )
else:
    s = (
        s.rstrip()
        + "\n\nhooks:\n  user_defines:\n    sqlite3:\n      source: system\n"
    )

p.write_text(s)
PY

  if [[ "$remove_integration_test" == '1' ]]; then
    # Flutter keeps this ignored generated file across pub-spec changes. Force
    # the next Android build to regenerate it without integration_test.
    rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
  fi

  "${FLUTTER_BIN:-flutter}" --no-version-check pub get
}

simichat_release_pubspec_restore() {
  if [[ -z "${SIMICHAT_RELEASE_PUBSPEC_TMP:-}" ]]; then
    return 0
  fi
  cp "$SIMICHAT_RELEASE_PUBSPEC_TMP/pubspec.yaml.bak" pubspec.yaml
  cp "$SIMICHAT_RELEASE_PUBSPEC_TMP/pubspec.lock.bak" pubspec.lock
  "${FLUTTER_BIN:-flutter}" --no-version-check pub get \
    >/tmp/simichat-release-pubspec-restore.log 2>&1 \
    || cat /tmp/simichat-release-pubspec-restore.log >&2
  rm -rf "$SIMICHAT_RELEASE_PUBSPEC_TMP"
  SIMICHAT_RELEASE_PUBSPEC_TMP=""
}
