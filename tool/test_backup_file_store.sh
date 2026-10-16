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
  swift/App/BackupFileStore.swift test/native/BackupFileStoreTests.swift \
  -o "$evidence/backup-file-store-tests"
"$evidence/backup-file-store-tests"
