---
name: scaffolding
description: Use when creating a new reinhardt project or adding an app - guides feature flag selection, template type, database backend, and authentication setup
versions: ["0.1.x", "0.2.x", "0.3.x", "0.4.x"]
---

# Reinhardt Project Scaffolding

Guide developers through creating new reinhardt-web projects and adding apps with correct configuration.

## When to Use

- User wants to create a new reinhardt project
- User wants to add a new app to an existing reinhardt project
- User mentions: "new project", "start project", "add app", "reinhardt-admin startproject", "scaffold", "initialize"

## Prerequisites

- Rust toolchain installed (edition 2024, >= 1.96.0)
- `reinhardt-admin` CLI available — install the current stable CLI with `cargo install reinhardt-admin-cli`
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

   # Pin the generated project to the 0.3 line when validating 0.3.x behavior
   reinhardt-admin startproject <name> --template pages --reinhardt-version "0.3.0"
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
5. **Verify registration** — current `startapp` templates add the module/export in `src/apps.rs` and the entry in `src/config/apps.rs`'s `installed_apps!` macro; register them manually only for legacy project layouts that the command cannot update

## Important Rules

- Project and app names MUST NOT start with `reinhardt_` or `reinhardt-` — these are reserved for the framework namespace (DI pseudo orphan rule). Cargo normalizes hyphens to underscores, so `reinhardt-myapp` becomes `reinhardt_myapp::*` which overlaps with the reserved `reinhardt_*` namespace
- ALWAYS use Rust 2024 Edition module system: `module.rs` + `module/` directory, NEVER `mod.rs`
- If generated templates contain `mod.rs` files, convert them to the new module system
- Generated app templates must not ship stale placeholder views, full absolute paths, or app-specific demo names that users are expected to rename later
- Generated Pages templates should use named imports, route reverse helpers, `form!`, and `use_form` in any interactive example
- In 0.4.0-alpha.1+, generated route-backed component templates must emit `#[reinhardt::pages::component("/<app>/", name = "placeholder")]`; do not emit positional route names or bare identifier shorthand
- ALL code comments must be in English
- Use `pub use` for explicit re-exports, NEVER `pub use module::*`
- In 0.3.x Pages apps, expect app-local split modules (`client/`, `server/`, `services/client.rs`, `services/server.rs`, `urls/client_router.rs`, `urls/server_router.rs`) and preserve generated empty directories with `.gitkeep`
- Do not keep obsolete app-local `pages.rs`, `client/pages`, `urls/server_urls.rs`, or broad project-level `shared/forms.rs` / `shared/types.rs` unless the project still has hand-written cross-app DTOs there
- Follow the Django-parity app boundary: every web application MUST create or select an app for user-facing endpoints, including minimal services and benchmarks with only one or two handlers
- Define HTTP endpoint handlers in `src/apps/<app>/views.rs` and Pages `#[server_fn]` functions in `src/apps/<app>/server_fn.rs` (or app-local equivalents), then register their routes in `src/apps/<app>/urls.rs` or an app-local `urls/` module
- Keep `src/config/urls.rs` composition-only: it may mount app routers and framework-level routes, but MUST NOT define application endpoint handlers directly; register every implementation app in `src/config/apps.rs`

## Cross-Domain References

If the user wants to immediately set up models after scaffolding, read
`../modeling/references/model-patterns.md`.

## Dynamic References

When you need the latest CLI options or template details:

1. Run `reinhardt-admin startproject --help` and `reinhardt-admin startapp --help`
2. Read `reinhardt/crates/reinhardt-admin-cli/src/main.rs` for CLI argument definitions
3. Read `reinhardt/crates/reinhardt-commands/src/start_commands.rs` for command implementation
4. Read `reinhardt/crates/reinhardt-commands/templates/` for actual template files
5. Read `reinhardt/Cargo.toml` `[features]` section for current feature flags
