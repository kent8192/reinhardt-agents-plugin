#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/hooks/scripts/inject-context.sh"
TEST_ROOT="$(mktemp -d)"
STATE_ROOT="$TEST_ROOT/state"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected output to contain: $2" ;;
  esac
}

assert_empty() {
  [ -z "$1" ] || fail "expected empty output, got: $1"
}

make_app() {
  local name="$1"
  local manifest="$2"
  local dir="$TEST_ROOT/$name"
  mkdir -p "$dir/src/bin" "$dir/src/apps"
  printf '%s\n' "$manifest" > "$dir/Cargo.toml"
  : > "$dir/src/bin/manage.rs"
  printf '%s\n' "$dir"
}

run_hook() {
  local dir="$1"
  local mode="$2"
  local payload="${3-}"
  if [ -z "$payload" ]; then
    payload='{"session_id":"test-session","source":"startup"}'
  fi
  (cd "$dir" && PLUGIN_DATA="$STATE_ROOT" "$HOOK" "$mode" <<<"$payload")
}

direct="$(make_app direct $'[package]\nname = "direct"\nversion = "0.1.0"\n[dependencies]\nreinhardt = { package = "reinhardt-web", version = "0.4.0", default-features = false, features = ["db-sqlite", "auth-session"] }')"
output="$(run_hook "$direct" session-start)"
assert_contains "$output" ':kind "baseline"'
assert_contains "$output" ':reinhardt-version "0.4.0"'
assert_contains "$output" ':default-features false'
assert_contains "$output" ':features "auth-session, db-sqlite"'
assert_contains "$output" ':db-backend "sqlite"'
assert_contains "$output" ':auth-method "session"'

generic="$(make_app generic $'[package]\nname = "generic"\nversion = "0.1.0"\n[dependencies]\nserde = "1"\n# reinhardt is mentioned only in a comment')"
assert_empty "$(run_hook "$generic" session-start)"

component="$(make_app component $'[package]\nname = "component"\nversion = "0.1.0"\n[dependencies]\nreinhardt-core = "0.4"')"
assert_empty "$(run_hook "$component" session-start)"

rm "$direct/src/bin/manage.rs"
assert_empty "$(run_hook "$direct" session-start)"

plain="$(make_app plain $'[dependencies]\nreinhardt = "0.4.2"')"
assert_contains "$(run_hook "$plain" session-start)" ':reinhardt-version "0.4.2"'

renamed="$(make_app renamed $'[dependencies]\nframework = { package = "reinhardt-web", version = "0.4.3" }')"
assert_contains "$(run_hook "$renamed" session-start)" ':reinhardt-version "0.4.3"'

path_dep="$(make_app path $'[dependencies.reinhardt]\npackage = "reinhardt-web"\npath = "../reinhardt"\nfeatures = ["db-postgres"]')"
output="$(run_hook "$path_dep" session-start)"
assert_contains "$output" ':reinhardt-version "path"'
assert_contains "$output" ':db-backend "postgres"'

target="$(make_app target $'[target.\'cfg(not(target_arch = "wasm32"))\'.dependencies]\nreinhardt = { package = "reinhardt-web", git = "https://example.invalid/reinhardt", features = [\n  "pages",\n  "auth-session",\n] }')"
output="$(run_hook "$target" session-start)"
assert_contains "$output" ':reinhardt-version "git"'
assert_contains "$output" ':features "auth-session, pages"'

workspace_root="$TEST_ROOT/workspace"
member="$workspace_root/member"
mkdir -p "$member/src/bin" "$member/src/apps" "$workspace_root/sibling/src/bin"
: > "$member/src/bin/manage.rs"
printf '%s\n' $'[workspace]\nmembers = ["member"]\n\n[workspace.dependencies]\nframework = { package = "reinhardt-web", version = "0.4.1", default-features = false, features = ["auth-jwt"] }' > "$workspace_root/Cargo.toml"
printf '%s\n' $'[dependencies]\nframework = { workspace = true, features = ["db-sqlite"] }' > "$member/Cargo.toml"
printf '%s\n' $'[dependencies]\nreinhardt = "0.4.8"' > "$workspace_root/sibling/Cargo.toml"
output="$(run_hook "$member" session-start)"
assert_contains "$output" ':reinhardt-version "0.4.1"'
assert_contains "$output" ':default-features false'
assert_contains "$output" ':features "auth-jwt, db-sqlite"'

mkdir -p "$TEST_ROOT/src/bin"
: > "$TEST_ROOT/src/bin/manage.rs"
printf '%s\n' $'[workspace]\n\n[workspace.dependencies]\nreinhardt = "9.9.9"' > "$TEST_ROOT/Cargo.toml"
output="$(run_hook "$member" session-start)"
assert_contains "$output" ':reinhardt-version "0.4.1"'

dev="$(make_app dev $'[dev-dependencies]\nreinhardt = "0.4"')"
assert_empty "$(run_hook "$dev" session-start)"

build="$(make_app build $'[build-dependencies]\nreinhardt = "0.4"')"
assert_empty "$(run_hook "$build" session-start)"

virtual="$TEST_ROOT/virtual"
mkdir -p "$virtual/src/bin" "$virtual/src/apps"
: > "$virtual/src/bin/manage.rs"
printf '%s\n' $'[workspace]\nmembers = []\n\n[workspace.dependencies]\nreinhardt = "0.4"' > "$virtual/Cargo.toml"
assert_empty "$(run_hook "$virtual" session-start)"

metadata="$(make_app metadata $'[package.metadata]\nframework = "reinhardt-web"')"
assert_empty "$(run_hook "$metadata" session-start)"

assert_contains "$(run_hook "$plain" subagent-start)" ':kind "baseline"'
assert_empty "$(run_hook "$plain" unknown-mode)"

printf 'PASS\n'
