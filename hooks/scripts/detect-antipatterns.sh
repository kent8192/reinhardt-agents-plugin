#!/usr/bin/env bash
# Launch the edit hook with the same Python runtime as context injection.
set -euo pipefail

command -v python3 >/dev/null 2>&1 || exit 0
exec python3 "$(dirname "$0")/detect_antipatterns.py" "$@"
