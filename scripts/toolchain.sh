# Sourced by the other scripts. CommandLineTools cannot compile Package.swift on this
# machine, and the default swiftbuild backend fails on this package (see CLAUDE.md).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SWIFT_BUILD_FLAGS=(--build-system native)
