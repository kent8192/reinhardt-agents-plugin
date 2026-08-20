#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/hooks/scripts/inject-context.sh"
PY_HOOK="$ROOT/hooks/scripts/inject_context.py"
PYTHON_BIN="$(python3 -c 'import sys; print(sys.executable)')"
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

assert_hook_mapping() {
  local event="$1" matcher="$2" command="$3"
  if awk -v wanted_event="$event" -v wanted_matcher="$matcher" -v wanted_command="$command" '
    function string_value(line, after_colon, i,c,escaped,out) {
      i=1
      if (after_colon) i=index(line, ":") + 1
      while (i <= length(line) && substr(line,i,1) != "\"") i++
      if (i > length(line)) return ""
      escaped=0; out=""
      for (i=i+1; i<=length(line); i++) {
        c=substr(line,i,1)
        if (escaped) {
          if (c=="n") out=out "\n"
          else if (c=="r") out=out "\r"
          else if (c=="t") out=out "\t"
          else out=out c
          escaped=0
        } else if (c=="\\") escaped=1
        else if (c=="\"") return out
        else out=out c
      }
      return ""
    }
    /^    "[^"]+": \[$/ { current_event=string_value($0, 0); current_matcher=""; next }
    /^        "matcher": / { current_matcher=string_value($0, 1); next }
    /^            "command": / {
      current_command=string_value($0, 1)
      if (current_event==wanted_event && current_matcher==wanted_matcher && current_command==wanted_command) found=1
    }
    END { exit !found }
  ' "$ROOT/hooks/hooks.json"; then
    return 0
  fi
  fail "missing $event hook mapping: $command"
}

decode_context() {
  local json="$1" event="$2"
  local prefix="{\"hookSpecificOutput\":{\"hookEventName\":\"$event\",\"additionalContext\":\""
  local suffix='"}}'
  case "$json" in "$prefix"*"$suffix") ;; *) return 1 ;; esac
  json="${json#"$prefix"}"
  json="${json%"$suffix"}"
  printf '%s' "$json" | awk '
    { input=input $0 }
    END {
      for (i=1; i<=length(input); i++) {
        c=substr(input,i,1)
        if (c!="\\") { if (c=="\"") exit 1; output=output c; continue }
        i++; c=substr(input,i,1)
        if (c=="n") output=output "\n"
        else if (c=="r") output=output "\r"
        else if (c=="t") output=output "\t"
        else if (c=="\\" || c=="\"") output=output c
        else exit 1
      }
      printf "%s", output
    }
  '
}

decode_tool_context() {
  decode_context "$1" PostToolUse
}

directory_mode() {
  local directory="$1" stat_command="${2:-stat}" mode
  if mode="$("$stat_command" -f '%Lp' "$directory" 2>/dev/null)"; then
    printf '%s\n' "$mode"
  else
    "$stat_command" -c '%a' "$directory" 2>/dev/null
  fi
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

run_hook_with_system_bash() {
  local dir="$1" mode="$2" payload="$3"
  (cd "$dir" && PLUGIN_DATA="$STATE_ROOT" /bin/bash "$HOOK" "$mode" <<<"$payload")
}

regression_categoryless_app() {
  local app error_file output
  app="$(make_app final-categoryless $'[dependencies]\nreinhardt = "0.4.0"')"
  mkdir -p "$app/src/apps/empty"
  error_file="$TEST_ROOT/final-categoryless.err"
  output="$(run_hook_with_system_bash "$app" prompt '{"session_id":"final-categoryless","prompt":"empty"}' 2>"$error_file")"
  [ ! -s "$error_file" ] || fail "categoryless app wrote stderr: $(<"$error_file")"
  assert_contains "$output" ':app "empty"'
  assert_contains "$output" ':categories ""'
}

assert_bounded_version() {
  local app="$1" expected="$2" output line value
  output="$(run_hook "$app" session-start '{"session_id":"bounded-version","source":"startup"}')"
  line="$(printf '%s\n' "$output" | awk '/^  :reinhardt-version /')"
  value="${line#*\"}"
  value="${value%\"}"
  [ "$(printf '%s' "$value" | LC_ALL=C wc -c | tr -d '[:space:]')" -le 128 ] || fail 'version scalar exceeded 128 bytes'
  [ "$value" = "$expected" ] || fail "unexpected bounded version: $value"
}

regression_bounded_text_boundaries() {
  local version_prefix app_prefix manifest app name output
  version_prefix="$(awk 'BEGIN { for (i=0; i<124; i++) printf "v" }')"

  manifest="$(printf '[dependencies]\nreinhardt = { version = "%s界tail" }\n' "$version_prefix")"
  app="$(make_app final-version-utf8 "$manifest")"
  assert_bounded_version "$app" "$version_prefix..."

  manifest="$(printf '[dependencies]\nreinhardt = { version = "%s\\\"tail" }\n' "$version_prefix")"
  app="$(make_app final-version-quote "$manifest")"
  assert_bounded_version "$app" "$version_prefix..."

  manifest="$(printf '[dependencies]\nreinhardt = { version = "%s\\\\tail" }\n' "$version_prefix")"
  app="$(make_app final-version-backslash "$manifest")"
  assert_bounded_version "$app" "$version_prefix..."

  app="$(make_app final-app-utf8 $'[dependencies]\nreinhardt = "0.4.0"')"
  app_prefix="$(awk 'BEGIN { for (i=0; i<92; i++) printf "a" }')"
  name="${app_prefix}界tail"
  mkdir -p "$app/src/apps/$name/models"
  output="$(run_hook "$app" prompt "{\"session_id\":\"bounded-app\",\"prompt\":\"src/apps/$name/models\"}")"
  assert_contains "$output" ":app \"$app_prefix...\""
}

regression_tool_path_boundaries() {
  local app invalid invalid_payload valid valid_payload absolute_payload session
  app="$(make_app final-tool-boundaries $'[dependencies]\nreinhardt = "0.4.0"')"
  mkdir -p "$app/src/apps/users/models"

  assert_contains "$(run_hook "$app" tool '{"session_id":"command-delimiter","tool_input":{"command":"cat src/apps/users/models.rs"},"tool_response":{"exit_code":0}}')" ':app \"users\"'
  assert_contains "$(run_hook "$app" tool '{"session_id":"json-delimiter","path":"src/apps/users","tool_response":{"exit_code":0}}')" ':app \"users\"'

  for session in nested absolute fused; do
    case "$session" in
      nested) invalid='vendor/src/apps/users/models.rs' ;;
      absolute) invalid='/tmp/src/apps/users/models.rs' ;;
      fused) invalid='foosrc/apps/users/models.rs' ;;
    esac
    invalid_payload="$(printf '{"session_id":"boundary-%s","path":"%s","tool_response":{"exit_code":0}}' "$session" "$invalid")"
    assert_empty "$(run_hook "$app" tool "$invalid_payload")"
    valid_payload="$(printf '{"session_id":"boundary-%s","path":"src/apps/users/models.rs","tool_response":{"exit_code":0}}' "$session")"
    valid="$(run_hook "$app" tool "$valid_payload")"
    assert_contains "$valid" ':app \"users\"'
  done

  absolute_payload="$(printf '{"session_id":"boundary-absolute-inside","path":"%s/src/apps/users/models.rs","tool_response":{"exit_code":0}}' "$app")"
  assert_contains "$(run_hook "$app" tool "$absolute_payload")" ':app \"users\"'
  assert_contains "$(run_hook "$app" tool '{"session_id":"boundary-dot-relative","path":"./src/apps/users/models.rs","tool_response":{"exit_code":0}}')" ':app \"users\"'
}

