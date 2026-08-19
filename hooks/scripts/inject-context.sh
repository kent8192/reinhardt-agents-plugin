#!/usr/bin/env bash
# inject-context.sh
# SessionStart hook: detects Reinhardt applications and injects baseline context.

set -euo pipefail

MODE="${1:-session-start}"
HOOK_INPUT="$(cat 2>/dev/null || true)"
CARGO_TOML="Cargo.toml"

REINHARDT_VERSION="unknown"
DEFAULT_FEATURES="true"
FEATURES=""
DB_BACKEND="none"
AUTH_METHOD="none"
APP_COUNT=0

parse_dependency_manifest() {
  local member_manifest="$1"
  local workspace_manifest="${2:-}"

  awk -v member="$member_manifest" -v workspace="$workspace_manifest" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function strip_comment(s, i,c,out,quoted,escaped) { quoted=escaped=0; out=""; for (i=1; i<=length(s); i++) { c=substr(s,i,1); if (escaped) { out=out c; escaped=0; continue }; if (quoted && c=="\\") { out=out c; escaped=1; continue }; if (c=="\"") quoted=!quoted; if (!quoted && c=="#") break; out=out c }; return out }
    function balance(s, i,c,quoted,escaped,n) { quoted=escaped=0; n=0; for (i=1; i<=length(s); i++) { c=substr(s,i,1); if (escaped) { escaped=0; continue }; if (quoted && c=="\\") { escaped=1; continue }; if (c=="\"") { quoted=!quoted; continue }; if (!quoted && (c=="{" || c=="[")) n++; if (!quoted && (c=="}" || c=="]")) n-- }; return n }
    function unquote(s) { s=trim(s); if (substr(s,1,1)=="\"" && substr(s,length(s),1)=="\"") return substr(s,2,length(s)-2); return s }
    function member_runtime(s) { gsub(/[[:space:]]/, "", s); if (s ~ /(^|\.)dev-dependencies(\.|$)/ || s ~ /(^|\.)build-dependencies(\.|$)/) return 0; return s=="dependencies" || s ~ /^dependencies\./ || s ~ /^target\..*\.dependencies(\.|$)/ }
    function workspace_runtime(s) { gsub(/[[:space:]]/, "", s); return s=="workspace.dependencies" || s ~ /^workspace\.dependencies\./ }
    function section_key(s, n,a) { n=split(s,a,"."); return unquote(a[n]) }
    function add_record(kind,key,text) { if (key=="") return; record_count++; record_kind[record_count]=kind; record_key[record_count]=key; record_text[record_count]=text }
    function flush_table() { if (table_active) add_record(table_kind,table_key,table_text); table_active=0; table_kind=""; table_key=""; table_text="" }
    function begin_section(raw,kind, section,is_table) { flush_table(); section=substr(raw,2,length(raw)-2); if ((kind=="member" && member_runtime(section)) || (kind=="workspace" && workspace_runtime(section))) { is_table=(kind=="member" ? (section ~ /\.dependencies\./ || section ~ /^dependencies\./) : section ~ /^workspace\.dependencies\./); if (is_table) { table_active=1; table_kind=kind; table_key=section_key(section); table_text="" }; active_kind=kind } else active_kind="" }
    function process_record(text, p,key,value) { p=index(text,"="); if (!p) return; key=unquote(trim(substr(text,1,p-1))); value=trim(substr(text,p+1)); if (table_active) table_text=table_text "\n" key "=" value; else if (active_kind!="") add_record(active_kind,key,value) }
    function read_quoted(s,pos, i,c,out,escaped) { out=""; escaped=0; for (i=pos+1; i<=length(s); i++) { c=substr(s,i,1); if (escaped) { out=out c; escaped=0; continue }; if (c=="\\") { escaped=1; continue }; if (c=="\"") { QVAL=out; QEND=i+1; return 1 }; out=out c }; QVAL=out; QEND=i; return 0 }
    function find_field(s,want,from, i,p,before,c) { if (from<1) from=1; for (i=from; i<=length(s)-length(want)+1; i++) { if (substr(s,i,length(want))!=want) continue; before=(i==1 ? "" : substr(s,i-1,1)); c=substr(s,i+length(want),1); if (before ~ /[[:alnum:]_-]/ || c ~ /[[:alnum:]_-]/) continue; p=i+length(want); while (substr(s,p,1) ~ /[[:space:]]/) p++; if (substr(s,p,1)!="=") continue; p++; while (substr(s,p,1) ~ /[[:space:]]/) p++; FPOS=p; return 1 }; return 0 }
    function scalar(s,want, p,end) { if (!find_field(s,want,1)) return ""; p=FPOS; if (substr(s,p,1)=="\"") { read_quoted(s,p); return QVAL }; end=p; while (substr(s,end,1)!="" && substr(s,end,1)!~ /[,}\]\n[:space:]]/) end++; return substr(s,p,end-p) }
    function direct_version(s, p) { p=1; while (substr(s,p,1) ~ /[[:space:]]/) p++; if (substr(s,p,1)=="\"") { read_quoted(s,p); return QVAL }; return "" }
    function collect_features(s, start,p,depth,c,quoted,escaped) { start=1; while (find_field(s,"features",start)) { p=FPOS; if (substr(s,p,1)!="[") { start=p+1; continue }; depth=0; quoted=escaped=0; for (; p<=length(s); p++) { c=substr(s,p,1); if (escaped) { escaped=0; continue }; if (quoted && c=="\\") { escaped=1; continue }; if (c=="\"") { if (!quoted) { read_quoted(s,p); feature[QVAL]=1; p=QEND-1 }; continue }; if (c=="[") depth++; if (c=="]") { depth--; if (!depth) break } }; start=p+1 } }
    function is_facade(key,text) { return key=="reinhardt" || scalar(text,"package")=="reinhardt-web" }
    function process_member(key,text, effective,version) { if (scalar(text,"workspace")=="true") { if (!(key in workspace_record)) return; inherited="true"; effective=text "\n" workspace_record[key] } else effective=text; if (!is_facade(key,effective)) return; found="true"; version=scalar(effective,"version"); if (version=="") version=direct_version(effective); if (explicit_version=="" && version!="") explicit_version=version; if (!path_seen && scalar(effective,"path")!="") path_seen=1; if (!git_seen && scalar(effective,"git")!="") git_seen=1; if (scalar(effective,"default-features")=="false") defaults="false"; collect_features(effective) }
    {
      kind=(FILENAME==member ? "member" : (FILENAME==workspace ? "workspace" : "")); line=strip_comment($0); if (trim(line)=="") next
      if (line ~ /^[[:space:]]*\[[^][]+\][[:space:]]*$/) { begin_section(trim(line),kind); pending=""; pending_balance=0; next }
      if (active_kind=="") next
      if (pending!="") { pending=pending "\n" line; pending_balance+=balance(line); if (pending_balance==0) { process_record(pending); pending="" }; next }
      if (index(line,"=")==0) next
      pending=line; pending_balance=balance(line); if (pending_balance==0) { process_record(pending); pending="" }
    }
    END {
      if (pending!="") process_record(pending); flush_table()
      for (i=1; i<=record_count; i++) if (record_kind[i]=="workspace") workspace_record[record_key[i]]=record_text[i]
      found="false"; inherited="false"; defaults="true"; explicit_version=""; path_seen=git_seen=0
      for (i=1; i<=record_count; i++) if (record_kind[i]=="member") process_member(record_key[i],record_text[i])
      feature_csv=""; for (name in feature) feature_csv=feature_csv (feature_csv=="" ? "" : ",") name
      if (explicit_version!="") source=explicit_version; else if (path_seen) source="path"; else if (git_seen) source="git"; else source="unknown"
      print found "\t" inherited "\t" source "\t" defaults "\t" feature_csv
    }
  ' "$member_manifest" "${workspace_manifest:-/dev/null}"
}

