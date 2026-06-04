#!/bin/bash
# detect-antipatterns.sh
# PostToolUse hook: runs semgrep on edited .rs files to detect reinhardt anti-patterns.
# Fallback: local semgrep -> docker semgrep -> warn and skip.

set -euo pipefail

# Extract file path from TOOL_INPUT (JSON with file_path key)
FILE_PATH=""
if [ -n "${TOOL_INPUT:-}" ]; then
  FILE_PATH=$(printf '%s' "$TOOL_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# If no file path found, exit silently
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only process .rs files
case "$FILE_PATH" in
  *.rs) ;;
  *) exit 0 ;;
esac

# Check for mod.rs anti-pattern (filename-based, not semgrep)
BASENAME=$(basename "$FILE_PATH")
if [ "$BASENAME" = "mod.rs" ]; then
  echo "ERROR [reinhardt-no-mod-rs]: File '$FILE_PATH' uses deprecated mod.rs pattern." >&2
  echo "  Reinhardt uses Rust 2024 Edition module system: use 'module.rs' + 'module/' directory instead." >&2
  echo "  See: https://doc.rust-lang.org/edition-guide/rust-2024/mod-rs.html" >&2
fi

# Determine semgrep rules path.
# Claude Code exposes CLAUDE_PLUGIN_ROOT; Codex native plugin hooks expose PLUGIN_ROOT.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}"
RULES="${PLUGIN_ROOT}/hooks/semgrep/reinhardt-antipatterns.yml"

# Run semgrep with fallback chain
if command -v semgrep &>/dev/null; then
  semgrep scan --config "$RULES" --no-git-ignore --metrics off --quiet "$FILE_PATH" >&2 || true
elif command -v docker &>/dev/null; then
  ABS_FILE=$(cd "$(dirname "$FILE_PATH")" && pwd)/$(basename "$FILE_PATH")
  ABS_RULES=$(cd "$(dirname "$RULES")" && pwd)/$(basename "$RULES")
  docker run --rm \
    -v "$(dirname "$ABS_FILE"):/target" \
    -v "$(dirname "$ABS_RULES"):/rules" \
    semgrep/semgrep \
    semgrep scan --config "/rules/$(basename "$ABS_RULES")" \
    --no-git-ignore --metrics off --quiet \
    "/target/$(basename "$ABS_FILE")" >&2 || true
else
  echo "WARNING: semgrep not found (local or docker). Skipping anti-pattern check." >&2
fi

exit 0
