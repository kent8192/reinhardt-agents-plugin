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

assert_hook_mapping() {
  local event="$1" matcher="$2" command="$3"
  if python3 - "$ROOT/hooks/hooks.json" "$event" "$matcher" "$command" <<'PY'
import json
import sys

path, event, matcher, command = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    hooks = json.load(source)["hooks"].get(event, [])
for registration in hooks:
    if registration.get("matcher", "") != matcher:
        continue
    if any(hook.get("type") == "command" and hook.get("command") == command for hook in registration.get("hooks", [])):
        raise SystemExit(0)
raise SystemExit(1)
PY
  then
    return 0
  fi
  fail "missing $event hook mapping: $command"
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

assert_empty "$(run_hook "$plain" session-start '{"session_id":')"

escaped_features="$(make_app escaped-features $'[dependencies]\nreinhardt = "0.4.2"')"
{
  printf '%s' 'reinhardt = { version = "0.4.2", features = ['
  for index in $(seq 1 20); do
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

assert_contains "$(run_hook "$plain" subagent-start)" ':kind "baseline"'
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

path_output="$(run_hook "$app" prompt '{"session_id":"path-session","prompt":"Inspect src/apps/polls/pages"}')"
assert_contains "$path_output" ':app "polls"'
assert_contains "$path_output" ':categories "pages"'

assert_empty "$(run_hook "$app" unknown '{"session_id":"unknown-session"}')"
assert_empty "$(run_hook "$app" prompt 'not-json')"

tool_payload='{"session_id":"tool-session","tool_name":"Bash","tool_input":{"command":"sed -n 1,80p src/apps/users/models.rs"},"tool_response":{"exit_code":0}}'
tool_output="$(run_hook "$app" tool "$tool_payload")"
assert_contains "$tool_output" '"hookEventName":"PostToolUse"'
assert_contains "$tool_output" '\n  :app \"users\"'
if ! python3 - "$tool_output" <<'PY'
import json
import sys

context = json.loads(sys.argv[1])["hookSpecificOutput"]["additionalContext"]
assert '\n  :app "users"' in context
PY
then
  fail "tool output is not valid JSON context"
fi

mkdir -p "$app/src/apps/reports/models"
tool_multi_payload='{"session_id":"tool-multi-session","tool_name":"Bash","tool_input":{"command":"cat src/apps/reports/models.rs src/apps/users/models.rs"},"tool_response":{"exit_code":0}}'
tool_multi_output="$(run_hook "$app" tool "$tool_multi_payload")"
[ "$(printf '%s\n' "$tool_multi_output" | wc -l | tr -d ' ')" -eq 1 ] || fail "tool multi-app output must be one JSON line"
if ! python3 - "$tool_multi_output" <<'PY'
import json
import sys

context = json.loads(sys.argv[1])["hookSpecificOutput"]["additionalContext"]
assert context.count(':kind "app"') == 2
assert ':app "reports"' in context
assert ':app "users"' in context
PY
then
  fail "tool multi-app output is not one valid JSON context"
fi

tool_root_path='{"session_id":"tool-root-path","tool_name":"Bash","tool_input":{"command":"ls src/apps/users"},"tool_response":{"exit_code":0}}'
assert_contains "$(run_hook "$app" tool "$tool_root_path")" ':app \"users\"'

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
assert_contains "$(run_hook "$app" subagent-start '{"session_id":"subagent-session","agent_type":"Explore"}')" ':kind "baseline"'
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
[ "$(stat -f '%Lp' "$marker_dir")" = 700 ] || fail "state marker directory is not private"

priority_root="$TEST_ROOT/claude-priority"
secondary_root="$TEST_ROOT/plugin-secondary"
(cd "$app" && CLAUDE_PLUGIN_DATA="$priority_root" PLUGIN_DATA="$secondary_root" "$HOOK" prompt <<< '{"session_id":"priority-session","prompt":"users"}') >/dev/null
[ -d "$priority_root" ] || fail "CLAUDE_PLUGIN_DATA was not selected"
[ ! -e "$secondary_root" ] || fail "PLUGIN_DATA was used before CLAUDE_PLUGIN_DATA"

unusable_root="$TEST_ROOT/unusable-root"
fallback_root="$TEST_ROOT/fallback-root"
mkdir "$unusable_root"
chmod 500 "$unusable_root"
fallback_one="$(cd "$app" && CLAUDE_PLUGIN_DATA="$unusable_root" PLUGIN_DATA="$fallback_root" "$HOOK" prompt <<< '{"session_id":"fallback-session","prompt":"users"}')"
fallback_two="$(cd "$app" && CLAUDE_PLUGIN_DATA="$unusable_root" PLUGIN_DATA="$fallback_root" "$HOOK" prompt <<< '{"session_id":"fallback-session","prompt":"users"}')"
chmod 700 "$unusable_root"
assert_contains "$fallback_one" ':app "users"'
assert_empty "$fallback_two"
[ -d "$fallback_root/fallback-session" ] || fail "writable fallback state root was not selected"

marker_failure_root="$TEST_ROOT/marker-failure-root"
mkdir -p "$marker_failure_root/marker-failure-session"
chmod 500 "$marker_failure_root/marker-failure-session"
marker_failure_one="$(cd "$app" && CLAUDE_PLUGIN_DATA="$marker_failure_root" PLUGIN_DATA=/dev/null "$HOOK" prompt <<< '{"session_id":"marker-failure-session","prompt":"users"}')"
marker_failure_two="$(cd "$app" && CLAUDE_PLUGIN_DATA="$marker_failure_root" PLUGIN_DATA=/dev/null "$HOOK" prompt <<< '{"session_id":"marker-failure-session","prompt":"users"}')"
chmod 700 "$marker_failure_root/marker-failure-session"
assert_contains "$marker_failure_one" ':app "users"'
assert_contains "$marker_failure_two" ':app "users"'

feature_manifest=$'[package]\nname = "bounded"\nversion = "0.1.0"\n[dependencies]\nreinhardt = { package = "reinhardt-web", version = "0.4.0", features = [\n  "00-quote\\\"feature",\n  "01-slash\\\\feature",\n'
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
