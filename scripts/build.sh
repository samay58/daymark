#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh

swift build "${SWIFT_BUILD_FLAGS[@]}"