regression_workspace_default_features() {
  local workspace member output

  workspace="$TEST_ROOT/final-workspace-false"
  member="$workspace/member"
  mkdir -p "$member/src/bin" "$member/src/apps"
  : > "$member/src/bin/manage.rs"
  printf '%s\n' $'[workspace]\nmembers = ["member"]\n[workspace.dependencies]\nframework = { package = "reinhardt-web", version = "0.4.0", default-features = false }' > "$workspace/Cargo.toml"
  printf '%s\n' $'[dependencies]\nframework = { workspace = true, default-features = true }' > "$member/Cargo.toml"
  output="$(run_hook "$member" session-start)"
  assert_contains "$output" ':default-features true'

  workspace="$TEST_ROOT/final-workspace-true"
  member="$workspace/member"
  mkdir -p "$member/src/bin" "$member/src/apps"
  : > "$member/src/bin/manage.rs"
  printf '%s\n' $'[workspace]\nmembers = ["member"]\n[workspace.dependencies]\nframework = { package = "reinhardt-web", version = "0.4.0", default-features = true }' > "$workspace/Cargo.toml"
  printf '%s\n' $'[dependencies]\nframework = { workspace = true, default-features = false }' > "$member/Cargo.toml"
  output="$(run_hook "$member" session-start)"
  assert_contains "$output" ':default-features true'

  workspace="$TEST_ROOT/final-workspace-omitted"
  member="$workspace/member"
  mkdir -p "$member/src/bin" "$member/src/apps"
  : > "$member/src/bin/manage.rs"
  printf '%s\n' $'[workspace]\nmembers = ["member"]\n[workspace.dependencies]\nframework = { package = "reinhardt-web", version = "0.4.0" }' > "$workspace/Cargo.toml"
  printf '%s\n' $'[dependencies]\nframework = { workspace = true, default-features = false }' > "$member/Cargo.toml"
  output="$(run_hook "$member" session-start)"
  assert_contains "$output" ':default-features true'
  assert_contains "$output" ':db-backend "postgres"'

  workspace="$TEST_ROOT/final-workspace-root"
  mkdir -p "$workspace/src/bin" "$workspace/src/apps"
  : > "$workspace/src/bin/manage.rs"
  printf '%s\n' \
    '[workspace]' \
    'members = []' \
    '[workspace.dependencies]' \
    'framework = { package = "reinhardt-web", version = "0.4.1" }' \
    '[dependencies]' \
    'framework = { workspace = true }' > "$workspace/Cargo.toml"
  output="$(run_hook "$workspace" session-start)"
  assert_contains "$output" ':reinhardt-version "0.4.1"'
}

regression_explicit_workspace_root() {
  local workspace member output

  workspace="$TEST_ROOT/final-explicit-workspace"
  member="$TEST_ROOT/final-explicit-member"
  mkdir -p "$workspace" "$member/src/bin" "$member/src/apps"
  : > "$member/src/bin/manage.rs"
  printf '%s\n' $'[workspace]\n[workspace.dependencies]\nframework = { package = "reinhardt-web", version = "0.4.0", default-features = false, features = ["auth-jwt"] }' > "$workspace/Cargo.toml"
  printf '%s\n' $'[package]\nname = "final-explicit-member"\nversion = "0.1.0"\nworkspace = "../final-explicit-workspace"\n[dependencies]\nframework = { workspace = true, features = ["db-sqlite"] }' > "$member/Cargo.toml"
  output="$(run_hook "$member" session-start)"
  assert_contains "$output" ':reinhardt-version "0.4.0"'
  assert_contains "$output" ':features "auth, auth-jwt, database, db-sqlite"'
  assert_contains "$output" ':db-backend "sqlite"'
}

regression_no_per_app_basename() {
  local app fake_bin output
  app="$(make_app final-no-basename $'[dependencies]\nreinhardt = "0.4.0"')"
  mkdir -p "$app/src/apps/users/models"
  fake_bin="$TEST_ROOT/final-no-basename-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/bin/sh' 'exit 99' > "$fake_bin/basename"
  chmod +x "$fake_bin/basename"
  output="$(cd "$app" && PATH="$fake_bin:$PATH" PLUGIN_DATA="$STATE_ROOT" "$PYTHON_BIN" "$PY_HOOK" prompt <<< '{"session_id":"no-basename","prompt":"users"}')"
  assert_contains "$output" ':app "users"'
}

regression_prompt_value_only() {
  local app output
  app="$(make_app final-prompt-value $'[dependencies]\nreinhardt = "0.4.0"')"
  mkdir -p "$app/src/apps/prompt" "$app/src/apps/session_id"
  assert_empty "$(run_hook "$app" prompt '{"session_id":"abc","prompt":"do unrelated work"}')"
  output="$(run_hook "$app" prompt '{"session_id":"abc","prompt":"open prompt"}')"
  assert_contains "$output" ':app "prompt"'
  output="$(run_hook "$app" prompt '{"session_id":"escaped-prompt","prompt":"inspect\n \u0070rompt"}')"
  assert_contains "$output" ':app "prompt"'
}

regression_unicode_prompt_boundaries() {
  local app output
  app="$(make_app final-unicode-prompt $'[dependencies]\nreinhardt = "0.4.0"')"
  mkdir -p "$app/src/apps/β"
  assert_empty "$(run_hook "$app" prompt '{"session_id":"unicode-boundary","prompt":"αβγ"}')"
  output="$(run_hook "$app" prompt '{"session_id":"unicode-exact","prompt":"inspect β"}')"
  assert_contains "$output" ':app "β"'
}

regression_default_feature_preset() {
  local app explicit output
  app="$(make_app final-default-preset $'[dependencies]\nreinhardt = "0.4.0"')"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':default-features true'
  assert_contains "$output" 'standard'
  assert_contains "$output" 'database'
  assert_contains "$output" 'db-postgres'
  assert_contains "$output" ':db-backend "postgres"'
  assert_contains "$output" ':auth-method "auth (default)"'

  explicit="$(make_app final-explicit-preset $'[dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["standard"] }')"
  output="$(run_hook "$explicit" session-start)"
  assert_contains "$output" ':default-features false'
  assert_contains "$output" ':db-backend "postgres"'
  assert_contains "$output" ':auth-method "auth (default)"'
}

