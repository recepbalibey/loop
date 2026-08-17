#!/bin/bash
# Runs the LoopKit test suite. `swift test` needs extra framework/library paths on
# this machine because only Command Line Tools are installed (no full Xcode) —
# Testing.framework and its runtime helper dylib live under CommandLineTools
# rather than the usual Xcode toolchain location.
set -euo pipefail
cd "$(dirname "$0")"

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
LIBS="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

DYLD_FRAMEWORK_PATH="$FRAMEWORKS" \
DYLD_LIBRARY_PATH="$LIBS" \
swift test \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$LIBS" \
  "$@"
