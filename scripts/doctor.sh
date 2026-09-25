#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh

swift run "${SWIFT_BUILD_FLAGS[@]}" daymark doctor "$@"
