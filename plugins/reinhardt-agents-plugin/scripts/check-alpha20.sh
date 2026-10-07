#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  CHECK_TARGET="$(mktemp -d "${TMPDIR:-/tmp}/reinhardt-plugin-alpha20-target.XXXXXX")"
  trap 'rm -rf "$CHECK_TARGET"' EXIT
  export CARGO_TARGET_DIR="$CHECK_TARGET"
fi
export CARGO_BUILD_BUILD_DIR="${CARGO_BUILD_BUILD_DIR:-$CARGO_TARGET_DIR/build}"
export CARGO_PROFILE_DEV_DEBUG=0
python3 "$ROOT/scripts/generate-alpha20-examples.py" --check
cargo fmt --manifest-path "$ROOT/compatibility/alpha20/Cargo.toml" --check
cargo test --manifest-path "$ROOT/compatibility/alpha20/Cargo.toml" --lib --locked
cargo check --manifest-path "$ROOT/compatibility/alpha20/Cargo.toml" --target wasm32-unknown-unknown --lib --locked