regression_explicit_default_feature() {
  local app output
  app="$(make_app final-explicit-default-feature $'[dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["default"] }')"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':db-backend "postgres"'
  assert_contains "$output" ':auth-method "auth (default)"'
}

regression_forwarded_default_feature() {
  local app output
  app="$(make_app final-forwarded-default-feature $'[features]\ndefault = ["framework/default"]\n[dependencies]\nframework = { package = "reinhardt-web", version = "0.4.0", default-features = false }')"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':db-backend "postgres"'
  assert_contains "$output" ':auth-method "auth (default)"'
}

regression_effective_facade_package() {
  local direct mismatch output
  direct="$(make_app final-direct-web-key $'[dependencies]\nreinhardt-web = "0.4.0"')"
  assert_contains "$(run_hook "$direct" session-start)" ':reinhardt-version "0.4.0"'

  mismatch="$(make_app final-mismatched-package $'[dependencies]\nreinhardt = { package = "some-other-crate", version = "0.4.0" }')"
  output="$(run_hook "$mismatch" session-start)"
  assert_empty "$output"
}

trace_match_processes() {
  local app="$1" trace_bin="$2" label="$3" awk_trace tr_trace real_awk real_tr
  awk_trace="$TEST_ROOT/$label.awk"
  tr_trace="$TEST_ROOT/$label.tr"
  real_awk="$(command -v awk)"
  real_tr="$(command -v tr)"
  : > "$awk_trace"
  : > "$tr_trace"
  (cd "$app" && \
    PATH="$trace_bin:$PATH" \
    TRACE_AWK="$awk_trace" TRACE_TR="$tr_trace" \
    REAL_AWK="$real_awk" REAL_TR="$real_tr" \
    PLUGIN_DATA="$STATE_ROOT" /bin/bash "$HOOK" prompt \
    <<< "{\"session_id\":\"$label\",\"prompt\":\"no-match-here\"}") >/dev/null
  printf '%s %s\n' \
    "$(wc -l < "$awk_trace" | tr -d '[:space:]')" \
    "$(wc -l < "$tr_trace" | tr -d '[:space:]')"
}

regression_one_pass_matching() {
  local one many trace_bin one_awk one_tr many_awk many_tr index
  one="$(make_app final-one-app $'[dependencies]\nreinhardt = "0.4.0"')"
  many="$(make_app final-many-apps $'[dependencies]\nreinhardt = "0.4.0"')"
  mkdir -p "$one/src/apps/app-01"
  for index in $(awk 'BEGIN { for (i=1; i<=40; i++) printf "%02d\n", i }'); do
    mkdir -p "$many/src/apps/app-$index"
  done

  trace_bin="$TEST_ROOT/final-process-trace-bin"
  mkdir -p "$trace_bin"
  printf '%s\n' '#!/bin/sh' 'printf "x\n" >> "$TRACE_AWK"' 'exec "$REAL_AWK" "$@"' > "$trace_bin/awk"
  printf '%s\n' '#!/bin/sh' 'printf "x\n" >> "$TRACE_TR"' 'exec "$REAL_TR" "$@"' > "$trace_bin/tr"
  chmod +x "$trace_bin/awk" "$trace_bin/tr"

  read -r one_awk one_tr <<< "$(trace_match_processes "$one" "$trace_bin" final-process-one)"
  read -r many_awk many_tr <<< "$(trace_match_processes "$many" "$trace_bin" final-process-many)"
  [ "$many_awk" -le $((one_awk + 1)) ] || fail "app-scaled awk processes: $one_awk -> $many_awk"
  [ "$many_tr" -le $((one_tr + 1)) ] || fail "app-scaled tr processes: $one_tr -> $many_tr"
}

regression_unbalanced_manifest() {
  local app
  app="$(make_app final-unbalanced $'[dependencies]\nreinhardt = { version = "0.4.0"')"
  assert_empty "$(run_hook "$app" session-start)"
}

regression_top_level_json_fields() {
  local app output
  app="$(make_app final-json-fields $'[dependencies]\nreinhardt = "0.4.0"')"
  mkdir -p "$app/src/apps/users/models"

  run_hook "$app" prompt '{"session_id":"outer-session","nested":{"session_id":"nested-session"},"session_id":"duplicate-session","prompt":"users"}' >/dev/null
  assert_empty "$(run_hook "$app" prompt '{"session_id":"outer-session","prompt":"users"}')"

  run_hook "$app" prompt '{"session_id":"source-session","prompt":"users"}' >/dev/null
  run_hook "$app" session-start '{"session_id":"source-session","source":"resume","nested":{"source":"clear"},"source":"clear"}' >/dev/null
  assert_empty "$(run_hook "$app" prompt '{"session_id":"source-session","prompt":"users"}')"

  output="$(run_hook "$app" tool '{"session_id":"exit-session","path":"src/apps/users/models.rs","tool_response":{"exit_code":1,"nested":{"exit_code":0},"exit_code":0}}')"
  assert_empty "$output"
}

regression_all_presets_expand() {
  local app output
  app="$(make_app final-graphql-preset $'[dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["graphql-server"] }')"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" 'database'
  assert_contains "$output" ':auth-method "auth (default)"'
}

regression_feature_implications() {
  local app output
  app="$(make_app final-feature-implications $'[dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["api", "openapi-router", "session-redis", "tasks-durable", "middleware-auth-jwt"] }')"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" 'rest'
  assert_contains "$output" 'openapi'
  assert_contains "$output" 'sessions'
  assert_contains "$output" 'middleware'
  assert_contains "$output" 'tasks'
  assert_contains "$output" ':auth-method "jwt"'
}

regression_base_feature_implications() {
  local app output
  app="$(make_app final-base-feature-implications $'[dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite", "auth-jwt"] }')"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':features "auth, auth-jwt, database, db-sqlite"'
}

regression_forwarded_default_features() {
  local app output
  app="$(make_app final-forwarded-feature $'[features]\ndefault = ["framework/db-sqlite"]\n[dependencies]\nframework = { package = "reinhardt-web", version = "0.4.0", default-features = false }')"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" 'db-sqlite'
  assert_contains "$output" ':db-backend "sqlite"'
}

regression_active_target_only() {
  local app output
  app="$(make_app final-active-target $'[target.\'cfg(windows)\'.dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-postgres"] }\n[target.\'cfg(unix)\'.dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }')"
  output="$(run_hook "$app" session-start)"
  if rustc --print cfg | grep -qx unix; then
    assert_contains "$output" ':db-backend "sqlite"'
  else
    assert_contains "$output" ':db-backend "postgres"'
  fi
}

