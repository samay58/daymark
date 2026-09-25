#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh

# Library tests, then the CLI tests from the prebuilt bundle. The CLI tests launch the
# daymark binary as a subprocess, so it must be built last to win the Daymark/daymark
# case-insensitive name collision.
swift test "${SWIFT_BUILD_FLAGS[@]}" --skip CommandTests
swift build "${SWIFT_BUILD_FLAGS[@]}" --build-tests
swift build "${SWIFT_BUILD_FLAGS[@]}" --product daymark
xcrun xctest "$(swift build "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)/DaymarkPackageTests.xctest"