find_workspace_manifest() {
  local directory="$1" candidate
  directory="${directory%/}"; [ -n "$directory" ] || directory="/"
  candidate="${directory%/*}"; [ -n "$candidate" ] || candidate="/"
  while :; do
    if [ -f "$candidate/Cargo.toml" ] && awk '
      function stripped(s, i,c,q,e,out) { q=e=0; out=""; for (i=1;i<=length(s);i++) { c=substr(s,i,1); if (e) { out=out c; e=0; continue }; if (q && c=="\\") { out=out c; e=1; continue }; if (c=="\"") q=!q; if (!q && c=="#") break; out=out c }; return out }
      stripped($0) ~ /^[[:space:]]*\[workspace\][[:space:]]*$/ { found=1; exit }
      END { exit !found }
    ' "$candidate/Cargo.toml"; then printf '%s\n' "$candidate/Cargo.toml"; return 0; fi
    [ "$candidate" = "/" ] && break
    candidate="${candidate%/*}"; [ -n "$candidate" ] || candidate="/"
  done
}

bounded_join() {
  local max_items="$1" max_bytes="$2" value output="" candidate suffix
  local -a values
  local count=0 index remaining
  while IFS= read -r value; do [ -n "$value" ] || continue; values[$count]="$value"; count=$((count + 1)); done < <(LC_ALL=C sort -u)
  for ((index=0; index<count; index++)); do
    remaining=$((count - index - 1))
    if [ "$index" -ge "$max_items" ]; then
      output="${output}${output:+, }... (+$((count - index)) more)"
      break
    fi
    suffix=""; [ "$remaining" -gt 0 ] && suffix=", ... (+$remaining more)"
    candidate="${output}${output:+, }${values[$index]}${suffix}"
    if [ "$(sanitized_byte_length "$candidate")" -le "$max_bytes" ]; then output="${output}${output:+, }${values[$index]}"; [ "$remaining" -eq 0 ] && break
    else
      suffix="... (+$((count - index)) more)"
      output="${output}${output:+, }${suffix}"
      break
    fi
  done
  printf '%s\n' "$output"
}