regression_configured_target() {
  local app output host_target
  app="$(make_app final-configured-target $'[target.\'cfg(target_arch = "wasm32")\'.dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }')"
  mkdir -p "$app/.cargo"
  printf '%s\n' $'[build]\ntarget = "wasm32-unknown-unknown"' > "$app/.cargo/config.toml"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':db-backend "sqlite"'

  app="$(make_app final-env-target $'[target.wasm32-unknown-unknown.dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }')"
  output="$(cd "$app" && CARGO_BUILD_TARGET=wasm32-unknown-unknown PLUGIN_DATA="$STATE_ROOT" "$HOOK" session-start <<< '{}')"
  assert_contains "$output" ':db-backend "sqlite"'

  host_target="$(rustc -vV | awk '/^host: / { print $2 }')"
  app="$TEST_ROOT/final-array-target"
  mkdir -p "$app/.cargo" "$app/src/bin" "$app/src/apps"
  : > "$app/src/bin/manage.rs"
  printf '%s\n' \
    '[target.wasm32-unknown-unknown.dependencies]' \
    'reinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }' \
    "[target.\"$host_target\".dependencies]" \
    'reinhardt = { version = "0.4.0", default-features = false, features = ["db-postgres"] }' > "$app/Cargo.toml"
  printf '%s\n' '[build]' "target = [\"wasm32-unknown-unknown\", \"$host_target\"]" > "$app/.cargo/config.toml"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" 'db-sqlite'
  assert_contains "$output" 'db-postgres'
}

regression_configured_rustflags() {
  local app output host_target host_arch
  app="$(make_app final-configured-rustflags $'[target.\'cfg(custom_flag)\'.dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }')"
  mkdir -p "$app/.cargo"
  printf '%s\n' $'[build]\nrustflags = ["--cfg", "custom_flag"]' > "$app/.cargo/config.toml"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':db-backend "sqlite"'

  host_target="$(rustc -vV | awk '/^host: / { print $2 }')"
  app="$(make_app final-target-rustflags $'[target.\'cfg(custom_flag)\'.dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }')"
  mkdir -p "$app/.cargo"
  printf '%s\n' "[target.\"$host_target\"]" 'rustflags = ["--cfg", "custom_flag"]' > "$app/.cargo/config"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':db-backend "sqlite"'

  host_arch="$(rustc --print cfg | sed -n 's/^target_arch="\(.*\)"$/\1/p')"
  app="$(make_app final-cfg-rustflags $'[target.\'cfg(custom_flag)\'.dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }')"
  mkdir -p "$app/.cargo"
  printf '%s\n' "[target.'cfg(target_arch = \"$host_arch\")']" 'rustflags = ["--cfg", "custom_flag"]' > "$app/.cargo/config"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':db-backend "sqlite"'

  app="$(make_app final-empty-rustflags $'[target.\'cfg(custom_flag)\'.dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }')"
  mkdir -p "$app/.cargo"
  printf '%s\n' $'[build]\nrustflags = ["--cfg", "custom_flag"]' > "$app/.cargo/config"
  output="$(cd "$app" && CARGO_ENCODED_RUSTFLAGS= PLUGIN_DATA="$STATE_ROOT" "$HOOK" session-start <<< '{}')"
  assert_empty "$output"
}

regression_config_file_precedence() {
  local app output host_target
  host_target="$(rustc -vV | awk '/^host: / { print $2 }')"
  app="$TEST_ROOT/final-config-file-precedence"
  mkdir -p "$app/.cargo" "$app/src/bin" "$app/src/apps"
  : > "$app/src/bin/manage.rs"
  printf '%s\n' \
    "[target.\"$host_target\".dependencies]" \
    'reinhardt = { version = "0.4.0", default-features = false, features = ["db-postgres"] }' \
    '[target.wasm32-unknown-unknown.dependencies]' \
    'reinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }' > "$app/Cargo.toml"
  printf '%s\n' "[build]" "target = \"$host_target\"" > "$app/.cargo/config"
  printf '%s\n' $'[build]\ntarget = "wasm32-unknown-unknown"' > "$app/.cargo/config.toml"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':db-backend "postgres"'
}

regression_config_file_selection() {
  local app output host_target
  host_target="$(rustc -vV | awk '/^host: / { print $2 }')"
  app="$TEST_ROOT/final-config-file-selection"
  mkdir -p "$app/.cargo" "$app/src/bin" "$app/src/apps"
  : > "$app/src/bin/manage.rs"
  printf '%s\n' \
    "[target.\"$host_target\".dependencies]" \
    'reinhardt = { version = "0.4.0", default-features = false, features = ["db-postgres"] }' \
    '[target.wasm32-unknown-unknown.dependencies]' \
    'reinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }' > "$app/Cargo.toml"
  printf '%s\n' '[net]' 'git-fetch-with-cli = true' > "$app/.cargo/config"
  printf '%s\n' $'[build]\ntarget = "wasm32-unknown-unknown"' > "$app/.cargo/config.toml"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':db-backend "postgres"'
}

regression_ancestor_rustflags() {
  local root app output
  root="$TEST_ROOT/final-ancestor-rustflags"
  app="$root/project/app"
  mkdir -p "$root/.cargo" "$app/.cargo" "$app/src/bin" "$app/src/apps"
  : > "$app/src/bin/manage.rs"
  printf '%s\n' $'[target.\'cfg(custom_flag)\'.dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["db-sqlite"] }' > "$app/Cargo.toml"
  printf '%s\n' $'[build]\nrustflags = ["--cfg", "custom_flag"]' > "$root/.cargo/config"
  printf '%s\n' $'[build]\nrustflags = ["--cfg", "ancestor_child_flag"]' > "$app/.cargo/config"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':db-backend "sqlite"'
}

regression_windows_tool_path() {
  local app output case_variant msys_variant
  app="$(make_app final-windows-path $'[dependencies]\nreinhardt = "0.4.0"')"
  mkdir -p "$app/src/apps/users/models"
  output="$(cd "$app" && PWD='C:/repo' PLUGIN_DATA="$STATE_ROOT" "$PYTHON_BIN" "$PY_HOOK" tool <<< '{"session_id":"windows-path","path":"C:\\repo\\src\\apps\\users\\models.rs","tool_response":{"exit_code":0}}')"
  assert_contains "$output" ':app \"users\"'
  case_variant="$(cd "$app" && PWD='C:/Repo' PLUGIN_DATA="$STATE_ROOT" "$PYTHON_BIN" "$PY_HOOK" tool <<< '{"session_id":"windows-case-variant","path":"c:\\repo\\src\\apps\\Users\\models.rs","tool_response":{"exit_code":0}}')"
  assert_contains "$case_variant" ':app \"users\"'
  msys_variant="$(cd "$app" && PWD='/c/Repo' PLUGIN_DATA="$STATE_ROOT" "$PYTHON_BIN" "$PY_HOOK" tool <<< '{"session_id":"windows-msys-variant","path":"c:\\repo\\src\\apps\\Users\\models.rs","tool_response":{"exit_code":0}}')"
  assert_contains "$msys_variant" ':app \"users\"'
}

