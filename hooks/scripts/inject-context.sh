#!/bin/bash
# inject-context.sh
# SessionStart hook: detects reinhardt projects and injects context.
# Output goes to stdout as additional context for Claude Code or Codex.

set -euo pipefail

CARGO_TOML="Cargo.toml"

# Exit silently if no Cargo.toml in current directory
if [ ! -f "$CARGO_TOML" ]; then
  exit 0
fi

# Check if this is a reinhardt project (dependency on reinhardt or reinhardt-*)
if ! grep -q 'reinhardt' "$CARGO_TOML" 2>/dev/null; then
  exit 0
fi

# Extract reinhardt version
REINHARDT_VERSION=$(grep -E '^reinhardt\s*=' "$CARGO_TOML" | grep -oE 'version\s*=\s*"[^"]*"' | grep -oE '"[^"]*"' | tr -d '"' | head -1)
if [ -z "$REINHARDT_VERSION" ]; then
  REINHARDT_VERSION=$(grep -E 'reinhardt\s*=' "$CARGO_TOML" | head -1 | grep -oE '"[0-9][^"]*"' | tr -d '"' | head -1)
fi
REINHARDT_VERSION="${REINHARDT_VERSION:-unknown}"

# Extract active features
FEATURES=""
FEATURES_LINE=$(grep -A 50 '^\[dependencies\]' "$CARGO_TOML" | grep -E '^reinhardt\s*=' | head -1)
if echo "$FEATURES_LINE" | grep -q 'features'; then
  FEATURES=$(echo "$FEATURES_LINE" | grep -oE 'features\s*=\s*\[[^]]*\]' | sed 's/features\s*=\s*\[//;s/\]//' | tr -d '"' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ', ' | sed 's/, $//')
fi

# Detect default-features
DEFAULT_FEATURES="true"
if echo "$FEATURES_LINE" | grep -q 'default-features\s*=\s*false'; then
  DEFAULT_FEATURES="false"
fi

# Detect DB backend from features
DB_BACKEND="none"
if echo "$FEATURES" | grep -q 'db-postgres'; then
  DB_BACKEND="postgres"
elif echo "$FEATURES" | grep -q 'db-mysql'; then
  DB_BACKEND="mysql"
elif echo "$FEATURES" | grep -q 'db-sqlite'; then
  DB_BACKEND="sqlite"
elif echo "$FEATURES" | grep -q 'db-cockroachdb'; then
  DB_BACKEND="cockroachdb"
elif echo "$FEATURES" | grep -q 'database'; then
  DB_BACKEND="configured (check settings)"
fi

# Detect auth method from features
AUTH_METHOD="none"
AUTH_METHODS=""
if echo "$FEATURES" | grep -q 'auth-jwt'; then
  AUTH_METHODS="${AUTH_METHODS}jwt, "
fi
if echo "$FEATURES" | grep -q 'auth-session'; then
  AUTH_METHODS="${AUTH_METHODS}session, "
fi
if echo "$FEATURES" | grep -q 'auth-oauth'; then
  AUTH_METHODS="${AUTH_METHODS}oauth, "
fi
if echo "$FEATURES" | grep -q 'auth-token'; then
  AUTH_METHODS="${AUTH_METHODS}token, "
fi
if echo "$FEATURES" | grep -q '\bauth\b'; then
  AUTH_METHODS="${AUTH_METHODS}auth (default), "
fi
AUTH_METHOD="${AUTH_METHODS%, }"
AUTH_METHOD="${AUTH_METHOD:-none}"

# Detect apps (look for src/apps/ subdirectories)
APPS=""
if [ -d "src/apps" ]; then
  APPS=$(ls -d src/apps/*/ 2>/dev/null | xargs -I{} basename {} | tr '\n' ', ' | sed 's/, $//')
fi
APPS="${APPS:-none detected}"

# Output context as structured text
cat << EOF
(reinhardt-project-context
  :reinhardt-version "$REINHARDT_VERSION"
  :default-features $DEFAULT_FEATURES
  :features "$FEATURES"
  :db-backend "$DB_BACKEND"
  :auth-method "$AUTH_METHOD"
  :apps "$APPS"
  :note "Use reinhardt-agent-plugin skills for domain-specific guidance. Available skills: scaffolding, modeling, api-development, testing, dependency-injection.")
EOF