sanitize_text() { LC_ALL=C tr -d '\000-\037\177' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

sanitized_byte_length() { printf '%s' "$1" | sanitize_text | LC_ALL=C wc -c | tr -d '[:space:]'; }

has_feature() { case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac; }

valid_hook_input() {
  [ -z "$HOOK_INPUT" ] && return 0
  printf '%s' "$HOOK_INPUT" | awk '
    function skip() { while (substr(input,position,1) ~ /[[:space:]]/) position++ }
    function string(    character,escaped,count) {
      if (substr(input,position,1) != "\"") return 0
      position++; escaped=0
      while (position <= input_length) {
        character=substr(input,position,1)
        if (escaped) {
          if (character ~ /["\\\\\/bfnrt]/) { position++; escaped=0; continue }
          if (character == "u") {
            for (count=1; count<=4; count++) if (substr(input,position+count,1) !~ /[[:xdigit:]]/) return 0
            position+=5; escaped=0; continue
          }
          return 0
        }
        if (character == "\\") { escaped=1; position++; continue }
        if (character == "\"") { position++; return 1 }
        if (character ~ /[[:cntrl:]]/) return 0
        position++
      }
      return 0
    }
    function number(    rest) {
      rest=substr(input,position)
      if (match(rest, /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/)) { position+=RLENGTH; return 1 }
      return 0
    }
    function value(    character) {
      skip(); character=substr(input,position,1)
      if (character == "\"") return string()
      if (character == "{") return object()
      if (character == "[") return array()
      if (character == "-" || character ~ /[0-9]/) return number()
      if (substr(input,position,4) == "true") { position+=4; return 1 }
      if (substr(input,position,5) == "false") { position+=5; return 1 }
      if (substr(input,position,4) == "null") { position+=4; return 1 }
      return 0
    }
    function array() {
      position++; skip()
      if (substr(input,position,1) == "]") { position++; return 1 }
      while (value()) {
        skip()
        if (substr(input,position,1) == "]") { position++; return 1 }
        if (substr(input,position,1) != ",") return 0
        position++; skip()
      }
      return 0
    }
    function object() {
      position++; skip()
      if (substr(input,position,1) == "}") { position++; return 1 }
      while (string()) {
        skip(); if (substr(input,position,1) != ":") return 0
        position++; if (!value()) return 0
        skip()
        if (substr(input,position,1) == "}") { position++; return 1 }
        if (substr(input,position,1) != ",") return 0
        position++; skip()
      }
      return 0
    }
    { input=input $0 ORS }
    END { input_length=length(input); position=1; if (!object()) exit 1; skip(); exit position <= input_length }
  '
}

load_reinhardt_metadata() {
  [ -f "$CARGO_TOML" ] || return 1
  [ -f "src/bin/manage.rs" ] || return 1
  local workspace_manifest found inherited version_or_source default_features feature_csv
  workspace_manifest="$(find_workspace_manifest "$PWD")"
  IFS=$'\t' read -r found inherited version_or_source default_features feature_csv < <(parse_dependency_manifest "$CARGO_TOML" "$workspace_manifest")
  [ "$found" = "true" ] || return 1
  REINHARDT_VERSION="$version_or_source"
  DEFAULT_FEATURES="$default_features"
  FEATURES="$(printf '%s\n' "$feature_csv" | tr ',' '\n' | bounded_join 20 512)"
  DB_BACKEND="none"
  if has_feature "$feature_csv" "db-postgres"; then DB_BACKEND="postgres"
  elif has_feature "$feature_csv" "db-mysql"; then DB_BACKEND="mysql"
  elif has_feature "$feature_csv" "db-sqlite"; then DB_BACKEND="sqlite"
  elif has_feature "$feature_csv" "db-cockroachdb"; then DB_BACKEND="cockroachdb"
  elif has_feature "$feature_csv" "database"; then DB_BACKEND="configured (check settings)"; fi
  AUTH_METHOD=""
  if has_feature "$feature_csv" "auth-jwt"; then AUTH_METHOD="jwt"; fi
  if has_feature "$feature_csv" "auth-session"; then AUTH_METHOD="${AUTH_METHOD:+$AUTH_METHOD, }session"; fi
  if has_feature "$feature_csv" "auth-oauth"; then AUTH_METHOD="${AUTH_METHOD:+$AUTH_METHOD, }oauth"; fi
  if has_feature "$feature_csv" "auth-token"; then AUTH_METHOD="${AUTH_METHOD:+$AUTH_METHOD, }token"; fi
  if has_feature "$feature_csv" "auth"; then AUTH_METHOD="${AUTH_METHOD:+$AUTH_METHOD, }auth (default)"; fi
  AUTH_METHOD="${AUTH_METHOD:-none}"
  APP_COUNT=0
  if [ -d src/apps ]; then APP_COUNT="$(find src/apps -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | awk 'END { print NR + 0 }')"; fi
}

render_baseline() {
  local version features database auth
  version="$(printf '%s' "$REINHARDT_VERSION" | sanitize_text)"; features="$(printf '%s' "$FEATURES" | sanitize_text)"; database="$(printf '%s' "$DB_BACKEND" | sanitize_text)"; auth="$(printf '%s' "$AUTH_METHOD" | sanitize_text)"
  printf '%s\n' \
    '(reinhardt-application-context' \
    '  :kind "baseline"' \
    '  :project-type "reinhardt-web application"' \
    "  :reinhardt-version \"$version\"" \
    "  :default-features $DEFAULT_FEATURES" \
    "  :features \"$features\"" \
    "  :db-backend \"$database\"" \
    "  :auth-method \"$auth\"" \
    "  :app-count $APP_COUNT" \
    '  :skills "scaffolding, architecture, modeling, api-development, pages, testing, dependency-injection, authentication, authorization, admin, migration, configuration, lint, macros, signals"' \
    '  :guidance "Inspect Cargo.toml and the application structure before editing. Use the bundled Reinhardt skills that apply, follow guidance for the detected Reinhardt version, and run relevant validation.")'
}

list_apps() {
  [ -d src/apps ] || return 0
  find src/apps -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | LC_ALL=C sort
}

payload_mentions_app() {
  local payload="$1" app="$2" mode="$3" lower_payload lower_app
  if [ "$mode" = "tool" ]; then
    printf '%s\n' "$payload" | awk -v path="src/apps/$app" '
      {
        start = 1
        while (start <= length($0)) {
          position = index(substr($0, start), path)
          if (!position) break
          position += start - 1
          after = substr($0, position + length(path), 1)
          if (after !~ /[A-Za-z0-9_-]/) { found=1; exit }
          start = position + 1
        }
      }
      END { exit !found }
    '
    return
  fi
  lower_payload="$(printf '%s' "$payload" | tr '[:upper:]' '[:lower:]')"
  lower_app="$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')"
  case "$lower_payload" in *"src/apps/$lower_app/"*|*"src/apps/$lower_app\\\""*) return 0 ;; esac
  printf '%s\n' "$lower_payload" | awk -v app="$lower_app" '
    {
      start = 1
      while (start <= length($0)) {
        position = index(substr($0, start), app)
        if (!position) break
        position += start - 1
        before = position == 1 ? "" : substr($0, position - 1, 1)
        after = substr($0, position + length(app), 1)
        if (before !~ /[A-Za-z0-9_-]/ && after !~ /[A-Za-z0-9_-]/) { found=1; exit }
        start = position + 1
      }
    }
    END { exit !found }
  '
}

state_root() {
  local candidate probe
  umask 077
  for candidate in "${CLAUDE_PLUGIN_DATA:-}" "${PLUGIN_DATA:-}" "${TMPDIR:-/tmp}/reinhardt-agents-plugin"; do
    [ -n "$candidate" ] || continue
    if mkdir -p "$candidate" 2>/dev/null; then
      probe="$candidate/.reinhardt-context-probe-$$"
      if mkdir "$probe" 2>/dev/null; then
        rmdir "$probe" 2>/dev/null || true
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  done
  return 1
}

valid_session_id() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && [ "$1" != "." ] && [ "$1" != ".." ]
}

claim_app() {
  local session_id="$1" app="$2" root marker
  umask 077
  valid_session_id "$session_id" || return 0
  root="$(state_root)" || return 0
  marker="$(printf '%s' "$app" | cksum | awk '{ print $1 }')"
  mkdir -p "$root/$session_id" 2>/dev/null || return 0
  if mkdir "$root/$session_id/$marker" 2>/dev/null; then return 0; fi
  [ -d "$root/$session_id/$marker" ] && return 1
  return 0
}

clear_session() {
  local session_id="$1" root
  valid_session_id "$session_id" || return 0
  root="$(state_root)" || return 0
  rm -rf "$root/$session_id"
}

extract_json_string() {
  local field="$1"
  printf '%s' "$HOOK_INPUT" | sed -n "s/.*\\\"$field\\\"[[:space:]]*:[[:space:]]*\\\"\\([^\\\"\\\\]*\\)\\\".*/\\1/p" | head -n 1
}

valid_object_input() {
  [ -n "$(printf '%s' "$HOOK_INPUT" | tr -d '[:space:]')" ] && valid_hook_input
}

display_app_name() {
  local value max_bytes=96
  value="$(printf '%s' "$1" | sanitize_text)"
  if [ "$(printf '%s' "$value" | LC_ALL=C wc -c | tr -d '[:space:]')" -le "$max_bytes" ]; then
    printf '%s' "$value"
  else
    printf '%s...' "$(printf '%s' "$value" | LC_ALL=C cut -c 1-$((max_bytes - 3)))"
  fi
}

render_app() {
  local app="$1" directory="src/apps/$1" display categories="" summary
  local -a found_categories=()
  { [ -f "$directory/models.rs" ] || [ -d "$directory/models" ]; } && found_categories+=(models)
  { [ -f "$directory/api.rs" ] || [ -d "$directory/api" ]; } && found_categories+=(api)
  { [ -f "$directory/pages.rs" ] || [ -d "$directory/pages" ]; } && found_categories+=(pages)
  { [ -f "$directory/admin.rs" ] || [ -d "$directory/admin" ]; } && found_categories+=(admin)
  [ -d "$directory/migrations" ] && found_categories+=(migrations)
  { [ -f "$directory/config.rs" ] || [ -d "$directory/config" ] || [ -f "$directory/settings.rs" ] || [ -d "$directory/settings" ]; } && found_categories+=(configuration)
  categories="$(printf '%s, ' "${found_categories[@]}")"
  categories="${categories%, }"
  display="$(display_app_name "$app")"
  summary="$(printf '%s\n' \
    '(reinhardt-application-context' \
    '  :kind "app"' \
    "  :app \"$display\"" \
    "  :path \"src/apps/$display\"" \
    "  :categories \"$categories\"" \
    '  :guidance "Inspect this app before editing and use the applicable bundled Reinhardt skills."' \
    ')')"
  [ "$(printf '%s' "$summary" | LC_ALL=C wc -c | tr -d '[:space:]')" -le 512 ] || return 1
  printf '%s\n' "$summary"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

emit_tool_context() {
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
    "$(json_escape "$1")"
}

render_matching_apps() {
  local payload="$1" session_id="$2" mode="$3" app emitted=0 summary context=""
  while IFS= read -r app; do
    payload_mentions_app "$payload" "$app" "$mode" || continue
    [ "$emitted" -lt 5 ] || break
    claim_app "$session_id" "$app" || continue
    summary="$(render_app "$app")" || continue
    if [ "$mode" = "tool" ]; then context="${context}${context:+$'\n'}$summary"; else printf '%s\n' "$summary"; fi
    emitted=$((emitted + 1))
  done < <(list_apps)
  if [ "$mode" = "tool" ] && [ -n "$context" ]; then emit_tool_context "$context"; fi
}

tool_succeeded() {
  local exit_code
  exit_code="$(printf '%s' "$HOOK_INPUT" | sed -n 's/.*"exit_code"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9][0-9]*\).*/\1/p' | head -n 1)"
  [ -z "$exit_code" ] || [ "$exit_code" -eq 0 ]
}

case "$MODE" in
  session-start)
    if valid_hook_input; then
      session_id="$(extract_json_string session_id)"
      source="$(extract_json_string source)"
      case "$source" in startup|clear|compact) clear_session "$session_id" ;; esac
      if load_reinhardt_metadata; then render_baseline; fi
    fi
    ;;
  prompt)
    if valid_object_input && load_reinhardt_metadata; then
      render_matching_apps "$HOOK_INPUT" "$(extract_json_string session_id)" prompt
    fi
    ;;
  tool)
    if valid_object_input && tool_succeeded && load_reinhardt_metadata; then
      render_matching_apps "$HOOK_INPUT" "$(extract_json_string session_id)" tool
    fi
    ;;
  subagent-start) if valid_hook_input && load_reinhardt_metadata; then render_baseline; fi ;;
  session-end) if valid_hook_input; then clear_session "$(extract_json_string session_id)"; fi ;;
esac