regression_combined_dependency_defaults() {
  local app output
  app="$(make_app final-combined-defaults $'[dependencies]\nreinhardt = "0.4.0"\n[target.\'cfg(unix)\'.dependencies]\nreinhardt = { version = "0.4.0", default-features = false }')"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':default-features true'
  assert_contains "$output" ':db-backend "postgres"'
}

regression_full_preset_auth() {
  local app output
  app="$(make_app final-full-preset $'[dependencies]\nreinhardt = { version = "0.4.0", default-features = false, features = ["full"] }')"
  output="$(run_hook "$app" session-start)"
  assert_contains "$output" ':auth-method "jwt, session, oauth, token"'
}

regression_optional_dependency_activation() {
  local inactive active
  inactive="$(make_app final-optional-inactive $'[features]\ndefault = []\n[dependencies]\nreinhardt = { version = "0.4.0", optional = true, features = ["db-sqlite"] }')"
  assert_empty "$(run_hook "$inactive" session-start)"

  active="$(make_app final-optional-active $'[features]\ndefault = ["dep:reinhardt"]\n[dependencies]\nreinhardt = { version = "0.4.0", optional = true, default-features = false, features = ["db-sqlite"] }')"
  assert_contains "$(run_hook "$active" session-start)" ':db-backend "sqlite"'
}

regression_invalid_dependency_type() {
  local app
  app="$(make_app final-invalid-dependency $'[dependencies]\nreinhardt = 1')"
  assert_empty "$(run_hook "$app" session-start)"
}

regression_no_unneeded_rustc_probe() {
  local app fake_bin trace output
  app="$(make_app final-no-rustc $'[dependencies]\nreinhardt = "0.4.0"')"
  fake_bin="$TEST_ROOT/final-no-rustc-bin"
  trace="$TEST_ROOT/final-no-rustc.trace"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/bin/sh' 'printf "called\n" >> "$RUSTC_TRACE"' 'exit 99' > "$fake_bin/rustc"
  chmod +x "$fake_bin/rustc"
  output="$(cd "$app" && PATH="$fake_bin:$PATH" RUSTC_TRACE="$trace" PLUGIN_DATA="$STATE_ROOT" "$PYTHON_BIN" "$PY_HOOK" session-start <<< '{}')"
  assert_contains "$output" ':kind "baseline"'
  [ ! -e "$trace" ] || fail "ordinary dependencies invoked rustc"
}

regression_tool_directory_boundary() {
  local app
  app="$(make_app final-tool-directory-boundary $'[dependencies]\nreinhardt = "0.4.0"')"
  mkdir -p "$app/src/apps/users/models"
  assert_empty "$(run_hook "$app" tool '{"session_id":"tool-file-boundary","path":"src/apps/users.rs","tool_response":{"exit_code":0}}')"
  assert_contains "$(run_hook "$app" tool '{"session_id":"tool-directory-boundary","path":"src/apps/users/models.rs","tool_response":{"exit_code":0}}')" ':app \"users\"'
}

regression_unreadable_apps_fail_open() {
  local app output
  app="$(make_app final-unreadable-apps $'[dependencies]\nreinhardt = "0.4.0"')"
  chmod 000 "$app/src/apps"
  output="$(run_hook "$app" session-start 2>/dev/null)"
  chmod 700 "$app/src/apps"
  assert_contains "$output" ':app-count 0'
}

regression_maximal_app_name() {
  local app name output
  app="$(make_app final-maximal-name $'[dependencies]\nreinhardt = "0.4.0"')"
  name="$(awk 'BEGIN { for (i=0; i<255; i++) printf "m" }')"
  mkdir -p "$app/src/apps/$name/models"
  output="$(run_hook "$app" prompt "{\"session_id\":\"maximal-name\",\"prompt\":\"src/apps/$name/models\"}")"
  [ "$(printf '%s' "$output" | wc -c | tr -d ' ')" -le 512 ] || fail "maximal app summary exceeded 512 bytes"
  assert_contains "$output" ":path \"src/apps/$name\""
}

final_review_failures=0
for regression in \
  regression_categoryless_app \
  regression_bounded_text_boundaries \
  regression_tool_path_boundaries \
  regression_workspace_default_features \
  regression_explicit_workspace_root \
  regression_no_per_app_basename \
  regression_prompt_value_only \
  regression_unicode_prompt_boundaries \
  regression_default_feature_preset \
  regression_explicit_default_feature \
  regression_forwarded_default_feature \
  regression_effective_facade_package \
  regression_one_pass_matching \
  regression_unbalanced_manifest \
  regression_top_level_json_fields \
  regression_all_presets_expand \
  regression_feature_implications \
  regression_base_feature_implications \
  regression_forwarded_default_features \
  regression_active_target_only \
  regression_configured_target \
  regression_configured_rustflags \
  regression_config_file_precedence \
  regression_config_file_selection \
  regression_ancestor_rustflags \
  regression_windows_tool_path \
  regression_combined_dependency_defaults \
  regression_full_preset_auth \
  regression_optional_dependency_activation \
  regression_invalid_dependency_type \
  regression_no_unneeded_rustc_probe \
  regression_tool_directory_boundary \
  regression_unreadable_apps_fail_open \
  regression_maximal_app_name
do
  if ( "$regression" ); then
    :
  else
    printf 'FINAL REVIEW REGRESSION FAILED: %s\n' "$regression" >&2
    final_review_failures=$((final_review_failures + 1))
  fi
done
[ "$final_review_failures" -eq 0 ] || fail "$final_review_failures final review regressions failed"

direct="$(make_app direct $'[package]\nname = "direct"\nversion = "0.1.0"\n[dependencies]\nreinhardt = { package = "reinhardt-web", version = "0.4.0", default-features = false, features = ["db-sqlite", "auth-session"] }')"
output="$(run_hook "$direct" session-start)"
assert_contains "$output" ':kind "baseline"'
assert_contains "$output" ':reinhardt-version "0.4.0"'
assert_contains "$output" ':default-features false'
assert_contains "$output" ':features "auth, auth-session, database, db-sqlite"'
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

literal="$(make_app literal $'[dependencies]')"
printf '%s\n' "framework = { package = 'reinhardt-web', version = '0.4.4' }" >> "$literal/Cargo.toml"
assert_contains "$(run_hook "$literal" session-start)" ':reinhardt-version "0.4.4"'

path_dep="$(make_app path $'[dependencies.reinhardt]\npackage = "reinhardt-web"\npath = "../reinhardt"\nfeatures = ["db-postgres"]')"
output="$(run_hook "$path_dep" session-start)"
assert_contains "$output" ':reinhardt-version "path"'
assert_contains "$output" ':db-backend "postgres"'

dotted="$(make_app dotted $'[dependencies]')"
printf '%s\n' \
  'reinhardt.package = "reinhardt-web"' \
  'reinhardt.path = "../reinhardt"' \
  'reinhardt.default-features = false' \
  'reinhardt.features = ["db-sqlite"]' >> "$dotted/Cargo.toml"
