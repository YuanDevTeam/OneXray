#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
platform=$(xcrun --sdk macosx --show-sdk-platform-path)
evidence=../references/onexray-tests/native
mkdir -p "$evidence"
xcrun swiftc \
  -F "$platform/Developer/Library/Frameworks" \
  -I "$platform/Developer/usr/lib" \
  -L "$platform/Developer/usr/lib" \
  -Xlinker -rpath -Xlinker "$platform/Developer/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$platform/Developer/usr/lib" \
  swift/All/RuntimeEnv.swift test/native/RuntimeEnvTests.swift \
  -o "$evidence/runtime-env-tests"
"$evidence/runtime-env-tests"
