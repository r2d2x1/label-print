#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export MACOSX_DEPLOYMENT_TARGET=14.0
export CARGO_HOME="$PWD/.cache/cargo"
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
cargo build --manifest-path backend/Cargo.toml --release --locked
swift build --disable-sandbox --cache-path "$PWD/.cache/swift" "$@"