output="$(run_hook "$dotted" session-start)"
assert_contains "$output" ':reinhardt-version "path"'
assert_contains "$output" ':db-backend "sqlite"'

single_feature="$(make_app single-feature $'[dependencies]')"
printf '%s\n' "reinhardt = { version = '0.4.0', default-features = false, features = ['db-sqlite'] }" >> "$single_feature/Cargo.toml"
assert_contains "$(run_hook "$single_feature" session-start)" ':db-backend "sqlite"'

underscore_default="$(make_app underscore-default $'[dependencies]')"
printf '%s\n' "reinhardt = { version = '0.4.0', default_features = false, features = ['db-sqlite'] }" >> "$underscore_default/Cargo.toml"
output="$(run_hook "$underscore_default" session-start)"
assert_contains "$output" ':default-features false'
assert_contains "$output" ':db-backend "sqlite"'

target="$(make_app target $'[target.\'cfg(not(target_arch = "wasm32"))\'.dependencies]\nreinhardt = { package = "reinhardt-web", git = "https://example.invalid/reinhardt", features = [\n  "pages",\n  "auth-session",\n] }')"
output="$(run_hook "$target" session-start)"
assert_contains "$output" ':reinhardt-version "git"'
assert_contains "$output" ':features "'
assert_contains "$output" 'auth-session'
assert_contains "$output" 'pages'
assert_contains "$output" 'db-postgres'

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
assert_contains "$output" ':features "auth, auth-jwt, database, db-sqlite"'

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

assert_empty "$(run_hook "$plain" session-start '{"session_id":')"

escaped_features="$(make_app escaped-features '[dependencies]')"
{
  printf '%s' 'reinhardt = { version = "0.4.2", features = ['
  for ((index=1; index<=20; index++)); do
    [ "$index" -eq 1 ] || printf ', '
    printf '"\\\\界xxxxxxxxxxxxxxxxxxxx%02d"' "$index"
  done
  printf '%s\n' '] }'
} >> "$escaped_features/Cargo.toml"
output="$(run_hook "$escaped_features" session-start)"
features_line="$(printf '%s\n' "$output" | awk '/^  :features /')"
features_value="${features_line#*\"}"
features_value="${features_value%\"}"
[ "$(LC_ALL=C printf '%s' "$features_value" | wc -c | tr -d '[:space:]')" -le 512 ] || fail 'expected escaped feature bytes to be at most 512'
assert_contains "$features_value" $'\\\\界'
case "$features_value" in
  *'... (+'*' more)') ;;
  *) fail 'expected escaped feature list to be truncated' ;;
esac

subagent_output="$(run_hook "$plain" subagent-start)"
assert_contains "$subagent_output" '"hookEventName":"SubagentStart"'
assert_contains "$(decode_context "$subagent_output" SubagentStart)" ':kind "baseline"'
assert_empty "$(run_hook "$plain" unknown-mode)"

app="$(make_app progressive $'[package]\nname = "progressive"\nversion = "0.1.0"\n[dependencies]\nreinhardt = { package = "reinhardt-web", version = "0.4.0", features = ["db-sqlite"] }')"
mkdir -p \
  "$app/src/apps/users/api" \
  "$app/src/apps/users/pages" \
  "$app/src/apps/users/migrations" \
  "$app/src/apps/users/config" \
  "$app/src/apps/polls/pages"
: > "$app/src/apps/users/models.rs"
: > "$app/src/apps/users/admin.rs"

baseline="$(run_hook "$app" session-start '{"session_id":"app-count-session","source":"startup"}')"
assert_contains "$baseline" ':app-count 2'

prompt_payload='{"session_id":"prompt-session","prompt":"Update the USERS authentication flow"}'
output="$(run_hook "$app" prompt "$prompt_payload")"
assert_contains "$output" ':kind "app"'
assert_contains "$output" ':app "users"'
assert_contains "$output" $':app "users"\n  :path "src/apps/users"\n  :categories "models, api, pages, admin, migrations, configuration"\n  :guidance "Inspect this app before editing and use the applicable bundled Reinhardt skills."'
assert_contains "$output" ':categories "models, api, pages, admin, migrations, configuration"'

assert_empty "$(run_hook "$app" prompt "$prompt_payload")"
assert_empty "$(run_hook "$app" prompt '{"session_id":"partial-session","prompt":"Update endusers"}')"

mkdir -p "$app/src/apps/Üsers/models"
assert_contains "$(run_hook "$app" prompt '{"session_id":"unicode-session","prompt":"Update the üSERS flow"}')" ':app "Üsers"'

path_output="$(run_hook "$app" prompt '{"session_id":"path-session","prompt":"Inspect src/apps/polls/pages"}')"
assert_contains "$path_output" ':app "polls"'
assert_contains "$path_output" ':categories "pages"'

assert_empty "$(run_hook "$app" unknown '{"session_id":"unknown-session"}')"
assert_empty "$(run_hook "$app" prompt 'not-json')"

tool_payload='{"session_id":"tool-session","tool_name":"Bash","tool_input":{"command":"sed -n 1,80p src/apps/users/models.rs"},"tool_response":{"exit_code":0}}'
tool_output="$(run_hook "$app" tool "$tool_payload")"
assert_contains "$tool_output" '"hookEventName":"PostToolUse"'
assert_contains "$tool_output" '\n  :app \"users\"'
decoded_tool_output="$(decode_tool_context "$tool_output")" || fail "tool output is not valid JSON context"
assert_contains "$decoded_tool_output" $'\n  :app "users"'

mkdir -p "$app/src/apps/reports/models"
tool_multi_payload='{"session_id":"tool-multi-session","tool_name":"Bash","tool_input":{"command":"cat src/apps/reports/models.rs src/apps/users/models.rs"},"tool_response":{"exit_code":0}}'
tool_multi_output="$(run_hook "$app" tool "$tool_multi_payload")"
[ "$(printf '%s\n' "$tool_multi_output" | wc -l | tr -d ' ')" -eq 1 ] || fail "tool multi-app output must be one JSON line"
decoded_tool_multi_output="$(decode_tool_context "$tool_multi_output")" || fail "tool multi-app output is not one valid JSON context"
[ "$(printf '%s\n' "$decoded_tool_multi_output" | awk '/:kind "app"/ { count++ } END { print count + 0 }')" -eq 2 ] || fail "tool multi-app context did not contain two summaries"
assert_contains "$decoded_tool_multi_output" ':app "reports"'
assert_contains "$decoded_tool_multi_output" ':app "users"'

tool_root_path='{"session_id":"tool-root-path","tool_name":"Bash","tool_input":{"command":"ls src/apps/users"},"tool_response":{"exit_code":0}}'
assert_contains "$(run_hook "$app" tool "$tool_root_path")" ':app \"users\"'

