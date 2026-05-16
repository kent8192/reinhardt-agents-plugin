---
name: scaffolding
description: Use when creating a new reinhardt project or adding an app - guides feature flag selection, template type, database backend, and authentication setup
---

# Reinhardt Project Scaffolding

Guide developers through creating new reinhardt-web projects and adding apps with correct configuration.

## When to Use

- User wants to create a new reinhardt project
- User wants to add a new app to an existing reinhardt project
- User mentions: "new project", "start project", "add app", "reinhardt-admin startproject", "scaffold", "initialize"

## Prerequisites

- Rust toolchain installed (edition 2024, >= 1.94.0)
- `reinhardt-admin` CLI available (installed via `cargo install reinhardt-admin-cli --version "0.1.0-rc.22"` — the `--version` flag is required during the RC phase because Cargo does not select pre-release versions by default)
- For database features: Docker Desktop running (needed for TestContainers)

## Workflow

### New Project

1. **Ask project name** — must be a valid Rust crate name (lowercase, underscores). Names starting with `reinhardt_` or `reinhardt-` are **rejected** (conflicts with DI pseudo orphan rule)
2. **Ask template type** — read `references/project-templates.md` for options
3. **Guide feature selection** — read `references/feature-flags.md` for presets and individual features
4. **Ask DB backend** — postgres (recommended), mysql, sqlite, cockroachdb, or none
5. **Ask auth method** — jwt, session, oauth, token, or none
6. **Execute scaffolding** — exactly one of the project-type flags is required (the CLI rejects ambiguity):
   ```bash
   # RESTful API project
   reinhardt-admin startproject <name> --with-rest

   # Full-stack project with reinhardt-pages (WASM + SSR)
   reinhardt-admin startproject <name> --with-pages

   # Equivalent canonical form
   reinhardt-admin startproject <name> --template rest
   reinhardt-admin startproject <name> --template pages
   ```
   Note: the legacy `-t restful|mtv` / `--template-type` flag was removed in rc.18 — use `--with-pages`/`--with-rest` (or `--template rest|pages`) instead.
7. **Adjust Cargo.toml** — set feature flags based on selections
8. **Verify** — run `cargo check` to confirm configuration compiles

### Adding an App

1. **Ask app name** — lowercase, singular (e.g., "user", "post", "order"). Names starting with `reinhardt_` or `reinhardt-` are **rejected** (conflicts with DI pseudo orphan rule)
2. **Ask app type** — RESTful or Pages (must match the parent project type)
3. **Execute**:
   ```bash
   # RESTful app
   reinhardt-admin startapp <name> --with-rest

   # Pages app (WASM + SSR)
   reinhardt-admin startapp <name> --with-pages
   ```
4. **Verify structure** — read `references/app-structure.md` for expected layout
5. **Register app** — add module to `src/apps.rs` and entry to `installed_apps!` macro in `src/config/apps.rs`

## Important Rules

- Project and app names MUST NOT start with `reinhardt_` or `reinhardt-` — these are reserved for the framework namespace (DI pseudo orphan rule). Cargo normalizes hyphens to underscores, so `reinhardt-myapp` becomes `reinhardt_myapp::*` which overlaps with the reserved `reinhardt_*` namespace
- ALWAYS use Rust 2024 Edition module system: `module.rs` + `module/` directory, NEVER `mod.rs`
- If generated templates contain `mod.rs` files, convert them to the new module system
- ALL code comments must be in English
- Use `pub use` for explicit re-exports, NEVER `pub use module::*`

## Cross-Domain References

If the user wants to immediately set up models after scaffolding, read
`${CLAUDE_PLUGIN_ROOT}/skills/modeling/references/model-patterns.md`.

## Dynamic References

When you need the latest CLI options or template details:
1. Run `reinhardt-admin startproject --help` and `reinhardt-admin startapp --help`
2. Read `reinhardt/crates/reinhardt-admin-cli/src/main.rs` for CLI argument definitions
3. Read `reinhardt/crates/reinhardt-commands/src/start_commands.rs` for command implementation
4. Read `reinhardt/crates/reinhardt-commands/templates/` for actual template files
5. Read `reinhardt/Cargo.toml` `[features]` section for current feature flags
