#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
platform=$(xcrun --sdk macosx --show-sdk-platform-path)
evidence=../references/onexray-tests/native
mkdir -p "$evidence"
evidence=$(cd "$evidence" && pwd)
xcrun swiftc \
  -F "$platform/Developer/Library/Frameworks" \
  -I "$platform/Developer/usr/lib" \
  -L "$platform/Developer/usr/lib" \
  -Xlinker -rpath -Xlinker "$platform/Developer/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$platform/Developer/usr/lib" \
  swift/macOS/ProxyHelper/ProxyHelperProtocol.swift test/native/ProxyHelperProtocolTests.swift \
  -o "$evidence/desktop-proxy-helper-tests"
"$evidence/desktop-proxy-helper-tests"

# The following tests use loopback only and never start a VPN/Network Extension.
library=swift/All/LibXray.xcframework/macos-arm64_x86_64
xcrun swiftc -swift-version 6 \
  -I "$library/Headers" -L "$library" -lXray -lresolv \
  swift/macOS/ProxyHelper/ProxyHelperProtocol.swift swift/macOS/ProxyHelper/ProxyHelperMain.swift \
  -o "$evidence/OneXrayProxyHelper"
xcrun swiftc \
  -F "$platform/Developer/Library/Frameworks" \
  -I "$platform/Developer/usr/lib" \
  -L "$platform/Developer/usr/lib" \
  -Xlinker -rpath -Xlinker "$platform/Developer/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$platform/Developer/usr/lib" \
  swift/macOS/ProxyHelper/ProxyHelperProtocol.swift swift/macOS/ProxyHelper/ProxyHelperProcess.swift \
  test/native/ProxyHelperProcessTests.swift test/native/DesktopProxyTerminationTests.swift \
  -o "$evidence/desktop-proxy-process-tests"
"$evidence/desktop-proxy-process-tests" "$evidence/OneXrayProxyHelper"