tool_punctuation_path='{"session_id":"tool-punctuation-path","tool_name":"Bash","tool_input":{"command":"ls src/apps/users && printf done"},"tool_response":{"exit_code":0}}'
assert_contains "$(run_hook "$app" tool "$tool_punctuation_path")" ':app \"users\"'

failed_tool='{"session_id":"failed-tool","tool_name":"Bash","tool_input":{"command":"cat src/apps/users/missing.rs"},"tool_response":{"exit_code":1}}'
assert_empty "$(run_hook "$app" tool "$failed_tool")"

partial_tool='{"session_id":"partial-tool","tool_name":"Bash","tool_input":{"command":"cat src/apps/users_extra/models.rs"},"tool_response":{"exit_code":0}}'
assert_empty "$(run_hook "$app" tool "$partial_tool")"

run_hook "$app" prompt '{"session_id":"compact-session","prompt":"users"}' >/dev/null
assert_empty "$(run_hook "$app" prompt '{"session_id":"compact-session","prompt":"users"}')"
run_hook "$app" session-start '{"session_id":"compact-session","source":"compact"}' >/dev/null
assert_contains "$(run_hook "$app" prompt '{"session_id":"compact-session","prompt":"users"}')" ':app "users"'

run_hook "$app" prompt '{"session_id":"clear-session","prompt":"users"}' >/dev/null
run_hook "$app" session-start '{"session_id":"clear-session","source":"clear"}' >/dev/null
assert_contains "$(run_hook "$app" prompt '{"session_id":"clear-session","prompt":"users"}')" ':app "users"'

run_hook "$app" prompt '{"session_id":"startup-session","prompt":"users"}' >/dev/null
run_hook "$app" session-start '{"session_id":"startup-session","source":"startup"}' >/dev/null
assert_contains "$(run_hook "$app" prompt '{"session_id":"startup-session","prompt":"users"}')" ':app "users"'

run_hook "$app" prompt '{"session_id":"resume-session","prompt":"users"}' >/dev/null
run_hook "$app" session-start '{"session_id":"resume-session","source":"resume"}' >/dev/null
assert_empty "$(run_hook "$app" prompt '{"session_id":"resume-session","prompt":"users"}')"

run_hook "$app" prompt '{"session_id":"subagent-session","prompt":"users"}' >/dev/null
subagent_output="$(run_hook "$app" subagent-start '{"session_id":"subagent-session","agent_type":"Explore"}')"
assert_contains "$subagent_output" '"hookEventName":"SubagentStart"'
assert_contains "$(decode_context "$subagent_output" SubagentStart)" ':kind "baseline"'
assert_empty "$(run_hook "$app" prompt '{"session_id":"subagent-session","prompt":"users"}')"

run_hook "$app" prompt '{"session_id":"end-session","prompt":"users"}' >/dev/null
run_hook "$app" session-end '{"session_id":"end-session","reason":"other"}' >/dev/null
assert_contains "$(run_hook "$app" prompt '{"session_id":"end-session","prompt":"users"}')" ':app "users"'

for name in app_one app_two app_three app_four app_five app_six; do
  mkdir -p "$app/src/apps/$name/models"
done
multi_output="$(run_hook "$app" prompt '{"session_id":"limit-session","prompt":"app_one app_two app_three app_four app_five app_six"}')"
multi_count="$(printf '%s\n' "$multi_output" | awk '/:kind "app"/ { count++ } END { print count + 0 }')"
[ "$multi_count" -eq 5 ] || fail "expected five app summaries, got $multi_count"
assert_contains "$(run_hook "$app" prompt '{"session_id":"limit-session","prompt":"app_two"}')" ':app "app_two"'

[ "$(printf '%s\n' "$tool_output" | wc -l | tr -d ' ')" -eq 1 ] || fail "tool JSON must be one line"
assert_contains "$tool_output" '\n'
assert_contains "$tool_output" '\"users\"'

untracked_one="$(cd "$app" && unset CLAUDE_PLUGIN_DATA && PLUGIN_DATA=/dev/null TMPDIR=/dev/null "$HOOK" prompt <<< '{"session_id":"no-state","prompt":"users"}')"
untracked_two="$(cd "$app" && unset CLAUDE_PLUGIN_DATA && PLUGIN_DATA=/dev/null TMPDIR=/dev/null "$HOOK" prompt <<< '{"session_id":"no-state","prompt":"users"}')"
assert_contains "$untracked_one" ':app "users"'
assert_contains "$untracked_two" ':app "users"'

unsafe_one="$(run_hook "$app" prompt '{"session_id":"../unsafe","prompt":"users"}')"
unsafe_two="$(run_hook "$app" prompt '{"session_id":"../unsafe","prompt":"users"}')"
assert_contains "$unsafe_one" ':app "users"'
assert_contains "$unsafe_two" ':app "users"'

dot_one="$(run_hook "$app" prompt '{"session_id":".","prompt":"users"}')"
dot_two="$(run_hook "$app" prompt '{"session_id":".","prompt":"users"}')"
dotdot_one="$(run_hook "$app" prompt '{"session_id":"..","prompt":"users"}')"
dotdot_two="$(run_hook "$app" prompt '{"session_id":"..","prompt":"users"}')"
assert_contains "$dot_one" ':app "users"'
assert_contains "$dot_two" ':app "users"'
assert_contains "$dotdot_one" ':app "users"'
assert_contains "$dotdot_two" ':app "users"'
[ -z "$(find "$STATE_ROOT" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' -print -quit)" ] || fail "dot session created a root-level state marker"

run_hook "$app" prompt '{"session_id":"safe-session","prompt":"users"}' >/dev/null
run_hook "$app" session-end '{"session_id":".","reason":"other"}' >/dev/null
run_hook "$app" session-end '{"session_id":"..","reason":"other"}' >/dev/null
assert_empty "$(run_hook "$app" prompt '{"session_id":"safe-session","prompt":"users"}')"

run_hook "$app" prompt '{"session_id":"permission-session","prompt":"users"}' >/dev/null
marker_dir="$(find "$STATE_ROOT/permission-session" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[ "$(directory_mode "$marker_dir")" = 700 ] || fail "state marker directory is not private"
if command -v gstat >/dev/null 2>&1; then
  [ "$(directory_mode "$marker_dir" "$(command -v gstat)")" = 700 ] || fail "GNU stat fallback did not read the private marker mode"
elif stat --version >/dev/null 2>&1; then
  [ "$(directory_mode "$marker_dir")" = 700 ] || fail "GNU stat fallback did not read the private marker mode"
fi

priority_root="$TEST_ROOT/claude-priority"
secondary_root="$TEST_ROOT/plugin-secondary"
(cd "$app" && CLAUDE_PLUGIN_DATA="$priority_root" PLUGIN_DATA="$secondary_root" "$HOOK" prompt <<< '{"session_id":"priority-session","prompt":"users"}') >/dev/null
[ -d "$priority_root" ] || fail "CLAUDE_PLUGIN_DATA was not selected"
[ ! -e "$secondary_root" ] || fail "PLUGIN_DATA was used before CLAUDE_PLUGIN_DATA"

