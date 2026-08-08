#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Keep the large nodejs-mobile checkout outside this repository.  Building in
# a copy prevents Android's previous out/Release artifacts or an interrupted
# iOS build from changing the source tree used for another target.
SOURCE_ROOT="${SIMICHAT_NODE_MOBILE_SOURCE:-}"
if [[ -z "$SOURCE_ROOT" || ! -x "$SOURCE_ROOT/tools/ios_framework_prepare.sh" ]]; then
  echo "SIMICHAT_NODE_MOBILE_SOURCE must point to a nodejs-mobile checkout with tools/ios_framework_prepare.sh" >&2
  exit 2
fi

BUILD_ROOT="${SIMICHAT_NODE_MOBILE_BUILD_ROOT:-$PWD/.cache/node-mobile-ios-build}"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
rsync -a --exclude 'out' --exclude 'out_ios*' --exclude '.git' "$SOURCE_ROOT/" "$BUILD_ROOT/"

# nodejs-mobile 18.20.4 contains a host-only macOS shared-memory block in
# V8's POSIX platform file. Newer Xcode SDKs intentionally make mach_vm.h
# unavailable to iOS targets, where V8 already provides the file-descriptor
# implementation. Keep this compatibility patch in the isolated build copy;
# never mutate the source checkout.
python3 - "$BUILD_ROOT/deps/v8/src/base/platform/platform-posix.cc" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
include_marker = '#include <mach/mach_vm.h>'
include_patch = '#if !V8_OS_IOS\n#include <mach/mach_vm.h>\n#endif'
if include_patch not in source:
    if include_marker not in source:
        raise SystemExit('nodejs-mobile V8 source no longer contains the expected mach_vm include')
    source = source.replace(include_marker, include_patch, 1)

host_block_marker = '#if defined(__APPLE__)\n// android-configure uses the Android target source list'
host_block_patch = '#if defined(__APPLE__) && !V8_OS_IOS\n// android-configure uses the Android target source list'
if host_block_patch not in source:
    if host_block_marker not in source:
        raise SystemExit('nodejs-mobile V8 source no longer contains the expected host-only shared-memory block')
    source = source.replace(host_block_marker, host_block_patch, 1)

# The nodejs-mobile source carries an Apple shared-memory implementation in
# platform-posix.cc for the Android host-tool build.  iOS also links
# platform-darwin.cc, which owns Stack::GetStackStart(); without this narrow
# guard both the host mksnapshot and the iOS target archive contain the same
# symbol.  Keep the shared-memory functions above, but leave the stack entry
# point to platform-darwin.cc for every iOS-targeted build (including the host
# tools whose V8 target is iOS).
stack_marker = '''Stack::StackSlot Stack::GetStackStart() {
  return pthread_get_stackaddr_np(pthread_self());
}'''
stack_patch = '''#if !defined(V8_TARGET_OS_IOS)
Stack::StackSlot Stack::GetStackStart() {
  return pthread_get_stackaddr_np(pthread_self());
}
#endif'''
if stack_patch not in source:
    if stack_marker not in source:
        raise SystemExit('nodejs-mobile V8 source no longer contains the expected Apple stack implementation')
    source = source.replace(stack_marker, stack_patch, 1)
path.write_text(source)
PY

# On Apple Silicon, invoking configure through Rosetta does not always change
# GYP's inferred host_arch.  The x86_64 simulator build then accidentally
# compiles the host V8 tools with arm64-only inline assembly.  Pin the host
# compiler architecture in the isolated copy; the target remains x86_64 and
# the source checkout is untouched.
python3 - "$BUILD_ROOT/tools/ios_framework_prepare.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = 'GYP_DEFINES="target_arch=x64 host_os=mac target_os=ios"'
new = 'GYP_DEFINES="target_arch=x64 host_arch=x64 host_os=mac target_os=ios"'
if new not in source:
    if old not in source:
        raise SystemExit('nodejs-mobile iOS script no longer contains the expected x64 GYP_DEFINES line')
    source = source.replace(old, new, 1)
old = '  arch -x86_64 ./configure ' + chr(92) + chr(10)
new = '  CC_host="clang -target x86_64-apple-macos10.10" CXX_host="clang++ -target x86_64-apple-macos10.10" arch -x86_64 ./configure ' + chr(92) + chr(10)
if new not in source:
    if old not in source:
        raise SystemExit('nodejs-mobile iOS script no longer contains the expected x64 Rosetta configure line')
    source = source.replace(old, new, 1)
path.write_text(source)
PY

# The old GYP file can add the arm64 host assembly while configuring the
# x86_64 simulator on Apple Silicon.  Keep the arm64 target condition intact,
# but prevent that source from entering the host toolset of an x86_64 build.
python3 - "$BUILD_ROOT/tools/v8_gypfiles/v8.gyp" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = "'_toolset == \"host\" and host_arch == \"arm64\" or _toolset == \"target\" and target_arch==\"arm64\"'"
new = "'_toolset == \"host\" and host_arch == \"arm64\" and target_arch!=\"x64\" or _toolset == \"target\" and target_arch==\"arm64\"'"
if new not in source:
    if old not in source:
        raise SystemExit('nodejs-mobile V8 GYP no longer contains the expected arm64 heap assembly condition')
    source = source.replace(old, new, 1)

old = "'_toolset == \"host\" and host_arch == \"x64\" or _toolset == \"target\" and target_arch==\"x64\"'"
new = "'_toolset == \"host\" and target_arch==\"x64\" or _toolset == \"target\" and target_arch==\"x64\"'"
if new not in source:
    if old not in source:
        raise SystemExit('nodejs-mobile V8 GYP no longer contains the expected x64 heap assembly condition')
    source = source.replace(old, new, 1)
path.write_text(source)
PY

pushd "$BUILD_ROOT" >/dev/null
./tools/ios_framework_prepare.sh
popd >/dev/null

TARGET="ios/Runner/NodeRuntime"
mkdir -p "$TARGET"
rm -rf "$TARGET/NodeMobile.xcframework"
cp -R "$BUILD_ROOT/out_ios/NodeMobile.xcframework" "$TARGET/NodeMobile.xcframework"

test -f "$TARGET/NodeMobile.xcframework/Info.plist"
find "$TARGET/NodeMobile.xcframework" -type f -name NodeMobile -print -exec file {} \;
echo "SIMICHAT_IOS_NODEMOBILE_XCFRAMEWORK_READY"
