---
description: Create a new reinhardt-web project with guided feature flag selection, database backend, and authentication setup
---

# Create New Reinhardt Project

You are guiding the user through creating a new reinhardt-web project. Follow this interactive workflow:

## Step 1: Project Name

Ask the user for a project name. It must be a valid Rust crate name (lowercase letters, digits, underscores). Suggest a name based on context if possible.

## Step 2: Template Type

Present the options:
- **restful** (default) — REST API backend without frontend
- **with-pages** — Full-stack with reinhardt-pages (WASM + SSR)

## Step 3: Feature Preset

Present the feature presets from `${CLAUDE_PLUGIN_ROOT}/skills/scaffolding/references/feature-flags.md`:
- **minimal** — Core routing, DI, HTTP server only
- **standard** (default) — Balanced for most projects
- **api-only** — REST APIs without templates/forms
- **full** — Everything enabled

## Step 4: Database Backend

Present the options:
- **postgres** (recommended) — PostgreSQL
- **mysql** — MySQL
- **sqlite** — SQLite (good for development)
- **cockroachdb** — CockroachDB
- **none** — No database

## Step 5: Authentication

Present the options:
- **jwt** — JWT token auth (recommended for APIs)
- **session** — Session-based auth (for web apps)
- **oauth** — OAuth2/OIDC (for third-party login)
- **token** — Simple API token auth
- **none** — No authentication

## Step 6: Execute

After collecting all preferences, invoke the scaffolding skill to execute the project creation. The scaffolding skill handles the actual `reinhardt-admin startproject` execution and post-scaffolding configuration.

## Important

- Do NOT execute any commands before collecting all preferences
- Always confirm the full configuration with the user before executing
- If `reinhardt-admin` is not installed, guide the user to install it: `cargo install reinhardt-admin-cli --version "0.1.0-rc.22"` (the `--version` flag is required during the RC phase because Cargo does not select pre-release versions by default)