unusable_root="$TEST_ROOT/unusable-root"
fallback_root="$TEST_ROOT/fallback-root"
: > "$unusable_root"
fallback_one="$(cd "$app" && CLAUDE_PLUGIN_DATA="$unusable_root" PLUGIN_DATA="$fallback_root" "$HOOK" prompt <<< '{"session_id":"fallback-session","prompt":"users"}')"
fallback_two="$(cd "$app" && CLAUDE_PLUGIN_DATA="$unusable_root" PLUGIN_DATA="$fallback_root" "$HOOK" prompt <<< '{"session_id":"fallback-session","prompt":"users"}')"
assert_contains "$fallback_one" ':app "users"'
assert_empty "$fallback_two"
[ -d "$fallback_root/fallback-session" ] || fail "writable fallback state root was not selected"

public_tmp="$TEST_ROOT/public-tmp"
mkdir -p "$public_tmp/reinhardt-agents-plugin"
chmod 777 "$public_tmp/reinhardt-agents-plugin"
public_one="$(cd "$app" && unset CLAUDE_PLUGIN_DATA && PLUGIN_DATA=/dev/null TMPDIR="$public_tmp" "$HOOK" prompt <<< '{"session_id":"public-state","prompt":"users"}')"
public_two="$(cd "$app" && unset CLAUDE_PLUGIN_DATA && PLUGIN_DATA=/dev/null TMPDIR="$public_tmp" "$HOOK" prompt <<< '{"session_id":"public-state","prompt":"users"}')"
assert_contains "$public_one" ':app "users"'
assert_contains "$public_two" ':app "users"'
[ ! -e "$public_tmp/reinhardt-agents-plugin/public-state" ] || fail "public state root was used"

marker_failure_root="$TEST_ROOT/marker-failure-root"
mkdir -p "$marker_failure_root"
: > "$marker_failure_root/marker-failure-session"
marker_failure_one="$(cd "$app" && CLAUDE_PLUGIN_DATA="$marker_failure_root" PLUGIN_DATA=/dev/null "$HOOK" prompt <<< '{"session_id":"marker-failure-session","prompt":"users"}')"
marker_failure_two="$(cd "$app" && CLAUDE_PLUGIN_DATA="$marker_failure_root" PLUGIN_DATA=/dev/null "$HOOK" prompt <<< '{"session_id":"marker-failure-session","prompt":"users"}')"
assert_contains "$marker_failure_one" ':app "users"'
assert_contains "$marker_failure_two" ':app "users"'

feature_manifest=$'[package]\nname = "bounded"\nversion = "0.1.0"\n[dependencies]\nreinhardt = { package = "reinhardt-web", version = "0.4.0", default-features = false, features = [\n  "00-quote\\\"feature",\n  "01-slash\\\\feature",\n'
for number in $(awk 'BEGIN { for (i = 2; i < 27; i++) print i }'); do
  feature_manifest+="  \"feature-$number\","
  feature_manifest+=$'\n'
done
feature_manifest+='] }'
bounded="$(make_app bounded "$feature_manifest")"
bounded_output="$(run_hook "$bounded" session-start '{"session_id":"feature-bounds","source":"startup"}')"
feature_value="$(printf '%s\n' "$bounded_output" | sed -n 's/^  :features "\(.*\)"$/\1/p')"
included_value="$(printf '%s' "$feature_value" | sed 's/, \.\.\. (+[0-9][0-9]* more)$//')"
included_count="$(printf '%s\n' "$included_value" | awk -F', ' '{ print NF }')"
[ "$included_count" -le 20 ] || fail "feature list exceeded 20 items"
[ "$(printf '%s' "$feature_value" | wc -c | tr -d ' ')" -le 512 ] || fail "feature list exceeded 512 bytes"
assert_contains "$feature_value" '... (+7 more)'
assert_contains "$feature_value" '\"'
assert_contains "$feature_value" '\\'

control_manifest="$(printf '[package]\nname = "control"\nversion = "0.1.0"\n[dependencies]\nreinhardt = "0.4.0\tunsafe"\n')"
control_app="$(make_app control "$control_manifest")"
control_output="$(run_hook "$control_app" session-start '{"session_id":"control-session","source":"startup"}')"
case "$control_output" in
  *$'\t'*) fail "baseline retained a control character" ;;
esac

long_name="$(awk 'BEGIN { for (i = 0; i < 200; i++) printf "a" }')"
mkdir -p "$app/src/apps/$long_name/models"
long_output="$(run_hook "$app" prompt "{\"session_id\":\"long-app\",\"prompt\":\"src/apps/$long_name/models\"}")"
[ "$(printf '%s' "$long_output" | wc -c | tr -d ' ')" -le 512 ] || fail "app summary exceeded 512 bytes"
assert_contains "$long_output" ":path \"src/apps/$long_name\""
case "$long_output" in
  *')') ;;
  *) fail "app summary is not a closed S-expression" ;;
esac

anti_pattern_command='"${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/hooks/run-hook.cmd" detect-antipatterns.sh'
tool_command='"${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/hooks/run-hook.cmd" inject-context.sh tool'
session_start_command='"${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/hooks/run-hook.cmd" inject-context.sh session-start'
prompt_command='"${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/hooks/run-hook.cmd" inject-context.sh prompt'
subagent_command='"${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/hooks/run-hook.cmd" inject-context.sh subagent-start'
session_end_command='"${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/hooks/run-hook.cmd" inject-context.sh session-end'
assert_hook_mapping PostToolUse 'Write|Edit' "$anti_pattern_command"
assert_hook_mapping PostToolUse 'Read|Glob|Grep|Edit|Write|Bash' "$tool_command"
assert_hook_mapping SessionStart '' "$session_start_command"
assert_hook_mapping UserPromptSubmit '' "$prompt_command"
assert_hook_mapping SubagentStart '' "$subagent_command"
assert_hook_mapping SessionEnd '' "$session_end_command"

claude_root_output="$(cd "$app" && CLAUDE_PLUGIN_ROOT="$ROOT" PLUGIN_DATA="$STATE_ROOT" bash "$ROOT/hooks/run-hook.cmd" inject-context.sh session-start <<< '{"session_id":"claude-root","source":"startup"}')"
assert_contains "$claude_root_output" ':kind "baseline"'
codex_root_output="$(cd "$app" && PLUGIN_ROOT="$ROOT" PLUGIN_DATA="$STATE_ROOT" bash "$ROOT/hooks/run-hook.cmd" inject-context.sh session-start <<< '{"session_id":"codex-root","source":"startup"}')"
assert_contains "$codex_root_output" ':kind "baseline"'

printf 'PASS\n'
