#!/usr/bin/env bash
# inject-context.sh
# Thin launcher for the Reinhardt application context hook.

set -euo pipefail

command -v python3 >/dev/null 2>&1 || exit 0
exec python3 "$(dirname "$0")/inject_context.py" "$@"
