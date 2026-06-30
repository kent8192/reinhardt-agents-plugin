#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/plugins/reinhardt-agents-plugin"

ITEMS=(
  AGENTS.md
  CLAUDE.md
  CHANGELOG.md
  LICENSE
  README.md
  .codex-plugin
  agents
  commands
  hooks
  scripts
  skills
)

usage() {
  cat <<'EOF'
Usage: scripts/sync-packaged-plugin.sh [--check]

Synchronize the installable Codex package under plugins/reinhardt-agents-plugin/
from the repository root. The root files are the source of truth.

Options:
  --check   Verify the package copy is synchronized without changing files.
EOF
}

check=false
case "${1:-}" in
  "")
    ;;
  --check)
    check=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ ! -d "$PACKAGE" ]]; then
  echo "Packaged plugin directory not found: $PACKAGE" >&2
  echo "Run this script from the source repository, not from an installed package copy." >&2
  exit 1
fi

if "$check"; then
  for item in "${ITEMS[@]}"; do
    diff -qr "$ROOT/$item" "$PACKAGE/$item"
  done
  exit 0
fi

mkdir -p "$PACKAGE"

for item in "${ITEMS[@]}"; do
  rm -rf "$PACKAGE/$item"
  cp -a "$ROOT/$item" "$PACKAGE/$item"
done
